#!/usr/bin/env bash
# A standalone repro/fix without plan files must have an explicit Phase 4 route.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
python3 - "$ROOT/plugins/core-lifecycle/skills" <<'PY'
from pathlib import Path
import sys
skills=Path(sys.argv[1]); life=(skills/'dev-lifecycle/SKILL.md').read_text(); repro=(skills/'reproduce-then-fix/SKILL.md').read_text()
mapping=life[life.index('### Phase mapping'):life.index('To distinguish Phase 3')]
for required in ('trusted in-session repro handoff','Phase 4: VALIDATE','fix SHA','repro SHA'):
 if required not in mapping: raise SystemExit('FAIL: phase map lacks '+required)
if mapping.index('trusted in-session repro handoff') > mapping.index('Branch, no spec'):
 raise SystemExit('FAIL: missing spec preempts the handoff')
section=repro[repro.index('**Standalone mode:** hand to the lifecycle'):repro.index('### Why this skill stops here')]
for required in ('repro SHA','fix SHA','same session'):
 if required not in section: raise SystemExit('FAIL: standalone handoff lacks '+required)
print('ALL PASS')
PY
