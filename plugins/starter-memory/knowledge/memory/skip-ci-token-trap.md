---
name: skip-ci-token-trap
description: "`[skip ci]` and variants are parsed anywhere in a commit message; backticks and prose context do not protect them"
metadata:
  type: project
---

GitHub Actions skips workflow runs when any of the following tokens appear **anywhere** in a commit message body: `[skip ci]`, `[ci skip]`, `[no ci]`, `[skip actions]`, `[actions skip]`. The parser is naive — surrounding backtick code spans, quoted prose, and backslash escapes do NOT prevent the match.

**Why:** A commit message that merely *documents* the directive (e.g., a bullet explaining that a code comment references `[skip ci]`) will trigger the skip just as surely as intentional use. Affected runs appear in a "skipped" state that can look green, so the problem may not be noticed unless you verify that the expected workflow names actually ran.

**How to apply:**
- Never include `[skip ci]`, `[ci skip]`, `[no ci]`, `[skip actions]`, or `[actions skip]` as literal substrings in commit messages, PR body text, or merge commit messages — even inside backtick code spans or example blocks.
- When you must document these directives in prose, use alternative renderings: `[SKIP-CI]` (different casing), `skip-ci` (hyphen instead of space), or rewrite as "the skip-ci directive."
- Same rule applies to PR bodies, since GitHub uses the PR title + body as the squash merge commit message.
- If you discover after pushing that CI was silently skipped: push a clean `git commit --allow-empty -m "ci: re-trigger CI"` rather than amending (preserves the audit trail).
- Detection: after pushing, run `gh run list --branch <branch> --limit 5 --json event,name,headSha` and confirm the expected workflow names (e.g., `pr-ci.yml`, `build.yml`) appear. If only secondary event-triggered workflows appear and the primary `push`/`pull_request` workflows are absent or skipped, suspect a `[skip ci]` trap.
