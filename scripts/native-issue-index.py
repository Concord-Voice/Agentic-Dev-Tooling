"""Keep user-authored issue text inside deterministic native-link operations."""
import argparse
import hashlib
import json
import os
import re
import string
import subprocess
import sys

OWNER = r"[A-Za-z0-9][A-Za-z0-9_.-]*"
REPO = r"(?!\.{1,2}[/#])[A-Za-z0-9_.-]+"
NUMBER = r"[1-9][0-9]*"
URL = re.compile(rf"https://github\.com/({OWNER})/({REPO})/issues/({NUMBER})")
BULLET = re.compile(rf"- (?:(?P<repo>{OWNER}/{REPO}))?#(?P<number>{NUMBER})(?: +— +(?P<title>.+))?")
INDEX_HEADING = "## Sub-Issues"
ATX_HEADING = re.compile(r"^ {0,3}#{1,6}(?:\s|$)")
COMMENT_END = re.compile(r"--!?>")
META = "query($url:URI!){resource(url:$url){__typename ... on Issue{url fullDatabaseId parent{url}}}}"
CHILD = "query($url:URI!){resource(url:$url){__typename ... on Issue{url title parent{url}}}}"
BODY = "query($url:URI!){resource(url:$url){__typename ... on Issue{url body}}}"


class Pending(Exception):
    """A fixed diagnostic safe to return across the issue-text boundary."""


def identity(url):
    match = URL.fullmatch(url) if isinstance(url, str) else None
    if match is None:
        raise Pending("invalid issue URL")
    return match.groups()


def issue_record(url, query):
    identity(url)
    packet = json.dumps({"query": query, "variables": {"url": url}}).encode()
    result = subprocess.run(["gh", "api", "--hostname", "github.com", "graphql", "--input", "-"],
                            input=packet, capture_output=True, timeout=30, check=False)
    if result.returncode:
        raise Pending("GitHub request failed")
    reply = json.loads(result.stdout)
    issue = reply["data"]["resource"]
    if reply.get("errors") or not isinstance(issue, dict) or issue["__typename"] != "Issue" or issue["url"] != url:
        raise Pending("issue identity could not be verified")
    return issue


def inspect(url):
    issue = issue_record(url, META)
    dbid = issue["fullDatabaseId"]
    if not isinstance(dbid, str) or not re.fullmatch(r"[1-9][0-9]{0,19}", dbid):
        raise Pending("invalid issue database ID")
    parent = issue["parent"]
    if parent is not None:
        parent = parent["url"]
        identity(parent)
    return {"url": url, "database_id": int(dbid), "parent": parent}


def issue_body(url):
    value = issue_record(url, BODY)["body"]
    if value is None:
        return ""
    if not isinstance(value, str):
        raise Pending("issue text unavailable")
    return value


def block_ending(line):
    opening = re.match(r"^ {0,3}(`{3,}|~{3,})", line)
    if opening:
        fence = opening[1]
        return re.compile(r"^ {0,3}" + fence[0] + "{" + str(len(fence)) + r",}[ \t]*$")
    if "<!--" in line and not COMMENT_END.search(line.rsplit("<!--", 1)[1]):
        return COMMENT_END
    return None


def continued_block(ending, line):
    close = ending.search(line)
    if not close:
        return ending
    if ending is COMMENT_END:
        return block_ending(line[close.end():])
    return None


def check_index_spelling(line, following):
    if "sub-issues" not in line.casefold():
        return
    if re.fullmatch(r" {0,3}(?:=+|-+)[ \t]*", following.rstrip("\r\n")):
        raise Pending("ambiguous Setext Sub-Issues heading")
    if ATX_HEADING.match(line) and line.strip() != INDEX_HEADING:
        raise Pending("ambiguous Sub-Issues section")


def markdown_headings(lines):
    ending = None
    headings = []
    for i, (raw, following) in enumerate(zip(lines, lines[1:] + [""])):
        line = raw.rstrip("\r\n")
        if ending is not None:
            ending = continued_block(ending, line)
            continue
        check_index_spelling(line, following)
        ending = block_ending(line)
        if ending is not None or "<!--" in line:
            continue
        if re.match(r" {0,3}<(?:/?[A-Za-z]|[!?])", line):
            raise Pending("unrecognized HTML block")
        if ATX_HEADING.match(line):
            headings.append(i)
    if ending is not None:
        raise Pending("unterminated Markdown block")
    return headings


def index_bounds(lines, headings):
    headers = [i for i in headings if lines[i].strip() == INDEX_HEADING]
    if len(headers) > 1:
        raise Pending("duplicate Sub-Issues section")
    if headers:
        start = headers[0] + 1
        following = (i for i in headings if i >= start and not lines[i].lstrip().startswith("###"))
        return start, next(following, len(lines))
    return None


def existing_children(lines, repo):
    seen = {}
    for offset, line in enumerate(lines):
        if not line.strip():
            continue
        match = BULLET.fullmatch(line.rstrip("\r\n"))
        if not match:
            raise Pending("unrecognized child index row")
        key = ((match["repo"] or repo).lower(), match["number"])
        if key in seen:
            raise Pending("duplicate child index row")
        seen[key] = (offset, match["title"])
    return seen


def plan_index(body, parent, titles):
    repo = "/".join(identity(parent)[:2])
    lines = body.splitlines(keepends=True)
    bounds = index_bounds(lines, markdown_headings(lines))
    rows = lines[slice(*bounds)] if bounds else []
    seen = existing_children(rows, repo)
    missing = {}
    additions = []
    eol = "\r\n" if "\r\n" in body else "\n"
    for url, title in titles.items():
        owner, child_repo, number = identity(url)
        child = (f"{owner}/{child_repo}".lower(), number)
        # Escape Markdown punctuation only in the display text. The issue reference stays live.
        escaped = re.sub(f"([{re.escape(string.punctuation)}])", r"\\\1", title)
        existing = seen.get(child)
        if existing is not None and existing[1] in (title, escaped):
            continue
        reference = f"- {owner}/{child_repo}#{number}"
        row = f"{reference} — {escaped}"
        missing[reference] = row
        if existing is None:
            additions.append(row)
        else:
            i = bounds[0] + existing[0]
            original = lines[i]
            lines[i] = row + original[len(original.rstrip("\r\n")):]
    if additions:
        end = bounds[1] if bounds else len(lines)
        prefix = "".join(lines[:end])
        suffix = "".join(lines[end:])
        if prefix and not prefix.endswith("\n"):
            prefix += eol
        if bounds is None:
            prefix += (eol if prefix else "") + INDEX_HEADING + eol
        proposed = prefix + eol.join(additions) + eol + (eol if suffix else "") + suffix
    else:
        proposed = "".join(lines)
    return proposed, missing


def verified_titles(parent, urls):
    owner = identity(parent)[0].lower()
    if not urls or len(set(urls)) != len(urls):
        raise Pending("list distinct approved children")
    inspect(parent)
    titles = {}
    for url in urls:
        if identity(url)[0].lower() != owner:
            raise Pending("child relationship is unverified")
        child = issue_record(url, CHILD)
        if child["parent"] != {"url": parent}:
            raise Pending("child relationship is unverified")
        title = child["title"]
        if not isinstance(title, str) or not title.strip() or len(title.splitlines()) != 1 or not title.isprintable():
            raise Pending("child title requires manual review")
        titles[url] = title
    return titles


def check_index(parent, urls, rows_file=None, confirmed_digest=None):
    titles = verified_titles(parent, urls)
    body = issue_body(parent)
    proposed, rows = plan_index(body, parent, titles)
    if not rows:
        return {"status": "current", "children": len(urls)}
    # Bind the prior body, proposed result, exact parent and approved child list.
    digest = hashlib.sha256(json.dumps([parent, titles, body, proposed]).encode()).hexdigest()
    if confirmed_digest is not None:
        if digest != confirmed_digest:
            raise Pending("index preview changed; obtain fresh exclusive confirmation")
        owner, repo, number = identity(parent)
        packet = json.dumps({"body": proposed}).encode()
        try:
            subprocess.run(["gh", "api", "--hostname", "github.com", "--method", "PATCH",
                            f"repos/{owner}/{repo}/issues/{number}", "--input", "-", "--silent"],
                           input=packet, capture_output=True, timeout=30, check=False)
        except (OSError, subprocess.SubprocessError):
            pass  # A lost receipt can follow a successful write. Always read back.
        after_titles = verified_titles(parent, urls)
        if after_titles != titles or issue_body(parent) != proposed:
            raise Pending("index update unverified; reconcile before any further write")
        return {"status": "current", "children": len(urls)}
    if rows_file is not None:
        # Exclusive creation protects existing drafts and rejects symlinks.
        fd = os.open(rows_file, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as out:
            for row in rows.values():
                out.write(row + "\n")
    return {"status": "pending", "children": len(urls), "missing_rows": list(rows), "digest": digest}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("inspect").add_argument("url")
    index = sub.add_parser("index")
    index.add_argument("--rows-file", help="write missing or outdated titled rows to a new private file")
    index.add_argument("parent")
    index.add_argument("children", nargs="+")
    apply = sub.add_parser("apply-index", help="apply a preview under a confirmed exclusive editing window")
    apply.add_argument("--exclusive-parent", required=True)
    apply.add_argument("--confirmed-digest", required=True)
    apply.add_argument("children", nargs="+")
    args = parser.parse_args()
    try:
        if args.command == "inspect":
            record = inspect(args.url)
        elif args.command == "index":
            record = check_index(args.parent, args.children, rows_file=args.rows_file)
        else:
            record = check_index(args.exclusive_parent, args.children, confirmed_digest=args.confirmed_digest)
        print(json.dumps(record))
        if record.get("status") == "pending":
            sys.exit(2)
    except Pending as exc:
        sys.exit(str(exc))
    except (TypeError, KeyError, ValueError, OSError, subprocess.SubprocessError, RecursionError):
        sys.exit("native issue operation incomplete")


if __name__ == "__main__":
    main()
