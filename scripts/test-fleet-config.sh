#!/usr/bin/env bash
set -euo pipefail

root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
mkdir -p "$work/bin" "$work/edition/skills/_shared" "$work/edition/skills/enhanced-pr-review"
cp "$root/config/fleet-workflows/repo-config.sh" "$work/edition/skills/_shared/"

cat > "$work/bin/gh" <<'FAKE'
#!/usr/bin/env bash
set -eu
id=1111111111111111111111111111111111111111
root_tree=2222222222222222222222222222222222222222
dir_tree=3333333333333333333333333333333333333333
blob=4444444444444444444444444444444444444444
case "$1 $2" in
  'repo view')
    [[ -z "${GH_REPO:-}" ]] || exit 19
    printf '%s\n' acme/example ;;
  'api graphql')
    [[ " $* " == *' owner=acme '* && " $* " == *' name=example '* ]] || exit 19
    jq -nc --arg sha "$id" --arg tree "$root_tree" \
      '{data:{repository:{nameWithOwner:"acme/example",defaultBranchRef:{target:{oid:$sha,tree:{oid:$tree}}}}}}' ;;
  "api repos/acme/example/git/trees/$root_tree")
    jq -nc --arg oid "$dir_tree" '{truncated:false,tree:[{path:".claude",type:"tree",mode:"040000",sha:$oid}]}' ;;
  "api repos/acme/example/git/trees/$dir_tree")
    case "${FIXTURE_STATE:-present}" in
      absent) printf '%s\n' '{"truncated":false,"tree":[]}' ;;
      error) exit 1 ;;
      truncated) printf '%s\n' '{"truncated":true,"tree":[]}' ;;
      link) jq -nc --arg sha "$blob" '{truncated:false,tree:[{path:"repo-config.json",type:"blob",mode:"120000",sha:$sha}]}' ;;
      *) jq -nc --arg sha "$blob" '{truncated:false,tree:[{path:"repo-config.json",type:"blob",mode:"100644",sha:$sha}]}' ;;
    esac ;;
  "api repos/acme/example/git/blobs/$blob")
    if [[ -n "${FIXTURE_CONFIG+x}" ]]; then config="$FIXTURE_CONFIG"; else config='{"value":"default","bots":[]}'; fi
    [[ "${FIXTURE_STATE:-present}" != malformed ]] || config='not JSON'
    encoded=$(jq -nr --arg config "$config" '$config | @base64')
    case "${FIXTURE_STATE:-present}" in
      wrapped) encoded=$(printf '%s' "$encoded" | fold -w 60); encoded+=$'\n' ;;
      bad-space) encoded+=' ' ;;
      bad-cr) encoded+=$'\r' ;;
      bad-padding) encoded='e30' ;;
    esac
    jq -nc --arg sha "$blob" --arg config "$config" --arg encoded "$encoded" \
      '{sha:$sha,size:($config|length),encoding:"base64",content:$encoded}' ;;
  *) exit 19 ;;
esac
FAKE
chmod 700 "$work/bin/gh"
export PATH="$work/bin:$PATH"

cat > "$work/edition/skills/enhanced-pr-review/check-review-dispositions.sh" <<'GATE'
#!/usr/bin/env bash
set -eu
[[ "$1" == 12 && "$GH_REPO" == acme/example ]]
[[ -z "${CV_REVIEW_FIXTURE:-}${CV_SKIP_EXISTENCE_CHECKS:-}${CV_BASE_REF:-}${CV_DEFAULT_BRANCH:-}${GITHUB_BASE_REF:-}" ]]
[[ -f "$CV_REPO_CONFIG" && ! -L "$CV_REPO_CONFIG" ]]
jq -e '.value == "default" and .bots == []' "$CV_REPO_CONFIG" >/dev/null
if [[ $# == 4 ]]; then
  [[ "$3" == acme/example && "$4" == 1111111111111111111111111111111111111111 ]]
  case "$2" in
    --maintainer-sources) echo '[]'; exit 0 ;;
    --formal-state) exit 1 ;;
  esac
fi
echo 'synthetic text that must remain local'
exit "${FIXTURE_GATE_RESULT:-0}"
GATE

# shellcheck disable=SC1091
source "$work/edition/skills/_shared/repo-config.sh"
id=1111111111111111111111111111111111111111
fleet_load_repo_config acme/example "$id"
[[ "$RC_TRUSTED_OID" == "$id" && "$RC_TRUSTED_STATE" == present && "$(rc_get .value)" == default ]]
pad=$(printf '%0120d' 0)
FIXTURE_CONFIG=$(jq -nc --arg pad "$pad" '{value:"default",bots:[],pad:$pad}')
FIXTURE_STATE=wrapped
export FIXTURE_CONFIG FIXTURE_STATE
fleet_load_repo_config acme/example "$id"
[[ "$(rc_get .pad)" == "$pad" ]]
unset FIXTURE_CONFIG FIXTURE_STATE
for state in truncated error link malformed bad-space bad-cr bad-padding; do
  export FIXTURE_STATE="$state"
  if fleet_load_repo_config acme/example 2>/dev/null; then exit 1; fi
  [[ -z "${RC_TRUSTED_CFG+x}${RC_TRUSTED_OID+x}${RC_TRUSTED_STATE+x}${RC_TRUSTED_REPO+x}" ]]
done
export FIXTURE_STATE=absent
fleet_load_repo_config acme/example
[[ "$RC_TRUSTED_STATE" == absent && "$RC_TRUSTED_CFG" == '{}' ]]
if fleet_load_repo_config acme/example 5555555555555555555555555555555555555555; then exit 1; fi
[[ -z "${RC_TRUSTED_CFG+x}${RC_TRUSTED_OID+x}" ]]
unset FIXTURE_STATE
# Issue intake binds the policy to its specified repository and exact revision.
export GH_REPO=other/fixture
fleet_load_issue_config acme/example "$id"
[[ "$RC_TRUSTED_REPO" == acme/example && "$RC_ISSUE_LINKAGE" == tasklist ]]
export FIXTURE_CONFIG='{"issue_creation":{"sub_issue_linkage":"native_rest"}}'
fleet_load_issue_config acme/example "$id"
[[ "$RC_ISSUE_LINKAGE" == native_rest ]]
fleet_load_repo_config acme/example "$id"
[[ -z "${RC_ISSUE_LINKAGE+x}" ]]
export FIXTURE_CONFIG='{"issue_creation":{"sub_issue_linkage":"tasklist"}}'
fleet_load_issue_config acme/example "$id"
[[ "$RC_ISSUE_LINKAGE" == tasklist ]]
for invalid in 'null' '{}' 'false' '"unknown"'; do
  FIXTURE_CONFIG="{\"issue_creation\":{\"sub_issue_linkage\":$invalid}}"
  if fleet_load_issue_config acme/example "$id" 2>/dev/null; then exit 1; fi
  [[ -z "${RC_TRUSTED_REPO+x}${RC_TRUSTED_CFG+x}${RC_ISSUE_LINKAGE+x}" ]]
done
export FIXTURE_CONFIG='{"issue_creation":null}'
if fleet_load_issue_config acme/example "$id" 2>/dev/null; then exit 1; fi
export FIXTURE_CONFIG='{"issue_creation":{}}'
fleet_load_issue_config acme/example "$id"
[[ "$RC_ISSUE_LINKAGE" == tasklist ]]
if fleet_load_issue_config other/fixture "$id"; then exit 1; fi
[[ -z "${RC_TRUSTED_REPO+x}${RC_ISSUE_LINKAGE+x}" ]]
if fleet_load_issue_config acme/example 5555555555555555555555555555555555555555; then exit 1; fi
[[ -z "${RC_TRUSTED_REPO+x}${RC_ISSUE_LINKAGE+x}" ]]
unset FIXTURE_CONFIG
export GH_REPO=other/fixture CV_REVIEW_FIXTURE=legacy CV_SKIP_EXISTENCE_CHECKS=1
export CV_REPO_CONFIG=alternate CV_BASE_REF=alternate GITHUB_BASE_REF=alternate CV_DEFAULT_BRANCH=alternate
for repo_arg in '' acme/example; do
  if [[ -n "$repo_arg" ]]; then
    receipt=$(fleet_check_dispositions 12 "$repo_arg")
  else
    receipt=$(fleet_check_dispositions 12)
  fi
  [[ "$receipt" == 'Inline and bot review dispositions verified.' ]]
done
for outcome in 1 7; do
  export FIXTURE_GATE_RESULT=$outcome
  code=0
  receipt=$(fleet_check_dispositions 12 acme/example 2>&1) || code=$?
  if [[ $outcome == 1 ]]; then [[ $code == 1 ]]; else [[ $code == 2 ]]; fi
  [[ "$receipt" != *'synthetic text'* ]]
done
unset FIXTURE_GATE_RESULT
[[ "$(fleet_check_dispositions 12 acme/example --maintainer-sources 1111111111111111111111111111111111111111)" == '[]' ]]
code=0
fleet_check_dispositions 12 acme/example --formal-state 1111111111111111111111111111111111111111 || code=$?
[[ "$code" == 1 ]]
# Changing the casing of the bound target must preserve its expected revision.
RC_TRUSTED_REPO=AcMe/ExAmPlE
RC_TRUSTED_OID=5555555555555555555555555555555555555555
for mode in --maintainer-sources --formal-state; do
  code=0
  receipt=$(fleet_check_dispositions 12 acme/example "$mode" "$id") || code=$?
  [[ $code == 2 && -z "$receipt" ]]
done
printf '%s\n' 'Fleet configuration and disposition fixtures passed.'
