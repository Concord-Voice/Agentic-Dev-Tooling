#!/usr/bin/env bash
set -euo pipefail; cd "$(dirname "$0")/.."
{
  echo "# Attributions"
  echo
  echo "Generated from imports/attributions.json — do not edit by hand."
  echo
  jq -r '.[] | "## \(.name)\n- Type: \(.type)  |  Origin: \(.origin)\n- Author: \(.author)\n- Upstream: \(.upstream_url // "—")  |  License: \(.upstream_license // "—")  |  Pin: \(.version_pin // "—")\n- Modifications: \(.modifications // "none")\n"' imports/attributions.json
}
