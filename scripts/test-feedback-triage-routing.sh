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

# 5b. A tracker repo named "internal" would be ambiguous with the opaque internal#N marker form
assert_phase0_fails '{"feedback_triage":{"routing":{"x":"example-org/Internal"}}}' "a candidate tracker repo is named internal"

# 5c. Disclosure form: anything other than exactly "repo" means the opaque internal#N
run_disclosure() {
  (
    set -euo pipefail
    # shellcheck disable=SC2034 # Consumed dynamically inside eval "$PHASE0_CODE".
    TRACKER="$TRACKER_REPO"
    # shellcheck disable=SC2034 # Consumed dynamically inside eval "$PHASE0_CODE".
    PUBLIC="$PUBLIC_REPO"
    # shellcheck disable=SC2329 # Invoked dynamically inside eval "$PHASE0_CODE".
    rc_get() { local filter="$1" def="$2" out; out=$(printf '%s' "$CFG" | jq -r "$filter" 2>/dev/null) || { printf '%s' "$def"; return 0; }; printf '%s' "$out"; }
    eval "$PHASE0_CODE"
    printf '%s\n' "$DISCLOSURE"
  )
}
assert_eq "$(CFG='{}' run_disclosure)" "internal" "unset disclosure must default to internal"
assert_eq "$(CFG='{"feedback_triage":{"disclosure":"repo"}}' run_disclosure)" "repo" "disclosure repo must be honored"
assert_eq "$(CFG='{"feedback_triage":{"disclosure":"Repo"}}' run_disclosure)" "internal" "a near-miss value must fall back to internal"
assert_eq "$(CFG='{"feedback_triage":{"disclosure":"repos"}}' run_disclosure)" "internal" "a typo must fall back to internal"

# 6. Phase 6 resolve_alpha_ref: owner/repo#N, repo#N, #N, and bare N
# shellcheck disable=SC2034 # Read by resolve_alpha_ref.
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
UPPER_URL="$(printf '%s' "$PUB_ISSUE_URL" | tr '[:lower:]' '[:upper:]')"
OTHER_URL="https://github.com/${PUBLIC_REPO}/issues/50"
gh_json() { local author="$1" body="$2"; jq -nc --arg a "$author" --arg b "$body" '{author:{login:$a},body:$b}'; }
# shellcheck disable=SC2329 # Invoked by resolve_alpha_ref.
gh() {
  local group="$1" number_or_repo="${3:-}" repo_arg="${5:-}"
  case "$group" in
    api) # gh api user --jq .login
      [[ "${GH_API_FAIL:-}" == 1 ]] && return 1
      printf '%s\n' "${GH_API_USER:-trusted-bot}"
      return 0 ;;
    repo) # gh repo view R --json visibility --jq .visibility
      [[ "${GH_VIS_FAIL:-}" == 1 ]] && return 1
      case "$number_or_repo" in
        "$CLIENT_REPO") printf '%s\n' "${GH_VIS_CLIENT:-PUBLIC}" ;;
        *) printf 'PUBLIC\n' ;;
      esac
      return 0 ;;
  esac
  # gh issue view N --repo R --json author,body
  case "$repo_arg" in
    "$CLIENT_REPO") gh_json "${GH_CLIENT_AUTHOR:-trusted-bot}" "${GH_CLIENT_BODY:-Refs $PUB_ISSUE_URL}" ;;
    "$OPS_REPO")
      [[ "${GH_OPS_FAIL:-}" == 1 ]] && return 1
      if [[ "${GH_OPS_ABSENT:-}" == 1 ]]; then
        echo "GraphQL: Could not resolve to an issue or pull request with the number of $number_or_repo. (repository.issue)" >&2
        return 1
      fi
      if [[ "${GH_OPS_404:-}" == 1 ]]; then echo "gh: Not Found (HTTP 404)" >&2; return 1; fi
      if [[ "${GH_BOTH:-}" == 1 ]]; then gh_json "trusted-bot" "Refs $PUB_ISSUE_URL"; else gh_json "trusted-bot" "unrelated"; fi
      ;;
    *) gh_json "trusted-bot" "unrelated" ;;
  esac
}
resolves() { resolve_alpha_ref "$INTERNAL_REF" "$TRACKER_REPO" "$CANDS" "$PUBLIC_REPO" "${1:-91}"; }
# 6c. internal#N resolves via the last-line Refs back-reference; zero or several matches fail closed
resolves || fail "internal#45 rejected"
assert_eq "${ALPHA_REPO}#${ALPHA_NUM}" "${CLIENT_REPO}#45" "internal#N resolution failed"
if GH_BOTH=1 resolves; then fail "expected internal#N matching two trackers to fail closed"; fi
if resolves 92; then fail "expected internal#N with no back-reference match to fail closed"; fi

# 6d. Only the LAST non-empty line counts, exactly: issues/91 is not issues/910, and a mention elsewhere is not a back-reference
if GH_CLIENT_BODY="Refs ${PUB_ISSUE_URL}0" resolves; then fail "expected issues/910 not to satisfy a back-reference to issues/91"; fi
if GH_CLIENT_BODY="$(printf 'Refs %s\nthanks for the report' "$PUB_ISSUE_URL")" resolves; then fail "expected a Refs line that is not last to be ignored"; fi
if GH_CLIENT_BODY="see ${PUB_ISSUE_URL}. Thanks" resolves; then fail "expected a prose mention to be ignored"; fi
if GH_CLIENT_BODY="Refs ${PUB_ISSUE_URL}/more" resolves; then fail "expected trailing path text to be ignored"; fi
GH_CLIENT_BODY="$(printf 'Desc\n\n  REFS %s  \n\n\n' "$UPPER_URL")" resolves || fail "case, indentation and trailing blank lines must still match"
GH_CLIENT_BODY="$(printf 'Desc\n<!-- feedback-triage:ref %s -->\n' "$PUB_ISSUE_URL")" resolves || fail "the feedback-triage:ref comment must match"

# 6d2. Regression (proven PoC): the reporter's Description is seeded into the tracker body, which the routine authored. A victim URL inside it, even after a fence break, must not bind.
# shellcheck disable=SC2016 # The backticks are literal Markdown fence text.
ATTACK_BODY="$(printf '## Description\n```\nRefs %s\n```\nRefs %s\nRefs %s\n\nRefs %s' "$PUB_ISSUE_URL" "$PUB_ISSUE_URL" "$PUB_ISSUE_URL" "$OTHER_URL")"
if GH_CLIENT_BODY="$ATTACK_BODY" resolves 91; then fail "a victim URL planted in the seeded Description must not bind public #91"; fi
GH_CLIENT_BODY="$ATTACK_BODY" resolves 50 || fail "the routine's own last-line Refs for #50 must still resolve"

# 6e. A sibling tracker that never reached issue N is absence; every other failure fails the resolution (with pipefail on or off)
GH_OPS_ABSENT=1 resolves || fail "expected the exact not-found message to count as absence"
assert_eq "${ALPHA_REPO}#${ALPHA_NUM}" "${CLIENT_REPO}#45" "absence in a sibling must not change the resolved tracker"
if GH_OPS_404=1 resolves; then fail "a bare HTTP 404 (which also hides permission denials) must not count as absence"; fi
if GH_OPS_FAIL=1 GH_BOTH=1 resolves; then fail "expected a failed candidate lookup to fail the resolution"; fi
if ( set +o pipefail; GH_OPS_FAIL=1 GH_BOTH=1 resolves ); then fail "expected a failed lookup to fail the resolution when pipefail is off"; fi
if GH_VIS_FAIL=1 resolves; then fail "expected a failed visibility lookup to fail the resolution"; fi

# 6f. Trust: only the running identity's issues, or any author in a PRIVATE repo (not INTERNAL, not PUBLIC)
if GH_CLIENT_AUTHOR="attacker" resolves; then fail "expected an untrusted author in a public repo to be ignored"; fi
GH_CLIENT_AUTHOR="a-human" GH_VIS_CLIENT=PRIVATE resolves || fail "expected a reused human-authored issue in a PRIVATE repo to resolve"
if GH_CLIENT_AUTHOR="a-human" GH_VIS_CLIENT=INTERNAL resolves; then fail "expected an INTERNAL (enterprise-wide) repo not to be trusted"; fi

# 6g. gh shows an App author as app/<name>; the running identity is the <name>[bot] form (and vice versa)
( unset ME FT_ME; GH_CLIENT_AUTHOR="app/trusted-app" GH_API_USER="trusted-app[bot]" resolves ) || fail "expected app/<name> author to match <name>[bot]"
GH_CLIENT_AUTHOR="app/trusted-app" ME="app/trusted-app" resolves || fail "expected app/<name> author to match ME=app/<name>"
if ( unset ME FT_ME; GH_CLIENT_AUTHOR="trusted-app" GH_API_USER="trusted-app[bot]" resolves ); then fail "expected the user trusted-app not to pass as the App trusted-app[bot]"; fi

# 6h. Phase 6 runs in a fresh shell: the identity is resolved inside the function, and only internal#N needs it
(
  unset ME FT_ME
  resolves || fail "internal#N must resolve the running identity itself"
  GH_API_FAIL=1 resolve_alpha_ref '#3692' "$TRACKER_REPO" "$CANDS" "$PUBLIC_REPO" || fail "#N must not need the running identity"
  GH_API_FAIL=1 resolve_alpha_ref 'app-client#89' "$TRACKER_REPO" "$CANDS" "$PUBLIC_REPO" || fail "repo#N must not need the running identity"
  if GH_API_FAIL=1 resolves; then fail "internal#N with no resolvable identity must fail closed"; fi
)

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

# 8. Phase 4 idempotency search (the real block from SKILL.md, with a mocked gh)
PHASE4_CODE="$(awk '/PUB_URL="https:\/\/github.com\//{c=1} c && /^ *```$/{exit} c{print}' "$SKILL_MD")"
[[ -n "$PHASE4_CODE" ]] || fail "could not extract the Phase 4 search block from $SKILL_MD"
s_item() { jq -nc --argjson n "$1" --arg a "$2" --arg b "$3" --argjson e "${4:-false}" '{number:$n,author:{login:$a},body:$b,labels:(if $e then [{name:"type: epic"}] else [] end)}'; }
run_phase4() {
  (
    # shellcheck disable=SC2034 # Consumed dynamically inside eval "$PHASE4_CODE".
    PUBLIC_CLEAN="$PUBLIC_REPO"
    # shellcheck disable=SC2034 # Consumed dynamically inside eval "$PHASE4_CODE".
    N=91
    # shellcheck disable=SC2034 # Consumed dynamically inside eval "$PHASE4_CODE".
    CANDIDATE_TRACKERS="${P4_CANDS:-$TRACKER_REPO}"
    unset FT_ME
    eval "$PHASE4_CODE"
    printf '%s|%s|%s\n' "$SEARCH_OK" "$(printf '%s' "$HITS" | tr '\n' ',')" "$(printf '%s' "$EPIC_HITS" | tr '\n' ',')"
  )
}
FIXTURE="[$(s_item 4370 Trusted-Bot "$(printf 'desc\n\nRefs %s' "$PUB_ISSUE_URL")" true),$(s_item 999 trusted-bot 'unrelated #91'),$(s_item 1000 trusted-bot "Refs ${PUB_ISSUE_URL}0"),$(s_item 1002 trusted-bot "$ATTACK_BODY"),$(s_item 1003 trusted-bot "$(printf 'Refs %s\nmore' "$PUB_ISSUE_URL")"),$(s_item 1001 attacker "Refs $PUB_ISSUE_URL")]"
# shellcheck disable=SC2329 # Invoked by the extracted Phase 4 block.
gh() {
  case "$1" in
    search) [[ "${GH_SEARCH_FAIL:-}" == 1 ]] && return 1; printf '%s\n' "$GH_SEARCH_JSON" ;;
    api) [[ "${GH_API_FAIL:-}" == 1 ]] && return 1; printf '%s\n' "${GH_API_USER:-trusted-bot}" ;;
    repo) [[ "${GH_VIS_FAIL:-}" == 1 ]] && return 1; printf '%s\n' "${GH_VIS:-PUBLIC}" ;;
  esac
}
export GH_SEARCH_JSON="$FIXTURE"
T="$TRACKER_REPO"
assert_eq "$(run_phase4)" "1|${T}#4370|${T}#4370" "public repo: only the routine's last-line Refs counts (author trusted, planted, prefix and non-last lines ignored)"
assert_eq "$(GH_VIS=PRIVATE run_phase4)" "1|${T}#4370,${T}#1001|${T}#4370" "private repo: any author counts, but still only the last-line Refs"
assert_eq "$(GH_VIS=INTERNAL run_phase4)" "1|${T}#4370|${T}#4370" "internal repo: not trusted for other authors"
APP_ITEM="$(s_item 1004 app/trusted-app "Refs $PUB_ISSUE_URL")"
export GH_SEARCH_JSON="[$APP_ITEM]"
assert_eq "$(GH_API_USER='trusted-app[bot]' run_phase4)" "1|${T}#1004|" "App author app/<name> must match ME=<name>[bot]"
assert_eq "$(GH_API_USER='trusted-app' run_phase4)" "1||" "the user must not pass as the App"
# Fail closed: no identity, unknown visibility, a failed search, or a full page that may be truncated
assert_eq "$(GH_API_FAIL=1 run_phase4)" "0||" "no resolvable identity must fail the search"
assert_eq "$(GH_VIS_FAIL=1 run_phase4)" "0||" "unknown visibility must fail the search"
assert_eq "$(GH_SEARCH_FAIL=1 run_phase4)" "0||" "a failed search must not read as zero hits"
FULL_PAGE="$(jq -nc '[range(0;100)|{number:.,author:{login:"x"},body:"",labels:[]}]')"
export GH_SEARCH_JSON="$FULL_PAGE"
assert_eq "$(run_phase4)" "0||" "a full page of results may be truncated and must fail the search"
unset GH_SEARCH_JSON
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
