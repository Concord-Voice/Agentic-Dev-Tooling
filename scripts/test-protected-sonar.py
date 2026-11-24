#!/usr/bin/env python3
"""Protected SonarCloud bridge: token scope in the workflow, and inert PR preparation.

Needs defusedxml: pip install --require-hashes --no-deps -r scripts/requirements-protected-sonar.txt
"""

import io
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
from urllib.error import HTTPError
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parent))
import protected_sonar as ps

WORKFLOW = Path(__file__).resolve().parents[1] / ".github/workflows/sonarcloud.yml"
HEAD, BASE = "a" * 40, "b" * 40
CANDIDATE = {"caller_run_id": 7, "caller_run_attempt": 2, "pr_number": 5, "head_sha": HEAD, "base_sha": BASE}


def jobs():
    """Split the workflow's jobs by their two-space-indented keys."""
    text = WORKFLOW.read_text(encoding="utf-8")
    body = text.split("\njobs:\n", 1)[1]
    parts = re.split(r"^  ([A-Za-z0-9_-]+):\n", body, flags=re.M)
    return text.split("\njobs:\n", 1)[0], dict(zip(parts[1::2], parts[2::2]))


class WorkflowTokenScope(unittest.TestCase):
    def test_token_only_in_environment_bound_main_job(self):
        header, found = jobs()
        self.assertNotIn("secrets.", header)
        holders = [name for name, body in found.items() if "secrets." in body]
        self.assertEqual(holders, ["sonarcloud"])
        body = found["sonarcloud"]
        self.assertEqual(body.count("secrets.SONAR_TOKEN"), 1)
        self.assertIn("    environment: protected-sonar\n", body)
        self.assertIn("github.ref == 'refs/heads/main'", body)
        self.assertNotIn("secrets: inherit", WORKFLOW.read_text(encoding="utf-8"))

    def test_pull_request_jobs_hold_no_secret_and_never_check_out_pr_into_scanner(self):
        _, found = jobs()
        for name in ("sync-coverage", "protected-sonar"):
            self.assertNotIn("secrets.", found[name])
            self.assertNotIn("environment:", found[name])
        self.assertIn("-f ref=main", found["protected-sonar"])
        self.assertIn("    permissions:\n      actions: write\n", found["protected-sonar"])
        # Main's checkout runs the preparer; the PR tree is only ever data.
        self.assertIn('/bin/python" -I -B scripts/protected_sonar.py', found["sonarcloud"])
        self.assertIn("pip install --only-binary=:all: --require-hashes --no-deps -r scripts/requirements-protected-sonar.txt", found["sonarcloud"])
        install = found["sonarcloud"].split("Install pinned XML parser", 1)[1].split("- name:", 1)[0]
        self.assertNotIn("SONAR_TOKEN", install)
        self.assertNotIn("ref: ${{", found["sonarcloud"])
        self.assertIn("github.ref != 'refs/heads/main'", found["reject-disabled-dispatch"])


def run_record(**overrides):
    record = {"id": 7, "run_attempt": 2, "event": "pull_request", "path": ps.CALLER_PATH,
              "head_sha": HEAD, "status": "in_progress", "conclusion": None,
              "repository": {"full_name": ps.REPO}, "head_repository": {"full_name": ps.REPO},
              "pull_requests": [{"number": 5}], "run_started_at": "2026-11-23T10:00:00Z"}
    record.update(overrides)
    return record


def pr_record(head=HEAD, base=BASE, **overrides):
    record = {"number": 5, "state": "open", "head": {"sha": head, "ref": "feat/x y", "repo": {"full_name": ps.REPO}},
              "base": {"sha": base, "ref": "main"}}
    record.update(overrides)
    return record


def report(filename="scripts/tool.py", extra=""):
    return (f'<?xml version="1.0" ?>{extra}<!-- coverage.py --><coverage><sources><source>/w/x</source></sources>'
            f'<packages><package><classes><class filename="{filename}"/></classes></package></packages>'
            f'</coverage>').encode()


def zipped(name=ps.REPORT, data=None):
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w") as archive:
        archive.writestr(name, report() if data is None else data)
    return buffer.getvalue()


class CallerChecks(unittest.TestCase):
    def test_accepts_live_same_repo_caller(self):
        ps.check_caller(CANDIDATE, run_record(), pr_record())

    def test_names_each_failed_field(self):
        with self.assertRaisesRegex(ps.Reject, "event,path"):
            ps.check_caller(CANDIDATE, run_record(event="workflow_dispatch", path="x.yml"), pr_record())
        with self.assertRaisesRegex(ps.Reject, "status"):
            ps.check_caller(CANDIDATE, run_record(status="completed", conclusion="success"), pr_record())
        with self.assertRaisesRegex(ps.Reject, "id,run_attempt"):
            ps.check_caller(CANDIDATE, None, pr_record())

    def test_rejects_moved_or_fork_pr(self):
        for pr in (pr_record(head="c" * 40), pr_record(state="closed"),
                   pr_record(base={"sha": BASE, "ref": "dev"}),
                   {**pr_record(), "head": {"sha": HEAD, "ref": "x", "repo": {"full_name": "a/b"}}}):
            with self.assertRaises(ps.Reject):
                ps.pr_ok(CANDIDATE, pr)


class ReportData(unittest.TestCase):
    def test_rewrites_sources_to_analysis_root(self):
        out = ps.coverage_report(report(), {"scripts/tool.py"}, Path("/tmp/analysis"))
        self.assertIn(b"<source>/tmp/analysis</source>", out)
        self.assertNotIn(b"/w/x", out)
        self.assertTrue(out.startswith(b"<?xml version='1.0' encoding='utf-8'?>\n<coverage>"))
        self.assertTrue(out.endswith(b"<sources><source>/tmp/analysis</source></sources></coverage>"))

    def test_rejects_dtd_foreign_file_bad_encoding_and_shape(self):
        cases = (report(extra='<!DOCTYPE c [<!ENTITY e "x">]>'), report("scripts/other.py"),
                 report("../etc/passwd"), "<coverage>é</coverage>".encode("latin-1"),
                 b"<coverage>", b"<other/>", b"<coverage/>")
        for content in cases:
            with self.assertRaises(ps.Reject):
                ps.coverage_report(content, {"scripts/tool.py"}, Path("/a"))

    def test_rejects_entity_attacks_fail_closed(self):
        laughs = ('<!DOCTYPE lolz [<!ENTITY a "aaaa"><!ENTITY b "&a;&a;&a;&a;">'
                  '<!ENTITY c "&b;&b;&b;&b;">]>')
        xxe = '<!DOCTYPE c [<!ENTITY x SYSTEM "file:///etc/passwd">]>'
        for dtd in (laughs, xxe):
            content = report(extra=dtd).replace(b"<coverage>", b"<coverage>&x;" if "SYSTEM" in dtd else b"<coverage>&c;")
            with self.assertRaisesRegex(ps.Reject, "DTD"):
                ps.coverage_report(content, {"scripts/tool.py"}, Path("/a"))

    def test_parser_layer_rejects_when_text_check_is_bypassed(self):
        with patch.object(ps.DET, "fromstring", side_effect=ps.DefusedXmlException("x")), \
                self.assertRaisesRegex(ps.Reject, "DTD or entity"):
            ps.coverage_report(report(), {"scripts/tool.py"}, Path("/a"))

    def test_deeply_nested_report_is_rejected_not_crashed(self):
        deep = b"<coverage>" + b"<a>" * 5000 + b'<class filename="scripts/tool.py"/>' + b"</a>" * 5000 + b"</coverage>"
        with self.assertRaisesRegex(ps.Reject, "XML invalid"):
            ps.coverage_report(deep, {"scripts/tool.py"}, Path("/a"))

    def test_zip_rejects_oversize_report(self):
        with patch.object(ps, "MAX_REPORT", 10), self.assertRaisesRegex(ps.Reject, "ZIP shape"):
            ps.one_zip(zipped())

    def test_zip_has_exactly_the_report(self):
        self.assertEqual(ps.one_zip(zipped()), report())
        for data in (zipped("other.xml"), zipped(data=b""), b"not a zip"):
            with self.assertRaises(ps.Reject):
                ps.one_zip(data)

    def test_property_escaping(self):
        self.assertEqual(ps.property_value("a b=c:d#é\U0001F600"), "a\\ b\\=c\\:d\\#\\u00e9\\ud83d\\ude00")
        for value in ("", "a\nb", "x" * 300, None):
            with self.assertRaises(ps.Reject):
                ps.property_value(value)

    def test_safe_path_and_time(self):
        for path in ("/a", "a/../b", ".git/config", "a\\b", "a\x01"):
            with self.assertRaises(ps.Reject):
                ps.safe_path(path)
        for value in (None, "nope", "2026-11-23T10:00:00"):
            with self.assertRaises(ps.Reject):
                ps.timestamp(value)


def git(repo, *args):
    return subprocess.run(["git", "-C", str(repo), *args], env=ps.GIT_ENV, check=True,
                          capture_output=True, text=True).stdout.strip()


class FakeApi:
    def __init__(self, responses):
        self.responses = responses

    def request(self, path, limit=ps.MAX_API, binary=False):
        value = self.responses[path.split("?")[0]]
        return value.pop(0) if isinstance(value, list) else value


class Preparation(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp, ignore_errors=True)
        remote = self.tmp / "remote"
        remote.mkdir()
        git(remote, "init", "-q", "-b", "main")
        git(remote, "config", "user.email", "t@example.invalid")
        git(remote, "config", "user.name", "t")
        (remote / "scripts").mkdir()
        (remote / "scripts/tool.py").write_text("print(1)\n")
        git(remote, "add", ".")
        git(remote, "commit", "-qm", "base")
        self.base = git(remote, "rev-parse", "HEAD")
        (remote / "sonar-project.properties").write_text("sonar.sources=/\n")
        (remote / "leak").symlink_to("/etc/passwd")
        git(remote, "add", ".")
        git(remote, "commit", "-qm", "pr")
        self.head = git(remote, "rev-parse", "HEAD")
        git(remote, "update-ref", "refs/pull/5/head", self.head)
        git(remote, "reset", "-q", "--hard", self.base)
        self.remote = str(remote)
        self.candidate = {**CANDIDATE, "head_sha": self.head, "base_sha": self.base}

    def api(self, pr=None, artifacts=None):
        pr = pr or pr_record(self.head, self.base)
        artifact = {"id": 9, "name": ps.ARTIFACT, "created_at": "2026-11-23T10:05:00Z", "expired": False,
                    "workflow_run": {"id": 7}, "size_in_bytes": 100}
        return FakeApi({"/actions/runs/7/attempts/2": run_record(head_sha=self.head),
                        "/pulls/5": [pr, pr],
                        "/actions/runs/7/artifacts": {"artifacts": artifacts if artifacts is not None else [
                            artifact, {**artifact, "id": 8, "created_at": "2026-11-22T00:00:00Z"}]},
                        "/actions/artifacts/9/zip": zipped()})

    def test_prepares_inert_tree_with_trusted_properties(self):
        out, cov = self.tmp / "analysis", self.tmp / "cov.xml"
        ps.prepare(self.candidate, out, cov, self.api(), remote=self.remote)
        self.assertFalse((out / "leak").is_symlink())
        self.assertEqual((out / "leak").read_text(), "/etc/passwd")
        props = (out / "sonar-project.properties").read_text()
        self.assertNotIn("sonar.sources=/\n", props)
        self.assertIn("sonar.projectKey=Concord-Voice_Agentic-Dev-Tooling", props)
        self.assertIn("sonar.pullrequest.branch=feat/x\\ y", props)
        self.assertIn(f"sonar.scm.revision={self.head}", props)
        self.assertIn(f"<source>{out}</source>", cov.read_text())
        self.assertEqual(git(out, "rev-parse", "HEAD"), self.head)

    def test_rejects_pr_that_moves_during_preparation(self):
        api = self.api()
        api.responses["/pulls/5"] = [pr_record(self.head, self.base), pr_record("c" * 40, self.base)]
        with self.assertRaisesRegex(ps.Reject, "moved"):
            ps.prepare(self.candidate, self.tmp / "analysis", self.tmp / "cov.xml", api, remote=self.remote)
        self.assertFalse((self.tmp / "analysis").exists())

    def test_rejects_wrong_head_base_and_missing_artifact(self):
        cases = ((dict(self.candidate, base_sha="c" * 40), self.api(pr_record(self.head, "c" * 40))),
                 (dict(self.candidate, head_sha=self.base), None),
                 (self.candidate, self.api(artifacts=[])))
        for candidate, api in cases:
            if api is None:
                api = self.api(pr_record(self.base, self.base))
                api.responses["/actions/runs/7/attempts/2"] = run_record(head_sha=self.base)
            with self.assertRaises(ps.Reject):
                ps.prepare(candidate, self.tmp / "analysis", self.tmp / "cov.xml", api, remote=self.remote)

    def test_refuses_existing_outputs(self):
        (self.tmp / "analysis").mkdir()
        with self.assertRaisesRegex(ps.Reject, "absent"):
            ps.prepare(self.candidate, self.tmp / "analysis", self.tmp / "cov.xml", self.api())


class Response(io.BytesIO):
    def __enter__(self):
        return self

    def __exit__(self, *args):
        return False


class ApiClient(unittest.TestCase):
    def test_json_binary_redirect_and_bounds(self):
        api = ps.GitHub("t")
        with patch.object(ps, "OPEN", side_effect=lambda *a, **k: Response(b'{"a": 1}')):
            self.assertEqual(api.request("/x"), {"a": 1})
            with self.assertRaisesRegex(ps.Reject, "byte bound"):
                api.request("/x", limit=2)
        with patch.object(ps, "OPEN", return_value=Response(b"{")), self.assertRaisesRegex(ps.Reject, "JSON"):
            api.request("/x")
        good = HTTPError("u", 302, "m", {"Location": "https://p.blob.core.windows.net/z"}, None)
        bad = HTTPError("u", 302, "m", {"Location": "https://evil.example/z"}, None)
        with patch.object(ps, "OPEN", side_effect=[good, Response(b"zip")]) as opener:
            self.assertEqual(api.request("/z", binary=True), b"zip")
            self.assertNotIn("Authorization", opener.call_args_list[1].args[0].headers)
        for effect in ([bad], [HTTPError("u", 404, "m", {}, None)], [OSError()], [good, OSError()]):
            with patch.object(ps, "OPEN", side_effect=effect), self.assertRaises(ps.Reject):
                api.request("/z", binary=True)
        with self.assertRaises(ps.Reject):
            api.request("x")
        with self.assertRaises(ps.Reject):
            ps.GitHub("")

    def test_main_exit_codes(self):
        args = ["--caller-run-id", "7", "--caller-run-attempt", "2", "--pr-number", "5", "--head-sha", HEAD,
                "--base-sha", BASE, "--analysis-dir", "a", "--coverage-out", "c"]
        with patch.object(ps, "prepare") as prepare, patch.dict(ps.os.environ, {"GITHUB_TOKEN": "t"}):
            self.assertEqual(ps.main(args), 0)
            self.assertEqual(prepare.call_args.args[0], CANDIDATE)
            prepare.side_effect = ps.Reject("no")
            self.assertEqual(ps.main(args), 1)
        self.assertEqual(ps.main([*args[:-6], "--base-sha", "x", *args[-4:]]), 1)


if __name__ == "__main__":
    unittest.main()
