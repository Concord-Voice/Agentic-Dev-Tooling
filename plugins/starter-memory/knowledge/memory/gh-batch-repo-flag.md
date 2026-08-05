---
name: gh-batch-repo-flag
description: "`gh` in a batch script that `cd`s away from the repo root needs `-R owner/repo`; silent 100% failure with exit 0"
metadata:
  type: project
---

`gh issue edit`, `gh issue close`, `gh issue view`, and `gh api` (with an implicit repo) all infer the target repo from the **current directory's git remote**. Batch scripts that `cd /tmp` (or any non-repo path, e.g., for `jq` scratch work) then call `gh` fail every call with `fatal: not a git repository` — while the surrounding `while ... done` loop still exits 0, masking a 100 % failure rate.

**Why:** The failure is invisible at the exit-code level; only the per-item output reveals that every call bombed. A batch that processes N items can log N failures while the shell script itself reports success. The bug is particularly insidious in agent-generated scripts where exit-code checking is the primary verification signal.

**How to apply:**
- Pass `-R owner/repo` on every `gh` call in batch scripts so they are cwd-independent, OR always run from the repo root.
- After any batch mutation (relabel, close, edit), verify results by sampling the actual resource state — not by checking the loop exit code.
- When debugging a batch that "succeeded" but made no visible changes, check the per-call stderr output first; `fatal: not a git repository` is the tell.
