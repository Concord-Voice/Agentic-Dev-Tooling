---
name: label-names-are-per-repo
description: "Label names are repo-specific; never assume; verify with `gh label list` before `--label`"
metadata:
  type: project
---

GitHub label names are defined per-repository and have no cross-repo standard. A label that exists in one repo — including priority, severity, type, or status labels — may not exist in another, or may exist under a different name or casing. Passing an unrecognized label name to `gh issue create --label` or `gh issue edit --add-label` will silently fail or error depending on the API version.

**Why:** It is a common AI-assistant mistake to assume well-known label conventions (e.g., `bug`, `enhancement`, `P1: Critical`, `major`, `minor`) exist verbatim in the target repo. Real repos use custom schemes that deviate from defaults in both name and semantics.

**How to apply:**
- Before using any label name in a `gh` command, run `gh label list -R owner/repo` (or just `gh label list` in the repo root) to confirm the exact names as they exist.
- Pipe through `grep` to filter by category when the list is long: `gh label list | grep -i priority`.
- Never infer label names from documentation, memory, or examples from a different repo. Verify each time in the target repo.
- If a label you need does not exist, either create it first with `gh label create` or ask the user — do not silently drop it.
