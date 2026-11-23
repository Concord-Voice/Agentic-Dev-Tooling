"""Fixed, sandboxed Git evidence queries for a trusted local commit pair."""

import argparse
from contextlib import ExitStack
import errno
import json
import os
from pathlib import Path
import re
import selectors
import shutil
import stat
import struct
import subprocess
import sys
import tempfile
import time


BASE = "refs/heads/base"
HEAD = "refs/heads/head"
LINUX_GIT = "/usr/bin/git"
LINUX_BWRAP = "/usr/bin/bwrap"
LINUX_SNAPSHOT = "/evidence"
HISTORY_LIMIT = 100
MAX_GIT_ALLOCATION = 64 * 1024 * 1024
OPERATIONS = {
    "history": ("log", "--no-notes", "--no-decorate", "--no-show-signature",
                f"--max-count={HISTORY_LIMIT + 1}", "--format=%H %s", f"{BASE}..{HEAD}", "--"),
    "diff": ("diff", "--no-ext-diff", "--no-textconv", "--no-color", "--no-renames",
             "--submodule=short", BASE, HEAD, "--"),
}
MAX_OUTPUT = 256 * 1024
SHALLOW_FILE = "shallow"
MAX_SHALLOW_BYTES = 1024 * 41
SHALLOW_NOTICE = "[Shallow checkout. Earlier ancestry may be unavailable.]\n"
TIMEOUT = 10
MAC_PROFILE = """
(version 1)
(deny default)
(import "dyld-support.sb")
(allow process-exec (literal (param "GIT")))
(allow file-read* file-map-executable
  (literal (param "GIT")) (subpath "/System/Library") (subpath "/usr/lib"))
(allow file-read* (subpath (param "SNAPSHOT")) (subpath (param "OBJECTS")))
(allow file-read* file-write-data (literal "/dev/null"))
"""


def _read_regular(path, limit):
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    with os.fdopen(fd, "rb") as stream:
        if not stat.S_ISREG(os.fstat(stream.fileno()).st_mode):
            raise ValueError("expected a regular Git metadata file")
        data = stream.read(limit + 1)
    if len(data) > limit:
        raise ValueError("Git metadata exceeds its size limit")
    return data


def _metadata(path):
    # Only trusted checkout administrative pointers and private snapshot metadata.
    data = _read_regular(path, 4096)
    result = os.fsdecode(data.removesuffix(b"\n"))
    if not result or any(ord(c) < 32 for c in result):
        raise ValueError("invalid Git metadata path")
    return result


def _object_directory(repository):
    gitdir = repository.resolve(strict=True) / ".git"
    if not gitdir.is_dir():
        pointer = _metadata(gitdir)
        if not pointer.startswith("gitdir: "):
            raise ValueError("expected a trusted local Git checkout")
        gitdir = (gitdir.parent / pointer[8:]).resolve(strict=True)
    common = gitdir
    if (gitdir / "commondir").exists():
        common = (gitdir / _metadata(gitdir / "commondir")).resolve(strict=True)
    objects = common / "objects"
    if objects.is_symlink() or not objects.is_dir():
        raise ValueError("expected a local Git object directory")
    return objects.resolve(strict=True)


def _copy_shallow(common, snapshot):
    try:
        data = _read_regular(common / SHALLOW_FILE, MAX_SHALLOW_BYTES)
    except FileNotFoundError:
        return []
    boundaries = data.removesuffix(b"\n").split(b"\n")
    if not all(re.fullmatch(rb"[0-9a-f]{40}", oid) for oid in boundaries):
        raise ValueError("invalid shallow Git boundary")
    (snapshot / SHALLOW_FILE).write_bytes(b"\n".join(boundaries) + b"\n")
    return [oid.decode("ascii") for oid in boundaries]


def prepare_snapshot(repository, base, head, snapshot):
    """Create a private bare view; caller owns its new path and its lifetime.

    repository is a trusted local checkout root. Git can read its object store
    and the two approved refs. Shallow ancestry is preserved in the private view.
    """
    if not all(isinstance(oid, str) and re.fullmatch(r"[0-9a-f]{40}", oid)
               for oid in (base, head)):
        raise ValueError("base and head must be full lowercase SHA-1 commit IDs")
    objects = _object_directory(Path(repository))
    snapshot = Path(snapshot)
    snapshot.mkdir(mode=0o700)
    try:
        (snapshot / "refs/heads").mkdir(parents=True)
        (snapshot / "objects").mkdir()
        (snapshot / "HEAD").write_text(f"ref: {HEAD}\n", encoding="ascii")
        (snapshot / BASE).write_text(base + "\n", encoding="ascii")
        (snapshot / HEAD).write_text(head + "\n", encoding="ascii")
        (snapshot / "object-directory").write_bytes(os.fsencode(objects) + b"\n")
        boundaries = _copy_shallow(objects.parent, snapshot)
        reader = Evidence(snapshot)
        reader.check()
        if boundaries:
            # Reject missing objects, blobs and tag IDs named as commit boundaries.
            commits = reader._git(("rev-list", "--no-walk=unsorted",
                                   *(oid + "^{commit}" for oid in boundaries), "--"))
            if set(commits.splitlines()) != set(boundaries):
                raise ValueError("shallow boundaries must name local commit objects")
    except BaseException:
        shutil.rmtree(snapshot)
        raise


def _socket_filter():
    """Classic BPF for bwrap --seccomp, using Linux seccomp_data offsets.

    Reject other syscall ABIs (including x32), socket creation, and io_uring,
    which can submit socket operations. No sockets are inherited by Git.
    """
    abi = {
        "x86_64": (0xC000003E, 41, 53),
        "aarch64": (0xC00000B7, 198, 199),
    }.get(os.uname().machine)
    if not abi:
        raise RuntimeError("unsupported architecture for the Linux Git sandbox")
    arch, socket, socketpair = abi
    load_word, jump_equal, jump_ge, ret = 0x20, 0x15, 0x35, 0x06
    kill, allow, denied = 0x80000000, 0x7FFF0000, 0x00050000 | errno.EPERM
    program = [(load_word, 0, 0, 4), (jump_equal, 1, 0, arch), (ret, 0, 0, kill),
               (load_word, 0, 0, 0), (jump_ge, 0, 1, 0x40000000), (ret, 0, 0, kill)]
    for number in (socket, socketpair, 425):  # __NR_io_uring_setup on both ABIs
        program.extend(((jump_equal, 0, 1, number), (ret, 0, 0, denied)))
    program.append((ret, 0, 0, allow))
    handle = os.fdopen(os.memfd_create("git-network-policy"), "w+b")
    try:
        for instruction in program:
            handle.write(struct.pack("=HBBI", *instruction))
        handle.seek(0)
        return handle
    except BaseException:
        handle.close()
        raise


def _require_linux_binaries():
    for path, package in ((LINUX_BWRAP, "bubblewrap"), (LINUX_GIT, "git")):
        if not Path(path).is_file() or not os.access(path, os.X_OK):
            raise RuntimeError(f"Install the distribution {package} package with an executable at {path}")


def _sandbox(snapshot, objects, descriptors):
    if sys.platform == "darwin":
        # /usr/bin/git is an xcrun launcher which needs host services. Invoke a
        # fixed Apple installation's real Git, without consulting PATH or xcrun.
        for path in ("/Library/Developer/CommandLineTools/usr/bin/git",
                     "/Applications/Xcode.app/Contents/Developer/usr/bin/git"):
            if Path(path).is_file():
                return (["/usr/bin/sandbox-exec", "-D", "GIT=" + path,
                         "-D", "SNAPSHOT=" + str(snapshot), "-D", "OBJECTS=" + str(objects),
                         "-p", MAC_PROFILE, path], str(snapshot), str(objects), ())
        raise RuntimeError("Apple Git is unavailable for isolated evidence")
    if sys.platform == "linux":
        _require_linux_binaries()
        policy = descriptors.enter_context(_socket_filter())
        command = [LINUX_BWRAP, "--seccomp", str(policy.fileno()), "--unshare-all", "--die-with-parent", "--new-session",
                   "--cap-drop", "ALL", "--ro-bind", LINUX_GIT, LINUX_GIT]
        for directory in ("/usr/lib", "/lib", "/lib64"):
            if Path(directory).is_dir():
                command.extend(("--ro-bind", directory, directory))
        command.extend(("--dev-bind", os.devnull, os.devnull,
                        "--ro-bind", str(snapshot), LINUX_SNAPSHOT,
                        "--ro-bind", str(objects), "/objects", "--remount-ro", "/",
                        "--chdir", LINUX_SNAPSHOT, "--", LINUX_GIT))
        return command, LINUX_SNAPSHOT, "/objects", (policy.fileno(),)
    raise RuntimeError("Git evidence requires a supported operating system sandbox")


def _bounded_run(command, cwd, environment, pass_fds):
    deadline = time.monotonic() + TIMEOUT
    with subprocess.Popen(command, cwd=cwd, env=environment, stdin=subprocess.DEVNULL,
                          stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                          close_fds=True, pass_fds=pass_fds, start_new_session=True) as process:
        output = bytearray()
        try:
            with selectors.DefaultSelector() as poll:
                poll.register(process.stdout, selectors.EVENT_READ)
                while poll.select(max(0, deadline - time.monotonic())):
                    if time.monotonic() >= deadline:
                        break
                    chunk = os.read(process.stdout.fileno(), 65536)
                    if not chunk:
                        if process.wait(timeout=max(0, deadline - time.monotonic())):
                            raise RuntimeError("isolated Git query failed")
                        return output.decode("utf-8", errors="replace")
                    output.extend(chunk)
                    if len(output) > MAX_OUTPUT:
                        raise RuntimeError("isolated Git evidence exceeds output limit")
                raise RuntimeError("isolated Git query timed out")
        except subprocess.TimeoutExpired:
            raise RuntimeError("isolated Git query timed out") from None
        finally:
            if process.poll() is None:
                # bwrap uses --die-with-parent. Apple Git cannot fork under
                # this profile. Signal the owned child directly on both.
                process.kill()


class Evidence:
    """Read only a private snapshot created by a trusted prepare_snapshot caller."""

    def __init__(self, snapshot):
        self.snapshot = Path(snapshot).resolve(strict=True)
        self.objects = Path(_metadata(self.snapshot / "object-directory"))
        if not self.objects.is_absolute() or not self.objects.is_dir():
            raise ValueError("invalid local Git object directory")

    def _git(self, args):
        with ExitStack() as descriptors:
            command, gitdir, objects, fds = _sandbox(self.snapshot, self.objects, descriptors)
            environment = {
                "HOME": "/unavailable", "PATH": "/unavailable", "LC_ALL": "C",
                "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": os.devnull,
                "GIT_ATTR_NOSYSTEM": "1", "GIT_OPTIONAL_LOCKS": "0",
                "GIT_NO_REPLACE_OBJECTS": "1", "GIT_NO_LAZY_FETCH": "1",
                "GIT_ALLOW_PROTOCOL": "", "GIT_TERMINAL_PROMPT": "0",
                "GIT_OBJECT_DIRECTORY": objects, "GIT_ALLOC_LIMIT": str(MAX_GIT_ALLOCATION),
            }
            command.extend(("--no-pager", "--git-dir=" + gitdir, "-c", "core.bare=true",
                            "-c", "core.attributesFile=/dev/null", "-c", "core.hooksPath=/dev/null",
                            "-c", "core.bigFileThreshold=4m", "-c", "core.packedGitWindowSize=16m",
                            "-c", "core.packedGitLimit=64m", *args))
            return _bounded_run(command, self.snapshot, environment, fds)

    def check(self):
        for ref in (BASE, HEAD):
            if self._git(("cat-file", "-t", ref)) != "commit\n":
                raise ValueError("both evidence refs must name local commit objects")

    def read(self, operation):
        if not isinstance(operation, str) or operation not in OPERATIONS:
            raise ValueError("expected history or diff")
        output = self._git(OPERATIONS[operation])
        if operation == "history":
            # Git's single-line subject format terminates each commit with LF.
            # The extra record distinguishes exactly 100 from a truncated range.
            entries = output.split("\n", HISTORY_LIMIT)
            if len(entries) > HISTORY_LIMIT and entries[-1]:
                entries[-1] = f"[History truncated at {HISTORY_LIMIT} commits.]\n"
                output = "\n".join(entries)
            if (self.snapshot / SHALLOW_FILE).exists():
                output += SHALLOW_NOTICE
        if len(output.encode("utf-8")) > MAX_OUTPUT:
            raise RuntimeError("formatted Git evidence exceeds output limit")
        return output


def collect(repository, base, head):
    """Produce one bounded JSON document or fail before publishing any evidence."""
    if not repository.is_absolute():
        raise ValueError("provide an absolute trusted checkout root")
    with tempfile.TemporaryDirectory(prefix="adt-git-evidence-", dir="/tmp") as directory:
        snapshot = Path(directory) / "evidence"
        prepare_snapshot(repository, base, head, snapshot)
        reader = Evidence(snapshot)
        evidence = {operation: reader.read(operation) for operation in OPERATIONS}
    document = json.dumps(evidence, separators=(",", ":"), ensure_ascii=True) + "\n"
    if len(document) > MAX_OUTPUT:
        raise ValueError("combined Git evidence exceeds 256 KiB. Choose a narrower commit range")
    return document


def main():
    parser = argparse.ArgumentParser(description=__doc__, allow_abbrev=False)
    parser.add_argument("--repo", required=True, type=Path)
    parser.add_argument("--base", required=True)
    parser.add_argument("--head", required=True)
    args = parser.parse_args()
    try:
        sys.stdout.write(collect(args.repo, args.base, args.head))
    except (OSError, RuntimeError, ValueError) as error:
        sys.exit(f"Git evidence unavailable: {error}")


if __name__ == "__main__":
    main()
