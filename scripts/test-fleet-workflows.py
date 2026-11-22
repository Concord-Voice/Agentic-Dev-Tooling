#!/usr/bin/env python3
"""Exercise the public fleet edition without activating a skill or a model."""
from concurrent.futures import ThreadPoolExecutor
from contextlib import redirect_stderr, redirect_stdout
import importlib.util
import io
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location("fleet", Path(__file__).with_name("resolve-fleet-workflow.py"))
fleet = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(fleet)


class FleetWorkflowTests(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.tmp = Path(tmp.name).resolve()
        self.cache = self.tmp / "cache"

    def test_complete_closed_edition(self):
        output = io.StringIO()
        with redirect_stdout(output):
            self.assertEqual(fleet.main(["--cache", str(self.cache), "--skill", "dev-lifecycle"]), 0)
        entry = Path(output.getvalue().strip())
        self.assertTrue(re.fullmatch(r"[0-9a-f]{64}", entry.parents[2].name))
        self.assertEqual(entry.parents[3], self.cache / "fleet-workflows")
        edition = entry.parents[1]
        for skill in fleet.SKILLS:
            path = edition / skill / "SKILL.md"
            self.assertIn("Fleet entry", path.read_text())
            self.assertIn("../_shared/nested-skills.md", path.read_text())
        all_text = "\n".join(p.read_text() for p in edition.rglob("*.md"))
        for term in ["red-team", "red_team.", ".review_agents", ".weekly_deps.deep_review_skill",
                     ".agents.escalation`", "executable proof-of-concept", "adversarial security pass",
                     "dynamic skill scoping (mandatory)"]:
            self.assertNotIn(term, all_text.lower())
        text = entry.read_text()
        for phase in range(1, 11):
            self.assertIn(f"## Phase {phase}:", text)
        self.assertIn("## Phase 7.5:", text)
        review = (edition / "_shared/pr-review-agent-dispatch.md").read_text()
        self.assertIn("codex-isolated-review.py", review)
        self.assertTrue((edition / "weekly-deps/references/autonomous-mode.md").is_file())
        self.assertTrue((edition / "enhanced-pr-review/check-review-dispositions.sh").is_file())
        for loader in (entry, edition/"pr-creation/SKILL.md", edition/"weekly-deps/SKILL.md"):
            self.assertIn("${FLEET_SKILLS:?}", loader.read_text())
            self.assertNotIn("git show \"$RC_OID:scripts/repo-config.sh", loader.read_text())

    def test_repeat_and_concurrent_materialization(self):
        def get(_):
            return fleet.resolve(self.cache, "issue-creation")
        with ThreadPoolExecutor(max_workers=3) as pool:
            paths = list(pool.map(get, range(5)))
        self.assertEqual(len(set(paths)), 1)
        old = paths[0].stat()
        self.assertEqual(get(0).stat().st_ino, old.st_ino)
        self.assertEqual(len(list((self.cache / "fleet-workflows").iterdir())), 1)

    def test_role_identity_matches_installed_native_bytes(self):
        import runpy
        renderer = runpy.run_path(str(fleet.ROOT / "scripts/render-agent-profiles.py"))
        for platform, (directory, suffix, _) in renderer["PROFILES"].items():
            name = "code-reviewer"
            role = self.tmp / directory / (name + suffix)
            role.parent.mkdir(parents=True, exist_ok=True)
            role.write_bytes(renderer["profile_bytes"](platform, name))
            args = ["--verify-role", name, "--platform", platform, "--profile", str(role)]
            with redirect_stdout(io.StringIO()) as out:
                self.assertEqual(fleet.main(args), 0)
            self.assertRegex(out.getvalue(), r"^[0-9a-f]{64}\n$")
            role.write_bytes(b"different role")
            with self.assertRaises(ValueError):
                fleet.verified_role(platform, name, role)
            role.unlink()
            role.symlink_to(fleet.EDITION / "nested-skills.md")
            with self.assertRaises(ValueError):
                fleet.verified_role(platform, name, role)
        for platform, name, path in [("copilot", "architect", self.tmp), ("codex", "architect", self.tmp)]:
            with self.assertRaises(ValueError):
                fleet.verified_role(platform, name, path)
        for args in (["--skill", "review-pr"], ["--verify-role", "architect"]):
            with redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
                fleet.main(args)

    def test_cache_drift(self):
        for kind in ("added", "removed", "body", "mode", "symlink", "directory", "hardlink"):
            with self.subTest(kind=kind):
                cache = self.cache / kind
                entry = fleet.resolve(cache, "issue-brief")
                if kind == "added":
                    entry.with_name("extra.md").write_text("extra")
                elif kind == "removed":
                    entry.unlink()
                elif kind == "body":
                    entry.write_text("stale")
                elif kind == "mode":
                    entry.chmod(0o644)
                elif kind == "symlink":
                    entry.unlink()
                    entry.symlink_to(self.tmp / "missing")
                elif kind == "directory":
                    (entry.parent / "extra").mkdir()
                else:
                    os.link(entry, self.tmp / "linked")
                with redirect_stderr(io.StringIO()):
                    self.assertEqual(fleet.main(["--cache", str(cache), "--skill", "issue-brief"]), 1)

    def test_cache_authority(self):
        with self.assertRaises(ValueError):
            fleet.resolve(self.cache, "../unlisted")
        with self.assertRaises(ValueError):
            fleet.cache_root(Path("relative"))
        self.cache.symlink_to(self.tmp, target_is_directory=True)
        with self.assertRaises(ValueError):
            fleet.cache_root(self.cache)
        if os.getuid() != 0:
            with self.assertRaises(ValueError):
                fleet.cache_root(self.cache / "child")
            self.assertFalse((self.tmp / "child").exists())
        self.cache.unlink()
        unsafe = self.tmp / "shared"
        unsafe.mkdir()
        unsafe.chmod(0o777)
        with self.assertRaises(ValueError):
            fleet.cache_root(unsafe / "target")
        self.assertFalse((unsafe / "target").exists())
        self.cache.mkdir(mode=0o700)
        (self.cache / "fleet-workflows").symlink_to(self.tmp, target_is_directory=True)
        with self.assertRaises(ValueError):
            fleet.cache_root(self.cache)
        with redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
            fleet.main(["--cache", str(self.cache), "--skill", "../another"])

    def test_changed_source_fails_before_materialization(self):
        with patch.object(fleet.Path, "read_bytes", return_value=b"changed"), self.assertRaises(ValueError):
            fleet.source_file("review-pr/SKILL.md", {"sha256": "0" * 64})
        self.assertFalse(self.cache.exists())

    def test_default_branch_config_is_the_only_data(self):
        repo = self.tmp / "repo"
        repo.mkdir()
        def run(*args, check=True):
            return subprocess.run(args, cwd=repo, capture_output=True, text=True, check=check)
        run("git", "init", "-q")
        run("git", "-c", "user.name=Test", "-c", "user.email=test@example.invalid", "commit", "--allow-empty", "-qm", "base")
        config = repo / ".claude/repo-config.json"
        config.parent.mkdir()
        helper = str(fleet.EDITION / "repo-config.sh")
        def read(oid):
            return run("bash", "-ec", 'source "$1"; fleet_load_config "$2"; rc_get ".value" absent; rc_has ".value"', "test", helper, oid, check=False)
        def commit():
            run("git", "add", ".claude/repo-config.json")
            run("git", "-c", "user.name=Test", "-c", "user.email=test@example.invalid", "commit", "-qm", "value")
            return run("git", "rev-parse", "HEAD").stdout.strip()
        empty = run("git", "rev-parse", "HEAD").stdout.strip()
        config.write_text('{"value": false}')
        good = commit()
        config.write_text('{"value": "working tree"}')
        self.assertEqual(read(good).stdout.strip(), "false")
        self.assertEqual(read(empty).stdout.strip(), "absent")
        fallback = run("bash", "-ec",
                       'source "$1"; fleet_load_config "$2"; rc_get \'.labels.namespaces | join(" ")\' "type area"; '
                       'source "$3"; printf "|%s" "$LABEL_NAMESPACES"',
                       "test", helper, empty, str(fleet.ROOT / fleet.CORE / "pr-creation/lib.sh"))
        self.assertEqual(fallback.stdout, "type area|type area domain release risk routine workflow-validation")
        config.write_text("invalid")
        self.assertNotEqual(read(commit()).returncode, 0)
        config.unlink()
        config.symlink_to(self.tmp / "somewhere")
        self.assertNotEqual(read(commit()).returncode, 0)
        self.assertNotEqual(read("HEAD").returncode, 0)


if __name__ == "__main__":
    unittest.main()
