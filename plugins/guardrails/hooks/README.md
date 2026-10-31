# `.claude/hooks/` — Inventory and Bypass Discipline

Hooks invoked by Claude Code per its settings file. Two delivery routes register them:

- **`install.sh claude`** merges the wiring in
  [`config/base.settings.json`](../../../config/base.settings.json) into
  `<root>/.claude/settings.json` (non-destructively — your own entries are kept).
- **Marketplace plugin install** registers them from this plugin's
  [`hooks/hooks.json`](hooks.json) instead; no settings.json edit is involved.

[`config/consumer-settings.example.json`](../../../config/consumer-settings.example.json)
is the fuller worked example — the same hooks plus per-hook `timeout` values, an
expanded permissions deny/allow list, and optional third-party hook entries.

## Hook inventory

| Hook | Tool | When it fires | What it does |
|---|---|---|---|
| [`auto-format.sh`](auto-format.sh) | PostToolUse(Edit/Write) | After every file edit | Runs the appropriate formatter (prettier, gofmt) on the changed file. |
| [`destructive-commands.sh`](destructive-commands.sh) | PreToolUse(Bash) | Before every Bash command | Blocks force-push (not `--force-with-lease`), `git reset --hard`, `git clean -f`, recursive `rm`, working-tree `git checkout`/`git restore`, `git branch -D`, `DROP TABLE`, `pkill`, etc. A best-effort regex guard checked in the hook, so it does not depend on a settings.json deny list; keep the deny list too. Needs `perl` (standard on macOS and Linux) to read quoted spans. See "Scoped bypass channels" below. |
| [`detect-secrets.sh`](detect-secrets.sh) | UserPromptSubmit | On prompt submit | Scans the submitted prompt for likely secrets (AWS keys, GitHub tokens, PEM blobs, etc.) and blocks submission on a high-confidence match. |
| [`issue-creation-nudge.sh`](issue-creation-nudge.sh) | UserPromptSubmit | On prompt submit | Nudges toward `/issue-creation` when the user describes new work. |
| [`protect-applied-migrations.sh`](protect-applied-migrations.sh) | PreToolUse(Edit) | Before editing a migration file | Blocks edits to migrations that already shipped to production. |
| [`protect-env-files.sh`](protect-env-files.sh) | PreToolUse(Edit/Write) | Before editing `.env` files | Hard block; env files must be edited by the operator on the server, not via agent. |
| [`protect-sensitive.sh`](protect-sensitive.sh) | PreToolUse(Edit/Write) | Before editing files matching `PROTECTED_PATTERNS` | Blocks edits to security-sensitive paths (`/e2ee/`, `/crypto/`, `/auth/`, `/preload/`, `src/main/ipc/`, etc.) unless authorized via marker file. |
| [`test-reminder.sh`](test-reminder.sh) | PostToolUse(Edit/Write) | After editing a test file | Reminds to run tests. |

## Scoped bypass channels

A few hooks support per-invocation bypass to avoid friction for legitimate automation that the static block would otherwise prevent. **Each bypass is structurally narrow** (one specific operation, not a global escape hatch) and uses a different mechanism appropriate to the use case.

### `destructive-commands.sh` — env-var prefix for `git branch -D`

**Mechanism.** Prepend `env CLAUDE_HOOK_ALLOW_BRANCH_DELETE=1` to a `git branch -D <branch>` invocation:

```bash
env CLAUDE_HOOK_ALLOW_BRANCH_DELETE=1 git branch -D feature/foo-bar
```

The hook string-matches the prefix in the command text (NOT the inherited env var — see "Detection model" below), strips it, then validates the remainder is exactly `git branch -D <branch>` with no shell metacharacters. Any chained command, command-substitution, or branch name with `;` / `&&` / `||` / `` ` `` / `$()` re-triggers the standard block.

**Use case.** The `commit-commands:clean_gone` skill iterates over `[gone]` branches and calls `git branch -D` on each. Without this bypass, every `clean_gone` invocation hits the block and requires a 3-step chmod-dance workaround. With the bypass, the skill prepends the prefix to its inner `git branch -D` call and runs end-to-end.

**Detection model.** The hook runs in the shell that *receives* the command, not the shell that *executes* it — so the env var on the actual subprocess (`env VAR=1 cmd`) doesn't propagate to the hook's process. The hook must inspect the command STRING itself. This gives a stricter security guarantee: bypass is only honored when the command literally begins with the prefix; you can't trip it accidentally by exporting `CLAUDE_HOOK_ALLOW_BRANCH_DELETE=1` in your shell.

**Logging.** Every bypass invocation emits `BYPASS: branch delete authorized (CLAUDE_HOOK_ALLOW_BRANCH_DELETE=1): <command>` to stderr. Post-hoc transcript review can identify every bypass event.

**Out of scope.** The bypass is scoped to `git branch -D` ONLY. `git push --force`, `git reset --hard`, `rm -rf`, `pkill`, etc. continue to block unconditionally.

**Plugin-cache customization.** The `commit-commands:clean_gone` skill lives in the upstream plugin cache and must be customized to use the env prefix. The customization is documented in `.claude/rules/plugin-cache-customization.md` (installed there by `install.sh claude`; source: [`docs/rules/plugin-cache-customization.md`](../../../docs/rules/plugin-cache-customization.md)), and the bypass itself is covered by [`scripts/test-hooks.sh`](../../../scripts/test-hooks.sh). The auto-mode classifier blocks agent-side edits to upstream plugin files, so the customization is a one-time manual step after merge (re-applied after each plugin upgrade per the rule file's "Re-applying after a plugin upgrade" procedure).

### `protect-sensitive.sh` — marker file

**Mechanism.** Write a list of authorized file paths to `.claude/state/hook-bypass/<sanitized-branch>.txt`. The hook reads the file and allows edits to listed paths.

**Use case.** When a spec or plan deliberately edits a security-sensitive file (e.g., a key-rotation feature that touches `/e2ee/`), the brainstorming and writing-plans skills prompt the developer to authorize the bypass once for the branch.

**Why a different mechanism than destructive-commands?** `protect-sensitive` blocks per-file edits across the branch's lifetime (many edits, many files); env-var-per-invocation would be repetitive. `destructive-commands` blocks one specific git operation that fires from a known skill loop; marker-file would be unnecessarily heavy.

See the `skills/brainstorming/SKILL.md` and `skills/writing-plans/SKILL.md` files in the **active** superpowers install for the prompt mechanics. Resolve that path from the plugin manifest rather than guessing a version directory — the cache keeps every version ever downloaded, and only one is loaded:

```bash
jq -r '.plugins["superpowers@claude-plugins-official"][].installPath' ~/.claude/plugins/installed_plugins.json
```

If the sections are missing there, the last plugin upgrade wiped them — re-apply per `.claude/rules/plugin-cache-customization.md`.

## Adding a new bypass channel

Before adding a new bypass mechanism to any hook, consider:

1. **Is there an existing channel that fits?** The env-var prefix for command-scoped bypasses; the marker file for branch-scoped edit bypasses. A third mechanism should justify its existence over both.
2. **Is the bypass structurally narrow?** A bypass that allows the entire blocked category for a session is a regression toward "global escape hatch."
3. **Is the bypass auditable?** Every bypass should emit a stderr log line so post-hoc review can find it.
4. **Does the bypass require an explicit, deliberate signal?** Implicit / shell-exported / file-presence-without-write defeats the safety model.

Document any new bypass channel in this README and add a corresponding smoke test under `scripts/test-<hook>-*.sh`.

## Disabling a hook (emergency)

`chmod -x .claude/hooks/<hook>.sh` disables the hook. The `protect-sensitive` hook is the canonical case where this is occasionally needed for ad-hoc edits not covered by the marker file. **The destructive-commands hook should rarely need chmod-disable** — the env-var bypass covers the known friction case.

Always `chmod +x` to re-enable.

## References

- [`config/base.settings.json`](../../../config/base.settings.json) — the wiring `install.sh claude` merges into your `.claude/settings.json`
- [`config/consumer-settings.example.json`](../../../config/consumer-settings.example.json) — fuller worked settings example (timeouts, deny/allow lists, optional third-party hooks)
- [`hooks/hooks.json`](hooks.json) — the same wiring for the marketplace plugin-install route
- `.claude/rules/plugin-cache-customization.md` — upstream plugin modifications (installed by `install.sh claude`; source under [`docs/rules/`](../../../docs/rules/))
- [`../../core-lifecycle/agents/`](../../core-lifecycle/agents/) — agent definitions (some agents have hook-bypass needs documented in their frontmatter)
- Memory `protect_sensitive_hook` — historical context on the marker-file bypass mechanism
