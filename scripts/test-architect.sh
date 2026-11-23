#!/usr/bin/env bash
set -euo pipefail
scripts="$(cd "$(dirname "$0")" && pwd)"
python3 -I -B "$scripts/test-architect-git-evidence.py" -v
python3 -I -B "$scripts/test-claude-architect.py" -v
