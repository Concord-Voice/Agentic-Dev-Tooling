#!/usr/bin/env bash
# A PR-head dependency install must never be presented as safe merely because
# its checkout lives in a detached worktree.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
python3 - "$ROOT/plugins/release-ops/skills/weekly-deps/SKILL.md" <<'PY'
from pathlib import Path
import os, subprocess, sys
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
attribution=s[s.index('### 6.3 Third-party attribution'):]
if 'sandbox' not in attribution[:attribution.index('**If it exits non-zero')]:
    raise SystemExit('FAIL: attribution regeneration can execute dependencies on the host')
if 'local test passed)' in s:
    raise SystemExit('FAIL: summary assumes a local test passed')
if '"$RC_FILE"' in s[s.index('4. **Run ',s.index('### 4.C')):s.index('   **4b. For a bundled-engine bump')]:
    raise SystemExit('FAIL: configured commands use an unset config file')
start=s.index('   if [ "$RC_TRUSTED_STATE" = absent ]; then',s.index('### 4.C'))
end=s.index('\n   ```',start)
command=s[start:end]+'\nprintf "%s" "$LOCAL_CMDS"\n'
def run(state, config):
    return subprocess.run(['bash','-c',command],text=True,capture_output=True,
                          env={**os.environ,'RC_TRUSTED_STATE':state,'RC_TRUSTED_CFG':config,'DIR':'app'})
assert run('present','{"weekly_deps":{"local_test_cmds":{"app":["npm test","npm run lint"]}}}').stdout == 'npm test\nnpm run lint'
assert run('absent','').stdout == ''
assert run('present','not-json').returncode != 0
print('ALL PASS')
PY
