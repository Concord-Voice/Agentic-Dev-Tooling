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
        self.title = "existing title"
        self.parent_of_child = self.parent

    def transport(self, argv, **options):
        self.assertTrue(options["capture_output"])
        self.calls.append(argv)
        packet = json.loads(options["input"])
        if "PATCH" in argv:
            self.assertEqual(argv, ["gh", "api", "--hostname", "github.com", "--method", "PATCH",
                                    "repos/example/parent/issues/2", "--input", "-", "--silent"])
            self.assertEqual(set(packet), {"body"})
            self.body = packet["body"]
            return subprocess.CompletedProcess(argv, 0, b"", b"")
        self.assertEqual(argv, ["gh", "api", "--hostname", "github.com", "graphql", "--input", "-"])
        url = packet["variables"]["url"]
        issue = {"__typename": "Issue", "url": url}
        if packet["query"] == index_helper.META:
            issue["fullDatabaseId"] = "4000000000"
            issue["parent"] = {"url": self.parent_of_child} if url == self.child and self.parent_of_child else None
        elif packet["query"] == index_helper.CHILD:
            self.assertEqual(url, self.child)
            issue["title"] = self.title
            issue["parent"] = {"url": self.parent_of_child} if self.parent_of_child else None
        else:
            self.assertEqual(packet["query"], index_helper.BODY)
            self.assertEqual(url, self.parent)
            issue["body"] = self.body
        data = {"data": {"resource": issue}}
        return subprocess.CompletedProcess(argv, 0, json.dumps(data).encode(), b"")

    def run_cli(self, *args, expect_pending=False):
        out, err = io.StringIO(), io.StringIO()
        with patch.object(sys, "argv", ["helper", *args]), redirect_stdout(out), redirect_stderr(err):
            if expect_pending:
                with self.assertRaises(SystemExit) as raised:
                    index_helper.main()
                self.assertEqual(raised.exception.code, 2)
            else:
                index_helper.main()
        self.assertEqual(err.getvalue(), "")
        for source_text in ("private text", "private [sample]", r"private \[sample\]", "private body", "private error"):
            self.assertNotIn(source_text, out.getvalue())
        return json.loads(out.getvalue())

    def test_real_cli_boundary_and_retry(self):
        with patch.object(index_helper.subprocess, "run", self.transport):
            self.assertEqual(self.run_cli("inspect", self.child),
                             {"url": self.child, "parent": self.parent, "database_id": 4000000000})
            result = self.run_cli("index", self.parent, self.child, expect_pending=True)
            self.assertEqual(result["missing_rows"], ["- example/child#2"])
            self.assertRegex(result["digest"], r"^[a-f0-9]{64}$")
            self.assertEqual(self.body, self.original)
            self.body = self.original.replace("## Sub-Issues\n\n## Criteria",
                             "## Sub-Issues\n- example/child#2 — existing title\n\n## Criteria")
            self.assertEqual(self.run_cli("index", self.parent, self.child)["status"], "current")
            self.assertFalse(any("PATCH" in args for args in self.calls))

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
            if json.loads(opts["input"])["query"] == index_helper.BODY:
                self.body = old + "concurrent change\n"
            return result
        with patch.object(index_helper.subprocess, "run", concurrent):
            result = self.run_cli("index", self.parent, self.child, expect_pending=True)
            self.assertEqual(result["missing_rows"], ["- example/child#2"])
            self.assertRegex(result["digest"], r"^[a-f0-9]{64}$")
        self.assertIn("concurrent change", self.body)
        self.assertFalse(any("PATCH" in args for args in self.calls))

    def test_confirmed_edit_preserves_body_and_sends_titled_rows_as_data(self):
        self.title = "private [sample]"
        old = self.original.replace("## Sub-Issues\n\n## Criteria",
                                    "## Sub-Issues\n- #77 — Other\n- example/child#2\n\n## Criteria")
        self.body = old
        with patch.object(index_helper.subprocess, "run", self.transport):
            preview = self.run_cli("index", "--private-preview", self.parent, self.child, expect_pending=True)
            rows_file = Path(preview["preview_file"])
            self.addCleanup(rows_file.unlink)
            self.assertEqual(rows_file.parent, Path(tempfile.gettempdir()).resolve())
            row = r"- example/child#2 — private \[sample\]"
            self.assertEqual(rows_file.read_text(), row + "\n")
            self.assertEqual(rows_file.stat().st_mode & 0o777, 0o600)
            result = self.run_cli("apply-index", "--exclusive-parent", self.parent,
                                  "--confirmed-digest", preview["digest"], self.child)
            self.assertEqual(result["status"], "current")
            self.assertEqual(self.body, old.replace("- example/child#2\n", row + "\n"))
            self.run_cli("index", self.parent, self.child)
            self.assertEqual(sum("PATCH" in argv for argv in self.calls), 1)

    def test_private_preview_uses_fresh_files_and_rejects_output_paths(self):
        with patch.object(index_helper.subprocess, "run", self.transport):
            receipt = self.run_cli("index", self.parent, self.child, expect_pending=True)
            self.assertNotIn("preview_file", receipt)
            previews = []
            for _ in range(2):
                receipt = self.run_cli("index", "--private-preview", self.parent, self.child, expect_pending=True)
                path = Path(receipt["preview_file"])
                self.addCleanup(path.unlink)
                previews.append(path)
            self.assertNotEqual(*previews)
            with redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
                self.run_cli("index", "--rows-file", str(previews[0]), self.parent, self.child)

    def test_preview_cleanup_resumes_from_retained_intake_after_temp_directory_changes(self):
        policy = (fleet.EDITION / "native-issue-links.md").read_text()
        cleanup = policy.split("### Remove the private preview", 1)[1].split("```bash\n", 1)[1].split("\n```", 1)[0]
        with tempfile.TemporaryDirectory() as intake, tempfile.TemporaryDirectory() as first, \
                tempfile.TemporaryDirectory() as later:
            record = Path(intake) / "native-index-receipt.abcdef12"
            with patch.dict(os.environ, {"TMPDIR": first}), patch.object(tempfile, "tempdir", None), \
                    patch.object(index_helper.subprocess, "run", self.transport):
                with record.open("x") as output, redirect_stdout(output), \
                        patch.object(sys, "argv", ["helper", "index", "--private-preview", self.parent, self.child]), \
                        self.assertRaises(SystemExit) as pending:
                    index_helper.main()
                self.assertEqual(pending.exception.code, 2)
                other = self.run_cli("index", "--private-preview", self.parent, self.child, expect_pending=True)
            receipt = json.loads(record.read_bytes())
            selected = Path(receipt["preview_file"])
            unrelated = Path(other["preview_file"])
            self.assertEqual(selected.parent, Path(first).resolve())
            self.assertEqual(selected.read_text(), "- example/child#2 — existing title\n")
            env = {**os.environ, "TMPDIR": later, "PREVIEW_RECORD": str(record), "ISSUE_DRAFT": intake}
            subprocess.run(["bash", "-c", cleanup], env=env, check=True, capture_output=True)
            self.assertFalse(selected.exists())
            self.assertTrue(unrelated.is_file())
            subprocess.run(["bash", "-c", cleanup], env=env, check=True, capture_output=True)

            selected.write_text("replacement")
            result = subprocess.run(["bash", "-c", cleanup], env=env, capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn(b"Preview identity changed", result.stderr)
            self.assertEqual(selected.read_text(), "replacement")
            self.assertTrue(record.is_file())
            # The workflow never accepts a receipt outside the retained owner-only intake.
            different = Path(later) / record.name
            different.write_text(json.dumps(other))
            result = subprocess.run(["bash", "-c", cleanup], env={**env, "PREVIEW_RECORD": str(different)},
                                    capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertTrue(unrelated.is_file())

    def test_incomplete_preview_is_removed_before_any_receipt(self):
        def interrupted():
            yield "- example/child#2 — Sample"
            raise OSError("fixture write interrupted")
        with tempfile.TemporaryDirectory() as tmp, patch.dict(os.environ, {"TMPDIR": tmp}), \
                patch.object(tempfile, "tempdir", None):
            with self.assertRaisesRegex(OSError, "fixture write interrupted"):
                index_helper.private_preview_file(interrupted())
            self.assertEqual(list(Path(tmp).iterdir()), [])

    def test_stale_title_or_body_invalidates_confirmation(self):
        with patch.object(index_helper.subprocess, "run", self.transport):
            preview = self.run_cli("index", self.parent, self.child, expect_pending=True)
            for change in ("title", "body"):
                with self.subTest(change=change):
                    self.title = "new" if change == "title" else "existing title"
                    self.body = self.original if change == "title" else self.original + "new edit"
                    with self.assertRaisesRegex(SystemExit, "index preview changed"):
                        self.run_cli("apply-index", "--exclusive-parent", self.parent,
                                     "--confirmed-digest", preview["digest"], self.child)
            self.assertFalse(any("PATCH" in argv for argv in self.calls))

    def test_ambiguous_submission_reads_back_without_retry(self):
        def changed_after_submission(argv, **opts):
            if "PATCH" in argv:
                self.calls.append(argv)
                raise subprocess.TimeoutExpired("gh", 30)
            return self.transport(argv, **opts)
        with patch.object(index_helper.subprocess, "run", changed_after_submission):
            preview = self.run_cli("index", self.parent, self.child, expect_pending=True)
            with self.assertRaisesRegex(SystemExit, "unverified"):
                self.run_cli("apply-index", "--exclusive-parent", self.parent,
                             "--confirmed-digest", preview["digest"], self.child)
            self.assertEqual(sum("PATCH" in argv for argv in self.calls), 1)

    def test_append_and_create_index_preserve_unrelated_sections(self):
        titles = {self.child: "Child"}
        row = "- example/child#2 — Child"
        pairs = [
            ("Context", f"Context\n\n## Sub-Issues\n{row}\n"),
            ("## Sub-Issues", f"## Sub-Issues\n{row}\n"),
            ("## Sub-Issues\r\n## Criteria\r\n- [ ] Keep\r\n",
             f"## Sub-Issues\r\n{row}\r\n\r\n## Criteria\r\n- [ ] Keep\r\n"),
        ]
        for body, expected in pairs:
            with self.subTest(body=body):
                candidate, rows = index_helper.plan_index(body, self.parent, titles)
                self.assertEqual(candidate, expected)
                self.assertEqual(list(rows.values()), [row])
                self.assertEqual(index_helper.plan_index(candidate, self.parent, titles), (candidate, {}))

    def test_annotated_rows_and_nested_sections_keep_parent_unchanged(self):
        examples = (
            "## Sub-Issues\n- example/child#2 — existing title (owner note)",
            "## Sub-Issues\n- example/child#2 — previous title",
            "- Operator checklist\n  ## Sub-Issues\n  - pending",
            "- Outer list\n    ## Sub-Issues",
            "- ## Sub-Issues",
            "> ## Sub-Issues",
            "## Sub-Issues\n- #77 — Existing\n  ## Nested details",
        )
        with patch.object(index_helper.subprocess, "run", self.transport):
            for body in examples:
                with self.subTest(body=body):
                    self.body = body
                    with self.assertRaises(SystemExit):
                        self.run_cli("apply-index", "--exclusive-parent", self.parent,
                                     "--confirmed-digest", "unused", self.child)
                    self.assertEqual(self.body, body)
            self.assertFalse(any("PATCH" in argv for argv in self.calls))

    def test_dot_prefixed_repository_names(self):
        for repo in (".github", ".dotfiles"):
            url = f"https://github.com/example/{repo}/issues/2"
            self.assertEqual(index_helper.identity(url), ("example", repo, "2"))
            row = f"- example/{repo}#2"
            self.assertEqual(set(index_helper.existing_children([row], "example/root")), {(f"example/{repo}", "2")})
        for repo in (".", ".."):
            with self.assertRaises(index_helper.Pending):
                index_helper.identity(f"https://github.com/example/{repo}/issues/2")
            with self.assertRaises(index_helper.Pending):
                index_helper.existing_children([f"- example/{repo}#2"], "example/root")

    def test_unsupported_html_blocks_leave_the_index_pending(self):
        for opener, closer in (("<![CDATA[", "]]>"), ("<?instruction", "?>"), ("<!DECLARATION", ">")):
            body = "\n".join([opener, "## Sub-Issues", "## Other", closer])
            with self.subTest(opener=opener), self.assertRaisesRegex(index_helper.Pending, "HTML"):
                index_helper.plan_index(body, self.parent, {self.child: "Sample"})

    def test_headings_inside_html_comments(self):
        for end in ("-->", "--!>"):
            with self.subTest(end=end):
                lines = ["<!-- comment " + end, "<!-- first", "## hidden", end + " <!-- next",
                         "## still hidden", end, "## Sub-Issues"]
                self.assertEqual(index_helper.markdown_headings(lines), [6])

    def test_index_sections_and_same_number_across_repos(self):
        children = {self.child: "Other repo", self.parent.replace("/2", "/7"): "Same repo"}
        current = "## Sub-Issues\r\n- #7 — Same repo\r\n"
        self.assertEqual(list(index_helper.plan_index(current, self.parent, children)[1]), ["- example/child#2"])
        self.assertEqual(list(index_helper.plan_index("Context", self.parent, children)[1]), ["- example/child#2", "- example/parent#7"])
        for body in ["Sub-Issues\n----------\n- example/child#2", "## Sub-Issues <!-- hidden -->\n- #2",
                     "## Sub-Issues\n### Backend\n- example/child#2", "## Sub-Issues\n## Sub-Issues\n", "## Sub-Issues\n- [ ] #2", "```\n",
                     "<!--private", "<pre>\n## Sub-Issues\n", "## Sub-Issues\n- #7\n- example/parent#7"]:
            with self.subTest(body=body), self.assertRaises(index_helper.Pending):
                index_helper.plan_index(body, self.parent, children)


class FleetWorkflowTests(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.tmp = Path(tmp.name).resolve()
        self.cache = self.tmp / "cache"

    def test_missing_posix_ownership_stops_before_cache_or_role_lookup(self):
        for args in (["--cache", str(self.cache), "--skill", "dev-lifecycle"],
                     ["--project", str(self.tmp), "--platform", "codex", "--select-role", "architect"],
                     ["--profile", str(self.tmp), "--platform", "claude", "--verify-role", "architect"]):
            with self.subTest(args=args), patch.object(os, "getuid", None, create=True), \
                    patch.object(fleet, "edition") as edition, patch.object(fleet, "select_role") as select, \
                    patch.object(fleet, "verified_role") as verify, redirect_stderr(io.StringIO()) as err:
                self.assertEqual(fleet.main(args), 1)
                self.assertIn("inside WSL", err.getvalue())
                edition.assert_not_called()
                select.assert_not_called()
                verify.assert_not_called()
                self.assertFalse(self.cache.exists())

    def test_acl_reader_handles_native_results(self):
        import ctypes
        import errno
        from unittest.mock import Mock

        lib = Mock()
        principal = ctypes.create_string_buffer(bytes(range(16)), 16)
        lib.acl_get_fd.return_value = 123
        lib.acl_get_qualifier.return_value = ctypes.addressof(principal)
        lib.acl_free.return_value = 0

        def tag_result(entry, out):
            out._obj.value = tag
            return 0

        def rights_result(entry, out):
            out._obj.value = mask
            return 0

        def next_entry(acl, index, out):
            if index == 0:
                out._obj.value = 1234
                return 0
            ctypes.set_errno(errno.EINVAL)
            return -1

        def identify(uid, out):
            out[:] = bytes(range(16)) if owner else bytes(16)
            return 0

        lib.acl_get_entry.side_effect = next_entry
        lib.acl_get_tag_type.side_effect = tag_result
        lib.acl_get_permset_mask_np.side_effect = rights_result
        lib.mbr_uid_to_uuid.side_effect = identify
        with patch.object(sys, "platform", "darwin"), patch.object(ctypes, "CDLL", return_value=lib):
            for tag, mask, owner, private, accepted in [
                (2, 0xffff, False, True, True), (1, 2, False, False, True),
                (1, 2, False, True, False), (1, 4, False, False, False),
                (1, 4, True, True, True), (99, 0, False, False, False),
            ]:
                with self.subTest(tag=tag, mask=mask, owner=owner, private=private):
                    if accepted:
                        fleet.check_darwin_cache_acl(4, private=private)
                    else:
                        with self.assertRaises(ValueError):
                            fleet.check_darwin_cache_acl(4, private=private)
            lib.acl_get_fd.return_value = None
            ctypes.set_errno(errno.ENOENT)
            fleet.check_darwin_cache_acl(4)
            ctypes.set_errno(errno.EACCES)
            with self.assertRaises(OSError):
                fleet.check_darwin_cache_acl(4)

    @unittest.skipUnless(sys.platform == "darwin", "uses macOS filesystem ACLs")
    def test_darwin_cache_acl(self):
        with tempfile.TemporaryDirectory() as tmp:
            parent = Path(tmp).resolve()
            folder = parent / "fixture"
            folder.mkdir(mode=0o700)
            fd = os.open(folder, os.O_RDONLY | os.O_DIRECTORY)
            try:
                def grant(ace):
                    subprocess.run(["/bin/chmod", "+a", ace, folder], check=True)
                fleet.check_darwin_cache_acl(fd, private=True)
                # A named owner entry can carry permissions on the owner's own directory.
                import pwd
                grant("user:" + pwd.getpwuid(os.getuid()).pw_name + " allow writeattr")
                fleet.check_darwin_cache_acl(fd, private=True)
                grant("group:everyone allow readattr")
                fleet.check_darwin_cache_acl(fd)
                with self.assertRaisesRegex(ValueError, "untrusted macOS cache ACL"):
                    fleet.check_darwin_cache_acl(fd, private=True)
                grant("group:everyone allow writeattr,directory_inherit")
                with self.assertRaisesRegex(ValueError, "untrusted macOS cache ACL"):
                    fleet.check_darwin_cache_acl(fd)
                child = folder / "empty"
                child.mkdir(mode=0o700)
                child_fd = os.open(child, os.O_RDONLY | os.O_DIRECTORY)
                try:
                    with self.assertRaisesRegex(ValueError, "untrusted macOS cache ACL"):
                        fleet.check_darwin_cache_acl(child_fd)
                finally:
                    os.close(child_fd)
            finally:
                os.close(fd)

    @unittest.skipUnless(sys.platform == "darwin", "uses macOS filesystem ACLs")
    def test_resolver_checks_acl_before_creating_cache(self):
        ancestor = self.tmp / "ancestor"
        ancestor.mkdir(mode=0o700)
        subprocess.run(["/bin/chmod", "+a", "group:everyone allow writeattr", ancestor], check=True)
        cache = ancestor / "new-cache"
        with self.assertRaisesRegex(ValueError, "untrusted macOS cache ACL"):
            fleet.resolve(cache, "issue-creation")
        self.assertFalse(cache.exists())

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
        for root in (edition, fleet.ROOT / fleet.CORE):
            review = (root / "enhanced-pr-review/SKILL.md").read_text()
            lifecycle = (root / "dev-lifecycle/SKILL.md").read_text()
            reference = "references/maintainer-decisions.md"
            self.assertIn(reference, review.split("**Step 3**", 1)[0])
            self.assertIn(reference, review.split("### 6.0", 1)[1].split("### 6.1", 1)[0])
            self.assertIn(reference, lifecycle.split("## Phase 8: FINAL", 1)[1].split("## Phase 9:", 1)[0])
            self.assertIn(reference, lifecycle.split("### Step 9.2", 1)[1])
            reconcile = review.split("## Phase 3.5", 1)[1].split("### 3.5.3", 1)[0]
            self.assertIn("only human findings needs no separate reconciliation post", reconcile)
            self.assertIn("When a bot or rostered machine reviewer spoke", reconcile)
            approval = review.split("### 6.2", 1)[1].split("### 6.3", 1)[0]
            self.assertIn("link the existing written decisions directly", approval)
            self.assertIn("no findings, report zero and omit the links", approval)
            self.assertNotIn("exactly one place", approval)
            self.assertIn("For human-only findings, link each source", lifecycle)
            rules = (root / "enhanced-pr-review" / reference).read_text()
            for term in ("--maintainer-sources", "--formal-state", "each actionable finding",
                         "no special human-comment marker", "new or edited entries"):
                self.assertIn(term, rules)
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

    def test_arrival_monitor_uses_pre_identity_snapshots(self):
        served = fleet.resolve(self.cache, "dev-lifecycle")
        native = fleet.ROOT / fleet.CORE / "dev-lifecycle/SKILL.md"
        for entry in (native, served):
            with self.subTest(entry=entry):
                tick = entry.read_text().split("  TYPED=$(", 1)[1].split("  cur_head=$(", 1)[0]
                reads, verdicts = tick.split("  VERIFIED_APPS=$(", 1)
                self.assertEqual(reads.count("gh pr view <PR> --json reviews,comments,statusCheckRollup"), 1)
                self.assertEqual(reads.count("gh pr view <PR> --json comments"), 1)
                self.assertNotIn("gh pr view <PR>", verdicts)
                self.assertIn("""{ printf '%s' "$PR_VIEW" """, verdicts)
                self.assertIn("""&& printf '%s' "$PR_COMMENTS" """, verdicts)
                self.assertIn("""nv_now=$( printf '%s' "$PR_COMMENTS" """, verdicts)

    def test_arrival_snapshot_requires_positive_app_identity(self):
        skill = fleet.resolve(self.cache, "dev-lifecycle").read_text()
        start = skill.index("  VERIFIED_APPS=$(")
        end = skill.index("  now=$( set -o pipefail", start)
        snippet = skill[start:end].replace("<owner>/<repo>", "example/project").replace("<PR>", "7")

        def item(node, login):
            return {"id": node, "author": {"login": login}}

        comments = [item("comment-1", "reviewer"), item("pending", "reviewer"), item("manual", "maintainer")]
        reviews = [item("review-1", "reviewer"), item("unconfirmed", "reviewer")]
        rollup = [{"name": "unit checks"}]
        view = {"comments": comments, "reviews": reviews, "statusCheckRollup": rollup}
        environment = {
            **os.environ,
            "TYPED": '["reviewer"]',
            "PR_VIEW": json.dumps(view),
            "PR_COMMENTS": json.dumps({"comments": comments}),
        }
        # Only the first comment and review have a matching Bot identity on their REST endpoint.
        fixture = """gh() {
            case "$3" in
              */issues/*) echo '[{"node_id":"comment-1","user":{"login":"Reviewer[bot]","type":"Bot"}}]';;
              */pulls/*) echo '[{"node_id":"review-1","user":{"login":"reviewer[bot]","type":"Bot"}}]';;
              *) return 1;;
            esac
        }
        """
        result = subprocess.run(["bash", "-c", fixture + snippet + 'echo "$PR_VIEW"; echo "$PR_COMMENTS"'],
                                env=environment, capture_output=True, text=True, check=True)
        filtered_view, filtered_comments = map(json.loads, result.stdout.splitlines())
        expected_comments = [comments[0], comments[2]]
        self.assertEqual(filtered_view, {"comments": expected_comments, "reviews": reviews[:1],
                                         "statusCheckRollup": rollup})
        self.assertEqual(filtered_comments, {"comments": expected_comments})

    def test_served_lifecycle_approval_matrix_and_dispatch_contract(self):
        entry = fleet.resolve(self.cache, "dev-lifecycle")
        dev = entry.read_text()
        shared = entry.parent.parent / "_shared"
        matrix = dev.split("### Mode-to-gate matrix (canonical)", 1)[1].split("\n\n", 2)[1]
        rows = [[col.strip() for col in line.strip("|").split("|")] for line in matrix.splitlines()]
        self.assertEqual(rows[0], ["Phase", "In-the-Loop", "On-the-Loop", "Automated End-to-End"])
        gate, auto = "**Gate**", "Auto"
        self.assertEqual(rows[2:], [
            ["1 UNDERSTAND", auto, auto, auto], ["2 PLAN", gate, gate, auto],
            ["3 EXECUTE", auto, auto, auto], ["4 VALIDATE", auto, auto, auto],
            ["5 COMMIT+DRAFT PR", gate, auto, auto], ["6 CI MONITOR", auto, auto, auto],
            ["7 READY", gate, auto, auto], ["7.5 WAIT FOR BOT REVIEWS", "Auto†", "Auto†", "Auto†"],
            ["8 FINAL REVIEW", auto, gate, auto], ["9 MERGE-READY", gate, gate, gate],
        ])
        for marker in ("suggested mode is always `On-the-Loop`", "confirmed persisted mode-state file ALWAYS wins",
                       "retain subsequent independent review, waiting and merge gates under every mode"):
            self.assertIn(marker, dev)
        phase3 = dev.split("\n## Phase 3:", 1)[1].split("\n## Phase 4:", 1)[0]
        self.assertIn("../_shared/lifecycle-agent-dispatch.md", phase3)
        self.assertIn("Keep dispatch decisions with the parent", phase3)
        phase4 = dev.split("\n## Phase 4:", 1)[1].split("\n## Phase 5:", 1)[0]
        self.assertIn("count-drift probe", phase4)
        self.assertIn(".docs.counts_script", phase4)
        issue = fleet.resolve(self.cache, "issue-creation").read_text()
        for skill in (dev, issue):
            self.assertIn("../_shared/context7-docs-discipline.md", skill)
        self.assertIn("The rule (MANDATORY)", (shared / "context7-docs-discipline.md").read_text())
        self.assertIn("record the earlier attempts and return the decision to the maintainer",
                      (shared / "lifecycle-agent-dispatch.md").read_text())
        catalog = (shared / "dispatchable-skills.md").read_text()
        self.assertIn("Only the entries here can transfer control", catalog)
        self.assertIn("billed or manual approval attached to the original step remains binding", catalog)

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
        self.assertIn("version epic governed by a REST-only rule", skill)
        lifecycle = fleet.resolve(self.cache, "dev-lifecycle").read_text()
        self.assertIn(".epic_linkage.version_epics` is absent or true", lifecycle)
        feature = lifecycle.split("### Parent-epic linkage check", 1)[1].split("#### Version-epic linkage", 1)[0]
        self.assertIn("fleet_load_issue_config", feature)
        self.assertIn("parent tasklist edit first", feature)
        self.assertIn("REST only as the fallback", feature)
        self.assertIn("native_rest", feature)
        self.assertIn("nested new-issue intake independently binds its own target", feature)
        self.assertNotIn("never a `- [ ] #N` tasklist", feature)
        creation = skill.split("## Phase 7:", 1)[1].split("## Phase 8:", 1)[0]
        self.assertLess(creation.index("separate Phase 7 absorption decision"),
                        creation.index('--method POST "repos/$RC_TRUSTED_REPO/issues"'))
        self.assertIn('${ISSUE_CONFIG_OID:?use the revision recorded at intake}', creation)
        native, tasklist = creation.split("**Tasklist mode only, Steps 3 and 4.**")
        self.assertIn("Run Step 2 for each newly created issue", native)
        self.assertNotIn("gh issue edit PARENT --body-file", native)
        self.assertIn("gh issue edit PARENT --body-file", tasklist)

    def test_create_request_from_preview_files_through_rendered_shell(self):
        entry = fleet.resolve(self.cache, "issue-creation")
        text = entry.read_text()
        control = 'case "${ISSUE_CREATE_CHOICE:-}" in'
        shell = control + text.split(control, 1)[1].split("\n```", 1)[0]
        template = 'cat "$ISSUE_DRAFT/before-rows.md"'
        prepare = template + text.split(template, 1)[1].split("\n```", 1)[0]
        title = 'Read "design" ($5) [draft]'
        body = "Overview\n\n* Draft body\n"
        (self.tmp / "title.txt").write_text(title + "\n")
        ending = "\n## Acceptance criteria\n- [ ] Preserve this independent criterion\n"
        body = body + "## Sub-Issues\n"
        rows = "- [ ] #8 — Existing child\n"
        (self.tmp / "before-rows.md").write_text(body)
        (self.tmp / "child-rows.md").write_text(rows)
        (self.tmp / "after-rows.md").write_text(ending)
        shared = self.tmp / "_shared"
        shared.mkdir()
        (shared / "repo-config.sh").write_text('fleet_load_issue_config() { [[ "$1" == example/test && "$2" == fixture ]]; }\n')
        env = {**os.environ, "ISSUE_DRAFT": str(self.tmp), "RC_TRUSTED_REPO": "example/test",
               "FLEET_SKILLS": str(self.tmp), "FLEET_TARGET_REPO": "example/test", "ISSUE_CONFIG_OID": "fixture"}
        subprocess.run(["bash", "-c", prepare], env=env, check=True)
        labels = ["type: feature", "area: cli"]
        (self.tmp / "labels.json").write_text(json.dumps(labels))
        # The fake API echoes only file data, just like an issue-creation response.
        fake = """gh() {
          echo call >> "$ISSUE_DRAFT/calls"
          [[ "$*" == "api --hostname github.com --method POST repos/example/test/issues --input $ISSUE_DRAFT/create.json" ]] || return 1
          jq '. + {html_url:"https://github.com/example/test/issues/7", number:7,
                   labels: [.labels[] | {name:.}], milestone: (if .milestone then {number:.milestone} else null end)}' "$ISSUE_DRAFT/create.json"
        }
"""
        for mode, number in (("create", ""), ("absorb", "23"), ("parent-only", "23")):
            with self.subTest(mode=mode):
                path = self.tmp / ("parent-only.md" if mode == "parent-only" else "body.md")
                oid = subprocess.check_output(["git", "hash-object", "--no-filters", "--", path], text=True).strip()
                approved = {**env, "MILESTONE_NUMBER": number, "ISSUE_CREATE_CHOICE": mode, "APPROVED_BODY_OID": oid}
                log = self.tmp / "calls"
                log.unlink(missing_ok=True)
                result = subprocess.run(["bash", "-c", fake + shell], env=approved,
                                        capture_output=True, text=True, check=True)
                self.assertEqual(log.read_text().splitlines(), ["call"])
                self.assertEqual(json.loads(result.stdout), {"url": "https://github.com/example/test/issues/7",
                                 "number": 7, "metadata_matches": True})
                request = json.loads((self.tmp / "create.json").read_bytes())
                self.assertEqual(request, {"title": title, "body": body + ("" if mode == "parent-only" else rows) + ending,
                                           "labels": labels, **({"milestone": int(number)} if number else {})})
        log.unlink()
        for mode in ("cancel", "missing-decision"):
            result = subprocess.run(["bash", "-c", fake + shell], env={**env, "ISSUE_CREATE_CHOICE": mode},
                                    capture_output=True)
            self.assertEqual(result.returncode == 0, mode == "cancel")
            self.assertFalse(log.exists())
        result = subprocess.run(["bash", "-c", fake + shell], env={**approved, "APPROVED_BODY_OID": "changed"},
                                capture_output=True)
        self.assertIn(b"Selected preview changed", result.stderr)
        self.assertFalse(log.exists())
        (self.tmp / "title.txt").write_text("first\nsecond")
        result = subprocess.run(["bash", "-c", fake + shell], env=approved, capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(b"Invalid issue draft", result.stderr)

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
        instructions = (fleet.EDITION / "nested-skills.md").read_text()
        self.assertIn("--verify-role ROLE --platform PLATFORM --profile ABSOLUTE_PATH", instructions)
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
            args = ["--verify-role", "architect", "--platform", platform,
                    "--profile", selected["profile"]]
            with redirect_stdout(io.StringIO()) as out:
                self.assertEqual(fleet.main(args), 0)
            self.assertEqual(selected["sha256"], out.getvalue().strip())
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
