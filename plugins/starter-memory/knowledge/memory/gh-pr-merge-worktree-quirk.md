---
name: gh-pr-merge-worktree-quirk
description: "`gh pr merge --delete-branch` from a worktree exits non-zero on local cleanup though the server merge already succeeded; verify with `gh pr view`"
metadata:
  type: project
---

When running `gh pr merge --auto --squash --delete-branch` from inside a git worktree while `main` is checked out in the parent repo, the command exits non-zero with `fatal: '<branch>' is already used by worktree at '<path>'`. The failing step is `gh`'s local post-merge cleanup — it tries to `git switch main` and delete the local branch, neither of which can succeed because `main` is held by another worktree.

**Why:** The exit code is misleading. The server-side merge has already succeeded by that point — the PR transitions to MERGED, the remote feature branch is deleted, and a merge commit is recorded. Only the local cleanup step fails. Treating the non-zero exit as "the merge didn't happen" causes double-reporting or unnecessary retries against an already-closed PR.

**How to apply:**
- Never treat `gh pr merge` failure in a worktree as proof the merge did not happen. Always re-check with `gh pr view <number> --json state,mergeCommit` before reporting failure or retrying.
- For squash-merge from a worktree the server-side action is reliable; only the local cleanup is fragile.
- Alternative: drop `--delete-branch` so the merge proceeds without the cleanup attempt; remove the local branch manually afterward. The current pattern (with `--delete-branch`) works correctly if you treat the exit code as advisory.
- Local worktree cleanup after a merged PR requires running `git worktree remove <path>` from the parent repo, not from inside the worktree itself.
