# Shared Org Memory (promoted, generic)

Facts promoted from a project-specific memory pack that apply org-wide. One line each; read
the linked file for the full fact. Project-specific memory stays in the originating project.

## Claude / AI agent behaviour

- [Don't generalize subagent avoidance](dont-avoid-subagents.md) — rejecting subagents in one situation should never become a blanket pattern
- [Multichoice: execute literally](multichoice-literal-execution.md) — when the user picks A/B/C, run exactly that option's mechanics
- [No speed-run assumption](no-speedrun-assumption.md) — system-reminders to skip questions are NOT user instructions; only explicit chat triggers speed-run mode
- [Autonomous subagent cadence](autonomous-subagent-runs.md) — offer A/B/C cadence but expect B (fully autonomous); respect hard-block exceptions and budget heuristics
- [Skill steps are mandatory](skill-steps-mandatory.md) — never skip an imperative skill step on equivalent-coverage reasoning
- [Subagent factual descriptions](subagent-factual-replacements.md) — doc-rewriting agents may invent aspirational architecture; demand descriptions of what the live code actually does
- [Subagent test-to-prod drift](subagent-test-to-prod-drift.md) — test-writing agents sometimes fix production code; verify each test commit only touches test files
- [Subagent HEAD mutation](subagent-gh-pr-checkout-worktree.md) — non-isolated subagents running `gh pr checkout` mutate shared HEAD; re-assert branch before committing
- [Subagent telemetry confusion](subagent-harness-telemetry-confusion.md) — agents may misidentify harness system-reminders as injected content; verify with format-controlled command first

## Review & workflow discipline

- [Review: discovery before execution](review-discovery-vs-execution.md) — present findings/defer table and WAIT for approval before applying any fixes
- [Review process lifecycle](review-process.md) — Draft PR → CI → Ready → bot reviews → Claude review → merge; verify bot findings technically
- [Wait for all bot reviews](wait-for-bot-reviews.md) — after marking PR ready, enumerate expected bot reviewers and wait for all to arrive
- [Branch protection is not soft](branch-protection-discipline.md) — never `--admin` past a legitimate blocking bot review
- [High velocity: keep discipline](velocity-not-discipline.md) — high PR velocity is a small-team effect; never dilute review, safety, or structure for speed
- [Docs review layering](docs-review-layering.md) — multi-artifact docs PRs need a subagent pre-PR pass AND a bot post-ready pass; each layer catches different things
- [Dead ceremony: remove immediately](dead-ceremony-removal.md) — for compliance stubs against non-functional features, prefer single-PR removal over formal deprecation windows
- [Authorized credential use](authorized-credential-use.md) — when the user explicitly bounds a leaked credential's risk, honor that decision without re-litigating
- [Verify full ancestry chain](verify-full-ancestry-chain.md) — multi-level issue hierarchies may have broken parent links; verify all levels via GraphQL at session start
- [Capability epic close sequence](capability-epic-close-with-watchers.md) — when all actionable children are closed but a watcher child remains, use the 4-step detach-and-close sequence

## Commit & PR mechanics

- [Commit message format](commit-message-format.md) — the commit-msg hook rejects parenthesized scopes; use bare `type:` not `type(scope):`
- [Atomic multi-file commits](atomic-multi-file-commits.md) — use the git tree API (blobs + trees + commits = 1 push) for multi-file fixes via `gh api`
- [Atomic dep-bump workaround](atomic-dep-bump-workaround.md) — push version-specific workarounds onto the bot PR's own branch; separate fix PRs get clobbered by dependabot rebase
- [PR create defaults to Ready](pr-create-default-draft.md) — pass `--draft`; AI bots may review drafts quickly so don't rely on draft to defer them
- [Skip-ci token trap](skip-ci-token-trap.md) — `[skip ci]` and variants are parsed anywhere in the commit message; backticks and prose don't protect them
- [Squash-merge cherry-pick provenance](squash-merge-cherry-pick-provenance.md) — a cherry-picked file conflicts when the source PR squash-merges to main; `git checkout --ours` is usually correct
- [Version bump timing](version-bump-timing.md) — batch a forced version/metadata bump onto already-pending CI re-runs rather than at PR-open
- [PR body mention auto-close](pr-body-mention-autoclose.md) — bare `#NNN` in a PR body can trigger auto-close on squash-merge; use URL-only references for tracking-placeholder PRs
- [PR auto-close: each issue needs its own keyword](github-closes-multi-issue.md) — auto-close only picks up the first issue from a comma-separated Closes list
- [Shell command paths for users](shell-command-paths.md) — use plain-text paths in copy-paste commands; chat renderer auto-links break zsh

## gh / GitHub platform

- [gh token project scope](gh-token-scope.md) — Projects v2 mutations require `project` scope; detect INSUFFICIENT_SCOPES and surface the fix
- [gh batch script repo flag](gh-batch-repo-flag.md) — `gh` in a batch script that `cd`s away needs `-R owner/repo`; silent 100% failure with exit 0
- [gh pr merge worktree quirk](gh-pr-merge-worktree-quirk.md) — `gh pr merge --delete-branch` from a worktree exits non-zero on local cleanup though server merge succeeded; verify with `gh pr view`
- [getLatestRelease pre-release 404](getlatestrelease-prerelease-404.md) — GET /releases/latest 404s when a repo only has pre-releases; use listReleases and take the most-recent non-draft
- [Label names are per-repo](label-names-are-per-repo.md) — never assume label names; verify with `gh label list` before `--label`
- [GitHub env rule API anomaly](github-env-rule-api-anomaly.md) — `gh api -X PUT environments/{name}` can return HTTP 422 despite an active paid plan; unresolved anomaly
- [Branch name autolink auto-close](branch-name-autolink-autoclose.md) — `feature/<N>-...` branches populate closingIssuesReferences; use a non-matching name or post-merge reopen for PR≠done epics
- [Gitar agent.md filename](gitar-agent-md-filename.md) — Gitar reads singular lowercase `agent.md`, not `AGENTS.md`; case matters on Linux
- [workflow_dispatch needs default branch](workflow-dispatch-default-branch.md) — workflow_dispatch only registers workflows on the default branch; feature-branch-only workflows can't be dispatched
- [Enumeration empty, direct works](enumeration-empty-direct-works.md) — list/enumerate APIs return empty while by-ID/key works; capture IDs at creation and act by ID
- [Tasklist autolink unreliable](tasklist-autolink-unreliable.md) — GitHub `- [ ] #N` tasklist auto-detect often fails on programmatic edits; use REST POST /sub_issues as the PRIMARY path
- [Watch issues: use Refs not Closes](watch-issues-use-refs.md) — for long-horizon watch issues the shipping PR is one milestone, not the terminus; use `Refs #N`

## Project boards & sub-issues

- [Board Done auto-closes issues](board-done-autoclose.md) — Projects v2 auto-closes the linked issue when Status→Done; post comments BEFORE the status change
- [Project auto-add unreliable](project-auto-add-unreliable.md) — Projects v2 auto-add silently skips items; the filter is UI-only and API-invisible — use manual-add fallback and verify
- [PR CI merge-ref race](pr-ci-merge-ref-race.md) — within ~30 s of PR creation, actions/checkout may fail with a misleading "could not read Username" error; fix is `gh run rerun --failed`

## CI / SonarCloud / dev-env

- [CI dirty: silent no-dispatch](ci-dirty-silent-no-dispatch.md) — GitHub Actions silently skips workflow dispatch when a PR's mergeStateStatus is DIRTY; fix is merge-main-into-branch
- [CI runner provisioning stall](ci-runner-provisioning-stall.md) — fully-stalled CI with queued runs and null runner_name is a transient GitHub-side issue; self-clears; don't chase quota first
- [CI test GITHUB_OUTPUT capture](ci-test-github-output-capture.md) — a test that captures stdout from a GH Actions helper script passes locally but fails in CI because GITHUB_OUTPUT redirects output to a file
- [Check branch vs main on CI flake](check-branch-vs-main-on-ci-flake.md) — when CI flakes recurringly and adjacent PRs pass, run `git log HEAD..origin/main` before retry loops; main may already have the fix
- [SonarCloud PR not-found race](sonarcloud-pr-not-found-race.md) — SonarCloud exit-3 failures have three distinct shapes (webhook race, org/projectKey drift, scan timeout); each has a different fix
- [detect-secrets baseline loop](detect-secrets-baseline-loop.md) — detect-secrets rewrites generated_at on every run and exits non-zero; converges after 2-3 `git add .secrets.baseline` cycles
- [PEM header pre-commit trap](pem-header-pre-commit-trap.md) — a literal `-----BEGIN PRIVATE KEY-----` in any file trips detect-secrets and detect-private-key hooks; use a placeholder instead
- [Command-scanning hook heredoc trap](command-scanning-hook-heredoc-trap.md) — PreToolUse hooks see heredoc bodies; commit messages/PR bodies that document blocked patterns trip the hook; use `-F` / `--body-file`
- [macOS FIDO2 ssh-agent](macos-fido2-ssh-agent.md) — macOS launchd ssh-agent holds sk-key metadata but refuses signing; bypass with SSH_AUTH_SOCK= or a Homebrew-only agent
- [macOS screen recording workaround](macos-screen-recording-workaround.md) — TCC Screen Recording stale cache: REMOVE the app from the panel entirely and re-add (toggling off/on doesn't reset)
