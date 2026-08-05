#!/usr/bin/env bash
set -euo pipefail; cd "$(dirname "$0")/.."
jq -e 'type=="array" and length>0' imports/attributions.json >/dev/null || { echo "FAIL: bad json"; exit 1; }
jq -e 'all(.[]; has("name") and has("type") and has("author") and has("origin"))' imports/attributions.json >/dev/null \
  || { echo "FAIL: missing required keys"; exit 1; }
jq -e 'all(.[]; .origin | IN("custom","imported","derived","referenced"))' imports/attributions.json >/dev/null \
  || { echo "FAIL: bad origin enum"; exit 1; }
bash scripts/generate-attributions.sh > /tmp/attr.md
diff -q /tmp/attr.md ATTRIBUTIONS.md || { echo "FAIL: ATTRIBUTIONS.md stale"; exit 1; }
echo ok
