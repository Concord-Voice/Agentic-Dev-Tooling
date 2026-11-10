#!/usr/bin/env bash
# A PR-head dependency install must never be presented as safe merely because
# its checkout lives in a detached worktree.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
python3 - "$ROOT/plugins/release-ops/skills/weekly-deps/SKILL.md" <<'PY'
from pathlib import Path
import sys
s=Path(sys.argv[1]).read_text()
section=s[s.index('4. **Run ',s.index('### 4.C')):s.index('   Use the repo\'s configured per-directory commands')]
required=('ephemeral sandbox','host credentials','network','NOT RUN')
for phrase in required:
    if phrase not in section:
        raise SystemExit('FAIL: Tier C test instructions lack ' + phrase)
if 'git worktree add --detach' in section:
    raise SystemExit('FAIL: detached host worktree still offered as test isolation')
probe=s[s.index('   **4b. For a bundled-engine bump'):s.index('   For each row Step 2b marked exposed')]
if 'sandbox' not in probe or 'NOT RUN' not in probe:
    raise SystemExit('FAIL: runtime probes can bypass the sandbox gate')
print('ALL PASS')
PY
