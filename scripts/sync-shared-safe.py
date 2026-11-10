#!/usr/bin/env python3
"""Safely update manifest-owned consumer copies using a content provenance ledger."""
from __future__ import annotations

import hashlib
import json
import os
import re
import shutil
import stat
import subprocess
import sys
import tempfile
from pathlib import Path


def fail(message: str) -> None:
    raise ValueError(message)


def digest(path: Path) -> str:
    h = hashlib.sha256()
    def visit(item: Path, relative: str) -> None:
        mode = item.lstat().st_mode
        if stat.S_ISLNK(mode):
            fail(f"nested symlink requires manual review: {item}")
        if stat.S_ISDIR(mode):
            h.update(f"D\0{relative}\0".encode())
            for child in sorted(item.iterdir(), key=lambda x: x.name):
                visit(child, f"{relative}/{child.name}")
        elif stat.S_ISREG(mode):
            h.update(f"F\0{relative}\0{mode & 0o111}\0".encode())
            with item.open('rb') as f:
                while chunk := f.read(65536):
                    h.update(chunk)
            h.update(b'\0')
        else:
            fail(f"unsupported file type: {item}")
    visit(path, '')
    return h.hexdigest()


def main() -> None:
    if len(sys.argv) != 3:
        fail('usage: sync-shared-safe.py MASTER CONSUMER')
    master, repo = (Path(p).resolve(strict=True) for p in sys.argv[1:])
    if not (repo / '.git').exists():
        fail(f'not a git repo: {repo}')
    claude = repo / '.claude'
    if claude.is_symlink():
        fail(f'refusing linked consumer configuration: {claude}')
    # An Internal checkout may also mirror the public config/ manifest. Its
    # root manifest describes the Internal overrides and takes precedence.
    manifest_path = master / 'shared-manifest.json'
    if not manifest_path.is_file():
        manifest_path = master / 'config/shared-manifest.json'
    manifest = json.loads(manifest_path.read_text())
    if not isinstance(manifest, dict):
        fail('manifest must be an object')
    items = []
    for category, key in [('skills', 'shared_skills'), ('agents', 'shared_agents')]:
        names = manifest.get(key, [])
        if not isinstance(names, list) or not all(
            isinstance(x, str)
            and re.fullmatch(r'[A-Za-z0-9._/-]+', x)
            and all(segment not in ('', '.', '..') for segment in x.split('/'))
            for x in names
        ):
            fail(f'invalid {key} manifest')
        if len({Path(x).name for x in names}) != len(names):
            fail(f'duplicate {key} entries')
        for name in names:
            suffix = '' if category == 'skills' else '.md'
            source = master / (name + suffix if '/' in name else f'{category}/{name}{suffix}')
            items.append((category, Path(name).name + suffix, source))
    ledger_path = claude / '.shared-tooling.lock.json'
    if ledger_path.is_symlink():
        fail('refusing symlinked provenance ledger')
    ignore = subprocess.run(
        ['git', '-C', str(repo), 'check-ignore', '--no-index', '-q', '--', '.claude/.shared-tooling.lock.json'],
        check=False,
    )
    if ignore.returncode == 0:
        fail('provenance ledger is ignored by Git; add an explicit .gitignore exception before syncing')
    if ignore.returncode != 1:
        fail('could not check whether the provenance ledger is ignored')
    ledger = json.loads(ledger_path.read_text()) if ledger_path.exists() else {'version': 1, 'items': {}}
    if not isinstance(ledger, dict) or ledger.get('version') != 1 or not isinstance(ledger.get('items'), dict):
        fail('invalid provenance ledger')
    previous = ledger['items']
    if not all(isinstance(k, str) and isinstance(v, str) and re.fullmatch(r'[0-9a-f]{64}', v) for k,v in previous.items()):
        fail('invalid provenance entries')
    protected_path = claude / 'agentic-protected-paths.json'
    if protected_path.is_symlink():
        fail('refusing symlinked protected paths')
    protected = []
    if protected_path.exists():
        reservation = json.loads(protected_path.read_text())
        if not isinstance(reservation, dict) or not isinstance(reservation.get('paths'), list):
            fail('invalid protected paths')
        for path in reservation['paths']:
            if not isinstance(path, str) or not path or path.startswith('/') or any(x in ('', '.', '..') for x in path.split('/')):
                fail('invalid protected path')
            protected.append(path)
    for category in ('skills', 'agents'):
        parent = claude / category
        if parent.is_symlink():
            fail(f'category symlink requires manual migration: {parent}')
        elif parent.exists() and not parent.is_dir():
            fail(f'category is not a directory: {parent}')
    plan = []
    for category, name, src in items:
        key = f'{category}/{name}'
        relative = f'.claude/{key}'
        if any(relative == path or relative.startswith(path + '/') or path.startswith(relative + '/') for path in protected):
            print(f'  protected {key}; left unchanged')
            continue
        override_lock = master / '.github/skill-overrides.lock.json'
        if category == 'skills' and override_lock.exists():
            resolver = master / 'scripts/resolve-skill-source.py'
            if not resolver.is_file():
                fail('Internal skill resolver is missing')
            resolved = subprocess.run(
                [sys.executable, str(resolver), name, '--internal', str(master)],
                text=True, capture_output=True, check=False,
            )
            if resolved.returncode or Path(resolved.stdout.strip()) != src.resolve():
                fail(f'Internal skill {name} requires reconciliation: {resolved.stderr.strip()}')
        dst = claude / category / name
        if not src.exists() or src.is_symlink():
            fail(f'missing or linked source: {src}')
        if not src.resolve().is_relative_to(master):
            fail(f'source escapes Master: {src}')
        new_hash = digest(src)
        if dst.is_symlink():
            if dst.resolve() != src.resolve():
                fail(f'foreign item symlink: {dst}')
        elif dst.exists():
            current = digest(dst)
            if current != new_hash and current != previous.get(key):
                fail(f'local or untracked customization; not overwriting: {dst}')
        plan.append((key, src, dst, new_hash))
    # Every collision is checked before touching any consumer item.
    claude.mkdir(parents=True, exist_ok=True)
    for key, src, dst, new_hash in plan:
        dst.parent.mkdir(parents=True, exist_ok=True)
        if dst.exists() and not dst.is_symlink() and digest(dst) == new_hash:
            previous[key] = new_hash
            continue
        with tempfile.TemporaryDirectory(prefix='.sync-shared-', dir=dst.parent) as tmp:
            stage = Path(tmp) / 'new'
            backup = Path(tmp) / 'old'
            if src.is_dir():
                shutil.copytree(src, stage)
            else:
                shutil.copy2(src, stage)
            if dst.exists() or dst.is_symlink():
                os.replace(dst, backup)
            try:
                os.replace(stage, dst)
            except BaseException:
                if backup.exists() or backup.is_symlink():
                    os.replace(backup, dst)
                raise
        previous[key] = new_hash
        print(f'  synced {key}')
    with tempfile.NamedTemporaryFile(mode='w', prefix='.shared-tooling-lock-', dir=claude, delete=False) as f:
        tmp_lock = f.name
        json.dump(ledger, f, indent=2, sort_keys=True)
        f.write('\n')
    os.replace(tmp_lock, ledger_path)
    print('sync-shared: done')


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        print(f'sync-shared: {exc}', file=sys.stderr)
        sys.exit(2)
