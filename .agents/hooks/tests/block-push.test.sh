#!/bin/bash
# tests/block-push.test.sh — regression suite for block-push.sh
#
# Creates throwaway git repos under $TMPDIR. Feeds JSON on stdin to the hook
# and asserts whether a "deny" envelope is emitted. Exits non-zero on failure.
#
# Rule: every DENY test for an explicit refspec must run from a repo whose
# current branch is NOT the default branch. That ensures the refspec detection
# is what triggers the deny, not the CURRENT_BRANCH == DEFAULT_BRANCH fallback.

set -uo pipefail

HOOK_SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/block-push.sh"
FAILURES=0

# ---------------------------------------------------------------------------
# Setup: bare origin + two worktrees
# ---------------------------------------------------------------------------
TDIR="$(mktemp -d "${TMPDIR:-/tmp}/block-push-test-XXXXXX")"
trap 'rm -rf "$TDIR"' EXIT

BARE="$TDIR/origin.git"
REPO_MAIN="$TDIR/repo-main"       # checked out on main (default branch)
REPO_FEATURE="$TDIR/repo-feature" # checked out on feature-branch

git init --bare "$BARE" -q
git -C "$BARE" symbolic-ref HEAD refs/heads/main

# Seed the bare repo with one commit via a temp clone.
_INIT="$TDIR/init-clone"
git clone "$BARE" "$_INIT" -q 2>/dev/null
git -C "$_INIT" config user.email "test@example.com"
git -C "$_INIT" config user.name "Test"
touch "$_INIT/README"
git -C "$_INIT" add README
git -C "$_INIT" -c commit.gpgsign=false commit -qm "init"
git -C "$_INIT" push -q origin main
rm -rf "$_INIT"

# repo-main: on main.
git clone "$BARE" "$REPO_MAIN" -q 2>/dev/null
git -C "$REPO_MAIN" config user.email "test@example.com"
git -C "$REPO_MAIN" config user.name "Test"

# repo-feature: on feature-branch (NOT the default branch).
git clone "$BARE" "$REPO_FEATURE" -q 2>/dev/null
git -C "$REPO_FEATURE" config user.email "test@example.com"
git -C "$REPO_FEATURE" config user.name "Test"
git -C "$REPO_FEATURE" checkout -b feature-branch -q

# ---------------------------------------------------------------------------
# Helper: run the hook with a command string.
# $1 = command, $2 = cwd (default REPO_FEATURE), $3 = extra VAR=val env pairs
# Default cwd is REPO_FEATURE so DENY tests exercise refspec detection, not
# the CURRENT_BRANCH fallback.
# ---------------------------------------------------------------------------
run_hook() {
  local cmd="$1"
  local cwd="${2:-$REPO_FEATURE}"
  local extra_env="${3:-}"
  local json _tmp output
  json=$(jq -n --arg c "$cmd" '{"tool_name":"Bash","tool_input":{"command":$c}}')
  _tmp=$(mktemp)
  printf '%s' "$json" > "$_tmp"
  # shellcheck disable=SC2086
  output=$(cd "$cwd" && env $extra_env bash "$HOOK_SCRIPT" < "$_tmp" 2>/dev/null)
  rm -f "$_tmp"
  printf '%s' "$output"
}

check() {
  local label="$1" expected="$2" output="$3" got
  if printf '%s' "$output" | grep -q '"deny"'; then got="deny"; else got="allow"; fi
  if [ "$got" = "$expected" ]; then
    printf 'PASS: %s\n' "$label"
  else
    printf 'FAIL: %s — expected %s, got %s\n' "$label" "$expected" "$got"
    printf '      output: %s\n' "$output"
    FAILURES=$((FAILURES + 1))
  fi
}

# ---------------------------------------------------------------------------
# Test cases
# All DENY-on-refspec cases run from $REPO_FEATURE (on feature-branch) so
# the CURRENT_BRANCH fallback cannot mask a broken refspec check.
# ---------------------------------------------------------------------------

# Plain push of the default branch name, run from a non-default-branch repo.
check "git push origin main (from feature branch) → deny" deny \
  "$(run_hook "git push origin main")"

# -C regression: naive `*"git push"*` substring misses this form entirely.
check "git -C <repo> push origin main → deny" deny \
  "$(run_hook "git -C $REPO_FEATURE push origin main" "$TDIR")"

# Double-space regression: `*"git push"*` substring misses this form.
check "git  push origin main (double space, from feature branch) → deny" deny \
  "$(run_hook "git  push origin main")"

# cd prefix: hook resolves REPO_DIR from the cd path.
check "cd <feature-repo> && git push origin main → deny" deny \
  "$(run_hook "cd $REPO_FEATURE && git push origin main" "$TDIR")"

# --all covers all branches including the default.
check "git push --all (from feature branch) → deny" deny \
  "$(run_hook "git push --all")"

# --mirror copies everything, which includes the default branch.
check "git push --mirror (from feature branch) → deny" deny \
  "$(run_hook "git push --mirror")"

# Explicit HEAD:<default> refspec from a non-default-branch repo.
check "git -C <feature-repo> push origin HEAD:main → deny" deny \
  "$(run_hook "git -C $REPO_FEATURE push origin HEAD:main" "$TDIR")"

# Force-push shorthand +<default>.
check "git -C <feature-repo> push origin +main → deny" deny \
  "$(run_hook "git -C $REPO_FEATURE push origin +main" "$TDIR")"

# --all via -C (REPO_DIR and flag detection work together).
check "git -C <feature-repo> push --all → deny" deny \
  "$(run_hook "git -C $REPO_FEATURE push --all" "$TDIR")"

# -c k=v global option skipping: hook must skip the value and still see push.
check "git -c http.sslVerify=false push origin main (from feature branch) → deny" deny \
  "$(run_hook "git -c http.sslVerify=false push origin main")"

# Explicit source:destination refspec where destination is the default branch.
check "git -C <feature-repo> push origin main:main → deny" deny \
  "$(run_hook "git -C $REPO_FEATURE push origin main:main" "$TDIR")"

# Multiple refspecs: deny when any of them resolves to the default branch.
check "git push origin feature-branch main (default branch second) → deny" deny \
  "$(run_hook "git -C $REPO_FEATURE push origin feature-branch main" "$TDIR")"

check "git push origin feature-branch HEAD:main (explicit dest second) → deny" deny \
  "$(run_hook "git -C $REPO_FEATURE push origin feature-branch HEAD:main" "$TDIR")"

check "git push origin main feature-branch (default branch first) → deny" deny \
  "$(run_hook "git -C $REPO_FEATURE push origin main feature-branch" "$TDIR")"

check "git push origin feature-branch other-branch (neither is default) → allow" allow \
  "$(run_hook "git -C $REPO_FEATURE push origin feature-branch other-branch" "$TDIR")"

check "git push origin feature-branch main:main (dest is default) → deny" deny \
  "$(run_hook "git -C $REPO_FEATURE push origin feature-branch main:main" "$TDIR")"

# Feature branch push from the feature-branch worktree → should be allowed.
check "git push origin feature-branch (on feature branch) → allow" allow \
  "$(run_hook "git push origin feature-branch")"

# Cross-repo: cwd is on main, but -C points to the feature-branch repo.
# The hook must evaluate CURRENT_BRANCH from the -C target, not from cwd.
check "git -C <feature-repo> push origin feature-branch (cwd on main) → allow" allow \
  "$(run_hook "git -C $REPO_FEATURE push origin feature-branch" "$REPO_MAIN")"

# A non-push command whose arguments happen to mention "git push" must not block.
check "git log --grep 'git push' → allow" allow \
  "$(run_hook "git log --grep 'git push'")"

# Bypass env var disables the hook entirely.
check "CLAUDE_BYPASS_PUSH_GUARD=1 → allow" allow \
  "$(run_hook "git push origin main" "$REPO_FEATURE" "CLAUDE_BYPASS_PUSH_GUARD=1")"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
printf '\n'
if [ "$FAILURES" -eq 0 ]; then
  printf 'All tests passed.\n'
  exit 0
else
  printf '%d test(s) failed.\n' "$FAILURES"
  exit 1
fi
