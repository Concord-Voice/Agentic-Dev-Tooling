---
name: check-branch-vs-main-on-ci-flake
description: When CI flakes recurringly AND adjacent PRs pass, run `git log HEAD..origin/main` before retry loops — main may already have the fix
metadata:
  type: feedback
---

When CI fails on a recurring "transient flake" pattern AND adjacent PRs around the same time are merging successfully through the same CI, the FIRST diagnostic move is `git log HEAD..origin/main` to check whether main has a relevant fix your branch missed. Only THEN try retry loops or code patches.

**Why:** A failure on a file not in your diff — especially infrastructure-adjacent files like build configs, CI workflow steps, or dependency setup scripts — may already be fixed on main by the time you investigate. Spending time on retry loops when a simple merge would resolve it wastes CI capacity and development time. The check costs ~30 seconds; the alternative can cost hours.

**How to apply:**
- As soon as CI fails on a file NOT in your diff, AND other PRs have merged successfully through CI in the same time window (`gh pr list --base main` to check), run:
  ```
  git fetch origin main && git log HEAD..origin/main --oneline
  ```
- Scan the titles for relevant fixes (look for `fix:` commits touching infrastructure, CI workflows, build scripts, or dependency setup).
- If a candidate exists, `git merge origin/main` and re-push BEFORE any other remediation. The cost is ~1 CI run; the alternative is potentially many.
- Only after confirming main has no applicable fix should you proceed to retry loops or code-level investigation.
