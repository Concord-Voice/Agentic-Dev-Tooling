# `starter-memory` — how to consume it

A curated pack of 54 generic, hard-won facts about `gh`, git, CI, and
subagent workflows, plus an [`INDEX.md`](knowledge/memory/INDEX.md) that
one-lines every entry. It is a **seed for your own project memory**, not a
runtime component.

## It is not auto-loaded

This pack ships no skills, agents, or hooks — only markdown under
`knowledge/memory/`. Neither route loads it into a session by itself:

- **Marketplace plugin install** registers a plugin's skills/agents/hooks.
  There is no "knowledge" layer that a plugin install auto-injects into
  context, so installing this pack alone changes nothing an agent sees.
- **`install.sh claude`** copies the `plugins/*/skills` and `plugins/*/agents`
  trees. This pack has neither, so it copies nothing either.

Adopting it is therefore a deliberate, one-time copy you control.

## Adopting it

Pick whichever fits how your repo already carries knowledge.

**1. Copy into your project and reference it from `CLAUDE.md`** (recommended —
the entries become yours to prune and extend):

```bash
mkdir -p <your-repo>/knowledge
cp -R plugins/starter-memory/knowledge/memory <your-repo>/knowledge/memory
```

Then add one line to your repo's `CLAUDE.md` so the index loads with every
session and the individual files are discoverable on demand:

```markdown
@knowledge/memory/INDEX.md
```

The `@path` syntax imports that file's contents into context. Import **only the
index** — it is a compact one-line-per-fact table of contents, and an agent can
read any linked file when a task actually touches it. Importing all 54 entries
eagerly costs context on every turn for facts most sessions never need.

**2. Cherry-pick.** Nothing depends on the pack being complete. Copy only the
files whose subject matter you actually hit (`gh-token-scope.md`,
`pr-ci-merge-ref-race.md`, …) and hand-write the index rows for them.

**3. Read-only reference.** Leave the pack where it is and consult
`INDEX.md` when debugging a `gh`/CI oddity. Costs nothing, gives no automatic
recall.

## Keeping it useful

These entries came from one team's incidents. Treat the copy in your repo as
**yours from the moment you make it**: delete what does not apply to your
stack, correct anything that contradicts your tooling, and append your own
facts in the same shape (one file per fact, one index line linking to it). A
memory pack that is never pruned becomes advice an agent trusts about a system
you no longer run.

Entries here are deliberately generic — anything project-specific stayed in the
project it came from. If you promote a fact out of a project into this shape,
apply the same test: would it still be true in a repo that shares none of that
project's code?
