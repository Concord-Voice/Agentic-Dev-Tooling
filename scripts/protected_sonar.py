#!/usr/bin/env python3
"""Prepare a protected SonarCloud PR scan from a pull-request run's data.

This runs only in the main-loaded `sonarcloud` job that holds the Sonar token.
The pull-request run that dispatched it is PR-controlled, so nothing it says is
trusted: the IDs it passes are re-checked against the GitHub API, its coverage
report is parsed as bounded data, and the PR tree is written out as plain files
from Git objects. Nothing from the PR is executed, and the scanner reads the
main branch's sonar-project.properties.
"""

import argparse
from datetime import datetime, timezone
import io
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
from urllib.error import HTTPError
from urllib.parse import urlparse
from urllib.request import HTTPRedirectHandler, Request, build_opener
import xml.etree.ElementTree as ET
import zipfile


REPO = "Concord-Voice/Agentic-Dev-Tooling"
API = f"https://api.github.com/repos/{REPO}"
REMOTE = f"https://github.com/{REPO}.git"
ROOT = Path(__file__).resolve().parents[1]
CALLER_PATH = ".github/workflows/sonarcloud.yml"
ARTIFACT, REPORT = "sync-coverage", "sync-coverage.xml"
SHA = re.compile(r"[0-9a-f]{40}\Z")
LIVE = ("queued", "in_progress", "requested", "waiting", "pending")
MAX_API = 2 * 1024 * 1024
MAX_ZIP = 8 * 1024 * 1024
MAX_REPORT = 32 * 1024 * 1024
MAX_FILES = 20000
MAX_FILE = 16 * 1024 * 1024
MAX_TOTAL = 256 * 1024 * 1024
# Git must not read the runner's global or system config: a filter driver or
# hook configured there could run while the PR tree is written out.
GIT_ENV = {k: v for k, v in os.environ.items()
           if not k.startswith("GIT_") and k not in ("GITHUB_TOKEN", "GH_TOKEN", "SONAR_TOKEN")}
GIT_ENV.update(GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL=os.devnull, GIT_TERMINAL_PROMPT="0")


class Reject(Exception):
    """Required provenance or data-safety evidence is missing."""


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


OPEN = build_opener(NoRedirect()).open


def positive(value):
    return type(value) is int and value > 0


def sha(value):
    return isinstance(value, str) and SHA.fullmatch(value) is not None


def timestamp(value):
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except (AttributeError, ValueError):
        raise Reject("time invalid") from None
    if parsed.tzinfo is None:
        raise Reject("time zone missing")
    return parsed.astimezone(timezone.utc)


def safe_path(path):
    if (not isinstance(path, str) or not path or len(path.encode()) > 4096 or path.startswith("/")
            or "\\" in path or any(part in ("", ".", "..") or part.casefold() == ".git"
                                   for part in path.split("/"))
            or any(ord(c) < 32 or ord(c) == 127 for c in path)):
        raise Reject("unsafe path")
    return path


class GitHub:
    def __init__(self, token):
        if not token:
            raise Reject("GitHub token missing")
        self.token = token
        self.count = 0

    def request(self, path, limit=MAX_API, binary=False):
        self.count += 1
        if not path.startswith("/") or ".." in path.split("/") or self.count > 20:
            raise Reject("API path or request bound invalid")
        url = API + path
        headers = {"Accept": "application/vnd.github+json", "Authorization": f"Bearer {self.token}",
                   "X-GitHub-Api-Version": "2022-11-28", "User-Agent": "protected-sonar"}
        try:
            with OPEN(Request(url, headers=headers), timeout=20) as response:
                body = response.read(limit + 1)
        except HTTPError as exc:
            # Artifact ZIPs redirect to signed storage; follow once, without our token.
            location = exc.headers.get("Location", "") if exc.code in (302, 303, 307) else ""
            host = urlparse(location).hostname or ""
            if not binary or urlparse(location).scheme != "https" or not (
                    host.endswith(".actions.githubusercontent.com") or host.endswith(".blob.core.windows.net")):
                raise Reject(f"GitHub API HTTP {exc.code}") from None
            try:
                with OPEN(Request(location, headers={"User-Agent": "protected-sonar"}), timeout=30) as response:
                    body = response.read(limit + 1)
            except OSError:
                raise Reject("artifact download failed") from None
        except OSError:
            raise Reject("GitHub API unavailable") from None
        if len(body) > limit:
            raise Reject("API byte bound exceeded")
        if binary:
            return body
        try:
            return json.loads(body)
        except (ValueError, RecursionError):
            raise Reject("API JSON invalid") from None


def check_caller(candidate, run, pr):
    """The dispatching run and the PR must both still describe the candidate revision."""
    run = run if isinstance(run, dict) else {}
    links = run.get("pull_requests") if isinstance(run.get("pull_requests"), list) else []
    failed = [name for name, ok in (
        ("id", run.get("id") == candidate["caller_run_id"]),
        ("run_attempt", run.get("run_attempt") == candidate["caller_run_attempt"]),
        ("event", run.get("event") == "pull_request"),
        ("path", run.get("path") == CALLER_PATH),
        ("head_sha", run.get("head_sha") == candidate["head_sha"]),
        ("status", run.get("status") in LIVE and run.get("conclusion") is None),
        ("repository", (run.get("repository") or {}).get("full_name") == REPO),
        ("head_repository", (run.get("head_repository") or {}).get("full_name") == REPO),
        ("pull_requests", any(isinstance(p, dict) and p.get("number") == candidate["pr_number"]
                              for p in links)),
    ) if not ok]
    if failed:
        # Field names only, never values, so a rejection says which check failed.
        raise Reject("caller run invalid: " + ",".join(failed))
    pr_ok(candidate, pr)


def pr_ok(candidate, pr):
    head = pr.get("head") if isinstance(pr, dict) and isinstance(pr.get("head"), dict) else {}
    base = pr.get("base") if isinstance(pr, dict) and isinstance(pr.get("base"), dict) else {}
    if (pr.get("number") != candidate["pr_number"] or pr.get("state") != "open"
            or head.get("sha") != candidate["head_sha"] or (head.get("repo") or {}).get("full_name") != REPO
            or base.get("sha") != candidate["base_sha"] or base.get("ref") != "main"):
        raise Reject("PR revision moved or is not a same-repository PR to main")


def coverage_artifact(api, run_id, started):
    body = api.request(f"/actions/runs/{run_id}/artifacts?name={ARTIFACT}&per_page=100")
    items = body.get("artifacts") if isinstance(body, dict) else None
    if not isinstance(items, list):
        raise Reject("artifact inventory malformed")
    # A re-run keeps earlier attempts' artifacts; take only this attempt's.
    matches = [a for a in items if isinstance(a, dict) and a.get("name") == ARTIFACT
               and timestamp(a.get("created_at")) >= started]
    if len(matches) != 1:
        raise Reject("coverage artifact missing or duplicate")
    meta = matches[0]
    if (not positive(meta.get("id")) or meta.get("expired") is not False
            or (meta.get("workflow_run") or {}).get("id") != run_id
            or not positive(meta.get("size_in_bytes")) or meta["size_in_bytes"] > MAX_ZIP):
        raise Reject("coverage artifact provenance invalid")
    return api.request(f"/actions/artifacts/{meta['id']}/zip", MAX_ZIP, binary=True)


def one_zip(data):
    try:
        with zipfile.ZipFile(io.BytesIO(data)) as archive:
            entries = archive.infolist()
            if (len(entries) != 1 or entries[0].filename != REPORT or entries[0].flag_bits & 1
                    or not 0 < entries[0].file_size <= MAX_REPORT):
                raise Reject("coverage ZIP shape invalid")
            with archive.open(entries[0]) as stream:
                content = stream.read(MAX_REPORT + 1)
    except (zipfile.BadZipFile, EOFError, OSError, ValueError, NotImplementedError):
        raise Reject("coverage ZIP invalid") from None
    if len(content) != entries[0].file_size:
        raise Reject("coverage ZIP size mismatch")
    return content


def coverage_report(content, files, base):
    """Return the Cobertura report re-rooted at `base`, naming only files in the tree."""
    # Checked on strict UTF-8 text so a UTF-16 body cannot hide a DTD from it;
    # without a DTD no entity, internal or external, can be declared or expanded.
    try:
        text = content.decode("utf-8")
    except UnicodeDecodeError:
        raise Reject("coverage report is not UTF-8") from None
    if "<!DOCTYPE" in text.upper() or "<!ENTITY" in text.upper():
        raise Reject("coverage report declares a DTD")
    try:
        root = ET.fromstring(content)
    except (ET.ParseError, ValueError, RecursionError):
        raise Reject("coverage report XML invalid") from None
    if root.tag != "coverage":
        raise Reject("coverage report root invalid")
    classes = list(root.iter("class"))
    if not classes or any(safe_path(c.get("filename")) not in files for c in classes):
        raise Reject("coverage report names a file outside the PR tree")
    for sources in root.findall("sources"):
        root.remove(sources)
    ET.SubElement(root, "sources").append(ET.Element("source"))
    root.find("sources/source").text = str(base)
    return ET.tostring(root, encoding="utf-8", xml_declaration=True)


def git(repo, *args, limit=MAX_API):
    try:
        result = subprocess.run(["git", "-C", str(repo), *args], env=GIT_ENV, stdout=subprocess.PIPE,
                                stderr=subprocess.DEVNULL, timeout=300, check=True)
    except (OSError, subprocess.CalledProcessError, subprocess.TimeoutExpired):
        raise Reject("Git evidence unavailable") from None
    if len(result.stdout) > limit:
        raise Reject("Git output bound exceeded")
    try:
        return result.stdout.decode("utf-8")
    except UnicodeDecodeError:
        raise Reject("Git output encoding invalid") from None


def checkout(repo, candidate, remote):
    """Write the PR head as regular files and return their paths."""
    git(repo.parent, "init", "-q", str(repo))
    git(repo, "fetch", "-q", "--no-tags", remote, "+refs/heads/main:refs/remotes/origin/main",
        f"+refs/pull/{candidate['pr_number']}/head:refs/remotes/origin/pr")
    if git(repo, "rev-parse", "refs/remotes/origin/pr").strip() != candidate["head_sha"]:
        raise Reject("fetched PR revision changed")
    try:
        git(repo, "merge-base", "--is-ancestor", candidate["base_sha"], "refs/remotes/origin/main")
    except Reject:
        raise Reject("PR base is not on main") from None
    git(repo, "update-ref", "refs/heads/analysis", candidate["head_sha"])
    git(repo, "symbolic-ref", "HEAD", "refs/heads/analysis")
    files, total = set(), 0
    for record in git(repo, "ls-tree", "-r", "-l", "-z", "HEAD", limit=32 * 1024 * 1024).split("\0"):
        if not record:
            continue
        header, path = record.split("\t", 1)
        mode, kind, _, size = header.split()
        safe_path(path)
        if kind != "blob":
            continue  # Submodules are not checked out.
        total += int(size)
        if int(size) > MAX_FILE or total > MAX_TOTAL or len(files) >= MAX_FILES:
            raise Reject("PR tree size or count bound exceeded")
        if mode in ("100644", "100755"):
            files.add(path)
    git(repo, "read-tree", "HEAD")
    # core.symlinks=false writes a PR symlink as a small text file holding its
    # target, so the scanner cannot be pointed at a file outside the tree.
    git(repo, "-c", "core.symlinks=false", "checkout-index", "-a", "-f")
    files.discard("sonar-project.properties")
    return files


def property_value(value):
    if not isinstance(value, str) or not value or len(value) > 256:
        raise Reject("PR branch invalid")
    out = []
    for ch in value:
        code = ord(ch)
        if code < 32 or code == 127:
            raise Reject("PR branch contains control characters")
        if code > 0xFFFF:
            code -= 0x10000
            out.append(f"\\u{0xD800 + (code >> 10):04x}\\u{0xDC00 + (code & 0x3FF):04x}")
        elif code > 126:
            out.append(f"\\u{code:04x}")
        else:
            out.append("\\" + ch if ch in "\\=:# !" else ch)
    return "".join(out)


def properties(repo, pr, candidate, report):
    text = (ROOT / "sonar-project.properties").read_text(encoding="utf-8")
    extra = (f"sonar.pullrequest.key={candidate['pr_number']}",
             f"sonar.pullrequest.branch={property_value(pr['head'].get('ref'))}",
             "sonar.pullrequest.base=main",
             f"sonar.scm.revision={candidate['head_sha']}",
             f"sonar.python.coverage.reportPaths={property_value(str(report))}")
    (repo / "sonar-project.properties").write_text(text.rstrip() + "\n" + "\n".join(extra) + "\n",
                                                   encoding="utf-8")


def prepare(candidate, directory, report, api, remote=REMOTE):
    if directory.exists() or report.exists() or not directory.parent.is_dir():
        raise Reject("analysis outputs must be absent with an existing parent")
    run_id, attempt = candidate["caller_run_id"], candidate["caller_run_attempt"]
    run = api.request(f"/actions/runs/{run_id}/attempts/{attempt}")
    check_caller(candidate, run, api.request(f"/pulls/{candidate['pr_number']}"))
    content = one_zip(coverage_artifact(api, run_id, timestamp(run.get("run_started_at"))))
    staging = Path(tempfile.mkdtemp(prefix="protected-sonar-", dir=directory.parent))
    try:
        repo = staging / "analysis"
        files = checkout(repo, candidate, remote)
        report.write_bytes(coverage_report(content, files, directory))
        pr = api.request(f"/pulls/{candidate['pr_number']}")
        pr_ok(candidate, pr)  # A PR move during preparation invalidates the tree.
        properties(repo, pr, candidate, report)
        os.replace(repo, directory)
    finally:
        shutil.rmtree(staging, ignore_errors=True)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("caller-run-id", "caller-run-attempt", "pr-number"):
        parser.add_argument(f"--{name}", type=int, required=True)
    for name in ("head-sha", "base-sha"):
        parser.add_argument(f"--{name}", required=True)
    parser.add_argument("--analysis-dir", type=Path, required=True)
    parser.add_argument("--coverage-out", type=Path, required=True)
    args = parser.parse_args(argv)
    candidate = {"caller_run_id": args.caller_run_id, "caller_run_attempt": args.caller_run_attempt,
                 "pr_number": args.pr_number, "head_sha": args.head_sha, "base_sha": args.base_sha}
    try:
        if not all(positive(candidate[k]) for k in ("caller_run_id", "caller_run_attempt", "pr_number")) \
                or not sha(args.head_sha) or not sha(args.base_sha):
            raise Reject("candidate identifiers invalid")
        prepare(candidate, args.analysis_dir.resolve(), args.coverage_out.resolve(),
                GitHub(os.environ.get("GITHUB_TOKEN", "")))
    except Reject as exc:
        print(f"protected Sonar preparation rejected: {exc}", file=sys.stderr)
        return 1
    print("protected Sonar analysis prepared")
    return 0


if __name__ == "__main__":
    sys.exit(main())
