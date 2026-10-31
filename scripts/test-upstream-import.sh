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
echo '{"upstream":"Org/Up","import":["svc/"],"private":[".github/workflows/deploy-"],"scrub":["[internal]","internal development reference omitted"]}' > .github/upstream-sync.json
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

cd "$up" && git reset -q --hard HEAD~1 && echo '+ [internal]/x' >> svc/b.txt && git commit -qam scrub3
run; rc=$?
check "marker on a line starting with + refused (got $rc)" '[[ $rc -eq 1 ]]'
reset
cd "$up" && git reset -q --hard HEAD~1

# A downstream that lists no scrub strings imports the same line.
cd "$down" && jq 'del(.scrub)' .github/upstream-sync.json > c.json && mv c.json .github/upstream-sync.json && git commit -qam no-scrub
cd "$up" && echo '+ [internal]/x' >> svc/b.txt && git commit -qam scrub4
run; rc=$?
check "no scrub list: marker line imports (got $rc)" '[[ $rc -eq 0 ]]'
reset
git -C "$down" reset -q --hard HEAD~1
cd "$up" && git reset -q --hard HEAD~1

# The diff's added-line indicator is not content: a '>'-prefixed marker
# must not match a plain line.
cd "$down" && jq '.scrub = [">REDACTED"]' .github/upstream-sync.json > c.json && mv c.json .github/upstream-sync.json && git commit -qam gt-scrub
cd "$up" && echo 'REDACTED' >> svc/b.txt && git commit -qam scrub5
run; rc=$?
check "indicator is not matched as content (got $rc)" '[[ $rc -eq 0 ]]'
reset
git -C "$down" reset -q --hard HEAD~1
cd "$up" && git reset -q --hard HEAD~1

# 4. Upstream edits a file downstream deleted: refused, lock unchanged.
lock_before=$(cat "$down/.github/upstream-sync.lock")
cd "$down" && git rm -q svc/b.txt && git commit -qm drop-b
cd "$up" && echo more >> svc/b.txt && git commit -qam edit-b
run; rc=$?
check "rejected patch exits 1 (got $rc)" '[[ $rc -eq 1 ]]'
check "lock unchanged after a rejected patch" '[[ $(cat "$down/.github/upstream-sync.lock") == "$lock_before" ]]'
check "tree clean after a rejected patch" 'git -C "$down" diff --quiet HEAD'
reset
git -C "$down" reset -q --hard HEAD~1
cd "$up" && git reset -q --hard HEAD~1

# 5. A glob character in an imported name can't pull in a private path.
cd "$down" && echo '{"import":["svc/a*"],"private":["svc/abc"]}' > .github/upstream-sync.json \
  && echo private-abc > svc/abc && git add -A && git commit -qm glob
cd "$up" && echo star > 'svc/a*' && echo up-abc > svc/abc && git add -A && git commit -qm glob
run; rc=$?
check "glob name imports cleanly (got $rc)" '[[ $rc -eq 0 ]]'
check "glob name: private svc/abc untouched" 'grep -qx private-abc "$down/svc/abc" && git -C "$down" diff --cached --quiet -- svc/abc'
reset
git -C "$down" reset -q --hard HEAD~1
cd "$up" && git reset -q --hard HEAD~1

# 6. Overlapping prefixes are a config error.
cd "$down" && echo '{"import":["svc/"],"private":["svc/secret"]}' > .github/upstream-sync.json && git commit -qam overlap
run; rc=$?
check "import/private overlap refused (got $rc)" '[[ $rc -eq 1 ]] && grep -q overlaps "$tmp/out"'
git reset -q --hard HEAD~1

# 7. A config that isn't JSON is refused.
cd "$down" && echo 'not json' > .github/upstream-sync.json && git commit -qam badjson
run; rc=$?
check "invalid JSON config refused (got $rc)" '[[ $rc -eq 1 ]] && grep -q "not valid JSON" "$tmp/out"'
git reset -q --hard HEAD~1

# 8. An upstream that doesn't descend from the lock is refused.
cd "$up" && git checkout -q --orphan other && git commit -qm unrelated
run; rc=$?
check "non-descendant refused (got $rc)" '[[ $rc -eq 1 ]] && grep -q "does not descend" "$tmp/out"'

[[ $failures -eq 0 ]] || exit 1
echo "upstream-import: all cases passed."
