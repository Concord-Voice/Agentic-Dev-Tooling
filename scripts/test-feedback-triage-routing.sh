#!/usr/bin/env bash
# Unit tests for feedback-triage multi-repo routing, validation, and alpha ref resolution.
set -euo pipefail

command -v jq >/dev/null 2>&1 || { echo "FAIL: jq is required for $0" >&2; exit 1; }

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
ME="trusted-bot"
CANDS="$(printf '%s\n%s\n%s' "$TRACKER_REPO" "$CLIENT_REPO" "$OPS_REPO")"

resolve_alpha_ref "${CLIENT_REPO}#45" "$TRACKER_REPO" "$CANDS" "$PUBLIC_REPO"
assert_eq "${ALPHA_REPO}#${ALPHA_NUM}" "${CLIENT_REPO}#45" "owner/repo#N resolution failed"

resolve_alpha_ref 'app-client#89' "$TRACKER_REPO" "$CANDS" "$PUBLIC_REPO"
assert_eq "${ALPHA_REPO}#${ALPHA_NUM}" "${CLIENT_REPO}#89" "repo#N resolution failed"

resolve_alpha_ref '#3692' "$TRACKER_REPO" "$CANDS" "$PUBLIC_REPO"
assert_eq "${ALPHA_REPO}#${ALPHA_NUM}" "${TRACKER_REPO}#3692" "#N resolution failed"

resolve_alpha_ref '4123' "$TRACKER_REPO" "$CANDS" "$PUBLIC_REPO"
assert_eq "${ALPHA_REPO}#${ALPHA_NUM}" "${TRACKER_REPO}#4123" "bare N resolution failed"

# 6b. Digit-leading repo basename parses as repo#N, not as a bare number
DIGIT_CANDS="$(printf '%s\n%s' "$TRACKER_REPO" "example-org/3d-client")"
resolve_alpha_ref '3d-client#89' "$TRACKER_REPO" "$DIGIT_CANDS" "$PUBLIC_REPO" || fail "3d-client#89 rejected"
assert_eq "${ALPHA_REPO}#${ALPHA_NUM}" "example-org/3d-client#89" "digit-leading repo#N resolution failed"

INTERNAL_REF="internal#45"
# 6c. internal#N resolves via the Refs back-reference; zero or several matches fail closed
# shellcheck disable=SC2329 # Invoked by resolve_alpha_ref.
gh_json() { local author="$1" body="$2"; jq -nc --arg a "$author" --arg b "$body" '{author:{login:$a},body:$b}'; }
# shellcheck disable=SC2329 # Invoked by resolve_alpha_ref.
gh() {
  local group="$1" number_or_repo="$3" repo_arg="${5:-}"
  if [[ "$group" == repo ]]; then # gh repo view R --json isPrivate --jq .isPrivate
    [[ "${GH_PRIV_FAIL:-}" == 1 ]] && return 1
    case "$number_or_repo" in
      "$CLIENT_REPO") printf '%s\n' "${GH_PRIV_CLIENT:-false}" ;;
      *) printf 'false\n' ;;
    esac
    return 0
  fi
  # gh issue view N --repo R --json author,body
  case "$repo_arg" in
    "$CLIENT_REPO") gh_json "${GH_CLIENT_AUTHOR:-$ME}" "${GH_CLIENT_BODY:-Refs $PUB_ISSUE_URL}" ;;
    "$OPS_REPO")
      [[ "${GH_OPS_FAIL:-}" == 1 ]] && return 1
      if [[ "${GH_OPS_ABSENT:-}" == 1 ]]; then
        echo "GraphQL: Could not resolve to an issue or pull request with the number of $number_or_repo. (repository.issue)" >&2
        return 1
      fi
      if [[ "${GH_BOTH:-}" == 1 ]]; then gh_json "$ME" "Refs $PUB_ISSUE_URL"; else gh_json "$ME" "unrelated"; fi
      ;;
    *) gh_json "$ME" "unrelated" ;;
  esac
}
resolve_alpha_ref "$INTERNAL_REF" "$TRACKER_REPO" "$CANDS" "$PUBLIC_REPO" 91 || fail "internal#45 rejected"
assert_eq "${ALPHA_REPO}#${ALPHA_NUM}" "${CLIENT_REPO}#45" "internal#N resolution failed"
if GH_BOTH=1 resolve_alpha_ref "$INTERNAL_REF" "$TRACKER_REPO" "$CANDS" "$PUBLIC_REPO" 91; then
  fail "expected internal#N matching two trackers to fail closed"
fi
if resolve_alpha_ref "$INTERNAL_REF" "$TRACKER_REPO" "$CANDS" "$PUBLIC_REPO" 92; then
  fail "expected internal#N with no back-reference match to fail closed"
fi
# 6d. Regression: URL match is number-anchored (issues/91 must not match issues/910), case-insensitive
if GH_CLIENT_BODY="Refs ${PUB_ISSUE_URL}0" resolve_alpha_ref "$INTERNAL_REF" "$TRACKER_REPO" "$CANDS" "$PUBLIC_REPO" 91; then
  fail "expected issues/910 not to satisfy a back-reference to issues/91"
fi
GH_CLIENT_BODY="see $(printf '%s' "$PUB_ISSUE_URL" | tr '[:lower:]' '[:upper:]'). Thanks" \
  resolve_alpha_ref "$INTERNAL_REF" "$TRACKER_REPO" "$CANDS" "$PUBLIC_REPO" 91 || fail "case/boundary-insensitive match rejected"
# 6e. Regression: a failed lookup fails the resolution instead of reading as absence
if GH_OPS_FAIL=1 GH_BOTH=1 resolve_alpha_ref "$INTERNAL_REF" "$TRACKER_REPO" "$CANDS" "$PUBLIC_REPO" 91; then
  fail "expected a failed candidate lookup to fail the resolution"
fi
# 6e1. A sibling tracker that never reached issue N is absence, not an error; other failures still fail
GH_OPS_ABSENT=1 resolve_alpha_ref "$INTERNAL_REF" "$TRACKER_REPO" "$CANDS" "$PUBLIC_REPO" 91 \
  || fail "expected a not-found issue in a sibling tracker to count as absence"
assert_eq "${ALPHA_REPO}#${ALPHA_NUM}" "${CLIENT_REPO}#45" "absence in a sibling must not change the resolved tracker"
# 6e2. Regression: the failed lookup must fail the resolution even WITHOUT pipefail
if ( set +o pipefail; GH_OPS_FAIL=1 GH_BOTH=1 resolve_alpha_ref "$INTERNAL_REF" "$TRACKER_REPO" "$CANDS" "$PUBLIC_REPO" 91 ); then
  fail "expected a failed lookup to fail the resolution when pipefail is off"
fi
# 6f. Regression: a back-reference authored by someone other than \$ME is ignored
if GH_CLIENT_AUTHOR="attacker" resolve_alpha_ref "$INTERNAL_REF" "$TRACKER_REPO" "$CANDS" "$PUBLIC_REPO" 91; then
  fail "expected an untrusted-author back-reference to be ignored"
fi
# 6f2. A human-authored issue in a PRIVATE tracker repo is a valid reused back-reference; an unknown visibility fails
GH_CLIENT_AUTHOR="a-human" GH_PRIV_CLIENT=true resolve_alpha_ref "$INTERNAL_REF" "$TRACKER_REPO" "$CANDS" "$PUBLIC_REPO" 91 \
  || fail "expected a reused human-authored issue in a private repo to resolve"
if GH_CLIENT_AUTHOR="a-human" GH_PRIV_FAIL=1 resolve_alpha_ref "$INTERNAL_REF" "$TRACKER_REPO" "$CANDS" "$PUBLIC_REPO" 91; then
  fail "expected a failed visibility lookup to fail the resolution"
fi
# 6g. Regression: gh shows an App author as app/<name>, ME is the REST <name>[bot] form (and vice versa)
GH_CLIENT_AUTHOR="app/trusted-app" ME="trusted-app[bot]" resolve_alpha_ref "$INTERNAL_REF" "$TRACKER_REPO" "$CANDS" "$PUBLIC_REPO" 91 \
  || fail "expected app/<name> author to match ME=<name>[bot]"
GH_CLIENT_AUTHOR="app/trusted-app" ME="app/trusted-app" resolve_alpha_ref "$INTERNAL_REF" "$TRACKER_REPO" "$CANDS" "$PUBLIC_REPO" 91 \
  || fail "expected app/<name> author to match ME=app/<name>"
if GH_CLIENT_AUTHOR="trusted-app" ME="trusted-app[bot]" resolve_alpha_ref "$INTERNAL_REF" "$TRACKER_REPO" "$CANDS" "$PUBLIC_REPO" 91; then
  fail "expected the user trusted-app not to pass as the App trusted-app[bot]"
fi
unset -f gh

# 7. Phase 6 resolve_alpha_ref fail-closed cases: $PUBLIC target, ambiguous basename, malformed ref
if resolve_alpha_ref "${PUBLIC_REPO}#9" "$TRACKER_REPO" "$CANDS" "$PUBLIC_REPO"; then
  fail "expected resolve_alpha_ref to reject PUBLIC repo"
fi

AMBIG_CANDS="$(printf '%s\n%s\n%s' "$TRACKER_REPO" "$CLIENT_REPO" "other-org/app-client")"
if resolve_alpha_ref 'app-client#10' "$TRACKER_REPO" "$AMBIG_CANDS" "$PUBLIC_REPO"; then
  fail "expected resolve_alpha_ref to reject ambiguous repo#N basename across orgs"
fi

# 7b. Legacy owner/repo#N and repo#N never resolve outside $CANDIDATE_TRACKERS
if resolve_alpha_ref "evil-org/other#5" "$TRACKER_REPO" "$CANDS" "$PUBLIC_REPO"; then
  fail "expected owner/repo#N outside candidates to be rejected"
fi
if resolve_alpha_ref 'unknown-repo#5' "$TRACKER_REPO" "$CANDS" "$PUBLIC_REPO"; then
  fail "expected repo#N basename outside candidates to be rejected"
fi

if resolve_alpha_ref "${CLIENT_REPO}#abc" "$TRACKER_REPO" "$CANDS" "$PUBLIC_REPO"; then
  fail "expected resolve_alpha_ref to reject non-numeric issue number"
fi

# 8. Crash-recovery jq filter syntax & epic label extraction check
JQ_FILTER="$(awk '/split\(\$pub_url/{gsub(/^ *'\''|'\''[^'\'']*$/, ""); print; exit}' "$SKILL_MD")"
[[ -n "$JQ_FILTER" ]] || fail "could not extract crash-recovery jq filter from $SKILL_MD"
jq_out="$(printf '%s' "[{\"number\":4370,\"author\":{\"login\":\"Trusted-Bot\"},\"body\":\"Refs $PUB_ISSUE_URL\",\"labels\":[{\"name\":\"type: epic\"}]},{\"number\":999,\"author\":{\"login\":\"trusted-bot\"},\"body\":\"unrelated #91\",\"labels\":[]},{\"number\":1000,\"author\":{\"login\":\"trusted-bot\"},\"body\":\"Refs ${PUB_ISSUE_URL}0\",\"labels\":[]},{\"number\":1002,\"author\":{\"login\":\"app/trusted-app\"},\"body\":\"Refs $PUB_ISSUE_URL\",\"labels\":[]},{\"number\":1001,\"author\":{\"login\":\"attacker\"},\"body\":\"Refs $PUB_ISSUE_URL\",\"labels\":[]}]" \
  | jq -r --arg repo "$TRACKER_REPO" --arg pub_url "$PUB_ISSUE_URL" --arg me "$ME" --arg priv false "$JQ_FILTER")"
expected_jq="$(printf '%s#4370\ttrue' "$TRACKER_REPO")"
assert_eq "$jq_out" "$expected_jq" "crash-recovery jq filter mismatch"
APP_JSON="[{\"number\":4370,\"author\":{\"login\":\"Trusted-Bot\"},\"body\":\"Refs $PUB_ISSUE_URL\",\"labels\":[{\"name\":\"type: epic\"}]},{\"number\":999,\"author\":{\"login\":\"trusted-bot\"},\"body\":\"unrelated #91\",\"labels\":[]},{\"number\":1000,\"author\":{\"login\":\"trusted-bot\"},\"body\":\"Refs ${PUB_ISSUE_URL}0\",\"labels\":[]},{\"number\":1002,\"author\":{\"login\":\"app/trusted-app\"},\"body\":\"Refs $PUB_ISSUE_URL\",\"labels\":[]},{\"number\":1001,\"author\":{\"login\":\"attacker\"},\"body\":\"Refs $PUB_ISSUE_URL\",\"labels\":[]}]"
app_out="$(printf '%s' "$APP_JSON" | jq -r --arg repo "$TRACKER_REPO" --arg pub_url "$PUB_ISSUE_URL" --arg me "trusted-app[bot]" --arg priv false "$JQ_FILTER")"
priv_out="$(printf '%s' "$APP_JSON" | jq -r --arg repo "$TRACKER_REPO" --arg pub_url "$PUB_ISSUE_URL" --arg me "nobody" --arg priv true "$JQ_FILTER" | cut -f1 | tr '\n' ' ')"
assert_eq "$priv_out" "$(printf '%s#4370 %s#1002 %s#1001 ' "$TRACKER_REPO" "$TRACKER_REPO" "$TRACKER_REPO")" "private repo must trust any author but still anchor the URL"
assert_eq "$app_out" "$(printf '%s#1002\tfalse' "$TRACKER_REPO")" "App-authored (app/<name>) hit must match ME=<name>[bot]"

# 9. Regression guard: sub-issue linking must never force replace_parent
if grep -q -- 'replace_parent' "$ALPHA_SYNC_MD"; then
  fail "$ALPHA_SYNC_MD must not reference replace_parent when linking sub-issues"
fi

# Exercise the filter that owns the trust boundary, using only synthetic metadata.
python3 - "$(dirname "$SKILL_MD")/validate-clusters.jq" <<'PYTEST'
import json
from pathlib import Path
import subprocess
import sys
import tempfile

with tempfile.TemporaryDirectory() as temp:
    catalog = Path(temp) / "catalog.json"
    catalog.write_text(json.dumps([{"number": n, "kind": k} for n, k in
                                   [(1, "bug"), (2, "bug"), (3, "feature")]]))
    command = ["jq", "-ces", "--slurpfile", "catalog", str(catalog), "-f", sys.argv[1]]
    group = {"members": [2, 1], "confidence": "high", "reason": "same-symptom"}
    valid = {"clusters": [group], "singletons": [3]}
    passed = subprocess.run(command, input=json.dumps(valid), capture_output=True, text=True, check=True)
    assert json.loads(passed.stdout)["clusters"][0]["members"] == [1, 2]
    bad_groups = [dict(group, reason="arbitrary text"), dict(group, rationale="raw text"),
                  dict(group, members=[1, 3]), dict(group, members=[1, 1]),
                  dict(group, confidence="unknown"), dict(group, members=[1, True])]
    bad = [json.dumps({"clusters": [g], "singletons": [3]}) for g in bad_groups]
    bad += [json.dumps(dict(valid, instructions="arbitrary text")), json.dumps(dict(valid, singletons=[])),
            json.dumps(dict(valid, singletons=[4])), json.dumps(valid) + "\n" + json.dumps(valid)]
    for payload in bad:
        result = subprocess.run(command, input=payload, capture_output=True, text=True)
        assert result.returncode != 0 and result.stdout == "", "untrusted cluster report escaped"
PYTEST

echo "PASS: test-feedback-triage-routing"
