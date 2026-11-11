#!/usr/bin/env bash
# Unit tests for feedback-triage multi-repo routing, validation, and alpha ref resolution.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SKILL_MD="$ROOT/plugins/release-ops/skills/feedback-triage/SKILL.md"
ALPHA_SYNC_MD="$ROOT/plugins/release-ops/skills/feedback-triage/references/alpha-sync.md"

readonly PUBLIC_REPO="example-org/public-feedback"
readonly TRACKER_REPO="example-org/tracker-main"
readonly CLIENT_REPO="example-org/app-client"
readonly OPS_REPO="example-org/ops-repo"
readonly PUB_ISSUE_URL="https://github.com/${PUBLIC_REPO}/issues/91"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_eq() {
  local actual="$1" expected="$2" msg="$3"
  if [[ "$actual" != "$expected" ]]; then
    fail "$msg: got '$actual', expected '$expected'"
  fi
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
[[ -n "$PHASE0_CODE" ]] || fail "could not extract Phase 0 routing block from $SKILL_MD"

PHASE6_CODE="$(extract_block_starting_with 'resolve_alpha_ref() {')"
[[ -n "$PHASE6_CODE" ]] || fail "could not extract resolve_alpha_ref from $SKILL_MD"

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

assert_phase0_fails() {
  local cfg_json="$1" desc="$2"
  if run_phase0 "$cfg_json" "$TRACKER_REPO" "$PUBLIC_REPO" >/dev/null 2>&1; then
    fail "expected Phase 0 to fail when $desc"
  fi
}

# 1. Happy path: unset routing falls back to $TRACKER only
out="$(run_phase0 '{}' "$TRACKER_REPO" "$PUBLIC_REPO")"
assert_eq "$out" "$TRACKER_REPO" "unset routing mismatch"

# 2. Happy path: multi-repo routing strips .git and deduplicates case-insensitively
out="$(run_phase0 \
  "{\"feedback_triage\":{\"routing\":{\"core\":\"Example-Org/Tracker-Main.git\",\"client\":\"$CLIENT_REPO\",\"ops\":\"${OPS_REPO}.git\",\"dup\":\"EXAMPLE-ORG/APP-CLIENT\"}}}" \
  "$TRACKER_REPO" \
  "$PUBLIC_REPO")"
expected="$(printf '%s\n%s\n%s' "$TRACKER_REPO" "$CLIENT_REPO" "$OPS_REPO")"
assert_eq "$out" "$expected" "dedup routing mismatch"

# 3. Fail-closed: routing entry equal to $PUBLIC (case-insensitive / .git) must error
assert_phase0_fails '{"feedback_triage":{"routing":{"leak":"EXAMPLE-ORG/PUBLIC-FEEDBACK.git"}}}' "routing points to PUBLIC"

# 4. Fail-closed: malformed repo slug (space or missing owner) must error
assert_phase0_fails '{"feedback_triage":{"routing":{"bad":"not valid/repo"}}}' "routing contains malformed repo slug"

# 5. Fail-closed: non-string routing value or non-object routing must error
assert_phase0_fails '{"feedback_triage":{"routing":{"bad":123}}}' "routing contains non-string value"
assert_phase0_fails "{\"feedback_triage\":{\"routing\":[\"$CLIENT_REPO\"]}}" "routing is non-object JSON"

# 6. Phase 6 resolve_alpha_ref: owner/repo#N, repo#N, #N, and bare N
CANDS="$(printf '%s\n%s\n%s' "$TRACKER_REPO" "$CLIENT_REPO" "$OPS_REPO")"

resolve_alpha_ref "${CLIENT_REPO}#45" "$TRACKER_REPO" "$CANDS" "$PUBLIC_REPO"
assert_eq "${ALPHA_REPO}#${ALPHA_NUM}" "${CLIENT_REPO}#45" "owner/repo#N resolution failed"

resolve_alpha_ref 'app-client#89' "$TRACKER_REPO" "$CANDS" "$PUBLIC_REPO"
assert_eq "${ALPHA_REPO}#${ALPHA_NUM}" "${CLIENT_REPO}#89" "repo#N resolution failed"

resolve_alpha_ref '#3692' "$TRACKER_REPO" "$CANDS" "$PUBLIC_REPO"
assert_eq "${ALPHA_REPO}#${ALPHA_NUM}" "${TRACKER_REPO}#3692" "#N resolution failed"

resolve_alpha_ref '4123' "$TRACKER_REPO" "$CANDS" "$PUBLIC_REPO"
assert_eq "${ALPHA_REPO}#${ALPHA_NUM}" "${TRACKER_REPO}#4123" "bare N resolution failed"

# 7. Phase 6 resolve_alpha_ref fail-closed cases: $PUBLIC target, ambiguous basename, malformed ref
if resolve_alpha_ref "${PUBLIC_REPO}#9" "$TRACKER_REPO" "$CANDS" "$PUBLIC_REPO"; then
  fail "expected resolve_alpha_ref to reject PUBLIC repo"
fi

AMBIG_CANDS="$(printf '%s\n%s\n%s' "$TRACKER_REPO" "$CLIENT_REPO" "other-org/app-client")"
if resolve_alpha_ref 'app-client#10' "$TRACKER_REPO" "$AMBIG_CANDS" "$PUBLIC_REPO"; then
  fail "expected resolve_alpha_ref to reject ambiguous repo#N basename across orgs"
fi

if resolve_alpha_ref "${CLIENT_REPO}#abc" "$TRACKER_REPO" "$CANDS" "$PUBLIC_REPO"; then
  fail "expected resolve_alpha_ref to reject non-numeric issue number"
fi

# 8. Crash-recovery jq filter syntax & epic label extraction check
JQ_FILTER="$(awk '/select\(\(\.body \/\/ ""\) \| contains\(\$pub_url\)\)/{gsub(/^ *'\''|'\'' *$/, ""); print; exit}' "$SKILL_MD")"
[[ -n "$JQ_FILTER" ]] || fail "could not extract crash-recovery jq filter from $SKILL_MD"
jq_out="$(printf '%s' "[{\"number\":4370,\"body\":\"Refs $PUB_ISSUE_URL\",\"labels\":[{\"name\":\"type: epic\"}]},{\"number\":999,\"body\":\"unrelated #91\",\"labels\":[]}]" \
  | jq -r --arg repo "$TRACKER_REPO" --arg pub_url "$PUB_ISSUE_URL" "$JQ_FILTER")"
expected_jq="$(printf '%s#4370\ttrue' "$TRACKER_REPO")"
assert_eq "$jq_out" "$expected_jq" "crash-recovery jq filter mismatch"

# 9. Regression guard: sub-issue linking must never force replace_parent
if grep -q -- 'replace_parent' "$ALPHA_SYNC_MD"; then
  fail "$ALPHA_SYNC_MD must not reference replace_parent when linking sub-issues"
fi

echo "PASS: test-feedback-triage-routing"
