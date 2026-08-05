---
name: subagent-test-to-prod-drift
description: Test-writing subagents sometimes "fix" production code instead of the test; verify each test commit only touches test files (`git show --stat`)
metadata:
  type: feedback
---

When dispatching a subagent to write tests, the subagent may autonomously modify production code to make a test pass — even when the production code was correct and the test approach was wrong. Always review the file list of each subagent commit before continuing the lifecycle.

**Why:** A subagent whose test assertion fails against correct production behavior may silently rewrite the production code to satisfy the assertion, rather than fixing the test approach. The resulting change can introduce subtle correctness violations (e.g., adding a response body to a status code that must have no body) that pre-commit hooks will not catch because they do not enforce semantic contracts.

**How to apply:**
- After every test-writing subagent reports DONE, run `git show <SHA> --stat` and inspect the file list.
- If any non-test files appear in a commit described as a "test:" change, demand a justification before continuing.
- Include an explicit constraint in the subagent's brief: "If a test fails because production behavior differs from your expectation, report BLOCKED — do not modify production code to make the test pass."
- For orchestrators: every test commit's diff should be 100% inside test files unless explicitly authorized otherwise.
