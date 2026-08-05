#!/usr/bin/env bash
# Test harness for repo-config.sh — verifies present/absent/null/default behavior.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
fail() { echo "FAIL: $*" >&2; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# Case A: no config file → rc_get returns the default; rc_has is false.
( cd "$TMP"
  export RC_FILE="$TMP/.claude/repo-config.json"
  source "$HERE/repo-config.sh"
  [ "$(rc_get '.default_branch' main)" = "main" ] || fail "absent: default not returned"
  rc_has '.project' && fail "absent: rc_has should be false" || true
)

# Case B: present config → values read; null key → default; missing key → default.
mkdir -p "$TMP/.claude"
cat > "$TMP/.claude/repo-config.json" <<'JSON'
{ "default_branch": "trunk", "project": null, "quality_gate": { "enabled": true, "coverage_min": 80 }, "flag_off": false, "count_zero": 0, "empty_str": "" }
JSON
( cd "$TMP"
  export RC_FILE="$TMP/.claude/repo-config.json"
  source "$HERE/repo-config.sh"
  [ "$(rc_get '.default_branch' main)" = "trunk" ] || fail "present: value not read"
  [ "$(rc_get '.project.id' NONE)" = "NONE" ] || fail "null section: default not returned"
  [ "$(rc_get '.quality_gate.coverage_min' 0)" = "80" ] || fail "nested: value not read"
  rc_has '.quality_gate' || fail "present: rc_has should be true"
  rc_has '.project' && fail "null: rc_has should be false for null" || true
  [ "$(rc_get '.flag_off' true)" = "false" ] || fail "false value must be returned, not default"
  [ "$(rc_get '.count_zero' 9)" = "0" ] || fail "zero value must be returned, not default"
  [ "$(rc_get '.empty_str' DEF)" = "" ] || fail "empty-string value must be returned verbatim"
  rc_has '.flag_off' || fail "rc_has should be true for a present false value"
)

# Case C: malformed JSON → rc_get returns default (never errors out the caller).
echo "{ not json" > "$TMP/.claude/repo-config.json"
( cd "$TMP"
  export RC_FILE="$TMP/.claude/repo-config.json"
  source "$HERE/repo-config.sh"
  [ "$(rc_get '.default_branch' main)" = "main" ] || fail "malformed: default not returned"
)

echo "ALL PASS"
