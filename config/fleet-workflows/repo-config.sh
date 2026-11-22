#!/usr/bin/env bash
# Sourced only from the verified fleet edition, with the exact default-branch OID.
fleet_load_config() {
  local oid="$1" entry
  [[ "$oid" =~ ^[0-9a-f]+$ ]] || return 1
  case "${#oid}" in 40|64) ;; *) return 1 ;; esac
  git cat-file -e "$oid^{commit}" || return 1
  entry="$(git ls-tree "$oid" -- .claude/repo-config.json)" || return 1
  RC_TRUSTED_CFG='{}'
  export RC_TRUSTED_STATE=absent
  case "${entry%% *}" in
    '') ;;
    100644|100755)
      RC_TRUSTED_CFG="$(git show "$oid:.claude/repo-config.json")" || return 1
      jq -e 'type == "object"' >/dev/null <<<"$RC_TRUSTED_CFG" || return 1
      RC_TRUSTED_STATE=present ;;
    *) return 1 ;;
  esac
}
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
