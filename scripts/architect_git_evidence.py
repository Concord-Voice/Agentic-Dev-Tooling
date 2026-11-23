"""Fixed, sandboxed Git evidence queries for a trusted local commit pair."""

from contextlib import ExitStack
import errno
import os
from pathlib import Path
import re
import selectors
import shutil
import stat
import struct
import subprocess
import sys
import time


BASE = "refs/heads/base"
HEAD = "refs/heads/head"
HISTORY_LIMIT = 100
MAX_GIT_ALLOCATION = 64 * 1024 * 1024
OPERATIONS = {
    "history": ("log", "--no-notes", "--no-decorate", "--no-show-signature",
                f"--max-count={HISTORY_LIMIT + 1}", "--format=%H %s", f"{BASE}..{HEAD}", "--"),
    "diff": ("diff", "--no-ext-diff", "--no-textconv", "--no-color", "--no-renames",
             "--submodule=short", BASE, HEAD, "--"),
}
MAX_OUTPUT = 256 * 1024
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


def _metadata(path):
    # Only trusted checkout administrative pointers and private snapshot metadata.
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    with os.fdopen(fd, "rb") as stream:
        if not stat.S_ISREG(os.fstat(stream.fileno()).st_mode):
            raise ValueError("expected a regular Git metadata file")
        data = stream.read(4097)
    if len(data) > 4096:
        raise ValueError("Git metadata path is too long")
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


def prepare_snapshot(repository, base, head, snapshot):
    """Create a private bare view; caller owns its new path and its lifetime.

    repository is a trusted local checkout root. Only its object store is made
    available to Git. No refs, config, hooks, indexes or working files are copied.
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
        Evidence(snapshot).check()
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
        policy = descriptors.enter_context(_socket_filter())
        command = ["/usr/bin/bwrap", "--seccomp", str(policy.fileno()), "--unshare-all", "--die-with-parent", "--new-session",
                   "--cap-drop", "ALL", "--ro-bind", "/usr/bin/git", "/usr/bin/git"]
        for directory in ("/usr/lib", "/lib", "/lib64"):
            if Path(directory).is_dir():
                command.extend(("--ro-bind", directory, directory))
        command.extend(("--dev-bind", "/dev/null", "/dev/null",
                        "--ro-bind", str(snapshot), "/evidence",
                        "--ro-bind", str(objects), "/objects", "--remount-ro", "/",
                        "--chdir", "/evidence", "--", "/usr/bin/git"))
        return command, "/evidence", "/objects", (policy.fileno(),)
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
                "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": "/dev/null",
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
                return "\n".join(entries)
        return output
