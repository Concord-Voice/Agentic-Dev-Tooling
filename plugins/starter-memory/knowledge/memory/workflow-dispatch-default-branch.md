---
name: workflow-dispatch-default-branch
description: "`workflow_dispatch` only registers workflows present on the default branch; feature-branch-only workflows can't be dispatched even via raw API `--ref`"
metadata:
  type: project
---

`gh workflow run <file> --ref <feature-branch>` returns HTTP 404 "workflow not found on the default branch" when the workflow file exists only on a feature branch. The CLI's pre-flight lookup queries the workflow registry, which GitHub populates **only from the default branch** (usually `main`).

The raw API endpoint `POST /repos/{owner}/{repo}/actions/workflows/{file_or_id}/dispatches` has the **same constraint** — it also returns 404 when the workflow is not on `main`, regardless of the `ref` body parameter. There is no workaround that bypasses this; it is a fundamental design constraint, not a bug.

**Why:** GitHub's workflow discovery is anchored on the default branch. The dispatch endpoint validates that the workflow exists in the registry before checking whether the file exists at the specified `ref`. A workflow that lives only on a feature branch is invisible to the dispatch surface entirely.

**How to apply:**
- For any workflow that needs `workflow_dispatch`: the workflow file must land on the default branch first. Only then can it be dispatched (optionally pointing `ref` at another branch).
- For one-shot tools: consider landing the file on `main` temporarily (even via admin bypass if branch protection blocks it), running the dispatch, then removing it in a follow-up commit. Net-zero on `main`'s permanent history.
- For ongoing dispatchable workflows: include them in a normal PR that merges to `main`.
- The constraint applies to all `workflow_dispatch` attempts, including `gh api` calls and third-party CI orchestration tools.
