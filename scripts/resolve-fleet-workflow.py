#!/usr/bin/env python3
"""Materialize one immutable edition of the public fleet workflow graph."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import runpy
import stat
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
CORE = "plugins/core-lifecycle/skills"
RELEASE = "plugins/release-ops/skills"
EDITION = ROOT / "config/fleet-workflows"
SKILLS = ("ci-status", "dev-lifecycle", "enhanced-pr-review", "issue-brief", "issue-creation",
          "pr-creation", "reproduce-then-fix", "review-pr", "verify-quality-gate", "weekly-deps")
TABLES = ("dispatchable-skills.md", "lifecycle-agent-dispatch.md", "nested-skills.md",
          "pr-review-agent-dispatch.md", "repo-config.sh")

ENTRY = (
    "\n**Fleet entry.** First read [the workflow and host boundary](../_shared/nested-skills.md). "
    "It applies to every nested operation and profile. All skill paths, including paths shown "
    "as checkout examples and paths inside native role prompts, refer to this edition. Verify "
    "required host capabilities before touching untrusted input. Leave unavailable required "
    "operations pending.\n"
)


def source_file(relative, spec):
    pack = RELEASE if relative.startswith("weekly-deps/") else CORE
    data = (ROOT / pack / relative).read_bytes()
    if hashlib.sha256(data).hexdigest() != spec["sha256"]:
        raise ValueError(f"source changed; review the fleet edition for {relative}")
    lines = data.decode().splitlines(keepends=True)
    for first, last, replacement in reversed(spec.get("edits", [])):
        lines[first - 1:last] = [replacement + "\n"] if replacement else []
    if relative.endswith("/SKILL.md"):
        header_end = lines.index("---\n", 1)
        lines.insert(header_end + 1, ENTRY)
    return "".join(lines).encode()


def edition():
    manifest = json.loads((EDITION / "sources.json").read_bytes())
    files = {Path("skills", path): source_file(path, spec) for path, spec in manifest.items()}
    for name in TABLES:
        files[Path("skills/_shared", name)] = (EDITION / name).read_bytes()
    digest = hashlib.sha256()
    for path, contents in sorted(files.items()):
        digest.update(str(path).encode() + b"\0" + hashlib.sha256(contents).digest())
    return digest.hexdigest(), files


def directory(path, *, private=False):
    st = path.lstat()
    if (not stat.S_ISDIR(st.st_mode) or st.st_uid != os.getuid()
            or st.st_mode & (0o077 if private else 0o022)):
        raise ValueError("fleet cache requires a trusted directory")


def trusted_parent(parent):
    if not os.path.lexists(parent):
        return
    st = parent.lstat()
    if stat.S_ISLNK(st.st_mode):
        if st.st_uid != 0:
            raise ValueError("linked parent of fleet cache")
        return
    public_sticky_root = st.st_uid == 0 and bool(st.st_mode & stat.S_ISVTX)
    if st.st_uid not in (0, os.getuid()) or (st.st_mode & 0o022 and not public_sticky_root):
        raise ValueError("untrusted parent of fleet cache")


def cache_root(cache):
    if not cache.is_absolute() or cache != Path(os.path.abspath(cache)):
        raise ValueError("fleet cache requires a normalized absolute path")
    # macOS /tmp and /var are root-owned aliases. A user-controlled link
    # in the supplied cache path has no authority to select another location.
    for parent in cache.parents:
        trusted_parent(parent)
    for parent in cache.parent.resolve().parents:
        trusted_parent(parent)
    cache.mkdir(mode=0o700, parents=True, exist_ok=True)
    directory(cache)
    root = cache.resolve() / "fleet-workflows"
    root.mkdir(mode=0o700, exist_ok=True)
    directory(root, private=True)
    return root


def verify_file(path, expected):
    st = path.lstat()
    mode = 0o700 if path.suffix == ".sh" else 0o600
    if (not stat.S_ISREG(st.st_mode) or st.st_uid != os.getuid() or st.st_nlink != 1
            or stat.S_IMODE(st.st_mode) != mode or st.st_size != len(expected)
            or path.read_bytes() != expected):
        raise ValueError("modified file in fleet edition")


def verify_tree(root, files):
    directory(root, private=True)
    directories = {parent for path in files for parent in path.parents}
    found = set()
    for base, names, filenames in os.walk(root, followlinks=False):
        for name in names:
            path = Path(base, name)
            if path.relative_to(root) not in directories:
                raise ValueError("unexpected directory in fleet edition")
            directory(path, private=True)
        for name in filenames:
            path = Path(base, name)
            relative = path.relative_to(root)
            if relative not in files:
                raise ValueError("unexpected file in fleet edition")
            verify_file(path, files[relative])
            found.add(relative)
    if found != set(files):
        raise ValueError("incomplete fleet edition")


def write_edition(stage, files):
    for relative, contents in files.items():
        out = stage / relative
        for parent in reversed(relative.parents):
            (stage / parent).mkdir(mode=0o700, exist_ok=True)
        with out.open("xb") as stream:
            os.fchmod(stream.fileno(), 0o700 if out.suffix == ".sh" else 0o600)
            stream.write(contents)


def publish_edition(target, files):
    with tempfile.TemporaryDirectory(prefix=".preparing-", dir=target.parent) as temporary:
        # Rename a child so TemporaryDirectory always owns a real cleanup root.
        stage = Path(temporary, "edition")
        stage.mkdir(mode=0o700)
        write_edition(stage, files)
        try:
            stage.rename(target)
        except OSError:
            # A concurrent process may have completed the same immutable edition.
            # The caller verifies it before returning any entry from that tree.
            if not os.path.lexists(target):
                raise


def resolve(cache, skill):
    if skill not in SKILLS:
        raise ValueError("unknown fleet workflow")
    digest, files = edition()
    target = cache_root(cache) / digest
    if not os.path.lexists(target):
        publish_edition(target, files)
    verify_tree(target, files)
    return target / "skills" / skill / "SKILL.md"


def verified_role(platform, name, profile):
    renderer = runpy.run_path(str(ROOT / "scripts/render-agent-profiles.py"))
    directory_name, suffix, names = renderer["PROFILES"][platform]
    if name not in names:
        raise ValueError("unsupported platform role")
    tail = Path(directory_name) / (name + suffix)
    if not profile.is_absolute() or profile.parts[-len(tail.parts):] != tail.parts:
        raise ValueError("expected a host-reported native role path")
    if profile.resolve(strict=True) != profile:
        raise ValueError("linked or noncanonical role path")
    expected = renderer["profile_bytes"](platform, name)
    st = profile.lstat()
    if (not stat.S_ISREG(st.st_mode) or st.st_nlink != 1 or st.st_mode & 0o022
            or st.st_uid not in (0, os.getuid()) or st.st_size != len(expected)
            or profile.read_bytes() != expected):
        raise ValueError("native role differs from the verified owner")
    return hashlib.sha256(expected).hexdigest()


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--skill", choices=SKILLS)
    mode.add_argument("--verify-role")
    parser.add_argument("--cache", type=Path)
    parser.add_argument("--platform", choices=("codex", "claude", "antigravity", "copilot"))
    parser.add_argument("--profile", type=Path)
    args = parser.parse_args(argv)
    try:
        if args.skill:
            if args.cache is None or args.platform or args.profile:
                parser.error("--skill takes only --cache")
            print(resolve(args.cache, args.skill))
        else:
            if args.cache or not args.platform or not args.profile:
                parser.error("--verify-role requires --platform and --profile")
            print(verified_role(args.platform, args.verify_role, args.profile))
    except (OSError, ValueError) as exc:
        print(f"fleet workflow unavailable: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
