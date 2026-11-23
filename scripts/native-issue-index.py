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
    return " ".join("".join(c if c.isalnum() or c == " " else
                            " " if c.isspace() or unicodedata.category(c).startswith("C")
                            else f"&#{ord(c)};" for c in title).split())


def markdown_headings(lines):
    fence = None
    comment = False
    headings = []
    for i, raw in enumerate(lines):
        line = raw.rstrip("\r\n")
        if fence:
            if re.fullmatch(r" {0,3}" + fence[0] + "{" + str(len(fence)) + r",}[ \t]*", line):
                fence = None
            continue
        if comment:
            if "-->" in line:
                comment = False
            continue
        if "<!--" in line:
            comment = "-->" not in line.split("<!--", 1)[1]
            continue
        opening = re.match(r"^ {0,3}(`{3,}|~{3,})", line)
        if opening:
            fence = opening[1]
        elif re.match(r" {0,3}</?[A-Za-z]", line):
            raise Pending("unrecognized HTML block")
        elif re.match(r"^ {0,3}#{1,6}(?:\s|$)", line):
            headings.append(i)
    if fence or comment:
        raise Pending("unterminated Markdown block")
    return headings


def reconcile(body, parent, children):
    repo = "/".join(identity(parent)[:2])
    lines = body.splitlines(keepends=True)
    headings = markdown_headings(lines)
    headers = [i for i in headings if lines[i].strip() == "## Sub-Issues"]
    if not headers:
        if any("sub-issues" in lines[i].casefold() for i in headings):
            raise Pending("ambiguous Sub-Issues section")
        newline = "\r\n" if "\r\n" in body else "\n"
        separator = "" if not body else newline if body.endswith("\n") else newline * 2
        return reconcile(body + separator + "## Sub-Issues" + newline, parent, children)
    if len(headers) != 1:
        raise Pending("one unambiguous Sub-Issues section required")
    start = headers[0] + 1
    seen = set()
    end = start
    while end < len(lines):
        line = lines[end].rstrip("\r\n")
        if end in headings:
            break
        if line.strip():
            match = BULLET.fullmatch(line)
            if not match:
                raise Pending("unrecognized child index row")
            key = ((match["repo"] or repo).lower(), match["number"])
            if key in seen:
                raise Pending("duplicate child index row")
            seen.add(key)
        end += 1
    additions = []
    for url, title in children:
        owner, child_repo, number = identity(url)
        name = f"{owner}/{child_repo}"
        key = (name.lower(), number)
        if key not in seen:
            additions.append(f"- {name}#{number} — {plain_title(title)}")
            seen.add(key)
    if not additions:
        return body
    insert = end
    while insert > start and not lines[insert-1].strip():
        insert -= 1
    newline = "\r\n" if lines[start-1].endswith("\r\n") else "\n"
    before = "".join(lines[:insert])
    return before + ("" if before.endswith("\n") else newline) + newline.join(additions) + newline + "".join(lines[insert:])


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
