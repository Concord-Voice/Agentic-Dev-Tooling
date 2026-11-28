#!/usr/bin/env bash
# agentic-dev-tooling installer. See CAPABILITIES.md for per-platform coverage.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
PLATFORM="${1:-}"; shift || true
PROJECT=""; USER_SCOPE=0; WITH_FLEET=0; FORCE=0; AGENTS_ONLY=0
while [ $# -gt 0 ]; do case "$1" in
  --project) PROJECT="$2"; shift 2;; --user) USER_SCOPE=1; shift;;
  --agents-only) AGENTS_ONLY=1; shift;;
  --with-fleet) WITH_FLEET=1; shift;; --force) FORCE=1; shift;;
  *) echo "unknown flag $1" >&2; exit 2;; esac; done

# --user only makes sense for the claude subcommand: it installs into $HOME/.claude
# instead of a --project root. The rulesync-compiled platforms (codex/copilot/gemini/
# antigravity) have no user-scope target of their own -- --user there would silently
# install into $HOME with no platform actually reading it from there. Fail fast rather
# than let that surprise an adopter.
if [ "$USER_SCOPE" = 1 ] && [ "$PLATFORM" != claude ]; then
  echo "--user is only supported for the claude subcommand" >&2
  exit 2
fi

need() { command -v "$1" >/dev/null || { echo "missing prerequisite: $1" >&2; exit 1; }; }

init_protected() {
  PROTECT_ROOT="$1"
  TOOLING_DOT="$PROTECT_ROOT/.claude"
  if [[ "$PROTECT_ROOT" = / ]]; then
    echo "install into a project directory with its own .claude directory" >&2; exit 1
  fi
  if [[ -L "$TOOLING_DOT" ]]; then
    if [[ "$USER_SCOPE" != 1 || ! -d "$TOOLING_DOT" || ! -O "$TOOLING_DOT" ]]; then
      echo "linked .claude requires --user and an existing user-owned target directory" >&2; exit 1
    fi
    # An explicit user install selects the existing dotfile directory. Use its
    # physical path for every write and still reject links below that boundary.
    TOOLING_DOT="$(cd -P "$TOOLING_DOT" && pwd -P)"
    if [[ "$TOOLING_DOT" = / || "$TOOLING_DOT" = "$(cd -P "$PROTECT_ROOT" && pwd -P)" ]]; then
      echo "linked .claude must select a dedicated configuration directory" >&2; exit 1
    fi
  fi
  PROTECT_FILE="$TOOLING_DOT/agentic-protected-paths.json"
  if [[ -L "$PROTECT_FILE" ]] || { [[ -e "$PROTECT_FILE" ]] && [[ ! -f "$PROTECT_FILE" ]]; }; then
    echo "protected paths must be a regular file, not a symlink: $PROTECT_FILE" >&2; exit 1
  fi
  [[ -f "$PROTECT_FILE" ]] || return 0
  need jq
  jq -e 'type == "object" and (.paths | type == "array") and
    ([.paths[] | type == "string" and length > 0 and
      (startswith("/") | not) and (contains("\\") | not) and
      (split("/") | all(. != "" and . != "." and . != ".."))] | all)' \
    "$PROTECT_FILE" >/dev/null || { echo "invalid protected paths: $PROTECT_FILE" >&2; exit 1; }
}

protected() { # true when the copied item overlaps a protected path, even under --force
  local dst=$1 rel
  [[ -n "${PROTECT_FILE:-}" ]] && [[ -f "$PROTECT_FILE" ]] || return 1
  rel="$(lock_key "$dst")"
  jq -e --arg p "$rel" '.paths | any(. as $entry | $entry == $p or ($p | startswith($entry + "/")) or ($entry | startswith($p + "/")))' "$PROTECT_FILE" >/dev/null
}

# A native profile and its ownership record belong inside this checkout. Reject
# linked parents even on an otherwise empty destination (including dangling links).
check_parents() {
  local path="${1%/*}"
  while [[ "$path" != "$PROTECT_ROOT" ]]; do
    if [[ -L "$path" ]]; then
      echo "destination traverses a symlink: $path" >&2; exit 1
    fi
    [[ "$path" != "$TOOLING_DOT" ]] || return 0
    path="${path%/*}"
  done
}

init_lock() {
  local platform="$1" file=".agentic-dev-tooling.lock"
  [[ "$platform" == claude ]] || file=".agentic-dev-tooling.$platform.lock"
  LOCK="$TOOLING_DOT/$file"
  check_parents "$LOCK"
  if [[ -L "$LOCK" ]] || { [[ -e "$LOCK" ]] && [[ ! -f "$LOCK" ]]; }; then
    echo "install lock must be a regular file: $LOCK" >&2; exit 1
  fi
  mkdir -p "$TOOLING_DOT"
}

copy() { # copy $1 -> $2 unless exists and differs without --force
  # `cp -R` must never run against an EXISTING destination directory: GNU cp (coreutils, the
  # default on Linux) nests the source inside it (dst/dst) when dst already exists, rather than
  # merging into it -- a macOS/BSD cp trailing-slash quirk previously hid this. So dst is always
  # made absent first (skip = don't touch it; --force = remove it) before any cp runs.
  # With LOCK set, a destination still holding exactly what the last install wrote is not a
  # local change, so upstream updates reach it; anything edited since keeps the skip.
  local src=$1 dst=$2
  check_parents "$dst"
  if [[ -L "$dst" ]]; then echo "skip (local symlink): $dst"; return 0; fi
  if protected "$dst"; then echo "skip (protected): $dst"; return 0; fi
  if [ -e "$dst" ]; then
    if diff -rq "$src" "$dst" >/dev/null 2>&1; then lock_record "$dst"; return 0; fi
    if [ "$FORCE" = 0 ] && ! lock_untouched "$dst"; then echo "skip (local changes, use --force): $dst"; return 0; fi
    rm -rf "$dst"
  fi
  mkdir -p "$(dirname "$dst")"; cp -R "$src" "$dst"; lock_record "$dst"
}
LOCK=""
# Symlinks count by target, so an adopter's added link reads as a local change.
tree_hash() { (cd "$1" 2>/dev/null && find . \( -type f -o -type l \) | LC_ALL=C sort | while IFS= read -r f; do printf '%s ' "$f"; if [ -L "$f" ]; then echo "-> $(readlink "$f")"; else cksum < "$f"; fi; done) || cksum < "$1"; }
lock_key() {
  case "$1" in
    "$TOOLING_DOT"/*) printf '.claude/%s' "${1#"$TOOLING_DOT"/}" ;;
    *) printf '%s' "${1#"$PROTECT_ROOT"/}" ;;
  esac
}
lock_untouched() { [ -n "$LOCK" ] && [ -f "$LOCK" ] && [ "$(jq -r --arg k "$(lock_key "$1")" '.[$k] // ""' "$LOCK")" = "$(tree_hash "$1" | cksum)" ]; }
lock_record() {
  [ -n "$LOCK" ] || return 0
  [ -f "$LOCK" ] || echo '{}' > "$LOCK"
  local t; t="$(mktemp)"
  jq --arg k "$(lock_key "$1")" --arg v "$(tree_hash "$1" | cksum)" '.[$k] = $v' "$LOCK" > "$t" && mv "$t" "$LOCK"
}

# Skip skill directories that hold only a SKILL.md.template scaffold and no real SKILL.md
# (e.g. plugins/core-lifecycle/skills/scaffold-component, scaffold-endpoint) -- those are
# authoring templates for consumers to fill in, not installable skills. Dirs that lack a
# SKILL.md for a different reason (e.g. skills/_shared, a reference bundle other skills link
# to via relative paths) are NOT template-only and must still be installed.
is_template_only_skill() { # $1 = skill dir, trailing slash optional
  local d="${1%/}"
  [ -f "$d/SKILL.md.template" ] && [ ! -f "$d/SKILL.md" ]
}

install_claude() {
  need jq; local root="${PROJECT:-$PWD}"; [ "$USER_SCOPE" = 1 ] && root="$HOME"
  mkdir -p "$root"; root="$(cd "$root" && pwd)"
  init_protected "$root"
  local dot="$TOOLING_DOT"
  init_lock claude
  for p in core-lifecycle guardrails release-ops reviewer-packs writing starter-memory; do
    [ -d "$HERE/plugins/$p/skills" ] && for s in "$HERE/plugins/$p/skills"/*/; do
      is_template_only_skill "$s" && continue
      copy "$s" "$dot/skills/$(basename "$s")"; done
    [ -d "$HERE/plugins/$p/agents" ] && for a in "$HERE/plugins/$p/agents"/*.md; do
      copy "$a" "$dot/agents/$(basename "$a")"; done
    [ -d "$HERE/plugins/$p/hooks" ] && for h in "$HERE/plugins/$p/hooks"/*.sh; do
      copy "$h" "$dot/hooks/$(basename "$h")"; done
  done
  if [ "$WITH_FLEET" = 1 ]; then
    for s in "$HERE/plugins/fleet/skills"/*/; do
      is_template_only_skill "$s" && continue
      copy "$s" "$dot/skills/$(basename "$s")"; done
    for h in "$HERE/plugins/fleet/hooks"/*.sh; do copy "$h" "$dot/hooks/$(basename "$h")"; done
    echo "NOTE: fleet pack requires the Claude Code desktop session-management MCP (mcp__ccd_session_mgmt)."
  fi
  copy "$HERE/config/repo-config.example.json" "$dot/repo-config.example.json"
  copy "$HERE/config/repo-config.reference.md" "$dot/repo-config.reference.md"
  # scripts/repo-config.sh and the path-scoped rules docs are PROJECT-level concepts:
  # the helper is sourced as `scripts/repo-config.sh` relative to a repo root, and the
  # rules docs are scoped to a repo's own file layout. Under --user, $root is $HOME --
  # `$HOME/scripts` is never resolved as a repo script root, and $HOME/.claude/rules
  # would apply one repo's path scoping to every repo. So both are project-scope only.
  if [ "$USER_SCOPE" = 0 ]; then
    copy "$HERE/scripts/repo-config.sh" "$root/scripts/repo-config.sh"
    # Skills/agents cite these as `.claude/rules/<name>.md`; this is where they land.
    for r in "$HERE/docs/rules"/*.md; do copy "$r" "$dot/rules/$(basename "$r")"; done
  else
    echo "note: --user scope skips scripts/repo-config.sh and .claude/rules/ (both project-level; install per-project with --project to get them)"
  fi
  # Merge hook wiring from base settings into settings.json.
  local settings="$dot/settings.json" merged_settings
  if [[ -L "$settings" ]]; then
    echo "skip (local symlink): $settings"
    return 0
  fi
  if protected "$settings"; then
    echo "skip (protected): $settings"
    echo "claude install complete: $dot"
    return 0
  fi
  [ -f "$settings" ] || echo '{}' > "$settings"

  # jq's `*` deep-merge replaces (not unions) array-valued keys wholesale. Used naively on the
  # whole document, an adopter with ANY pre-existing hooks.PreToolUse entry would lose every
  # base guardrail hook silently. So: non-hooks keys still deep-merge with the adopter winning
  # (plain `*`), but each hooks.<event> array is unioned explicitly -- every adopter entry is
  # kept, and only base entries whose hook command isn't already present (by command string,
  # anywhere in that event's adopter entries) get appended.
  # The fleet hook ships wired only for the marketplace route (hooks.json), so add it here.
  local base="$HERE/config/base.settings.json"
  if [ "$WITH_FLEET" = 1 ]; then
    base="$(mktemp)"
    jq '.hooks.SessionStart += [{matcher: "startup|resume|clear|compact",
          hooks: [{type: "command", command: ".claude/hooks/session-handshake.sh", timeout: 10}]}]' \
      "$HERE/config/base.settings.json" > "$base"
  fi
  local had_existing_hooks
  had_existing_hooks="$(jq '((.hooks // {}) | [.[] | length] | add // 0) > 0' "$settings")"

  # Hook commands must not be bare relative paths. Claude Code runs a hook with cwd set to
  # Claude's CURRENT directory, and that follows Claude into a worktree or after a `cd`, so
  # ".claude/hooks/x.sh" resolves against whichever repo Claude is in at the moment: it runs
  # that repo's copy of the hook, or fails when the repo has none. ${CLAUDE_PROJECT_DIR} stays
  # at the root where the session started, which is where the loop above installed them.
  # So --project writes every ".claude/hooks/..." command (base- or adopter-supplied, with or
  # without a leading interpreter such as `python3`) as "${CLAUDE_PROJECT_DIR:-.}"/.claude/hooks/...,
  # which also repairs an older install on re-run. --user writes the absolute install path
  # instead, because $HOME is not the project root. `norm` maps all three forms to the bare
  # relative one, so dedupe and matcher widening see one hook, not three.
  merged_settings="$(mktemp "$dot/.settings.XXXXXXXX")"
  if jq -s --arg abs_prefix "$root/.claude/hooks/" --argjson userscope "$([[ "$USER_SCOPE" = 1 ]] && echo true || echo false)" '
    # Compare in bare relative form: earlier installs wrote relative, absolute (--user) or
    # ${CLAUDE_PROJECT_DIR} commands, optionally after an interpreter word. Only BALANCED
    # forms are recognised: the variable quoted on its own ("$X"/ "${X}"/ "${X:-.}"/), bare
    # ($X/ ${X}/ ${X:-.}/), or the whole path quoted ("$X/.claude/hooks/f", closing quote
    # dropped with it). Matching each quote or brace on its own left a stray quote behind,
    # which no shell can parse, and let a broken ${X/... form pass as the base hook.
    # Whole-path normalization identifies managed commands. Rendering preserves
    # the full quoted word for custom paths.
    def pdvar: "(?:\\$CLAUDE_PROJECT_DIR|\\$\\{CLAUDE_PROJECT_DIR(?::-\\.)?\\})";
    def user_anchor:
      $abs_prefix | if test("^[A-Za-z0-9_./-]+$") then . else @sh end;
    def norm: if type != "string" then . else
      (user_anchor as $user_anchor |
       if startswith($user_anchor) then ".claude/hooks/" + ltrimstr($user_anchor)
       elif startswith($abs_prefix) then ".claude/hooks/" + ltrimstr($abs_prefix)
       else . end)
      | sub("^(?<i>(?:[A-Za-z0-9_.-]+ +)?)\"" + pdvar + "/\\.claude/hooks/(?<p>(?:[A-Za-z0-9_-][A-Za-z0-9_.-]*/)*[A-Za-z0-9_-][A-Za-z0-9_.-]*)\"(?=[[:blank:]]|$)"; "\(.i).claude/hooks/\(.p)")
      | sub("^(?<i>(?:[A-Za-z0-9_.-]+ +)?)(?:\"" + pdvar + "\"|" + pdvar + ")/\\.claude/hooks/"; "\(.i).claude/hooks/")
      end;
    def anchor($to): if type == "string"
      then sub("^(?<i>(?:[A-Za-z0-9_.-]+ +)?)\\.claude/hooks/"; "\(.i)\($to)") else . end;
    def quoted_project_prefix:
      "^(?<i>(?:[A-Za-z0-9_.-]+ +)?)\"" + pdvar + "/\\.claude/hooks/";
    def user_literal_command:
      sub("(?<original>" + quoted_project_prefix + "(?<p>[A-Za-z0-9_./() -]+)\")(?=[[:blank:]]|$)";
          # Only re-anchor complete literal path components.
          if (.p | split("/") | all(length > 0 and . != "." and . != ".."))
          then "\(.i)\(($abs_prefix + .p) | @sh)"
          else .original
          end);
    def render($to; $managed):
      if type != "string" then .
      elif test(quoted_project_prefix) then
        norm as $normalized |
        if ($managed | index($normalized)) != null then $normalized | anchor($to)
        elif $userscope then
          user_literal_command
        else .
        end
      else norm | anchor($to)
      end;
    (.[0]) as $adopter | (.[1]) as $base |
    ($base * $adopter) as $shallow |
    ( ($base.hooks // {}) as $bh | ($adopter.hooks // {}) as $ah |
      (($bh | keys) + ($ah | keys) | unique) as $events |
      ($events | map({
        key: .,
        value: (
          (($ah[.]) // []) as $aarr |
          (($bh[.]) // []) as $barr |
          ($aarr | [.[] | .hooks[]?.command | norm]) as $existing |
          ($barr | map(select(((.hooks // []) | any(. as $h | ($existing | index($h.command | norm)) != null)) | not))) as $toadd |
          # An adopter entry that runs a base hook keeps its own matcher, widened by the
          # base matcher, so a release that adds a tool (Edit -> Edit|Write) reaches
          # existing installs without ever narrowing what the adopter chose.
          ($aarr | map(. as $ae |
            ([$barr[] | select(((.hooks // []) | map(.command | norm)) as $bc
                | (($ae.hooks // []) | any(.command | norm | IN($bc[]))))
              | .matcher // empty]) as $bm |
            # Only an entry that runs nothing but base hooks is widened, so an adopter hook
            # sharing the entry never starts firing on new tools; "*" already matches all.
            ([$barr[] | .hooks[]?.command | norm]) as $allbase |
            if ($bm | length) > 0 and ($ae.matcher | type) == "string" and $ae.matcher != "" and $ae.matcher != "*"
               and (($ae.hooks // []) | all(.command | norm | IN($allbase[])))
            then .matcher = (($ae.matcher | split("|")) as $own
                | ($own + (($bm | map(split("|")) | add) - $own | unique)) | join("|"))
            else . end)) as $aarr2 |
          ($aarr2 + $toadd)
        )
      }) | from_entries)
    ) as $mergedhooks |
    ($shallow + { hooks: $mergedhooks }) as $merged |
    (if $userscope then user_anchor else "\"${CLAUDE_PROJECT_DIR:-.}\"/.claude/hooks/" end) as $to |
    [$base.hooks[]?[]?.hooks[]?.command | norm] as $managed |
    $merged | .hooks |= with_entries(.value |= map(
      .hooks |= map(if has("command") then .command |= render($to; $managed) else . end)
    ))
  ' "$settings" "$base" > "$merged_settings"; then
    mv "$merged_settings" "$settings"
  else
    rm -f "$merged_settings"
    return 1
  fi
  [ "$WITH_FLEET" = 1 ] && rm -f "$base"

  [ "$had_existing_hooks" = "true" ] && \
    echo "note: settings.json already had hook entries — merged (kept every existing entry, added any missing base hook wiring)"
  echo "claude install complete: $dot"
}

install_staged_files() {
  local generated="$1" root="$2" f
  while IFS= read -r -d '' f; do
    copy "$f" "$root/${f#"$generated"/}"
  done < <(find "$generated" -type f -print0)
}

install_agents_only() (
  need python3; need jq
  local root="${PROJECT:-$PWD}" stage
  mkdir -p "$root"; root="$(cd "$root" && pwd)"
  init_protected "$root"; init_lock "$PLATFORM"
  stage="$(mktemp -d)"
  trap 'rm -rf "$stage"' EXIT
  python3 "$HERE/scripts/render-agent-profiles.py" "$PLATFORM" "$stage"
  install_staged_files "$stage" "$root"
  echo "$PLATFORM specialist profiles installed: $root"
)

install_rulesync_platform() {
  need npx; local local_root="${PROJECT:-$PWD}"
  mkdir -p "$local_root"; local_root="$(cd "$local_root" && pwd)"
  init_protected "$local_root"; init_lock "$PLATFORM"

  # rulesync target ids, verified empirically against rulesync@16.7.0's own
  # `generate --help` and `rulesync docs reference/supported-tools` -- NOT what
  # the brief assumed:
  #  - codex   -> codexcli   (matches the brief)
  #  - copilot -> copilot    (matches the brief)
  #  - gemini  -> no target exists at all. rulesync's supported-tools table has
  #    no "geminicli" id and no Gemini CLI row of any kind (only the two
  #    Antigravity targets, which share Gemini's config tree) -- consistent
  #    with consumer Gemini CLI's 2026-06 sunset. Handled directly below,
  #    bypassing rulesync generate entirely.
  #  - antigravity -> no plain "antigravity" id either; Antigravity 2.0 split
  #    into antigravity-ide and antigravity-cli. antigravity-cli is used here
  #    to match the CLI-oriented naming of the other three platforms.
  # A `case` rather than an associative array on purpose: `declare -A` needs bash 4+,
  # and stock macOS still ships bash 3.2, where the array literal's `[codex]=...` is
  # parsed as an arithmetic subscript instead -- so `codex` is evaluated as a variable
  # name and `set -u` aborts the install with `codex: unbound variable`.
  local rulesync_target=""
  case "$PLATFORM" in
    codex)       rulesync_target=codexcli ;;
    copilot)     rulesync_target=copilot ;;
    antigravity) rulesync_target=antigravity-cli ;;
    gemini)      rulesync_target="" ;;  # no rulesync target exists; handled directly below
  esac

  local stage; stage=$(mktemp -d)
  local genout; genout=$(mktemp -d)
  # shellcheck disable=SC2064 # expand now: these locals are out of scope when EXIT fires
  trap "rm -rf '$stage' '$genout'" EXIT
  # Stage a claudecode-shaped project for rulesync import.
  ( PROJECT="$stage" USER_SCOPE=0 WITH_FLEET=0 FORCE=1 install_claude ) >/dev/null

  # install_claude does not ship a root CLAUDE.md (only .claude/skills|agents|
  # hooks + config docs) -- verified: with none present, `rulesync import
  # --targets claudecode` reports "No rule files found" and imports nothing, so
  # AGENTS.md/GEMINI.md/copilot-instructions.md would come out empty. Seed a
  # minimal root rules doc so the rules layer has real content to convert.
  cat > "$stage/CLAUDE.md" <<'MD'
# AI agent instructions

Use the skills and specialist profiles discovered by your client for this checkout.
Use only its advertised operations. A required isolated dispatch needs an actual
agent with the specified scope and permissions. Report a missing capability with
its name and host. See .claude/repo-config.reference.md for project configuration.
MD

  # `rulesync import --targets claudecode` with no -f imports only the "rules"
  # feature by default (verified) -- mcp/hooks/permissions need an explicit -f.
  # subagents and skills are deliberately EXCLUDED here: importing either
  # hard-fails (exit 1, aborting this whole pipeline under set -e) against this
  # repo's real content, not a hypothetical:
  #  - subagents: any .claude/agents/*.md whose frontmatter `description`
  #    contains ": " inside an unquoted YAML scalar (e.g. researcher.md) fails
  #    rulesync's strict YAML parser.
  #  - skills: .claude/skills/_shared (deliberately no SKILL.md -- see
  #    is_template_only_skill) aborts the importer outright, and several real
  #    skills (ci-status, dev-lifecycle, reproduce-then-fix, review-pr, ...) use
  #    an unquoted `argument-hint: [foo]`, which YAML parses as a one-element
  #    array where rulesync's schema requires a string.
  # Skills are therefore emitted directly (copy, not rulesync-import) below,
  # for the two platforms with a native .agents/skills/ convention.
  ( cd "$stage" && npx --ignore-scripts -y rulesync@16.7.0 import --targets claudecode \
      -f rules,mcp,hooks,permissions )

  # CRITICAL fix (Task 10 review): rulesync writes real files, not through
  # copy() -- pointing it straight at $local_root would silently clobber an
  # adopter's hand-edit to a previously generated file on every re-run, with
  # --force having no effect on this path (reproduced: a hand-edited AGENTS.md
  # got destroyed by a plain re-run). So generate (and gemini's direct
  # emission) targets a SECOND staging dir ($genout), and every file it
  # produced is then walked and installed into $local_root through copy() --
  # giving this path the same identical/adopter-modified/missing/--force
  # semantics as the claude path.
  if [ "$PLATFORM" = gemini ]; then
    # No rulesync generate target exists for Gemini CLI (verified above) --
    # stage GEMINI.md directly from the staged root doc instead.
    mkdir -p "$genout"; cp "$stage/CLAUDE.md" "$genout/GEMINI.md"
    echo "NOTE: consumer Gemini CLI was sunset 2026-06, and rulesync (16.7.0) has no Gemini CLI target either — GEMINI.md is written directly, not rulesync-generated. Use antigravity unless on enterprise Code Assist. See CAPABILITIES.md."
  else
    # rulesync generate has no --base-dir flag (verified via `generate --help`);
    # the real equivalent is --output-roots.
    ( cd "$stage" && npx --ignore-scripts -y rulesync@16.7.0 generate --targets "$rulesync_target" \
        -f rules,mcp,hooks,permissions --output-roots "$genout" )
    if [ "$PLATFORM" = antigravity ]; then
      # Two more rulesync-side degradations for antigravity-cli, both silent
      # (stderr-only, easy to miss) and confirmed on every run against this
      # repo's real staged content:
      echo "NOTE: rulesync skips the beforeSubmitPrompt hook event for antigravity-cli (not supported) — the UserPromptSubmit-mapped hook (detect-secrets.sh) does not convert. See CAPABILITIES.md."
      echo "NOTE: antigravity-cli supports the permissions layer only in global scope (--global) — project-scope permissions are not written by this installer. See CAPABILITIES.md."
    fi
  fi

  if [[ "$PLATFORM" != gemini ]]; then
    need python3
    python3 "$HERE/scripts/render-agent-profiles.py" "$PLATFORM" "$genout"
  fi
  install_staged_files "$genout" "$local_root"

  # Profiles and hooks reference the Claude rule/config paths even on a
  # standalone install. Keep those paths usable without enabling Claude hooks.
  for r in "$stage/.claude/rules"/*.md; do copy "$r" "$local_root/.claude/rules/$(basename "$r")"; done
  copy "$stage/.claude/repo-config.reference.md" "$local_root/.claude/repo-config.reference.md"
  copy "$stage/.claude/repo-config.example.json" "$local_root/.claude/repo-config.example.json"
  copy "$HERE/scripts/repo-config.sh" "$local_root/scripts/repo-config.sh"

  # The converted hook configs still run .claude/hooks/<name>.sh, so ship those scripts too.
  for p in core-lifecycle guardrails release-ops reviewer-packs writing starter-memory; do
    [ -d "$HERE/plugins/$p/hooks" ] && for h in "$HERE/plugins/$p/hooks"/*.sh; do
      copy "$h" "$local_root/.claude/hooks/$(basename "$h")"; done
  done

  # Skills already went through copy() directly (never the clobbering bug
  # above) -- kept as whole-directory copies straight to $local_root, same
  # granularity install_claude uses for the same skill directories.
  case "$PLATFORM" in
    codex|antigravity)
      # Run the native bundled helpers from the same .agents path where the
      # whole skill is installed. Preserve the skills' trusted-ref checks.
      for s in "$stage/.claude/skills"/*; do
        if [[ -f "$s/SKILL.md" ]]; then
          sed -e 's|\.claude/skills/|.agents/skills/|g' "$s/SKILL.md" > "$s/SKILL.md.tmp"
          mv "$s/SKILL.md.tmp" "$s/SKILL.md"
        fi
        copy "$s" "$local_root/.agents/skills/$(basename "$s")"
      done
      ;;
  esac

  [ "$PLATFORM" = copilot ] && echo "NOTE: Copilot hook support is partial — rulesync skips PreToolUse/PostToolUse matcher hooks for copilot (not supported), keeping only UserPromptSubmit-shaped hooks. See CAPABILITIES.md."
  echo "$PLATFORM install complete: $local_root"
}

doctor() {
  for c in git jq; do command -v "$c" >/dev/null && echo "ok: $c" || echo "MISSING: $c"; done
  for c in gh npx; do command -v "$c" >/dev/null && echo "ok: $c" || echo "warn: $c missing (gh: lifecycle skills; npx: non-claude installs)"; done
  echo "capability notes: Copilot hooks are partial (PreToolUse/PostToolUse unsupported); Gemini CLI has no rulesync target (sunset); Antigravity hooks are partial (beforeSubmitPrompt/UserPromptSubmit unsupported) and permissions are global-scope only (not written by --project installs); fleet pack Claude-desktop-only; see CAPABILITIES.md"
}

imports_cmd() {
  cat "$HERE/imports/README.md"
  command -v claude >/dev/null && \
    echo "Run: claude plugin marketplace add claude-plugins-official && claude plugin install superpowers mattpocock-skills" || \
    echo "claude CLI not found — follow the instructions above manually."
}

if [[ "$AGENTS_ONLY" == 1 ]]; then
  case "$PLATFORM" in claude|codex|copilot|antigravity) ;; *) echo "--agents-only requires claude, codex, copilot or antigravity" >&2; exit 2 ;; esac
  if [[ "$USER_SCOPE" == 1 || "$WITH_FLEET" == 1 ]]; then
    echo "--agents-only installs project profiles; --user and --with-fleet are incompatible" >&2; exit 2
  fi
  install_agents_only
  exit
fi

case "$PLATFORM" in
  claude) install_claude ;;
  doctor) doctor ;;
  imports) imports_cmd ;;
  codex|copilot|gemini|antigravity) install_rulesync_platform ;;
  *) echo "usage: install.sh {claude|codex|copilot|gemini|antigravity|imports|doctor} [--project <path>|--user] [--with-fleet] [--agents-only] [--force]" >&2; exit 2 ;;
esac
