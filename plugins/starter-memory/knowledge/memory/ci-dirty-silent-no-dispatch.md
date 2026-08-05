---
name: ci-dirty-silent-no-dispatch
description: GitHub Actions silently skips workflow dispatch when a PR's mergeStateStatus is DIRTY; looks like a CI outage but the fix is merge-main-into-branch
metadata:
  type: project
---

When a PR's `mergeStateStatus` is `DIRTY` (merge conflict with the base branch), **GitHub Actions silently does NOT dispatch any workflow runs on subsequent pushes to the head branch**. The push succeeds and the SHA updates on the remote, but no CI is queued.

**Symptom:** `gh pr checks <num> --watch` exits immediately with exit code 1 and the message "no checks reported on the '<branch>' branch".

**Detection:** `gh pr view <num> --json mergeStateStatus` returns `"DIRTY"`. There may be a stale-cache window where GitHub continues reporting `DIRTY` for ~1-2 min after the conflict is resolved.

**Resolution:** fetch main, merge it into the PR branch, resolve conflicts, push the merge commit. `.secrets.baseline` is a common conflict surface (both sides update its `generated_at` timestamp) — take `--ours`; the detect-secrets hook will re-validate. CI dispatches automatically once the PR re-evaluates as `MERGEABLE`.

**Why:** GitHub's design choice — running CI on a conflicted PR would test code that can't actually merge. But the silent skip combined with no clear "dispatch blocked" API signal makes this look like a CI outage from the developer's side.

**How to apply:** If a push to a PR branch produces zero workflow runs after ~2 min, check `mergeStateStatus` BEFORE assuming CI itself is broken. The fix is always merge-main-into-branch (or rebase if force-push is authorized), never a CI re-trigger trick.
