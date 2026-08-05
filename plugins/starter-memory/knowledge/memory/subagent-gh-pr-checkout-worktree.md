---
name: subagent-gh-pr-checkout-worktree
description: Non-isolated subagents running `gh pr checkout` mutate the shared HEAD; re-assert the branch before committing, or dispatch with isolation: worktree
metadata:
  type: feedback
---

Subagents dispatched without worktree isolation share the main session's filesystem and its checked-out branch. Any `gh pr checkout` or `git checkout` they run mutates the shared HEAD out from under the orchestrator. Commits made after the switch land on the stray branch, and `git push` may silently no-op if that branch has no upstream.

**Why:** Review and inspection subagents commonly run `gh pr checkout <PR>` to inspect a PR's code. Without isolation, this switches the shared working tree's branch. The next commit the orchestrator makes — believing it is on the PR's feature branch — actually lands on the stray checkout branch and does not push to the intended ref.

**How to apply:**
1. For review or inspection subagents that might check out refs (anything calling `gh pr checkout`), pass `isolation: "worktree"` so they operate on an isolated copy.
2. After ANY subagent dispatch, BEFORE committing, re-assert the branch: check `git branch --show-current` and run `git checkout <expected-branch>` if it drifted.
3. Recovery when a commit lands on a stray fast-forward branch: `git push origin <stray>:<pr-head-branch>` grafts it onto the PR with no `--force` (it is a fast-forward child of the PR head). Then `git checkout <pr-head-branch> && git merge --ff-only <stray>` to reconcile local state, and `git branch -d <stray>`.
