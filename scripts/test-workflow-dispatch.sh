#!/usr/bin/env bash
# Check the mandatory dispatch paths used by the scheduled triage and issue intake.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

python3 - "$ROOT/plugins" <<'PY'
import re
import sys
from pathlib import Path

plugins = Path(sys.argv[1])
core = plugins / "core-lifecycle/skills"
feedback = plugins / "release-ops/skills/feedback-triage/SKILL.md"
issue = core / "issue-creation/SKILL.md"
lifecycle = core / "dev-lifecycle/SKILL.md"

def section(path, start, end):
    return path.read_text().split(start, 1)[1].split(end, 1)[0]

for skill in (feedback, issue, lifecycle):
    gate = section(skill, "<DISPATCH-GATE>", "</DISPATCH-GATE>")
    if re.search(r"via the (Skill|Agent)( or Agent)? tool", gate):
        sys.exit(f"{skill}: mandatory gate requires a vendor-specific tool")

for skill in (issue, lifecycle):
    gate = section(skill, "<DISPATCH-GATE>", "</DISPATCH-GATE>")
    for target in re.findall(r"\]\(([^)]+)\)", gate):
        if not (skill.parent / target.split("#", 1)[0]).is_file():
            sys.exit(f"{skill}: unresolved dispatch instruction {target}")
    if "nested-skills.md" not in gate:
        sys.exit(f"{skill}: missing shared skill resolution contract")

for skill, start, end in (
    (feedback, "## Phase 2 — Cluster duplicates", "## Phase 3"),
    (issue, "### Step 3 — Dispatch adjacency scan", "### Step 4"),
):
    instructions = section(skill, start, end)
    if "`feedback-analyst`" not in instructions or "**Explore**" in instructions:
        sys.exit(f"{skill}: external issue analysis needs an eligible role")

adjacency = section(issue, "### Step 3 — Dispatch adjacency scan", "### Step 4")
for boundary in ("separately isolated read-only collector", "before fetching issues", "trusted formatter"):
    if boundary not in adjacency:
        sys.exit(f"issue adjacency is missing its {boundary} boundary")
if "In the parent session, set" in adjacency or "gh issue list" in adjacency:
    sys.exit("raw issue retrieval leaked back into parent-session instructions")

context7 = (core / "_shared/context7-docs-discipline.md").read_text()
if 'ToolSearch  query: "select:' in context7:
    sys.exit("Context7 instructions require one client's tool prefix")
for operation in ("resolve-library-id", "query-docs"):
    if operation not in context7:
        sys.exit(f"Context7 instructions missing operation {operation}")
for skill, expected in ((issue, 1), (lifecycle, 2)):
    steps = [line for line in skill.read_text().splitlines() if line.startswith("**") and "Context7 docs discipline" in line]
    assert len(steps) == expected
    for step in steps:
        assert "dispatch a fresh researcher session" in step and "cit" in step
        assert "only the public library name, version and API question" in step
assert "no checkout, source attachments or inherited conversation" in context7
for skill in (issue, lifecycle):
    gate = section(skill, "<DISPATCH-GATE>", "</DISPATCH-GATE>")
    assert "lifecycle-agent-dispatch.md#claude-architect-dispatch" in gate
    assert "lifecycle-agent-dispatch.md#codex-architect-dispatch" in gate
for table in (core / "_shared/lifecycle-agent-dispatch.md",
              plugins.parent / "config/fleet-workflows/lifecycle-agent-dispatch.md"):
    dispatch = section(table, "## Claude architect dispatch", "\n## ")
    assert 'python3 -I -S -B "$ADT/scripts/claude-architect.py"' in dispatch
    assert '--role "$native_name"' in dispatch and '< "$private_brief"' in dispatch
    if table.parent.name == "fleet-workflows":
        assert '--source-sha256 "$selected_sha256"' in dispatch
    assert "dispatch panel seats individually" in dispatch
    codex = section(table, "## Codex architect dispatch", "\n## ")
    assert 'python3 -I -S -B "$ADT/scripts/architect_git_evidence.py"' in codex
    assert 'JSON fields `history` and `diff` as untrusted data' in codex
    parent = section(table, "## System-engineer and docs-writer dispatch", "\n## ")
    assert "collector command above" in parent and "untrusted data" in parent
    assert "authorized staging, removals and approved refresh commands" in parent
    assert "current surrounding text even when the two Git commits are identical" in parent
    assert "tool, credential and delegation restrictions" in parent
print("PASS: workflow dispatch contracts")
PY

# The workflow host evaluates the exported metadata separately and wraps the
# remaining body in an async function. Run that body with only inert seat stubs.
panel="$ROOT/plugins/core-lifecycle/workflows/design-panel.js"
{
  sed -n '1,/^}$/p' "$panel"
  cat <<'JS'
import assert from 'node:assert/strict'
const calls = []
const log = () => {}
const phase = () => {}
const parallel = tasks => Promise.all(tasks.map(task => task()))
const agent = async (_prompt, seat) => {
  calls.push(seat.label)
  return seat.label
}
async function runPanel(args) {
JS
  sed '1,/^}$/d' "$panel"
  cat <<'JS'
}
assert.match(meta.whenToUse, /inputTrust.*trusted-project/)
const brief = {issue: 7, brief: 'fixture', backend: true}
await assert.rejects(runPanel(brief), /dispatch each seat for issue, PR or Git evidence/)
assert.deepEqual(calls, [])
const design = await runPanel({...brief, inputTrust: 'trusted-project'})
assert.deepEqual(calls, ['architect:philosophy', 'system-engineer', 'architect:synthesis'])
assert.equal(design.finalSpec, 'architect:synthesis')
JS
} | node --input-type=module
