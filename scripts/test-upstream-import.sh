#!/usr/bin/env bash
# Checks are single-quoted on purpose: check() evals them after each run.
# shellcheck disable=SC2016,SC2034
# Regression test for upstream-import.sh, on throwaway git repos.
set -uo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/upstream-import.sh"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
failures=0
check() { if eval "$2"; then :; else echo "FAIL: $1"; failures=$((failures + 1)); fi; }

# Upstream: svc/a.txt (4 lines), ci/x.yml. Downstream: same svc/a.txt with a
# private edit on line 1, plus files it owns.
up="$tmp/up"; down="$tmp/down"
git init -q -b main "$up" && cd "$up" || exit 1
mkdir svc ci && printf 'one\ntwo\nthree\nfour\n' > svc/a.txt && echo up > ci/x.yml
git add -A && git commit -qm base && base=$(git rev-parse HEAD)

git init -q -b main "$down" && cd "$down" || exit 1
mkdir -p svc .github/workflows && printf 'ONE-private\ntwo\nthree\nfour\n' > svc/a.txt
echo secret-deploy > .github/workflows/deploy-prod.yml
echo '{"upstream":"Org/Up","import":["svc/"],"private":[".github/workflows/deploy-"]}' > .github/upstream-sync.json
echo "$base" > .github/upstream-sync.lock
git add -A && git commit -qm base

reset() { git -C "$down" reset -q --hard && git -C "$down" clean -qfd; }
run() { (cd "$down" && bash "$SCRIPT" "$up" >"$tmp/out" 2>&1); }

# 1. Upstream changes line 4, adds a file, and changes a path outside import.
cd "$up" && printf 'one\ntwo\nthree\nFOUR\n' > svc/a.txt && echo new > svc/b.txt && echo changed > ci/x.yml
git add -A && git commit -qm change && head1=$(git rev-parse HEAD)
run; rc=$?
check "clean import exits 0 (got $rc: $(cat "$tmp/out"))" '[[ $rc -eq 0 ]]'
check "private edit on line 1 survives" 'grep -qx ONE-private "$down/svc/a.txt"'
check "upstream line 4 lands" 'grep -qx FOUR "$down/svc/a.txt"'
check "new upstream file lands" '[[ -f "$down/svc/b.txt" ]]'
check "path outside import is skipped" '[[ ! -e "$down/ci/x.yml" ]] && grep -q "ci/x.yml" "$tmp/out"'
check "deploy file untouched" 'grep -qx secret-deploy "$down/.github/workflows/deploy-prod.yml"'
check "lock moves to upstream head" '[[ $(cat "$down/.github/upstream-sync.lock") == "$head1" ]]'
git -C "$down" commit -qm import

# 2. Both sides change the same line: conflict (exit 2), never an overwrite.
cd "$down" && sed -i 's/^two$/TWO-private/' svc/a.txt && git commit -qam private
cd "$up" && sed -i 's/^two$/TWO-up/' svc/a.txt && git commit -qam clash
run; rc=$?
check "same-line clash exits 2 (got $rc)" '[[ $rc -eq 2 ]]'
check "private line not silently replaced" '! grep -qx TWO-up "$down/svc/a.txt" || grep -q "^<<<<<<<" "$down/svc/a.txt"'
reset

# 3. Scrub tokens are refused before anything is applied.
cd "$up" && git reset -q --hard HEAD~1 && echo 'path: [internal]/x' >> svc/b.txt && git commit -qam scrub
run; rc=$?
check "[internal] refused (got $rc)" '[[ $rc -eq 1 ]] && grep -q "scrub" "$tmp/out"'
check "nothing staged after a refusal" 'git -C "$down" diff --cached --quiet'
reset
cd "$up" && git reset -q --hard HEAD~1 && echo '// Issue: internal development reference omitted' >> svc/b.txt && git commit -qam scrub2
run; rc=$?
check "reference-omitted marker refused (got $rc)" '[[ $rc -eq 1 ]]'
reset

# 4. Overlapping prefixes are a config error.
cd "$down" && echo '{"import":["svc/"],"private":["svc/secret"]}' > .github/upstream-sync.json && git commit -qam overlap
run; rc=$?
check "import/private overlap refused (got $rc)" '[[ $rc -eq 1 ]] && grep -q overlaps "$tmp/out"'
git reset -q --hard HEAD~1

# 5. An upstream that doesn't descend from the lock is refused.
cd "$up" && git checkout -q --orphan other && git commit -qm unrelated
run; rc=$?
check "non-descendant refused (got $rc)" '[[ $rc -eq 1 ]] && grep -q "does not descend" "$tmp/out"'

[[ $failures -eq 0 ]] || exit 1
echo "upstream-import: all cases passed."
