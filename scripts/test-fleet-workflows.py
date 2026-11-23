#!/usr/bin/env python3
"""Exercise the public fleet edition without activating a skill or a model."""
from concurrent.futures import ThreadPoolExecutor
from contextlib import redirect_stderr, redirect_stdout
import importlib.util
import io
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import sys
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location("fleet", Path(__file__).with_name("resolve-fleet-workflow.py"))
fleet = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(fleet)


INDEX_SPEC = importlib.util.spec_from_file_location("index_helper", Path(__file__).with_name("native-issue-index.py"))
index_helper = importlib.util.module_from_spec(INDEX_SPEC)
INDEX_SPEC.loader.exec_module(index_helper)


class NativeIssueIndexTests(unittest.TestCase):
    parent = "https://github.com/example/parent/issues/2"
    child = "https://github.com/example/child/issues/2"
    original = "## Context\n\n```md\n## Sub-Issues\n```\n\n## Sub-Issues\n\n## Criteria\n- [ ] private text\n"

    def setUp(self):
        self.body = self.original
        self.calls = []
        self.parent_of_child = self.parent

    def transport(self, argv, *, input, **options):
        self.assertEqual(argv[:4], ["gh", "api", "--hostname", "github.com"])
        self.assertTrue(options["capture_output"])
        self.calls.append(argv)
        if "graphql" in argv:
            url = argv[-1].removeprefix("url=")
            parent = {"url": self.parent_of_child} if url == self.child and self.parent_of_child else None
            data = {"data": {"resource": {"__typename": "Issue", "url": url, "parent": parent}}}
        elif "PATCH" in argv:
            self.assertIn("--silent", argv)
            self.body = json.loads(input)["body"]
            return subprocess.CompletedProcess(argv, 0, b"", b"")
        else:
            url = self.parent if "/parent/" in argv[-1] else self.child
            data = {"id": 4000000000, "html_url": url, "body": self.body, "title": "private @group\n#7"}
        return subprocess.CompletedProcess(argv, 0, json.dumps(data).encode(), b"")

    def run_cli(self, *args):
        out, err = io.StringIO(), io.StringIO()
        with patch.object(sys, "argv", ["helper", *args]), redirect_stdout(out), redirect_stderr(err):
            index_helper.main()
        self.assertEqual(err.getvalue(), "")
        self.assertNotIn("private", out.getvalue())
        return json.loads(out.getvalue())

    def test_real_cli_boundary_and_retry(self):
        with patch.object(index_helper.subprocess, "run", self.transport):
            self.assertEqual(self.run_cli("inspect", self.child),
                             {"url": self.child, "parent": self.parent, "database_id": 4000000000})
            self.assertEqual(self.run_cli("index", self.parent, self.child), {"status": "updated", "children": 1})
            self.assertEqual(self.body, self.original.replace("## Sub-Issues\n\n## Criteria",
                             "## Sub-Issues\n- example/child#2 — private &#64;group &#35;7\n\n## Criteria"))
            self.assertEqual(self.run_cli("index", self.parent, self.child)["status"], "current")
            self.assertEqual(sum("PATCH" in args for args in self.calls), 1)

    def test_unverified_relationship_and_provider_error(self):
        self.parent_of_child = None
        with patch.object(index_helper.subprocess, "run", self.transport):
            with self.assertRaisesRegex(SystemExit, "^child relationship is unverified$"):
                self.run_cli("index", self.parent, self.child)
            with self.assertRaisesRegex(SystemExit, "^invalid issue URL$"):
                self.run_cli("inspect", self.child + "?query")
        error = subprocess.CompletedProcess([], 1, b"private body", b"private error")
        with patch.object(index_helper.subprocess, "run", return_value=error):
            with self.assertRaisesRegex(SystemExit, "^GitHub request failed$"):
                self.run_cli("inspect", self.child)
        self.assertFalse(any("PATCH" in args for args in self.calls))

    def test_concurrent_parent_edits_stay_pending(self):
        def concurrent(argv, **opts):
            old = self.body
            result = self.transport(argv, **opts)
            if argv[-1] == index_helper.endpoint(self.parent) and len(self.calls) >= 5:
                self.body = old + "concurrent change\n"
            return result
        with patch.object(index_helper.subprocess, "run", concurrent):
            with self.assertRaisesRegex(SystemExit, "^parent changed before update$"):
                self.run_cli("index", self.parent, self.child)
        self.assertFalse(any("PATCH" in args for args in self.calls))

    def test_index_sections_and_same_number_across_repos(self):
        children = [(self.child, "T"), (self.parent.replace("/2", "/7"), "Other")]
        row = "- example/child#2 — T"
        current = "## Sub-Issues\r\n- #7 — Same repo\r\n"
        self.assertEqual(index_helper.reconcile(current, self.parent, children), current + row + "\r\n")
        self.assertEqual(index_helper.reconcile("Context", self.parent, children[:1]),
                         "Context\n\n## Sub-Issues\n" + row + "\n")
        for body in ["## Sub-Issues\n## Sub-Issues\n", "## Sub-Issues\n- [ ] #2", "```\n",
                     "<!--private", "<pre>\n## Sub-Issues\n", "## Sub-Issues\n- #7\n- example/parent#7"]:
            with self.subTest(body=body), self.assertRaises(index_helper.Pending):
                index_helper.reconcile(body, self.parent, children)


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
        self.assertNotIn("/superpowers:", text)
        weekly = (edition / "weekly-deps/SKILL.md").read_text()
        self.assertNotIn('RC_FILE="$(mktemp)', weekly)
        self.assertIn('fleet_load_repo_config "$OWNER_REPO"', weekly)
        enhanced = (edition / "enhanced-pr-review/SKILL.md").read_text()
        self.assertIn('fleet_check_dispositions "$0"', enhanced)
        self.assertIn('<<<"$RC_TRUSTED_CFG"', enhanced)
        self.assertNotIn('$(git rev-parse --show-toplevel)/.claude/repo-config.json', enhanced)
        coverage = edition / "enhanced-pr-review/review-coverage.sh"
        subprocess.run(["bash", "-n", coverage], check=True)
        for number, fixture in (("0", ""), ("11", "invalid-fixture")):
            result = subprocess.run(["bash", coverage, number, "example/repo"],
                                    env={**os.environ, "CV_COVERAGE_FIXTURE": fixture},
                                    capture_output=True, text=True, check=False)
            self.assertEqual(result.returncode, 2)
            self.assertIn("live PR coverage required", result.stderr)
        review = (edition / "_shared/pr-review-agent-dispatch.md").read_text()
        self.assertIn("codex-isolated-review.py", review)
        self.assertTrue((edition / "weekly-deps/references/autonomous-mode.md").is_file())
        self.assertTrue((edition / "enhanced-pr-review/check-review-dispositions.sh").is_file())
        for loader in (entry, edition/"pr-creation/SKILL.md", edition/"weekly-deps/SKILL.md"):
            self.assertIn("${FLEET_SKILLS:?}", loader.read_text())
            self.assertNotIn("git show \"$RC_OID:scripts/repo-config.sh", loader.read_text())

    def test_issue_linkage_policy_reaches_direct_and_nested_intake(self):
        entry = fleet.resolve(self.cache, "issue-creation")
        skill = entry.read_text()
        shared = entry.parent.parent / "_shared"
        nested = (shared / "nested-skills.md").read_text()
        self.assertIn("sibling `../NAME/SKILL.md`", nested)
        self.assertIn("On direct or nested entry", skill)
        self.assertEqual((shared / "native-issue-index.py").read_bytes(), Path(index_helper.__file__).read_bytes())
        policy = (shared / "native-issue-links.md").read_text()
        self.assertIn("(../_shared/native-issue-links.md)", skill)
        self.assertIn("Validated full parent issue URL in native mode", skill)
        self.assertIn("database ID", policy)
        self.assertIn("replace_parent=true", policy)
        self.assertIn("After every intended child verifies", policy)
        self.assertIn("one plain bullet per child", policy)
        creation = skill.split("## Phase 7:", 1)[1].split("## Phase 8:", 1)[0]
        self.assertLess(creation.index("separate Phase 7 absorption decision"),
                        creation.index('gh issue create --repo "$RC_TRUSTED_REPO"'))
        self.assertIn('${ISSUE_CONFIG_OID:?use the revision recorded at intake}', creation)
        native, tasklist = creation.split("**Tasklist mode only, Steps 3 and 4.**")
        self.assertIn("Run Step 2 for each newly created issue", native)
        self.assertNotIn("gh issue edit PARENT --body-file", native)
        self.assertIn("gh issue edit PARENT --body-file", tasklist)

    def test_coverage_uses_exact_default_config(self):
        entry = fleet.resolve(self.cache, "enhanced-pr-review")
        helper = entry.with_name("review-coverage.sh")
        gh = self.tmp / "gh"
        gh.write_text("""
#!/usr/bin/env bash
case "$*" in
  'api repos/acme/example/pulls/5')
    echo '{"head":{"sha":"1111111111111111111111111111111111111111"},"user":{"login":"author"}}' ;;
  'api graphql '*)
    echo '{"data":{"repository":{"nameWithOwner":"acme/example","defaultBranchRef":{"target":{"oid":"2222222222222222222222222222222222222222","tree":{"oid":"3333333333333333333333333333333333333333"}}}}}}' ;;
  'api repos/acme/example/git/trees/3333333333333333333333333333333333333333')
    echo '{"truncated":false,"tree":[]}' ;;
  'api --paginate --slurp repos/acme/example/'*)
    echo '[[]]' ;;
  *) exit 9 ;;
esac
""".lstrip())
        gh.chmod(0o700)
        env = {"PATH": str(self.tmp) + os.pathsep + os.environ["PATH"]}
        for expected, code in (("2"*40, 1), ("4"*40, 2)):
            result = subprocess.run(["bash", helper, "5", "acme/example", expected],
                                    env=env, capture_output=True, text=True, check=False)
            self.assertEqual(result.returncode, code, result.stderr)
        self.assertIn("cannot verify default-commit configuration", result.stderr)

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

    def test_collision_only_role_binding(self):
        renderer_path = fleet.ROOT / "scripts/render-agent-profiles.py"
        import runpy
        renderer = runpy.run_path(str(renderer_path))
        for platform in ("claude", "codex"):
            stage = self.tmp / platform
            stage.mkdir(mode=0o700)
            for name in ("architect", "security-reviewer"):
                self.assertIn(name, renderer["PROFILES"][platform][2])
            command = [sys.executable, "-I", "-B", str(renderer_path), platform, str(stage),
                       "--fleet-alias", "architect", "--fleet-alias", "security-reviewer"]
            subprocess.run(command, check=True)
            directory, suffix, _ = renderer["PROFILES"][platform]
            root = stage / directory
            self.assertEqual({p.name for p in root.iterdir()},
                             {"fleet-architect" + suffix, "fleet-security-reviewer" + suffix})
            canonical = root / ("architect" + suffix)
            fallback = root / ("fleet-architect" + suffix)
            canonical.write_text("benign project-owned architect")
            args = ["--select-role", "architect", "--platform", platform, "--project", str(stage)]
            with redirect_stdout(io.StringIO()) as out:
                self.assertEqual(fleet.main(args), 0)
            selected = json.loads(out.getvalue())
            self.assertEqual(selected["native_name"], "fleet-architect")
            self.assertEqual(selected["profile"], str(fallback))
            self.assertEqual(selected["sha256"], fleet.verified_role(platform, "architect", fallback))
            self.assertEqual(canonical.read_text(), "benign project-owned architect")
            # Compare the whole native file with only its declared identity normalized.
            source = renderer["profile_bytes"](platform, "architect")
            self.assertEqual(fallback.read_bytes().replace(b"fleet-architect", b"architect", 1), source)
            self.assertTrue(subprocess.run(command, capture_output=True).returncode)
            canonical.write_bytes(source)
            self.assertEqual(fleet.select_role(platform, "architect", stage)["native_name"], "architect")
            canonical.unlink()
            fallback.write_text("foreign fallback")
            with self.assertRaises(ValueError):
                fleet.select_role(platform, "architect", stage)
        with self.assertRaises(ValueError):
            fleet.select_role("claude", "architect", Path("relative"))
        for platform, role in (("copilot", "code-reviewer"), ("claude", "feedback-analyst")):
            with self.assertRaises(ValueError):
                renderer["fleet_alias_name"](platform, role)
        with redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
            fleet.main(["--select-role", "architect", "--platform", "claude"])

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
        with self.assertRaises((OSError, ValueError)):
            fleet.cache_root(self.cache)
        if os.getuid() != 0:
            with self.assertRaises((OSError, ValueError)):
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
        with self.assertRaises((OSError, ValueError)):
            fleet.cache_root(self.cache)
        with redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
            fleet.main(["--cache", str(self.cache), "--skill", "../another"])

    def test_created_directory_requires_verified_descriptor_ownership(self):
        from types import SimpleNamespace
        seen = []
        actual = os.fstat

        def different_owner(fd):
            st = actual(fd)
            if (self.tmp / "new-parent").exists() and st.st_ino == (self.tmp / "new-parent").stat().st_ino:
                seen.append(st.st_ino)
                return SimpleNamespace(st_uid=os.getuid()+1, st_mode=st.st_mode)
            return st

        with patch.object(fleet.os, "fstat", side_effect=different_owner), self.assertRaises(ValueError):
            fleet.cache_root(self.tmp / "new-parent/cache")
        self.assertTrue(seen)
        self.assertFalse((self.tmp / "new-parent/cache").exists())

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
