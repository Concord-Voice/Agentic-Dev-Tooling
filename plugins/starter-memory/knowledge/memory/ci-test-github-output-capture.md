---
name: ci-test-github-output-capture
description: A test that runs a GitHub Actions helper script and captures stdout passes locally but fails in CI because the runner sets GITHUB_OUTPUT, causing the script to write to a file instead of stdout
metadata:
  type: project
---

A bash or JS test harness that invokes a GitHub Actions helper script and captures **stdout** will pass locally but **fail in CI** if the script uses the common `$GITHUB_OUTPUT` emission pattern:

```bash
emit() {
  if [[ -n "$GITHUB_OUTPUT" ]]; then
    echo "key=value" >> "$GITHUB_OUTPUT"
  else
    echo "key=value"
  fi
}
```

**Why it breaks in CI:** Locally `GITHUB_OUTPUT` is unset, so output goes to stdout and the test sees it. In CI the runner pre-sets `GITHUB_OUTPUT` for every step — including the test step — so the script writes into the Actions output file instead of stdout. The test's captured stdout is empty and every output assertion silently fails.

**Fix:** In the test harness, point `GITHUB_OUTPUT` at a per-call tmpfile and read it back after the script runs. This also exercises the real CI file-output path:

```bash
gho=$(mktemp)
( GITHUB_OUTPUT="$gho" bash "$SCRIPT" >/dev/null 2>&1 )
out=$(cat "$gho")
```

**Corollary:** Wiring a previously local-only test into CI is valuable precisely because it surfaces this class of local-vs-CI environment leak — the test gave false assurance before because it never ran in the real environment.

**How to apply:** Whenever a test exercises a script that might write to `$GITHUB_OUTPUT`, control the variable in the test harness and read the file rather than capturing stdout. This pattern works both locally (where `GITHUB_OUTPUT` is otherwise unset) and in CI.
