#!/usr/bin/env python3
"""Run against the real OS sandbox with small, local synthetic Git objects."""

from contextlib import ExitStack
from pathlib import Path
import os
import struct
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))
import architect_git_evidence as evidence


def linux_boundary_unavailable():
    if sys.platform != "linux":
        return None
    if not Path("/usr/bin/bwrap").is_file():
        return "Ubuntu/Linux runner has no /usr/bin/bwrap"
    # Distinguish host namespace policy from bugs in the production Git command.
    command = ["/usr/bin/bwrap", "--unshare-all", "--die-with-parent", "--cap-drop", "ALL",
               "--ro-bind", "/usr/bin/true", "/usr/bin/true"]
    for directory in ("/usr/lib", "/lib", "/lib64"):
        if Path(directory).is_dir():
            command.extend(("--ro-bind", directory, directory))
    result = subprocess.run([*command, "--", "/usr/bin/true"], capture_output=True,
                            env={"LC_ALL": "C"}, timeout=5, text=True)
    if result.returncode:
        if any(reason in result.stderr.lower() for reason in
               ("operation not permitted", "no permissions", "permission denied")):
            return "Ubuntu/Linux runner denies unprivileged bwrap namespaces: " + result.stderr.strip()
        raise RuntimeError("independent bubblewrap preflight failed: " + result.stderr.strip())
    return None


class GitFixtureMixin:
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)
        self.repo = self.root / "repo"
        self.repo.mkdir()
        self.snapshot = self.root / "snapshot"
        self.git("init", "--quiet", "--template=")
        self.file = self.repo / "tracked"
        self.file.write_text("first\n")
        self.git("add", "tracked")
        self.git("commit", "-qm", "base fixture")
        self.base = self.git("rev-parse", "HEAD")
        self.file.write_text("second\n")
        self.git("add", "tracked")
        self.git("commit", "-qm", "head fixture")
        self.head = self.git("rev-parse", "HEAD")

    def git(self, *args, input=None):
        result = subprocess.run(
            ["/usr/bin/git", "-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid",
             "-c", "core.hooksPath=/dev/null", *args],
            cwd=self.repo, env={"HOME": str(self.root), "PATH": os.defpath,
                                "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": "/dev/null"},
            check=True, capture_output=True, text=True, input=input, timeout=10)
        return result.stdout.strip()

    def prepare(self):
        evidence.prepare_snapshot(self.repo, self.base, self.head, self.snapshot)
        return evidence.Evidence(self.snapshot)


class GitEvidenceTests(GitFixtureMixin, unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        reason = linux_boundary_unavailable()
        if reason:
            if os.environ.get("ARCHITECT_REQUIRE_LINUX_SANDBOX") == "1":
                raise RuntimeError("required native Linux sandbox unavailable: " + reason)
            raise unittest.SkipTest(reason)

    def test_reads_commits_without_worktree_config_or_inherited_environment(self):
        self.git("config", "diff.noprefix", "true")
        self.file.write_text("working copy only\n")
        injected_config = {"GIT_CONFIG_COUNT": "1", "GIT_CONFIG_KEY_0": "diff.noprefix",
                           "GIT_CONFIG_VALUE_0": "true", "GIT_DIR": str(self.repo / ".git")}
        with patch.dict(os.environ, injected_config):
            reader = self.prepare()
            self.assertEqual(reader.read("history"), self.head + " head fixture\n")
            diff = reader.read("diff")
            self.assertIn("diff --git a/tracked b/tracked", diff)
            self.assertIn("-first\n+second\n", diff)
            self.assertNotIn("working copy only", diff)
        self.assertFalse((self.snapshot / "config").exists())
        self.assertEqual(list((self.snapshot / "objects").iterdir()), [])

    def test_history_distinguishes_exactly_100_from_101_commits(self):
        # fast-import creates the tiny synthetic history in one Git process.
        commits = []
        for number in range(1, 102):
            subject = f"fixture {number}"
            parent = f":{number - 1}" if number > 1 else self.base
            commits.append(f"commit refs/heads/fixture\nmark :{number}\n"
                           "committer Fixture <fixture@example.invalid> 1700000000 +0000\n"
                           f"data {len(subject)}\n{subject}\nfrom {parent}\n\n")
        self.git("fast-import", "--quiet", input="".join(commits))
        for count, revision in ((100, "refs/heads/fixture^"), (101, "refs/heads/fixture")):
            with self.subTest(count=count):
                self.head = self.git("rev-parse", revision)
                self.snapshot = self.root / str(count)
                lines = self.prepare().read("history").splitlines()
                if count > 100:
                    self.assertEqual(lines.pop(), "[History truncated at 100 commits.]")
                self.assertEqual(len(lines), 100)
                self.assertTrue(lines[0].endswith(f" fixture {count}"))
                self.assertTrue(lines[-1].endswith(f" fixture {count - 99}"))

    def test_git_allocation_limit_fails_closed(self):
        reader = self.prepare()
        with patch.object(evidence, "MAX_GIT_ALLOCATION", 32), self.assertRaises(RuntimeError):
            reader.read("diff")

    def test_linked_worktree_and_fixed_operation_allowlist(self):
        linked = self.root / "linked"
        self.git("worktree", "add", "--detach", str(linked), self.head)
        evidence.prepare_snapshot(linked, self.base, self.head, self.snapshot)
        reader = evidence.Evidence(self.snapshot)
        self.assertIn("head fixture", reader.read("history"))
        for operation in ("status", "diff --stat", ["diff"], None):
            with self.subTest(operation=operation), self.assertRaises(ValueError):
                reader.read(operation)

    def test_sandbox_denies_outside_read_and_snapshot_write(self):
        reader = self.prepare()
        marker = self.root / "private-fixture"
        marker.write_text("synthetic sibling\n")
        # Check the same builtin succeeds on a readable file before testing denial.
        self.assertRegex(reader._git(("hash-object", "--no-filters", "HEAD")), r"^[0-9a-f]{40}")
        with self.assertRaises(RuntimeError):
            reader._git(("hash-object", "--no-filters", str(marker)))
        with self.assertRaises(RuntimeError):
            reader._git(("update-ref", "refs/heads/write-probe", self.head))
        self.assertFalse((self.snapshot / "refs/heads/write-probe").exists())

    def test_network_boundary_denies_loopback_bind(self):
        # An ephemeral loopback bind needs no service, traffic or credentials.
        source = self.root / "probe.c"
        probe = self.root / "probe"
        source.write_text("""
#include <errno.h>
#include <netinet/in.h>
#include <sys/socket.h>
int main(void) {
    struct sockaddr_in addr = { .sin_family = AF_INET };
    addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd >= 0 && bind(fd, (struct sockaddr *)&addr, sizeof(addr)) == 0) return 1;
    return (errno == EPERM || errno == EACCES) ? 0 : 2;
}
""")
        subprocess.run(["/usr/bin/cc", str(source), "-o", str(probe)], check=True, timeout=30)
        self.assertEqual(subprocess.run([probe], timeout=2).returncode, 1)
        reader = self.prepare()
        with ExitStack() as stack:
            command, _, _, fds = evidence._sandbox(reader.snapshot, reader.objects, stack)
            if sys.platform == "darwin":
                command[command.index("-D") + 1] = "GIT=" + str(probe.resolve())
                command[-1] = str(probe.resolve())
            else:
                # Replace just the executable mounted as /usr/bin/git.
                command[command.index("--ro-bind") + 1] = str(probe)
            evidence._bounded_run(command, reader.snapshot, {}, fds)
        print(f"Verified native Git sandbox denied a loopback bind on {sys.platform}.", flush=True)

    def test_invalid_revision_or_system_boundary_fails_closed(self):
        for invalid in ("HEAD", self.head.upper()):
            with self.subTest(invalid=invalid), self.assertRaises(ValueError):
                evidence.prepare_snapshot(self.repo, self.base, invalid, self.snapshot)
            self.assertFalse(self.snapshot.exists())
        blob = self.git("rev-parse", "HEAD:tracked")
        with self.assertRaises(ValueError):
            evidence.prepare_snapshot(self.repo, self.base, blob, self.snapshot)
        self.assertFalse(self.snapshot.exists())
        with patch.object(sys, "platform", "unsupported"), self.assertRaises(RuntimeError):
            self.prepare()
        self.assertFalse(self.snapshot.exists())

    def test_output_limit_discards_partial_result(self):
        reader = self.prepare()
        with patch.object(evidence, "MAX_OUTPUT", 10), self.assertRaisesRegex(RuntimeError, "limit"):
            reader.read("diff")


class BoundaryTests(GitFixtureMixin, unittest.TestCase):
    def test_unavailable_linux_guest_refuses_snapshot(self):
        reason = linux_boundary_unavailable()
        if not reason:
            self.skipTest("native sandbox available; live positive and denial tests run")
        with self.assertRaises((OSError, RuntimeError)):
            self.prepare()
        self.assertFalse(self.snapshot.exists())
        print("Verified fail-closed Git evidence:", reason, flush=True)

    def test_fixed_commands_and_environment_on_both_platforms(self):
        self.snapshot.mkdir()
        (self.snapshot / "object-directory").write_text(str(self.repo / ".git/objects"))
        reader = evidence.Evidence(self.snapshot)
        for platform in ("darwin", "linux"):
            with (self.subTest(platform=platform), patch.object(sys, "platform", platform),
                  patch.object(evidence, "_socket_filter", side_effect=tempfile.TemporaryFile),
                  patch.object(Path, "is_file", return_value=True), patch.object(os, "access", return_value=True),
                  patch.object(evidence, "_bounded_run", return_value="data") as runner,
                  patch.dict(os.environ, {"SSH_AUTH_SOCK": str(self.root / "agent")})):
                self.assertEqual(reader.read("history"), "data")
                command, cwd, env, fds = runner.call_args.args
                self.assertEqual(cwd, self.snapshot.resolve())
                self.assertTrue(set(("SSH_AUTH_SOCK", "GIT_CONFIG_COUNT")).isdisjoint(env))
                self.assertEqual(env["GIT_ALLOW_PROTOCOL"], "")
                self.assertEqual(env["GIT_CONFIG_GLOBAL"], "/dev/null")
                self.assertEqual(command[-1], "--")
                self.assertIn(f"{evidence.BASE}..{evidence.HEAD}", command)
                if platform == "linux":
                    self.assertIn("--unshare-all", command)
                    self.assertIn("--remount-ro", command)
                    self.assertIn("--seccomp", command)
                    self.assertEqual(len(fds), 1)
                else:
                    self.assertIn("(deny default)", command[command.index("-p") + 1])
                    self.assertEqual(fds, ())

    def test_missing_or_nonexecutable_linux_prerequisite(self):
        git, bwrap = self.root / "git", self.root / "bwrap"
        for binary, package in ((git, "git"), (bwrap, "bubblewrap")):
            for present in (True, False):
                with (self.subTest(binary=binary.name, present=present), patch.object(sys, "platform", "linux"),
                      patch.object(evidence, "LINUX_GIT", str(git)), patch.object(evidence, "LINUX_BWRAP", str(bwrap))):
                    for fixture in (git, bwrap):
                        fixture.touch()
                        fixture.chmod(0o700)
                    if present:
                        binary.chmod(0o600)
                    else:
                        binary.unlink()
                    with self.assertRaises(RuntimeError) as failure:
                        self.prepare()
                    self.assertIn(f"distribution {package} package", str(failure.exception))
                    self.assertIn(str(binary), str(failure.exception))
                    self.assertFalse(self.snapshot.exists())

    def test_rejects_invalid_metadata_and_unavailable_native_git(self):
        pointer = self.root / "pointer"
        for data in (b"", b"bad\x00path", b"x" * 4097):
            pointer.write_bytes(data)
            with self.assertRaises(ValueError):
                evidence._metadata(pointer)
        pointer.unlink()
        pointer.symlink_to(self.repo / "tracked")
        with self.assertRaises(OSError):
            evidence._metadata(pointer)
        with (patch.object(sys, "platform", "darwin"), patch.object(Path, "is_file", return_value=False),
              self.assertRaisesRegex(RuntimeError, "Apple Git")):
            self.prepare()
        self.assertFalse(self.snapshot.exists())

    def test_bounded_subprocess_errors_timeout_and_output(self):
        self.assertEqual(evidence._bounded_run(["/usr/bin/true"], self.root, {}, ()), "")
        with self.assertRaisesRegex(RuntimeError, "failed"):
            evidence._bounded_run(["/usr/bin/false"], self.root, {}, ())
        with patch.object(evidence, "TIMEOUT", 0.02), self.assertRaisesRegex(RuntimeError, "timed out"):
            evidence._bounded_run([sys.executable, "-I", "-c", "import time; time.sleep(1)"],
                                  self.root, {}, ())
        with patch.object(evidence, "MAX_OUTPUT", 4), self.assertRaisesRegex(RuntimeError, "limit"):
            evidence._bounded_run([sys.executable, "-I", "-c", "print('fixture')"], self.root, {}, ())

    def test_linux_seccomp_policy_actions(self):
        # Exercise the production filter on either host using the native BPF ABI.
        # A temporary anonymous descriptor also works on macOS, without memfd.
        for machine, arch, socket, socketpair in (("x86_64", 0xC000003E, 41, 53),
                                                  ("aarch64", 0xC00000B7, 198, 199)):
            with (self.subTest(machine=machine), tempfile.TemporaryFile() as storage,
                  patch.object(os, "uname") as uname, patch.object(os, "memfd_create", create=True,
                  return_value=os.dup(storage.fileno()))):
                uname.return_value.machine = machine
                with evidence._socket_filter() as policy:
                    instructions = list(struct.iter_unpack("=HBBI", policy.read()))
                def verdict(architecture, syscall):
                    pc = reg = 0
                    while pc < len(instructions):
                        op, yes, no, val = instructions[pc]
                        pc += 1
                        if op == 0x20:
                            reg = {0: syscall, 4: architecture}[val]
                        elif op == 0x15:
                            pc += yes if reg == val else no
                        elif op == 0x35:
                            pc += yes if reg >= val else no
                        elif op == 0x06:
                            return val
                        else:
                            self.fail("unexpected BPF opcode")
                    self.fail("BPF program fell through")
                self.assertEqual(verdict(arch, 0), 0x7FFF0000)
                for number in (socket, socketpair, 425):
                    self.assertEqual(verdict(arch, number), 0x00050001)
                self.assertEqual(verdict(arch ^ 1, socket), 0x80000000)
                self.assertEqual(verdict(arch, socket | 0x40000000), 0x80000000)
        with patch.object(os, "uname") as uname, self.assertRaisesRegex(RuntimeError, "architecture"):
            uname.return_value.machine = "unsupported"
            evidence._socket_filter()


if __name__ == "__main__":
    unittest.main()
