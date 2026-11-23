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
          "pr-review-agent-dispatch.md", "repo-config.sh", "native-issue-links.md")

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
    files[Path("skills/_shared/native-issue-index.py")] = (ROOT / "scripts/native-issue-index.py").read_bytes()
    digest = hashlib.sha256()
    for path, contents in sorted(files.items()):
        digest.update(str(path).encode() + b"\0" + hashlib.sha256(contents).digest())
    return digest.hexdigest(), files


def directory(path, *, private=False):
    st = path.lstat()
    if (not stat.S_ISDIR(st.st_mode) or st.st_uid != os.getuid()
            or st.st_mode & (0o077 if private else 0o022)):
        raise ValueError("fleet cache requires a trusted directory")


def cache_child(parent_fd, name):
    flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW
    try:
        return os.open(name, flags, dir_fd=parent_fd)
    except FileNotFoundError:
        try:
            os.mkdir(name, 0o700, dir_fd=parent_fd)
        except FileExistsError:
            pass  # A concurrent creator still has to pass the descriptor checks.
        return os.open(name, flags, dir_fd=parent_fd)


def check_cache_component(st, level):
    if level == "managed":
        if st.st_uid != os.getuid() or stat.S_IMODE(st.st_mode) != 0o700:
            raise ValueError("invalid private fleet directory")
    elif level == "cache":
        if st.st_uid != os.getuid() or st.st_mode & 0o022:
            raise ValueError("untrusted cache directory")
    else:
        sticky_root = st.st_uid == 0 and bool(st.st_mode & stat.S_ISVTX)
        if st.st_uid not in (0, os.getuid()) or (st.st_mode & 0o022 and not sticky_root):
            raise ValueError("untrusted parent of fleet cache")


def cache_root(cache):
    if not cache.is_absolute() or not cache.name or cache != Path(os.path.abspath(cache)):
        raise ValueError("fleet cache requires a normalized absolute path")
    parts = cache.parts[1:]
    # The conventional Darwin aliases reside directly under root. Accept just
    # the OS-owned, known destinations; all descriptor opens below use NOFOLLOW.
    if sys.platform == "darwin" and parts[0] in ("tmp", "var"):
        alias = Path("/", parts[0])
        if alias.is_symlink() and alias.lstat().st_uid == 0 and str(alias.readlink()) == "private/" + parts[0]:
            parts = ("private", *parts)
    components = [(name, "ancestor") for name in parts[:-1]]
    components.extend(((parts[-1], "cache"), ("fleet-workflows", "managed")))
    fd = os.open("/", os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        for name, level in components:
            child_fd = cache_child(fd, name)
            os.close(fd)
            fd = child_fd
            check_cache_component(os.fstat(fd), level)
    finally:
        os.close(fd)
    return Path("/", *parts, "fleet-workflows")


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


def role_candidates(renderer, platform, name):
    directory_name, suffix, names = renderer["PROFILES"][platform]
    if name not in names:
        raise ValueError("unsupported platform role")
    yield name, Path(directory_name, name + suffix), renderer["profile_bytes"]
    if platform in ("claude", "codex") and name != "feedback-analyst":
        alias = renderer["fleet_alias_name"](platform, name)
        yield alias, Path(directory_name, alias + suffix), renderer["alias_bytes"]


def verified_role(platform, name, profile):
    renderer = runpy.run_path(str(ROOT / "scripts/render-agent-profiles.py"))
    candidates = role_candidates(renderer, platform, name)
    generate = next((body for _, tail, body in candidates
                     if profile.parts[-len(tail.parts):] == tail.parts), None)
    if not profile.is_absolute() or generate is None:
        raise ValueError("expected a host-reported native role path")
    if profile.resolve(strict=True) != profile:
        raise ValueError("linked or noncanonical role path")
    expected = generate(platform, name)
    st = profile.lstat()
    if (not stat.S_ISREG(st.st_mode) or st.st_nlink != 1 or st.st_mode & 0o022
            or st.st_uid not in (0, os.getuid()) or st.st_size != len(expected)
            or profile.read_bytes() != expected):
        raise ValueError("native role differs from the verified owner")
    return hashlib.sha256(expected).hexdigest()


def select_role(platform, name, project):
    if not project.is_absolute() or project.resolve(strict=True) != project or not project.is_dir():
        raise ValueError("expected a physical project directory")
    renderer = runpy.run_path(str(ROOT / "scripts/render-agent-profiles.py"))
    for native_name, relative, _ in role_candidates(renderer, platform, name):
        profile = project / relative
        try:
            digest = verified_role(platform, name, profile)
        except (OSError, ValueError):
            continue
        return {"native_name": native_name, "profile": str(profile), "sha256": digest}
    raise ValueError("no verified native role binding")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--skill", choices=SKILLS)
    mode.add_argument("--verify-role")
    mode.add_argument("--select-role")
    parser.add_argument("--project", type=Path)
    parser.add_argument("--cache", type=Path)
    parser.add_argument("--platform", choices=("codex", "claude", "antigravity", "copilot"))
    parser.add_argument("--profile", type=Path)
    args = parser.parse_args(argv)
    try:
        if args.skill:
            if args.cache is None or args.platform or args.profile or args.project:
                parser.error("--skill takes only --cache")
            print(resolve(args.cache, args.skill))
        elif args.select_role:
            if args.cache or args.profile or not args.project or not args.platform:
                parser.error("--select-role requires --platform and --project")
            print(json.dumps(select_role(args.platform, args.select_role, args.project)))
        else:
            if args.cache or args.project or not args.platform or not args.profile:
                parser.error("--verify-role requires --platform and --profile")
            print(verified_role(args.platform, args.verify_role, args.profile))
    except (OSError, ValueError) as exc:
        print(f"fleet workflow unavailable: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
