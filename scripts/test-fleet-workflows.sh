#!/usr/bin/env bash
set -euo pipefail
python3 -I -B "$(dirname "$0")/test-fleet-workflows.py"
