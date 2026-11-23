"""Keep user-authored issue text inside deterministic native-link operations."""
import argparse
import json
import re
import subprocess
import sys

OWNER = r"[A-Za-z0-9][A-Za-z0-9_.-]*"
REPO = r"(?!\.{1,2}[/#])[A-Za-z0-9_.-]+"
NUMBER = r"[1-9][0-9]*"
URL = re.compile(rf"https://github\.com/({OWNER})/({REPO})/issues/({NUMBER})")
BULLET = re.compile(rf"- (?:(?P<repo>{OWNER}/{REPO}))?#(?P<number>{NUMBER})(?:\s+—\s+.*)?")
INDEX_HEADING = "## Sub-Issues"
ATX_HEADING = re.compile(r"^ {0,3}#{1,6}(?:\s|$)")
COMMENT_END = re.compile(r"--!?>")
META = "query($url:URI!){resource(url:$url){__typename ... on Issue{url fullDatabaseId parent{url}}}}"
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
    seen = set()
    for line in lines:
        if not line.strip():
            continue
        match = BULLET.fullmatch(line.rstrip("\r\n"))
        if not match:
            raise Pending("unrecognized child index row")
        key = ((match["repo"] or repo).lower(), match["number"])
        if key in seen:
            raise Pending("duplicate child index row")
        seen.add(key)
    return seen


def missing_rows(body, parent, urls):
    repo = "/".join(identity(parent)[:2])
    lines = body.splitlines(keepends=True)
    bounds = index_bounds(lines, markdown_headings(lines))
    rows = lines[slice(*bounds)] if bounds else []
    seen = existing_children(rows, repo)
    missing = []
    for url in urls:
        owner, child_repo, number = identity(url)
        if (f"{owner}/{child_repo}".lower(), number) not in seen:
            missing.append(f"- {owner}/{child_repo}#{number}")
    return missing


def check_index(parent, urls):
    owner = identity(parent)[0].lower()
    if not urls or len(set(urls)) != len(urls):
        raise Pending("list distinct approved children")
    inspect(parent)
    for url in urls:
        if identity(url)[0].lower() != owner or inspect(url)["parent"] != parent:
            raise Pending("child relationship is unverified")
    rows = missing_rows(issue_body(parent), parent, urls)
    if rows:
        return {"status": "pending", "children": len(urls), "missing_rows": rows}
    return {"status": "current", "children": len(urls)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("inspect").add_argument("url")
    index = sub.add_parser("index")
    index.add_argument("parent")
    index.add_argument("children", nargs="+")
    args = parser.parse_args()
    try:
        record = inspect(args.url) if args.command == "inspect" else check_index(args.parent, args.children)
        print(json.dumps(record))
        if record.get("status") == "pending":
            sys.exit(2)
    except Pending as exc:
        sys.exit(str(exc))
    except (TypeError, KeyError, ValueError, OSError, subprocess.SubprocessError, RecursionError):
        sys.exit("native issue operation incomplete")


if __name__ == "__main__":
    main()
