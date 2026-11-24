# Threat model — Agentic-Dev-Tooling

| Field | Value |
|---|---|
| Repository | Concord-Voice/Agentic-Dev-Tooling |
| Visibility | Public |
| Last reviewed | 2026-11-23 at commit `7992a84` |
| Owner | Concord Voice maintainers |
| Review when | A change to authentication, a trust boundary, or exposed surface; and at each release. Here that means: a new or changed hook, bypass channel, installer target, sync path, CI workflow, or a skill or agent that gains a tool. |

## System summary

This repository is a library of instructions and guard scripts for AI coding agents. It ships no network service and processes no user data. Its content runs in two places: on developer machines, with the developer's credentials, and in the CI of consuming repositories. Production use is an agent session in a consuming repository with the hooks active. Agents there can run shell, edit files, push branches, open pull requests and comment; in the automated lifecycle mode they do so with no person present until the merge.

- **Content.** Seven plugin packs under `plugins/` hold skills and agent definitions (Markdown that agents follow), hook scripts, and a starter memory pack. `.claude-plugin/marketplace.json` lists them.
- **Control layer.** `plugins/guardrails/hooks/` holds the hooks that inspect an agent's tool calls. `config/base.settings.json` wires them and adds a read deny list.
- **Distribution.** Five routes reach a consumer: `install.sh` (five platform targets; non-Claude targets compile through the pinned npm tool `rulesync@16.7.0`; `--agents-only` installs role profiles alone, rendered by `scripts/render-agent-profiles.py`), the plugin marketplace, the scheduled workflow `templates/sync-tooling.yml`, the copy and symlink scripts described in `docs/org-tooling-distribution.md`, and a pinned workflow edition that `scripts/resolve-fleet-workflow.py` builds into a private cache from sources locked by hash in `config/fleet-workflows/sources.json`. `CAPABILITIES.md` records which layers survive on each platform.
- **Build and release workflows.** `.github/workflows/ci.yml` (publish guard, unit tests, installer smoke test), `.github/workflows/static-analysis.yml` (ShellCheck and Semgrep, pinned), `.github/workflows/sonarcloud.yml` (same-repository pull requests and the default branch only). There is no tagged release: consumers take the default branch. `scripts/publish-guard.sh` screens the tree before publication.
- **Tests.** The `scripts/test-*.sh` harnesses, run by CI. `scripts/test-hooks.sh` covers the guards; `scripts/test-install.sh` and `scripts/test-install-platforms.sh` cover the installer.

## Assets

Ranked by value to an attacker.

1. **Integrity of what agents are told to do**: skill, agent, rule and memory text. One change here changes agent behaviour in every consumer.
2. **Integrity of the control layer**: hook scripts, their wiring (`config/base.settings.json`, `plugins/guardrails/hooks/hooks.json`), and the bypass channels in `plugins/guardrails/hooks/README.md`.
3. **Developer and CI authority that agents and scripts borrow**: the developer's GitHub session, shell, SSH and cloud credentials; the developer's AI-client login (`auth.json` in the client's home directory), which the review worker started by `scripts/codex-isolated-review.py` reuses; in consumers, the sync workflow's App key (a consumer secret, named `SYNC_APP_PRIVATE_KEY` in the template `templates/sync-tooling.yml`) and its write token.
4. **Integrity of the distribution path**: `install.sh`, `templates/sync-tooling.yml`, `scripts/sync-shared-safe.py`, `scripts/render-agent-profiles.py`, `scripts/resolve-fleet-workflow.py` with its hash manifest `config/fleet-workflows/sources.json`, the install lock, and the pinned third-party versions.
5. **Secrets in agent or CI reach**: env files, credential files, anything pasted into a prompt or printed into tool output or logs; and this repository's CI secrets `SONAR_TOKEN`, `PUBLISH_GUARD_DENYLIST` and `PUBLISH_GUARD_ALLOWLIST` (repository secrets, read in `.github/workflows/`).
6. **Confidentiality of organisation-internal identifiers** that the publish guard keeps out of this public tree.

## Adversaries

| Adversary | Goal | Starts with | Does not have | A failure grants |
|---|---|---|---|---|
| Anonymous internet user | Steer an agent, or land a change here | A GitHub account: can open a fork pull request, file an issue, comment on a public repository, publish a web page | Write access; CI secrets; a developer's session | Agent actions under a developer's identity, or malicious content merged upstream |
| Compromised dependency or CI input | Run code at install time or in CI | Control of an npm package, an action, a scanner ruleset, or a third-party plugin | A place in this repository's review | Code execution as the developer or the CI runner |
| Compromised or mistaken upstream change | Reach every consumer at once | A merged commit on the default branch | Direct write to consumer default branches | Tooling changes proposed to, or installed in, each consumer |
| Compromised or misdirected AI agent | Exceed its task; persist | The session's tools and the developer's credentials; in an unattended mode, no person watching before the merge gate | The human decision at the merge gate | Edits to protected files, destructive git operations, pushed branches and opened pull requests, secret disclosure, poisoned instructions |
| Pull-request author in a consumer | Weaken the review of their own change | A branch that can edit configuration and agent files | Control of the default branch | A merge with fewer reviewers than policy requires |

## Attack surface

| Entry point | Code path | Who can reach it | Untrusted input | Reduce? |
|---|---|---|---|---|
| Pull request to this repository | `plugins/` (including the seed memory in `plugins/starter-memory/`), `install.sh`, `.github/workflows/ci.yml`, and the root agent instruction files such as `AGENTS.md` | Unauthenticated (fork); merged by maintainers only | Instruction and memory text, shell, workflow definitions | |
| External text read by skills | `plugins/core-lifecycle/skills/dev-lifecycle/SKILL.md`, `plugins/core-lifecycle/skills/enhanced-pr-review/SKILL.md`, `plugins/release-ops/skills/feedback-triage/SKILL.md`, `plugins/release-ops/skills/weekly-deps/SKILL.md` | Unauthenticated: anyone who can write an issue, comment, review or dependency release note | Issue and pull-request bodies, comments, bot reviews, release notes, tool output | |
| Retrieved documentation | `plugins/core-lifecycle/agents/researcher.md`, `plugins/core-lifecycle/skills/_shared/context7-docs-discipline.md` | Unauthenticated: whoever can publish text that the documentation service indexes, or a web page a session is told to fetch | Documentation passages returned by the session's documentation connector; fetched specification pages | |
| Isolated review worker | `scripts/codex-isolated-review.py`, `scripts/codex_review_session.py` | Unauthenticated: the author of any pull request whose diff is staged for review | The staged diff; the client binary, found in fixed install locations or named by the caller; every message the worker process returns | |
| Pinned workflow edition and role check | `scripts/resolve-fleet-workflow.py`, `config/fleet-workflows/sources.json`, `config/fleet-workflows/repo-config.sh` | Build-time: developer or agent session | The cache path and its parent directories; role profile files in the project; repository configuration read from the default branch | |
| Hook input | Blocking: `plugins/guardrails/hooks/destructive-commands.sh`, `plugins/guardrails/hooks/protect-sensitive.sh`, `plugins/guardrails/hooks/protect-env-files.sh`, `plugins/guardrails/hooks/protect-applied-migrations.sh`, `plugins/guardrails/hooks/detect-secrets.sh`. Non-blocking: `plugins/guardrails/hooks/auto-format.sh`, which runs local formatters on the file the agent wrote | The agent (so, indirectly, whoever steers it) | Shell command text, file paths, prompt text, the checked-out repository configuration | |
| Native installer | `install.sh`, `scripts/render-agent-profiles.py` | Build-time: developer, or consumer CI | Existing settings, lock and protected-paths files in the target; symlinks in the target path | |
| Compiled installer targets | `install.sh` (the `npx` calls) | Build-time | The npm registry package and its dependency tree | The `gemini` target is legacy: yes |
| Scheduled sync | `templates/sync-tooling.yml` | Build-time, in consumer CI | The default-branch head of this repository | |
| Marketplace install | `.claude-plugin/marketplace.json`, `plugins/guardrails/hooks/hooks.json` | Build-time: developer | Repository content at install time | |
| Copy and symlink distribution | `scripts/sync-shared-safe.py`, `scripts/setup-symlinks.sh`, `scripts/sync-all.sh`, `scripts/new-repo.sh` | Build-time: developer | Sibling directory layout; the manifest `config/shared-manifest.json`; the consumer's provenance ledger and protected-paths file | Convenience route beside the installer: yes |
| Private downstream import | `scripts/upstream-import.sh` | Build-time, in consumer CI | An upstream clone and its diff; the consumer's import configuration and lock file | |
| Session-to-session messages | `plugins/fleet/hooks/session-handshake.sh`, `plugins/fleet/skills/supervise/SKILL.md` | Other local agent sessions | Messages that arrive as user turns | Opt-in pack: keep it opt-in |
| This repository's CI | `.github/workflows/ci.yml`, `.github/workflows/sonarcloud.yml`, `.github/workflows/static-analysis.yml` | Unauthenticated (fork pull request runs the test scripts) | Pull-request code; scanner rulesets fetched at run time | |
| Publish screen | `scripts/publish-guard.sh`, `.githooks/pre-commit` | Maintainers, CI | Tree content; deny and allow lists | |

## Trust boundaries

| Boundary | Actors | What crosses | Control | Proof |
|---|---|---|---|---|
| Contributor to default branch | Fork author, maintainer | Instructions and code for all consumers | Pull-request review; blocking CI; no secrets for fork runs | `.github/workflows/ci.yml`, `.github/workflows/static-analysis.yml`, `.github/workflows/sonarcloud.yml` |
| This repository to a consumer tree | Upstream, consumer maintainer | Hooks, settings wiring, skills, agents | No-clobber copy with a lock for each platform; protected paths; no write through a symlinked directory below the target root, except a user-owned tooling directory chosen with the user-scope flag; in CI, the installer runs with no write token and only a path-filtered patch reaches the job that can push; the result is a draft pull request | `install.sh`, `templates/sync-tooling.yml` |
| This repository to a developer machine | Upstream, developer | Scripts that run as the developer on every tool call | The developer chooses to install; user scope is one explicit flag | `install.sh` |
| External content to agent instructions | Anyone who can write text an agent reads; the agent | Text that may contain directives | A written rule, in the skill or agent that reads the text, that fetched text is data and never instruction | `plugins/core-lifecycle/skills/dev-lifecycle/SKILL.md`, `plugins/release-ops/skills/weekly-deps/SKILL.md`, `plugins/core-lifecycle/agents/researcher.md` |
| Privileged session to an isolated worker | The calling session; the worker; the author of the text under review | Untrusted text in; findings out | Pull-request review on the Codex client: a separate client process; a canary run under the same sandbox profile before the input is opened; the client's own attestation that the thread is read-only with no network, tools or MCP servers, which the parent checks; a reply rebuilt from fixed severity and category codes and line numbers. Feedback clustering: a collector the skill requires to be read-only, an analyst whose definition grants no tools (a limit on Claude Code; on the Codex client a role inherits its parent's permissions), and a reply the skill validates with a shipped script. Issue adjacency scan: the same analyst; the collector's isolation and the reply check are written instructions | `scripts/codex-isolated-review.py`, `scripts/codex_review_session.py`, `plugins/core-lifecycle/skills/_shared/pr-review-agent-dispatch.md`, `plugins/core-lifecycle/agents/feedback-analyst.md`, `plugins/release-ops/skills/feedback-triage/validate-clusters.jq` |
| Agent to protected files and commands | Agent, developer | Edits and shell commands | Hooks that block on a match and fail closed when `jq` is missing or the input is malformed; a read deny list; a marker file only a person should write | `plugins/guardrails/hooks/protect-sensitive.sh`, `plugins/guardrails/hooks/destructive-commands.sh`, `config/base.settings.json` |
| Pull-request head to review policy | Pull-request author, reviewers | The reviewer roster and review floor | Policy is read from the merge base or the default branch, never from the head | `config/repo-config.reference.md`, `plugins/core-lifecycle/skills/review-pr/SKILL.md`, `plugins/core-lifecycle/skills/enhanced-pr-review/review-coverage.sh` |
| Agent to shared state and merge | Agent, developer, reviewers | Pushed branches, draft pull requests, the ready-for-review flip, comments; then the decision to merge | Only the merge is held for a person in every mode. The automated lifecycle mode pushes, opens a draft pull request, marks it ready and summons reviewers unattended. The review skill never merges. The dependency routine's scheduled modes do not merge, push or open pull requests | `plugins/core-lifecycle/skills/dev-lifecycle/SKILL.md`, `plugins/core-lifecycle/skills/enhanced-pr-review/SKILL.md`, `plugins/release-ops/skills/weekly-deps/references/autonomous-mode.md` |
| npm registry to installer | Package publisher, developer | Code executed during install | Version pin; install scripts disabled; output staged in temporary directories before the no-clobber copy | `install.sh` |
| Private sources to this public tree | Maintainers | Internal identifiers | Deny-list scan of content and path names in CI and in an opt-in pre-commit hook | `scripts/publish-guard.sh`, `config/denylist.public.txt`, `.githooks/pre-commit` |

## Security objectives

A change must keep each of these. Each is written so a reviewer can test it.

1. Every blocking hook blocks when `jq` is missing or its input is not valid JSON, and the path guard blocks on an invalid configured pattern. A change that adds a fail-closed branch adds a case for it to `scripts/test-hooks.sh`.
2. No bypass channel meant for agent use is wider than one operation or one branch-scoped list of paths, and each use writes a log line. The emergency disable in `plugins/guardrails/hooks/README.md` is a developer action, not an agent channel.
3. The installer does not overwrite a locally edited file without `--force`, never writes a protected path, and writes only under the chosen target root (`scripts/test-install.sh`).
4. In `templates/sync-tooling.yml`, upstream code never runs in a job that holds a write token, and the applied patch touches only the tooling directory and `scripts/repo-config.sh`, with no symlink or submodule.
5. A pull request cannot shrink its own review floor or reviewer roster.
6. A new or changed skill or agent that reads external content states that fetched text is data, and passes user-authored text to tools by file or standard input, never on a command line.
7. No mode merges without a human decision: the merge gate is the one checkpoint no mode waives (`plugins/core-lifecycle/skills/dev-lifecycle/SKILL.md`). Unattended runs may push a work branch, open a pull request as a draft, mark it ready and post comments; any further unattended shared-state action is a trust-boundary change. Unattended writes to a public repository stay reversible issue and comment changes inside stated caps (`plugins/release-ops/skills/feedback-triage/SKILL.md`).
8. No secret value is in the tree. Templates name secrets by environment variable only (`config/sonarqube.mcp.json`). Fork pull requests receive no CI secret.
9. Third-party actions are pinned by commit, and downloaded tools by version and, where the workflow downloads a binary, by checksum.
10. No tracked file except the deny list itself is exempt from the publish guard, and third-party content is vendored only with a licence record in `imports/attributions.json`.
11. The review worker returns to the calling session only a reply rebuilt from fixed codes and line numbers, and feedback clustering accepts only a reply that passes `plugins/release-ops/skills/feedback-triage/validate-clusters.jq`; neither returns free text. The review worker checks its sandbox with a canary and the client's attestation before it opens untrusted input (`scripts/test-native-agents.sh`, `scripts/test-feedback-triage-routing.sh`).

## Attack paths

Each row is a hypothesis to test, not a finding. Ranked by reach.

| # | Attacker goal | Path through the surface | Boundary that must hold | Existing control | A failure grants | Tags |
|---|---|---|---|---|---|---|
| 1 | Run code on every developer machine that uses this tooling | A harmful change to a hook, the installer or the settings wiring is merged here, then flows out by sync, marketplace update or re-install | Contributor to default branch; upstream to consumer tree | Review; CI; draft sync pull request; path filter | Code execution with developer credentials in each consumer | A03, A08, LLM03, GV, PR |
| 2 | Make an agent with push, comment and shell rights act for the attacker | Directives planted in an issue, comment, review, dependency note or web page that a skill reads | External content to agent instructions | The written data-not-instructions rule in the skills that state one; the isolated review worker and the payload-only analyst on the paths that use them; structural fields only in commands; hooks; the merge gate | Commits, pushed branches, pull requests, comments and issue changes under the developer's identity, with no person in the loop before the merge gate in an unattended mode; disclosure of context | LLM01, LLM06, LLM02, A05 |
| 3 | Reach the trust that same-repository branches carry | Steer an unattended run (path 2) so that it pushes a branch, opens a pull request and marks it ready. Workflows often trust same-repository branches more than forks, as `.github/workflows/sonarcloud.yml` does here | Agent to shared state and merge | Hooks; draft state until CI is green; the review phase; the merge gate | Attacker-influenced commits in a trusted branch: CI runs with that trust, reviewers are summoned, and one decision remains | LLM06, LLM01, A01, A08 |
| 4 | Persist altered behaviour across sessions | Change skill, agent, rule or memory text, here by pull request or in a consumer through a steered agent | Integrity of instructions | Review; install lock; `scripts/drift-check-shared.sh` | Durable poisoning of later sessions | LLM04, LLM03, A08 |
| 5 | Get an agent past a guard | A shell form the pattern guards do not model; a change to hook wiring, configuration or authorization state | Agent to protected files and commands | Fail-closed hooks; deny list; guard-protects-itself patterns in `config/repo-config.reference.md` | Edits to security-critical files; lost work | LLM06, A01, A06, A10 |
| 6 | Execute code during installation | A compromised release or dependency of the compiler package | npm registry to installer | Version pin; install scripts disabled; staging | Code execution as the developer or CI runner | A03, LLM03 |
| 7 | Read a consumer's source from its CI | Compromised upstream head runs inside the consumer's read-only sync job | Upstream to consumer tree | No write token in that job; patch filter | Read access to the consumer checkout | A03, A08, LLM03 |
| 8 | Merge with less review than policy requires | Edit review configuration or reviewer definitions on the branch; imitate a decision marker or a bot approval | Pull-request head to review policy | Merge-base reads; author-association checks on markers | A weakened review record | A01, A08, LLM06 |
| 9 | Obtain secrets | Have the agent read an env or credential file, or carry a secret into a comment, commit or log | Agent to protected files | Env-file hook; read deny list; prompt secret scan | Credential disclosure | LLM02, A02, A09 |
| 10 | Exhaust budget or attention | Induce long agent loops, large unattended batches, or message storms between sessions | Agent to shared state and merge; session messages | A turn cap in the `researcher` definition; the eight-issue batch cap of the automated mode; the three-message budget: the limit of three posts to the supervisor in a session's lifetime (login, collision, completion) that `plugins/fleet/hooks/session-handshake.sh` states | Cost and reviewer fatigue | LLM10 |

## Weakest ground

Structural, ranked. Scans start here. The hardening actions in the next section are also ranked, and each cites the item it answers by number.

1. **The instruction boundary is mostly prose.** The rule that fetched text is data lives in the wording of individual skills and in the model's compliance. Two paths add a mechanical layer: pull-request review on the Codex client runs in a separate worker (`scripts/codex-isolated-review.py`), and feedback clustering sends records to an analyst defined with no tools and an explicit deny list of built-in tools (`plugins/core-lifecycle/agents/feedback-analyst.md`) and validates the reply with a shipped script. Both rest on the client enforcing its own sandbox and tool list, and on the client's own report of them. The issue adjacency scan uses the same analyst, but its isolation and its reply check are written instructions. Every other path that reads external text has only the wording. The pinned edition carries one shared rule (`config/fleet-workflows/nested-skills.md`); in the standard packs the rule is stated per skill, so a new skill that reads external content inherits nothing. Feedback-triage also binds a public report to a tracker issue only through that issue's last non-empty line (`Refs <public URL>`), and only when the routine authored the issue or its repo is private, because the reporter's text is seeded into the tracker body; the trust rule lives in `plugins/release-ops/skills/feedback-triage/SKILL.md` Phases 4 and 6.
2. **Only the merge is held for a person.** In the automated lifecycle mode, committing, pushing, opening a pull request, marking it ready and summoning reviewers all run with no person present, for any work the developer admits, whatever its risk label (`plugins/core-lifecycle/skills/dev-lifecycle/SKILL.md`). `templates/sync-tooling.yml` also opens pull requests on a schedule. Everything before the merge gate rests on items 1 and 3, and the gate is a single decision.
3. **Pattern guards over shell text.** The command gate and the shell side of the path guard are deny lists over command strings; their own headers say so. The path guard is about 1,950 lines of shell that parses hostile input, and each widening adds adjacent surface. The read deny list in `config/base.settings.json` is the second layer, and it travels only with the `install.sh` route.
4. **Protection is off until configured.** The path guard protects nothing, including the hooks themselves, until a consumer lists patterns (`README.md`, `config/repo-config.reference.md`).
5. **Guards do not follow the instructions to every platform.** `CAPABILITIES.md` records targets that receive the skills with fewer hooks, or with none. The agency stays; the control layer does not. Role profiles now reach those targets too (`scripts/render-agent-profiles.py`), and `CAPABILITIES.md` records that on the Codex client a role inherits its parent session's permissions, so a role's tool list is advice there, not a limit.
6. **Consumers follow a moving branch.** The sync template and the marketplace take the default-branch head. There is no signed tag. The install lock detects local edits; it does not attest upstream content. The pinned workflow edition locks its text to the source hashes recorded in its manifest, but the revision it is built from is still the operator's choice.
7. **Install-time code from a registry.** The compiler package is pinned by version only, with no integrity hash and no pinned dependency tree.
8. **Hooks trust the checkout.** Hooks read repository configuration from the working tree. The skills that read configuration load `scripts/repo-config.sh` from the default-branch commit, and review policy reads from the merge base; hook decisions, and helper scripts run outside their skill, do not.
9. **Review evidence shares the agent's identity.** Decisions are recorded under the same GitHub login the agent uses, so a complete record does not prove that a person decided. The review skill says this itself.
10. **The publish screen is a short string list.** Two public patterns, an optional private list, text files only, and a local hook each contributor must enable.
11. **No ownership file and no analysis of the instruction layer.** The tree has no code-owners file. `sonar-project.properties` excludes Markdown, so only shell and Python are scanned.
12. **Each release widens the surface.** Every new skill, agent, hook, bypass or platform target adds agency. Several agent definitions hold unrestricted shell and edit tools.

## Hardening and surface reduction

1. **Second layer (6).** Publish signed, tagged releases. Give `templates/sync-tooling.yml` a pinned ref, as the tool checkout in `docs/upstream-import.md` already has, and record the upstream commit in the lock.
2. **Second layer (1).** Keep one shared instruction-source rule under `plugins/core-lifecycle/skills/_shared/`, require every skill that reads external content to cite it, and assert that in CI in the manner of `scripts/test-weekly-deps-sandbox.sh`.
3. **Narrow (2).** Run unattended modes under a separate, least-privilege identity that can push only to a work-branch namespace. Keep their pull requests in draft until a person marks them ready. Restore a mode floor for work labelled security-sensitive.
4. **Narrow (4).** Seed the guard-protects-itself patterns when a consumer has no configuration, and make `install.sh doctor` report a consumer whose guard is unconfigured.
5. **Second layer (3).** Ship the read deny list with the marketplace route. Treat the hooks as one layer and run unattended agents inside an operating-system sandbox with no host credentials.
6. **Narrow (5, 12).** On targets that lose tool-call hooks, install a reduced skill set without push, merge or posting steps. Give each agent definition the smallest tool list its role needs, and review every new tool grant as a trust-boundary change.
7. **Remove (5, 12).** Retire the `gemini` target and, once consumers use the installer, the symlink route in `scripts/setup-symlinks.sh`.
8. **Second layer (7).** Pin the compiler package by integrity hash with a locked dependency tree, and publish a CycloneDX bill of materials for the installer.
9. **Second layer (10, 11).** Add a code-owners file for `plugins/guardrails/`, `install.sh`, `templates/`, `config/base.settings.json` and `.github/workflows/`. Make the publish guard a required check and enable its local hook from a bootstrap step.
10. **Narrow (8).** Read security-relevant configuration from the default-branch tip wherever a pull request could otherwise edit it.
11. **Second layer (9).** Require an approval from an identity the agent cannot use before a merge.

## Assumptions and unknowns

- This repository runs no service and processes no personal data. Privacy regimes do not apply to it; they apply to the products that consume it.
- The model assumes each AI platform runs the configured hooks before a tool call, treats a blocking exit as a refusal, and enforces its own permission deny rules. Those behaviours belong to the platform. It also assumes each consumer protects its default branch and reviews the sync pull request before merge.
- Out of scope: third-party plugins named in `imports/README.md`, which are fetched from their own sources; a consumer's own repository configuration; any private downstream copy of this tooling; and an attacker who already controls the developer's machine, against whom hooks are no defence.

## Standards alignment

Alignment targets only. No claim of compliance or certification is made.

| Framework | What it prioritises here |
|---|---|
| OWASP Top 10 for LLM Applications 2025 | LLM01 and LLM06 first: content that agents read, and what they may do with it before a person looks. Then LLM03 and LLM04 for the instruction supply chain, and LLM02 for secrets in context. |
| OWASP Top 10:2025 | A03 and A08 dominate: this repository is a supply chain. A06 and A10 cover guards that must fail closed. |
| OWASP ASVS 5.0 | V13 Configuration: guard configuration that is safe by default (weakest ground 4). V15 Secure Coding and Architecture: pinned, attestable dependencies and releases (weakest ground 6 and 7). |
| NIST AI RMF 1.0 | Treat instruction text as a governed component of an AI system; keep human oversight at merge and decide deliberately which unattended actions come before it; measure agent behaviour instead of assuming it (`docs/ai-workflows/model-security-baselines.md`). |
| NIST CSF 2.0 | GV for supply-chain risk in both directions; PR for the hooks; DE for drift checks and bypass logs. |
