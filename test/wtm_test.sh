#!/usr/bin/env bash
#
# Runs the real wtm against throwaway repos in a temp folder, so it can't touch
# yours. The menu itself needs a keyboard, so this covers everything behind it.
#
#   bash test/wtm_test.sh

set -uo pipefail

WT="$(cd "$(dirname "$0")/.." && pwd)/bin/wtm"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/config"
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com
mkdir -p "$HOME" "$XDG_CONFIG_HOME/wtm" "$TMP/code"
printf '%s\n' "$TMP/code" >"$XDG_CONFIG_HOME/wtm/roots"

passed=0 failed=0
ok()   { passed=$((passed + 1)); printf '  ok    %s\n' "$1"; }
fail() { failed=$((failed + 1)); printf '  FAIL  %s\n' "$1"; }
check() { local name="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$name"; else fail "$name"; fi; }
has()  { grep -qF -- "$2" <<<"$1"; }

# A remote with one commit, and a clone of it with a gitignored .env.
git init -q --bare -b main "$TMP/origin.git"
git clone -q "$TMP/origin.git" "$TMP/seed" 2>/dev/null
printf '.env\n' >"$TMP/seed/.gitignore"
git -C "$TMP/seed" add .gitignore && git -C "$TMP/seed" commit -qm "First commit"
git -C "$TMP/seed" push -q origin main
git clone -q "$TMP/origin.git" "$TMP/code/app"
REPO="$TMP/code/app"
printf 'SECRET=1\n' >"$REPO/.env"

echo "init"
out="$(cd "$REPO" && "$WT" init 2 2>&1)"
check "makes slot 1" test -e "$REPO/.worktrees/1/.git"
check "makes slot 2" test -e "$REPO/.worktrees/2/.git"
check "slots start on their own wt branch" test "$(git -C "$REPO/.worktrees/2" branch --show-current)" = wt2
check "copies gitignored env files in" test -f "$REPO/.worktrees/1/.env"
check "keeps .worktrees out of git status" test -z "$(git -C "$REPO" status --porcelain)"
out="$(cd "$REPO" && "$WT" init 2 2>&1)"
check "running it again leaves slots alone" has "$out" "already exists"

echo "list and status"
rows="$("$WT" _rows)"
check "lists the main checkout" has "$rows" $'\tmain\t'
check "shows an untouched slot as free" has "$(grep '/.worktrees/1' <<<"$rows")" "free"
git -C "$REPO/.worktrees/1" switch -qc feature
printf 'x\n' >"$REPO/.worktrees/1/new.txt"
git -C "$REPO/.worktrees/1" add new.txt && git -C "$REPO/.worktrees/1" commit -qm "Add a file"
check "counts commits no remote has" has "$("$WT" status)" "1 unpushed"
printf 'y\n' >>"$REPO/.worktrees/1/new.txt"
check "counts uncommitted changes" has "$("$WT" status)" "1 modified"

echo "free"
out="$("$WT" _free "$REPO/.worktrees/1" slot 2>&1)"
check "won't free a slot with uncommitted work" has "$out" "uncommitted change"
check "and leaves it on its branch" test "$(git -C "$REPO/.worktrees/1" branch --show-current)" = feature
git -C "$REPO/.worktrees/1" checkout -q -- new.txt
out="$("$WT" _free "$REPO/.worktrees/1" slot 2>&1)"
check "frees a clean slot" test "$(git -C "$REPO/.worktrees/1" branch --show-current)" = wt1
check "keeps the branch it held" git -C "$REPO" rev-parse --verify -q refs/heads/feature
check "says it was already free the second time" has "$("$WT" _free "$REPO/.worktrees/1" slot 2>&1)" "already free"
git -C "$REPO/.worktrees/2" commit -q --allow-empty -m "Oops, on the wt branch"
git -C "$REPO/.worktrees/2" switch -qc other
check "won't reset a wt branch with commits of its own" has "$("$WT" _free "$REPO/.worktrees/2" slot 2>&1)" "commit(s) of its own"
check "only frees numbered slots" has "$("$WT" _free "$REPO" main 2>&1)" "Only numbered slots"

echo "remove"
git -C "$REPO" worktree add -q "$TMP/code/app-extra" -b extra-branch 2>/dev/null
check "won't remove a slot" has "$("$WT" _remove "$REPO/.worktrees/1" slot 2>&1)" "Only extras"
"$WT" _remove "$TMP/code/app-extra" extra <<<"y" >/dev/null 2>&1 || true
check "removes an extra worktree" test ! -e "$TMP/code/app-extra"
check "keeps its branch" git -C "$REPO" rev-parse --verify -q refs/heads/extra-branch

printf '\n%d passed, %d failed\n' "$passed" "$failed"
[ "$failed" -eq 0 ]
