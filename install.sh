#!/usr/bin/env bash
# agentic-dev-tooling installer. See CAPABILITIES.md for per-platform coverage.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
PLATFORM="${1:-}"; shift || true
PROJECT=""; USER_SCOPE=0; WITH_FLEET=0; FORCE=0
while [ $# -gt 0 ]; do case "$1" in
  --project) PROJECT="$2"; shift 2;; --user) USER_SCOPE=1; shift;;
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

copy() { # copy $1 -> $2 unless exists and differs without --force
  # `cp -R` must never run against an EXISTING destination directory: GNU cp (coreutils, the
  # default on Linux) nests the source inside it (dst/dst) when dst already exists, rather than
  # merging into it -- a macOS/BSD cp trailing-slash quirk previously hid this. So dst is always
  # made absent first (skip = don't touch it; --force = remove it) before any cp runs.
  local src=$1 dst=$2
  if [ -e "$dst" ]; then
    if diff -rq "$src" "$dst" >/dev/null 2>&1; then return 0; fi   # identical: nothing to do
    if [ "$FORCE" = 0 ]; then echo "skip (local changes, use --force): $dst"; return 0; fi
    rm -rf "$dst"
  fi
  mkdir -p "$(dirname "$dst")"; cp -R "$src" "$dst"
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
  local dot="$root/.claude"
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
  local settings="$dot/settings.json"; mkdir -p "$dot"
  [ -f "$settings" ] || echo '{}' > "$settings"

  # jq's `*` deep-merge replaces (not unions) array-valued keys wholesale. Used naively on the
  # whole document, an adopter with ANY pre-existing hooks.PreToolUse entry would lose every
  # base guardrail hook silently. So: non-hooks keys still deep-merge with the adopter winning
  # (plain `*`), but each hooks.<event> array is unioned explicitly -- every adopter entry is
  # kept, and only base entries whose hook command isn't already present (by command string,
  # anywhere in that event's adopter entries) get appended.
  local had_existing_hooks
  had_existing_hooks="$(jq '((.hooks // {}) | [.[] | length] | add // 0) > 0' "$settings")"

  # base.settings.json wires hooks with paths already relative to the project root
  # (".claude/hooks/<name>.sh"), matching exactly where the loop above installs them
  # (<root>/.claude/hooks/<name>.sh) -- Claude Code runs hook commands with cwd at the
  # project root, so no path rewrite is needed for --project. --user is different: those
  # relative commands resolve against whatever project is active at hook-run time, not
  # $HOME, so they're inert there. For --user we rewrite any ".claude/hooks/..." command
  # (base- or adopter-supplied) to the absolute path they were just installed at.
  jq -s --arg abs_prefix "$dot/hooks/" --argjson userscope "$([ "$USER_SCOPE" = 1 ] && echo true || echo false)" '
    (.[0]) as $adopter | (.[1]) as $base |
    ($base * $adopter) as $shallow |
    ( ($base.hooks // {}) as $bh | ($adopter.hooks // {}) as $ah |
      (($bh | keys) + ($ah | keys) | unique) as $events |
      ($events | map({
        key: .,
        value: (
          (($ah[.]) // []) as $aarr |
          (($bh[.]) // []) as $barr |
          ($aarr | [.[] | .hooks[]?.command]) as $existing |
          ($barr | map(select(((.hooks // []) | any(. as $h | ($existing | index($h.command)) != null)) | not))) as $toadd |
          ($aarr + $toadd)
        )
      }) | from_entries)
    ) as $mergedhooks |
    ($shallow + { hooks: $mergedhooks }) as $merged |
    if $userscope then
      $merged | .hooks |= with_entries(.value |= map(
        .hooks |= map(
          if (.command | type) == "string" and (.command | startswith(".claude/hooks/"))
          then .command |= sub("^\\.claude/hooks/"; $abs_prefix)
          else . end
        )
      ))
    else $merged end
  ' "$settings" "$HERE/config/base.settings.json" > "$settings.tmp" \
    && mv "$settings.tmp" "$settings"

  [ "$had_existing_hooks" = "true" ] && \
    echo "note: settings.json already had hook entries — merged (kept every existing entry, added any missing base hook wiring)"
  echo "claude install complete: $dot"
}

install_rulesync_platform() {
  need npx; local local_root="${PROJECT:-$PWD}"
  mkdir -p "$local_root"; local_root="$(cd "$local_root" && pwd)"

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

Installed via agentic-dev-tooling. See .claude/skills/, .claude/agents/, and
.claude/hooks/ for available capabilities; .claude/repo-config.reference.md
documents optional per-repo configuration.
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
  ( cd "$stage" && npx -y rulesync@16.7.0 import --targets claudecode \
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
    ( cd "$stage" && npx -y rulesync@16.7.0 generate --targets "$rulesync_target" \
        -f rules,mcp,hooks,permissions --output-roots "$genout" )
    if [ "$PLATFORM" = antigravity ]; then
      # Two more rulesync-side degradations for antigravity-cli, both silent
      # (stderr-only, easy to miss) and confirmed on every run against this
      # repo's real staged content:
      echo "NOTE: rulesync skips the beforeSubmitPrompt hook event for antigravity-cli (not supported) — the UserPromptSubmit-mapped hook (detect-secrets.sh) does not convert. See CAPABILITIES.md."
      echo "NOTE: antigravity-cli supports the permissions layer only in global scope (--global) — project-scope permissions are not written by this installer. See CAPABILITIES.md."
    fi
  fi

  # Install every rulesync-staged file into the real target through copy(),
  # preserving relative paths (copy() mkdir -p's the parent dir for each).
  while IFS= read -r -d '' f; do
    copy "$f" "$local_root/${f#"$genout"/}"
  done < <(find "$genout" -type f -print0)

  # Skills already went through copy() directly (never the clobbering bug
  # above) -- kept as whole-directory copies straight to $local_root, same
  # granularity install_claude uses for the same skill directories.
  case "$PLATFORM" in
    codex|antigravity)
      for p in core-lifecycle guardrails release-ops reviewer-packs writing starter-memory; do
        [ -d "$HERE/plugins/$p/skills" ] && for s in "$HERE/plugins/$p/skills"/*/; do
          is_template_only_skill "$s" && continue
          copy "$s" "$local_root/.agents/skills/$(basename "$s")"
        done
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

case "$PLATFORM" in
  claude) install_claude ;;
  doctor) doctor ;;
  imports) imports_cmd ;;
  codex|copilot|gemini|antigravity) install_rulesync_platform ;;
  *) echo "usage: install.sh {claude|codex|copilot|gemini|antigravity|imports|doctor} [--project <path>|--user] [--with-fleet] [--force]" >&2; exit 2 ;;
esac
