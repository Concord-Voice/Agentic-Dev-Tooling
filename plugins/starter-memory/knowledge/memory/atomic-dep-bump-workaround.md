---
name: atomic-dep-bump-workaround
description: Push version-specific workarounds onto the bot PR's own branch; don't split into a separate fix PR (dependabot rebase clobbers maintainer commits)
metadata:
  type: feedback
---

For dependency bumps that require a code workaround specifically because of that bump's behavior change, push the workaround as a maintainer commit ONTO the bot PR's branch rather than landing it as a separate fix PR on main.

**Why:** A workaround whose new code path only makes sense in the context of the bumped version is dead code on main as it currently stands — it has zero observable behavior without the bump. Splitting them creates problems:
- `git bisect` can land on a nonsense intermediate state (workaround present, bump absent)
- Reverting the bump leaves orphaned workaround code that no one remembers the purpose of
- The reviewer of the bump PR has to context-switch to a separate PR to understand the full regression story

The "independently valuable / forward-compatible for future majors" framing is usually hand-wavy justification and does not outweigh these costs.

**How to apply:**
- Push to the bot PR's branch via `git worktree add /tmp/<name> <bot-branch>` → edit → commit → push.
- After the maintainer commit lands, do NOT issue `@dependabot rebase` — it force-pushes and clobbers maintainer commits.
- Use `gh pr update-branch` instead if the branch needs the base branch's HEAD.
- Dependabot's auto-rebase on base-branch advance is documented to skip when maintainer commits are present, so it is safe to leave the PR alone until merge.
