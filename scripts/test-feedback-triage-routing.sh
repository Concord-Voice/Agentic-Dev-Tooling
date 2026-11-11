#!/usr/bin/env bash
# Unit tests for feedback-triage multi-repo routing, validation, and alpha ref resolution.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SKILL_MD="$ROOT/plugins/release-ops/skills/feedback-triage/SKILL.md"
ALPHA_SYNC_MD="$ROOT/plugins/release-ops/skills/feedback-triage/references/alpha-sync.md"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

extract_block_starting_with() {
  local marker="$1"
  awk -v marker="$marker" '
    index($0, marker) { capture=1 }
    capture && /^```$/ { capture=0; exit }
    capture { print }
  ' "$SKILL_MD"
}

PHASE0_CODE="$(extract_block_starting_with '# Optional owning-repo map')"
[ -n "$PHASE0_CODE" ] || fail "could not extract Phase 0 routing block from $SKILL_MD"

PHASE6_CODE="$(extract_block_starting_with 'resolve_alpha_ref() {')"
[ -n "$PHASE6_CODE" ] || fail "could not extract resolve_alpha_ref from $SKILL_MD"

# shellcheck disable=SC1090
eval "$PHASE6_CODE"

run_phase0() {
  local cfg_json="$1" tracker="$2" pub="$3"
  (
    set -euo pipefail
    # shellcheck disable=SC2034,SC2329 # Consumed dynamically inside eval "$PHASE0_CODE".
    TRACKER="$tracker"
    # shellcheck disable=SC2034 # Consumed dynamically inside eval "$PHASE0_CODE".
    PUBLIC="$pub"
    # shellcheck disable=SC2329 # Invoked dynamically inside eval "$PHASE0_CODE".
    rc_get() {
      local filter="$1" def="$2" out
      if ! out=$(printf '%s' "$cfg_json" | jq -r "$filter" 2>/dev/null); then
        printf '%s' "$def"
        return 0
      fi
      printf '%s' "$out"
    }
    eval "$PHASE0_CODE"
    printf '%s\n' "$CANDIDATE_TRACKERS"
  )
}

# 1. Happy path: unset routing falls back to $TRACKER only
out="$(run_phase0 '{}' 'example-org/tracker-main' 'example-org/public-feedback')"
expected=$'example-org/tracker-main'
[ "$out" = "$expected" ] || fail "unset routing mismatch: got '$out', expected '$expected'"

# 2. Happy path: multi-repo routing strips .git and deduplicates case-insensitively
out="$(run_phase0 \
  '{"feedback_triage":{"routing":{"core":"Example-Org/Tracker-Main.git","client":"example-org/app-client","ops":"example-org/ops-repo.git","dup":"EXAMPLE-ORG/APP-CLIENT"}}}' \
  'example-org/tracker-main' \
  'example-org/public-feedback')"
expected=$'example-org/tracker-main\nexample-org/app-client\nexample-org/ops-repo'
[ "$out" = "$expected" ] || fail "dedup routing mismatch: got '$out', expected '$expected'"

# 3. Fail-closed: routing entry equal to $PUBLIC (case-insensitive / .git) must error
if run_phase0 '{"feedback_triage":{"routing":{"leak":"EXAMPLE-ORG/PUBLIC-FEEDBACK.git"}}}' 'example-org/tracker-main' 'example-org/public-feedback' >/dev/null 2>&1; then
  fail "expected Phase 0 to fail when routing points to PUBLIC"
fi

# 4. Fail-closed: malformed repo slug (space or missing owner) must error
if run_phase0 '{"feedback_triage":{"routing":{"bad":"not valid/repo"}}}' 'example-org/tracker-main' 'example-org/public-feedback' >/dev/null 2>&1; then
  fail "expected Phase 0 to fail on malformed repo slug"
fi

# 5. Fail-closed: non-string routing value or non-object routing must error
if run_phase0 '{"feedback_triage":{"routing":{"bad":123}}}' 'example-org/tracker-main' 'example-org/public-feedback' >/dev/null 2>&1; then
  fail "expected Phase 0 to fail on non-string routing value"
fi
if run_phase0 '{"feedback_triage":{"routing":["example-org/app-client"]}}' 'example-org/tracker-main' 'example-org/public-feedback' >/dev/null 2>&1; then
  fail "expected Phase 0 to fail on non-object routing config"
fi

# 6. Phase 6 resolve_alpha_ref: owner/repo#N, repo#N, #N, and bare N
CANDS=$'example-org/tracker-main\nexample-org/app-client\nexample-org/ops-repo'

resolve_alpha_ref 'example-org/app-client#45' 'example-org/tracker-main' "$CANDS" 'example-org/public-feedback'
[ "$ALPHA_REPO" = 'example-org/app-client' ] && [ "$ALPHA_NUM" = '45' ] || fail "owner/repo#N resolution failed: $ALPHA_REPO#$ALPHA_NUM"

resolve_alpha_ref 'app-client#89' 'example-org/tracker-main' "$CANDS" 'example-org/public-feedback'
[ "$ALPHA_REPO" = 'example-org/app-client' ] && [ "$ALPHA_NUM" = '89' ] || fail "repo#N resolution failed: $ALPHA_REPO#$ALPHA_NUM"

resolve_alpha_ref '#3692' 'example-org/tracker-main' "$CANDS" 'example-org/public-feedback'
[ "$ALPHA_REPO" = 'example-org/tracker-main' ] && [ "$ALPHA_NUM" = '3692' ] || fail "#N resolution failed: $ALPHA_REPO#$ALPHA_NUM"

resolve_alpha_ref '4123' 'example-org/tracker-main' "$CANDS" 'example-org/public-feedback'
[ "$ALPHA_REPO" = 'example-org/tracker-main' ] && [ "$ALPHA_NUM" = '4123' ] || fail "bare N resolution failed: $ALPHA_REPO#$ALPHA_NUM"

# 7. Phase 6 resolve_alpha_ref fail-closed cases: $PUBLIC target, ambiguous basename, malformed ref
if resolve_alpha_ref 'example-org/public-feedback#9' 'example-org/tracker-main' "$CANDS" 'example-org/public-feedback'; then
  fail "expected resolve_alpha_ref to reject PUBLIC repo"
fi

AMBIG_CANDS=$'example-org/tracker-main\nexample-org/app-client\nother-org/app-client'
if resolve_alpha_ref 'app-client#10' 'example-org/tracker-main' "$AMBIG_CANDS" 'example-org/public-feedback'; then
  fail "expected resolve_alpha_ref to reject ambiguous repo#N basename across orgs"
fi

if resolve_alpha_ref 'example-org/app-client#abc' 'example-org/tracker-main' "$CANDS" 'example-org/public-feedback'; then
  fail "expected resolve_alpha_ref to reject non-numeric issue number"
fi

# 8. Crash-recovery jq filter syntax & epic label extraction check
JQ_FILTER="$(awk '/select\(\(\.body \/\/ ""\) \| contains\(\$pub_url\)\)/{gsub(/^ *'\''|'\'' *$/, ""); print; exit}' "$SKILL_MD")"
[ -n "$JQ_FILTER" ] || fail "could not extract crash-recovery jq filter from $SKILL_MD"
jq_out="$(printf '%s' '[{"number":4370,"body":"Refs https://github.com/example-org/public-feedback/issues/91","labels":[{"name":"type: epic"}]},{"number":999,"body":"unrelated #91","labels":[]}]' \
  | jq -r --arg repo "example-org/tracker-main" --arg pub_url "https://github.com/example-org/public-feedback/issues/91" "$JQ_FILTER")"
expected_jq=$'example-org/tracker-main#4370\ttrue'
[ "$jq_out" = "$expected_jq" ] || fail "crash-recovery jq filter mismatch: got '$jq_out', expected '$expected_jq'"

# 9. Regression guard: sub-issue linking must never force replace_parent
if grep -q -- 'replace_parent' "$ALPHA_SYNC_MD"; then
  fail "$ALPHA_SYNC_MD must not reference replace_parent when linking sub-issues"
fi

echo "PASS: test-feedback-triage-routing"
