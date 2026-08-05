# Attributions

Generated from imports/attributions.json — do not edit by hand.

## core-lifecycle
- Type: skills+agents  |  Origin: custom
- Author: agentic-dev-tooling contributors
- Upstream: —  |  License: —  |  Pin: —
- Modifications: none

## guardrails
- Type: hooks  |  Origin: custom
- Author: agentic-dev-tooling contributors
- Upstream: —  |  License: —  |  Pin: —
- Modifications: none

## release-ops
- Type: skills  |  Origin: custom
- Author: agentic-dev-tooling contributors
- Upstream: —  |  License: —  |  Pin: —
- Modifications: none

## reviewer-packs
- Type: agents+templates  |  Origin: custom
- Author: agentic-dev-tooling contributors
- Upstream: —  |  License: —  |  Pin: —
- Modifications: none

## fleet
- Type: hooks+skill  |  Origin: custom
- Author: agentic-dev-tooling contributors
- Upstream: —  |  License: —  |  Pin: —
- Modifications: none

## writing
- Type: skills  |  Origin: custom
- Author: agentic-dev-tooling contributors
- Upstream: —  |  License: —  |  Pin: —
- Modifications: covers create-migration and ipc-channel-audit (original custom skills); ste-writing within this pack is vendored and has its own imported record below

## starter-memory
- Type: knowledge  |  Origin: custom
- Author: agentic-dev-tooling contributors
- Upstream: —  |  License: —  |  Pin: —
- Modifications: none

## scripts
- Type: scripts  |  Origin: custom
- Author: agentic-dev-tooling contributors
- Upstream: —  |  License: —  |  Pin: —
- Modifications: none

## config
- Type: config  |  Origin: custom
- Author: agentic-dev-tooling contributors
- Upstream: —  |  License: —  |  Pin: —
- Modifications: none

## ste-writing
- Type: skill  |  Origin: imported
- Author: woosal1337
- Upstream: https://github.com/woosal1337/blog/tree/b912d5fa59f368253683af2ebfac64ad6d08312d/videos/ep01-the-cure-for-ai-slop  |  License: MIT  |  Pin: b912d5fa59f368253683af2ebfac64ad6d08312d
- Modifications: generalized wording; vendored with LICENSE.upstream kept beside the tree in plugins/writing/skills/ste-writing

## rulesync
- Type: dependency  |  Origin: imported
- Author: dyoshikawa
- Upstream: https://github.com/dyoshikawa/rulesync  |  License: MIT  |  Pin: 16.7.0
- Modifications: none

## superpowers
- Type: marketplace plugin  |  Origin: referenced
- Author: Jesse Vincent (obra)
- Upstream: https://github.com/obra/superpowers  |  License: MIT  |  Pin: —
- Modifications: distributed via the official Anthropic marketplace (source.url points at github.com/obra/superpowers.git); fetched from upstream at install time, never vendored

## pr-review-toolkit
- Type: marketplace plugin  |  Origin: referenced
- Author: Anthropic
- Upstream: https://github.com/anthropics/claude-plugins-official/tree/main/plugins/pr-review-toolkit  |  License: Apache-2.0  |  Pin: —
- Modifications: first-party Anthropic marketplace plugin; a real dispatch dependency named in _shared/pr-review-agent-dispatch.md and dispatchable-skills.md, fetched from upstream at install time, never vendored

## mattpocock-skills
- Type: marketplace plugin  |  Origin: referenced
- Author: Matt Pocock
- Upstream: https://github.com/mattpocock/skills  |  License: MIT  |  Pin: —
- Modifications: fetched from upstream marketplace at install time; never vendored

## ponytail
- Type: marketplace plugin  |  Origin: referenced
- Author: DietrichGebert
- Upstream: https://github.com/DietrichGebert/ponytail  |  License: MIT  |  Pin: —
- Modifications: fetched from its own upstream marketplace at install time; never vendored

## graphify
- Type: tool  |  Origin: referenced
- Author: safishamsi
- Upstream: https://github.com/Graphify-Labs/graphify  |  License: Apache-2.0 OR MIT  |  Pin: —
- Modifications: fetch-only by policy — external CLI dependency, not vendored; dual-licensed upstream (LICENSE + LICENSE-MIT), github.com/safishamsi/graphify is the same project's original owner path

## dev-lifecycle
- Type: skill  |  Origin: derived
- Author: agentic-dev-tooling contributors
- Upstream: —  |  License: —  |  Pin: —
- Modifications: phase-gate pattern derived from superpowers plan-execution discipline

