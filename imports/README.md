# Third-party imports — fetch from source

Nothing here is vendored except where a confirmed redistribution license allows it
(see `plugins/writing/skills/ste-writing` and `plugins/writing/skills/i-have-adhd`,
the two exceptions — each keeps its upstream `LICENSE` beside the tree). Everything else in the launch roster is installed from
upstream at use time, not copied into this repo. Full detail, including license and
pin info, lives in `imports/attributions.json` (source of truth) and the generated
`ATTRIBUTIONS.md` (human-readable render — regenerate with
`scripts/generate-attributions.sh`, never hand-edit).

## Per-import fetch instructions

- **superpowers, mattpocock-skills, pr-review-toolkit** — official/curated
  marketplace entries: `claude plugin marketplace add claude-plugins-official`
  then `claude plugin install <name>`.
- **ponytail** — its own marketplace: `claude plugin marketplace add
  DietrichGebert/ponytail` per the upstream README, then install the plugin.
- **graphify** — install per upstream instructions
  (`github.com/Graphify-Labs/graphify`, dual-licensed Apache-2.0/MIT). It's an
  external CLI dependency, not a skill or agent tree — fetch-only by policy,
  do not vendor.
- **rulesync** — installer dependency, pinned to `16.7.0`. Installed via the
  package manager the installer uses (see `scripts/` machinery), not copied
  into this tree.

## Origin values

Each `imports/attributions.json` record's `origin` is one of four values:
`custom` (written here, no upstream), `imported` (vendored or pulled in as a
pinned dependency, upstream credited), `derived` (written here but its
pattern/discipline is knowingly adapted from an upstream project, credited in
`modifications`), or `referenced` (never vendored — installed straight from
upstream at use time, credited here and in `attributions.json` all the same).

## Vendoring policy

Only vendor a third-party skill or tool when its upstream license explicitly
permits redistribution, and only by keeping the upstream `LICENSE` (or a
`LICENSE.upstream` file, when the repo's own top-level `LICENSE` also applies
to local modifications) beside the vendored tree — see
`plugins/writing/skills/ste-writing/LICENSE.upstream` for the pattern this
repo follows. Everything without a confirmed license, or without a need to
ship the code itself, stays referenced-only: installed from upstream by the
consumer, never copied here.
