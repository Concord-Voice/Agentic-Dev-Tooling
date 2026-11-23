"""Keep user-authored issue text inside deterministic native-link operations."""
import argparse
import json
import re
import subprocess
import sys
import unicodedata

PART = r"[A-Za-z0-9][A-Za-z0-9_.-]*"
NUMBER = r"[1-9][0-9]*"
URL = re.compile(rf"https://github\.com/({PART})/({PART})/issues/({NUMBER})")
BULLET = re.compile(rf"- (?:(?P<repo>{PART}/{PART}))?#(?P<number>{NUMBER})(?:\s+—\s+.*)?")
COMMENT_END = re.compile(r"--!?>")
META = "query($url:URI!){resource(url:$url){__typename ... on Issue{url parent{url}}}}"


class Pending(Exception):
    """A fixed diagnostic safe to return across the issue-text boundary."""


def identity(url):
    match = URL.fullmatch(url) if isinstance(url, str) else None
    if match is None:
        raise Pending("invalid issue URL")
    return match.groups()


def endpoint(url):
    owner, repo, number = identity(url)
    return f"repos/{owner}/{repo}/issues/{number}"


def api(*args, body=None):
    data = json.dumps(body).encode() if body is not None else b""
    result = subprocess.run(["gh", "api", "--hostname", "github.com", *args],
                            input=data, capture_output=True, timeout=30, check=False)
    if result.returncode:
        raise Pending("GitHub request failed")
    return json.loads(result.stdout) if result.stdout else None


def inspect(url):
    identity(url)
    reply = api("graphql", "-f", "query=" + META, "-f", "url=" + url)
    issue = reply["data"]["resource"]
    if reply.get("errors") or not isinstance(issue, dict) or issue["__typename"] != "Issue" or issue["url"] != url:
        raise Pending("issue identity could not be verified")
    dbid = issue_record(url)["id"]
    if type(dbid) is not int or dbid <= 0:
        raise Pending("invalid issue database ID")
    parent = issue["parent"]
    if parent is not None:
        parent = parent["url"]
        identity(parent)
    return {"url": url, "database_id": dbid, "parent": parent}


def issue_record(url):
    obj = api(endpoint(url))
    if not isinstance(obj, dict) or obj.get("html_url") != url or "pull_request" in obj:
        raise Pending("issue identity changed")
    return obj


def issue_text(url, field):
    value = issue_record(url)[field]
    if value is None and field == "body":
        return ""
    if not isinstance(value, str):
        raise Pending("issue text unavailable")
    return value


def plain_title(title):
    # Encode punctuation to prevent mentions, links and embedded Markdown in the index.
    chars = []
    for char in title:
        if char.isalnum():
            chars.append(char)
        elif char.isspace() or unicodedata.category(char).startswith("C"):
            chars.append(" ")
        else:
            chars.append(f"&#{ord(char)};")
    return " ".join("".join(chars).split())


def block_ending(line):
    opening = re.match(r"^ {0,3}(`{3,}|~{3,})", line)
    if opening:
        fence = opening[1]
        return re.compile(r"^ {0,3}" + fence[0] + "{" + str(len(fence)) + r",}[ \t]*$")
    if "<!--" in line and not COMMENT_END.search(line.rsplit("<!--", 1)[1]):
        return COMMENT_END
    return None


def markdown_headings(lines):
    ending = None
    headings = []
    for i, raw in enumerate(lines):
        line = raw.rstrip("\r\n")
        if ending is not None:
            close = ending.search(line)
            if close:
                ending = block_ending(line[close.end():]) if ending is COMMENT_END else None
            continue
        ending = block_ending(line)
        if ending is not None or "<!--" in line:
            continue
        if re.match(r" {0,3}</?[A-Za-z]", line):
            raise Pending("unrecognized HTML block")
        if re.match(r"^ {0,3}#{1,6}(?:\s|$)", line):
            headings.append(i)
    if ending is not None:
        raise Pending("unterminated Markdown block")
    return headings


def index_bounds(lines, headings):
    headers = [i for i in headings if lines[i].strip() == "## Sub-Issues"]
    if len(headers) > 1:
        raise Pending("duplicate Sub-Issues section")
    if headers:
        start = headers[0] + 1
        return start, next((i for i in headings if i >= start), len(lines))
    if any("sub-issues" in lines[i].casefold() for i in headings):
        raise Pending("ambiguous Sub-Issues section")
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


def missing_bullets(children, seen):
    additions = []
    for url, title in children:
        owner, child_repo, number = identity(url)
        name = f"{owner}/{child_repo}"
        key = (name.lower(), number)
        if key not in seen:
            additions.append(f"- {name}#{number} — {plain_title(title)}")
            seen.add(key)
    return additions


def reconcile(body, parent, children):
    repo = "/".join(identity(parent)[:2])
    lines = body.splitlines(keepends=True)
    bounds = index_bounds(lines, markdown_headings(lines))
    newline = "\r\n" if "\r\n" in body else "\n"
    if bounds is None:
        if body and not body.endswith("\n"):
            lines.append(newline)
        if body:
            lines.append(newline)
        lines.append("## Sub-Issues" + newline)
        bounds = len(lines), len(lines)
    start, end = bounds
    additions = missing_bullets(children, existing_children(lines[start:end], repo))
    if not additions:
        return body
    while end > start and not lines[end - 1].strip():
        end -= 1
    before = "".join(lines[:end])
    if not before.endswith("\n"):
        before += newline
    return before + newline.join(additions) + newline + "".join(lines[end:])


def update_index(parent, urls):
    owner = identity(parent)[0].lower()
    if not urls or len(set(urls)) != len(urls):
        raise Pending("list distinct approved children")
    inspect(parent)
    children = []
    for url in urls:
        if identity(url)[0].lower() != owner or inspect(url)["parent"] != parent:
            raise Pending("child relationship is unverified")
        children.append((url, issue_text(url, "title")))
    body = issue_text(parent, "body")
    revised = reconcile(body, parent, children)
    if revised == body:
        return {"status": "current", "children": len(children)}
    latest = issue_text(parent, "body")
    if latest != body:
        raise Pending("parent changed before update")
    api("--method", "PATCH", endpoint(parent), "--input", "-", "--silent", body={"body": revised})
    if issue_text(parent, "body") != revised:
        raise Pending("parent changed during update")
    return {"status": "updated", "children": len(children)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("inspect").add_argument("url")
    index = sub.add_parser("index")
    index.add_argument("parent")
    index.add_argument("children", nargs="+")
    args = parser.parse_args()
    try:
        record = inspect(args.url) if args.command == "inspect" else update_index(args.parent, args.children)
        print(json.dumps(record))
    except Pending as exc:
        sys.exit(str(exc))
    except (TypeError, KeyError, ValueError, OSError, subprocess.SubprocessError, RecursionError):
        sys.exit("native issue operation incomplete")


if __name__ == "__main__":
    main()
