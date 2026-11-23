#!/usr/bin/env bash
# Source from the verified fleet edition. This helper reads configuration as data.
fleet_clear_config() {
  unset RC_TRUSTED_CFG RC_TRUSTED_STATE RC_TRUSTED_OID RC_TRUSTED_REPO RC_ISSUE_LINKAGE
}

fleet_set_config() {
  local oid="$1" raw="$2" state="$3" config
  config=$(jq -ces 'if length == 1 and (.[0] | type) == "object" then .[0] else error("expected one object") end' <<<"$raw") || return 1
  RC_TRUSTED_CFG=$config
  RC_TRUSTED_STATE=$state
  RC_TRUSTED_OID=$oid
  export RC_TRUSTED_STATE RC_TRUSTED_OID
}

# For callers that already verified a local commit against the default branch.
fleet_load_config() {
  local oid="${1:-}" entry value parent
  fleet_clear_config
  [[ "$oid" =~ ^[0-9a-f]{40}$ || "$oid" =~ ^[0-9a-f]{64}$ ]] || return 1
  git --no-replace-objects cat-file -e "$oid^{commit}" || return 1
  parent=$(git --no-replace-objects ls-tree "$oid" -- .claude) || return 1
  case "${parent%% *}" in ''|040000) ;; *) return 1 ;; esac
  entry=$(git --no-replace-objects ls-tree "$oid" -- .claude/repo-config.json) || return 1
  case "${entry%% *}" in
    '') fleet_set_config "$oid" '{}' absent ;;
    100644|100755)
      value=$(git --no-replace-objects show "$oid:.claude/repo-config.json") || return 1
      fleet_set_config "$oid" "$value" present ;;
    *) return 1 ;;
  esac
}

fleet_tree_entry() {
  local repo="$1" tree="$2" name="$3" kind="$4" listing
  listing=$(gh api "repos/$repo/git/trees/$tree") || return 1
  jq -er --arg name "$name" --arg kind "$kind" '
    if .truncated != false or (.tree|type) != "array" then error("incomplete Git tree") else
      [.tree[] | select(.path == $name)] |
      if length == 0 then "-"
      elif length == 1 and .[0].type == $kind and
          (.[0].mode | if $kind == "tree" then . == "040000" else . == "100644" or . == "100755" end) and
          (.[0].sha | test("^[a-f0-9]{40}$")) then .[0].sha
      else error("unexpected Git tree entry") end end' <<<"$listing"
}

fleet_load_repo_config() {
  local repo="${1:-}" expected="${2:-}" result oid tree directory blob response config
  fleet_clear_config
  [[ "$repo" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*/[A-Za-z0-9_.-]+$ ]] || return 1
  case "${repo#*/}" in .|..) return 1 ;; *) ;; esac
  # The dollar-prefixed variables belong to GraphQL.
  # shellcheck disable=SC2016
  result=$(gh api graphql -f query='query($owner:String!,$name:String!){repository(owner:$owner,name:$name){nameWithOwner defaultBranchRef{target{... on Commit{oid tree{oid}}}}}}' \
    -f owner="${repo%/*}" -f name="${repo#*/}") || return 1
  result=$(jq -er --arg repo "$repo" '
    select((.errors // [] | length) == 0) | .data.repository
    | select((.nameWithOwner | ascii_downcase) == ($repo | ascii_downcase))
    | .defaultBranchRef.target | [.oid, .tree.oid]
    | select(all(.[]; type == "string" and test("^[a-f0-9]{40}$"))) | @tsv' <<<"$result") || return 1
  IFS=$'\t' read -r oid tree <<<"$result"
  [[ -z "$expected" || "$expected" == "$oid" ]] || return 1
  directory=$(fleet_tree_entry "$repo" "$tree" .claude tree) || return 1
  blob=-
  if [[ "$directory" != - ]]; then
    blob=$(fleet_tree_entry "$repo" "$directory" repo-config.json blob) || return 1
  fi
  if [[ "$blob" == - ]]; then
    fleet_set_config "$oid" '{}' absent || return 1
  else
    response=$(gh api "repos/$repo/git/blobs/$blob") || return 1
    config=$(jq -er --arg id "$blob" 'select(.sha == $id and .encoding == "base64" and
      (.size | type == "number" and . > 0)) | .content | @base64d | fromjson
      | select(type == "object") | tojson' <<<"$response") || return 1
    fleet_set_config "$oid" "$config" present || return 1
  fi
  RC_TRUSTED_REPO=$repo
}

# Bind the linkage policy to the authorized intake repository at its default revision.
fleet_load_issue_config() {
  fleet_load_repo_config "$@" || return 1
  # The calling issue-creation skill reads this result in the same shell.
  # shellcheck disable=SC2034
  RC_ISSUE_LINKAGE=$(jq -er '
    if (has("issue_creation") | not) then "tasklist"
    elif (.issue_creation | type) != "object" then error("invalid issue_creation")
    elif (.issue_creation | has("sub_issue_linkage") | not) then "tasklist"
    else .issue_creation.sub_issue_linkage |
      if . == "tasklist" or . == "native_rest" then . else error("invalid sub_issue_linkage") end
    end' <<<"$RC_TRUSTED_CFG") || { fleet_clear_config; return 1; }
}

# Execute the bundled disposition gate against a private snapshot of the same
# verified configuration. Free-form comments and HTTP errors stay in the child.
fleet_check_dispositions() (
  local pr="${1:-}" repo="${2:-}" expected='' dir gate scratch code
  [[ "$pr" =~ ^[1-9][0-9]*$ ]] || return 2
  case $# in
    1|2) ;;
    4) [[ "$3" == --maintainer-sources || "$3" == --formal-state ]] && [[ "$4" =~ ^[0-9a-f]{40}$ ]] || return 2 ;;
    *) return 2 ;;
  esac
  if [[ -z "$repo" ]]; then
    repo=$(unset GH_REPO; gh repo view --json nameWithOwner --jq .nameWithOwner) || return 2
  fi
  if [[ "${RC_TRUSTED_REPO:-}" == "$repo" ]]; then expected=${RC_TRUSTED_OID:-}; fi
  fleet_load_repo_config "$repo" "$expected" >/dev/null 2>&1 || return 2
  [[ "${BASH_SOURCE[0]}" == /* ]] || return 2
  dir=$(CDPATH='' cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P) || return 2
  gate="$dir/../enhanced-pr-review/check-review-dispositions.sh"
  [[ -f "$gate" && ! -L "$gate" ]] || return 2
  umask 077
  scratch=$(mktemp -d /tmp/fleet-dispositions.XXXXXXXX) || return 2
  trap 'rm -f -- "$scratch/config.json"; rmdir -- "$scratch"' EXIT
  printf '%s\n' "$RC_TRUSTED_CFG" > "$scratch/config.json" || return 2
  unset CV_REVIEW_FIXTURE CV_SKIP_EXISTENCE_CHECKS CV_BASE_REF CV_DEFAULT_BRANCH GITHUB_BASE_REF BASH_ENV ENV
  export GH_REPO="$repo" CV_REPO_CONFIG="$scratch/config.json"
  if [[ $# == 4 ]]; then
    # Only the two fixed metadata modes can return output: canonical source links
    # with timestamps, or a status code for the current formal review decision.
    /bin/bash "$gate" "$pr" "$3" "$repo" "$4" 2>/dev/null
    return $?
  fi
  if /bin/bash "$gate" "$pr" >/dev/null 2>&1; then
    printf '%s\n' 'Inline and bot review dispositions verified.'
    return 0
  else
    code=$?
    if [[ $code == 1 ]]; then printf '%s\n' 'Review dispositions require attention.' >&2; return 1; fi
    printf '%s\n' 'Review disposition verification incomplete.' >&2
    return 2
  fi
)

rc_get() {
  local filter="$1" fallback="${2:-}"
  local result
  if result="$(jq -r --arg fallback "$fallback" "($filter) | if . == null then \$fallback elif type == \"string\" then . else tostring end" <<<"$RC_TRUSTED_CFG" 2>/dev/null)"; then
    printf '%s' "$result"
  else
    printf '%s' "$fallback"
  fi
}
rc_has() {
  local filter="$1"
  jq -e "($filter) != null" >/dev/null <<<"$RC_TRUSTED_CFG"
}
