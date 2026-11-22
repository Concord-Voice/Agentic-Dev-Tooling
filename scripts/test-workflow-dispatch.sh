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
        if not (skill.parent / target).is_file():
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
print("PASS: workflow dispatch contracts")
PY
