#!/usr/bin/env bash
# Test harness for install.sh's rulesync-compiled platforms (codex/copilot/gemini/antigravity).
#
# Deviations from the original brief, verified empirically against rulesync@16.7.0
# (see task-10-report.md for the full deviation log):
#  - antigravity: rulesync has no plain "antigravity" target (split into
#    antigravity-ide/antigravity-cli, mapped to antigravity-cli here); with only a
#    single flat root rule doc staged, rulesync's antigravity output has nothing to
#    put under .agents/rules/ (that path is for *non-root* detail rules, of which
#    this installer currently ships none) -- it writes the root rule to AGENTS.md
#    instead, same file codex uses. So this test asserts AGENTS.md for antigravity,
#    not .agents/rules/*.
#  - copilot's hook-warning line comes from install.sh's own NOTE echo (stdout);
#    rulesync's own "Skipped matcher hook(s) for copilot (not supported)" message
#    goes to stderr and would not survive the `| tee` below on its own.
#  - each platform gets its own mktemp target dir (Task 10 review, MINOR): a
#    shared target let antigravity's AGENTS.md assertion pass on codex's earlier
#    write alone, without antigravity ever having produced the file itself.
set -euo pipefail; cd "$(dirname "$0")/.."
tmp_codex=$(mktemp -d); tmp_copilot=$(mktemp -d); tmp_gemini=$(mktemp -d); tmp_antigravity=$(mktemp -d)
trap 'rm -rf "$tmp_codex" "$tmp_copilot" "$tmp_gemini" "$tmp_antigravity"' EXIT
git -C "$tmp_codex" init -q
git -C "$tmp_copilot" init -q
git -C "$tmp_gemini" init -q
git -C "$tmp_antigravity" init -q

./install.sh codex --project "$tmp_codex"
[ -f "$tmp_codex/AGENTS.md" ] || { echo "FAIL: no AGENTS.md"; exit 1; }
ls "$tmp_codex/.agents/skills"/*/SKILL.md >/dev/null 2>&1 || { echo "FAIL: no codex skills"; exit 1; }

./install.sh copilot --project "$tmp_copilot" | tee "$tmp_copilot/cop.out"
grep -qi "hooks.*not supported\|skip" "$tmp_copilot/cop.out" || { echo "FAIL: no copilot hook warning"; exit 1; }
[ -f "$tmp_copilot/.github/copilot-instructions.md" ] || { echo "FAIL: no copilot instructions"; exit 1; }

./install.sh gemini --project "$tmp_gemini"
[ -f "$tmp_gemini/GEMINI.md" ] || { echo "FAIL: no GEMINI.md"; exit 1; }

./install.sh antigravity --project "$tmp_antigravity"
[ -f "$tmp_antigravity/AGENTS.md" ] || { echo "FAIL: no antigravity AGENTS.md"; exit 1; }
ls "$tmp_antigravity/.agents/skills"/*/SKILL.md >/dev/null 2>&1 || { echo "FAIL: no antigravity skills"; exit 1; }

# No-clobber regression (Task 10 review, CRITICAL): rulesync-generated output
# must respect copy()'s adopter-wins default and --force override, same as the
# claude path -- a hand-edit to a generated file must never be silently
# destroyed by re-running install.sh. Reproduced pre-fix: a plain re-run of
# `install.sh antigravity` overwrote a hand-edited AGENTS.md unconditionally.
marker="LOCAL EDIT $$-$(date +%s)"
printf '%s\n' "$marker" >> "$tmp_antigravity/AGENTS.md"

out="$(./install.sh antigravity --project "$tmp_antigravity")"
grep -qF "$marker" "$tmp_antigravity/AGENTS.md" \
  || { echo "FAIL: re-run destroyed a hand-edit to AGENTS.md (no-clobber regression)"; exit 1; }
printf '%s\n' "$out" | grep -q "skip (local changes, use --force):.*AGENTS.md" \
  || { echo "FAIL: no skip message for the hand-edited AGENTS.md"; exit 1; }

./install.sh antigravity --project "$tmp_antigravity" --force >/dev/null
grep -qF "$marker" "$tmp_antigravity/AGENTS.md" \
  && { echo "FAIL: --force did not restore generated AGENTS.md content"; exit 1; }

echo ok
