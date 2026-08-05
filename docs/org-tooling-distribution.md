# How shared tooling reaches each repository

There are two ways to consume this tooling. **Installing the plugins** from the
marketplace (`.claude-plugin/marketplace.json`) is the simplest: each plugin
brings its own skills, agents, and hooks, and updates arrive with the plugin.

The second way is the **Master pattern**: one repository in your organization
owns the canonical assets, and every other repository receives copies or links
from it. Use it when you need per-repo overrides, assets that are not packaged
as plugins (rules files, org knowledge, editor config), or a single place to
edit that many repositories track. This document describes that pattern.

## Distribution mechanics

- **Knowledge** auto-loads via the `CLAUDE.md` directory walk-up, and via the
  `AGENTS.md` import for agents that read that file instead. Put org-wide facts
  in a file at the workspace root that every nested repository inherits.

- **Skills and agents** are copied in as **REAL files** by
  `scripts/sync-shared.sh`. Claude Code's skill and agent loader walks real
  directories and ignores symlinks, so a symlinked skill or agent never loads —
  copies are not a style preference, they are the only thing that works. The
  shared set is declared in the master's `shared-manifest.json`;
  `scripts/drift-check-shared.sh` flags copies that have fallen behind the
  master.

- **Rules and hooks** are symlinked from the master into each repository's
  `.claude/` by `scripts/setup-symlinks.sh`. Hooks are invoked by path, so
  symlinks resolve correctly for them.

- **Other agent surfaces** (a second agent runtime alongside Claude Code) are
  committed repo-local files that point at the existing `.claude/` assets where
  possible, rather than duplicating their content. Keep a verification script
  for that surface — an unverified migration surface drifts silently.
  `imports/org-tooling-router.template/` is a starting point for the skill that
  routes such a runtime to the right instructions.

- **Overrides**: a repository's own `.claude/<category>/<name>` takes precedence
  over the shared one of the same name. The model is base + overlay — copy the
  shared asset down and edit it locally when a repository genuinely differs, and
  drop the local copy to rejoin the shared version.

## Adopting a template

The templates in `plugins/reviewer-packs/templates/`, the
`SKILL.md.template` files, and `imports/org-tooling-router.template/` are
**copied once and completed**, not synced. To adopt one:

1. Copy it to its live location — a reviewer template to
   `.claude/agents/<name>.md`, a scaffold template to
   `.claude/skills/<name>/SKILL.md` — dropping the `.template` suffix.
2. Complete **every** FILL slot, deleting each `<!-- FILL: … -->` comment as you
   satisfy it.
3. Verify none are left:

```bash
grep -rn 'FILL:' .claude/agents/ .claude/skills/
```

That command must print nothing. The reviewer templates also self-check: each one
refuses to emit its pass line while any `FILL:` comment remains, and reports
itself unconfigured instead — so a half-completed copy fails loudly rather than
signing off on a review it never performed. Wire the grep into your pre-commit
config to catch it earlier.

## Choosing what to share

Only assets a consumer should keep **byte-identical** to the master belong in
`shared-manifest.json`. Anything meant to be copied once and adapted locally —
the reviewer templates in `plugins/reviewer-packs/templates/`, the scaffold
skill templates, the org-tooling router — must stay out of the manifest, or the
next sync will overwrite the adopter's work.
