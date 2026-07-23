#!/usr/bin/env bash
# tests/test-push-guard.sh — integration tests for block-push.sh
#
# These tests require a temporary git repo and a mock `gh` binary because
# they exercise behaviour that cannot be covered by static JSON fixtures:
#   1. Forged origin/HEAD: even after `git symbolic-ref refs/remotes/origin/HEAD`
#      is rewritten to a decoy branch, the hook (which uses gh as its PRIMARY
#      source) must still deny a push to the true default branch (H2 fix).
#   2. Metacharacter branch name: a branch name containing a regex metacharacter
#      (e.g. "fix+1") must not cause grep to error and silently fail open (H2 fix).
#
# Both tests place a mock `gh` script at the front of PATH and run the hook
# against a minimal temp git repo.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PUSH_HOOK="$REPO_ROOT/.agents/hooks/block-push.sh"

pass=0
fail=0

# ---------------------------------------------------------------------------
# Test 1: Forged origin/HEAD still denies a push to the true default branch
# ---------------------------------------------------------------------------
# Set up a temp git repo where git symbolic-ref says the default is "decoy",
# but our mock `gh` reports the true default as "main".
# The hook (with H2 fix: gh is PRIMARY) must deny `git push origin main`.
(
  _tmpdir=$(mktemp -d)
  trap 'rm -rf "$_tmpdir"' EXIT

  # Create a minimal repo with a commit so HEAD is valid.
  cd "$_tmpdir"
  git init -q
  git config user.email "test@test.com"
  git config user.name "Test"
  git commit --allow-empty -q -m "init"
  # Check out a non-default branch so current branch != default.
  git checkout -q -b feature-work

  # Forge the local origin/HEAD to point at a decoy branch.
  git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/decoy 2>/dev/null || true

  # Create a mock `gh` that returns "main" as the default branch.
  _bindir=$(mktemp -d)
  cat >"$_bindir/gh" <<'GHEOF'
#!/bin/bash
# Mock gh: always report main as the default branch.
echo "main"
GHEOF
  chmod +x "$_bindir/gh"

  # Run the hook inside the temp repo with mock gh at front of PATH.
  # The entire pipeline runs in the modified-PATH environment via a subshell.
  payload='{"tool_name":"Bash","tool_input":{"command":"git push origin main"}}'
  result=$(
    export PATH="$_bindir:$PATH"
    printf '%s' "$payload" | CLAUDE_BYPASS_PUSH_GUARD=0 bash "$PUSH_HOOK" 2>/dev/null || true
  )
  if printf '%s' "$result" | grep -q '"permissionDecision".*"deny"'; then
    echo "PASS forged-origin-head-denied"
    exit 0
  else
    echo "FAIL forged-origin-head-denied: expected deny, got allow (gh primary source not used or not found)"
    exit 1
  fi
) && pass=$((pass + 1)) || { fail=$((fail + 1)); true; }

# ---------------------------------------------------------------------------
# Test 2: Branch name with regex metacharacter does not fail open
# ---------------------------------------------------------------------------
# A default branch name like "fix+1" contains '+' which is a regex metachar.
# Old code: grep -Eq ":${DEFAULT_BRANCH}([[:space:]]|$)" would error with rc 2,
# leaving EXPLICIT_HIT=0 and allowing the push.
# Fixed code: escapes the branch name before use in grep ERE.
(
  _tmpdir=$(mktemp -d)
  trap 'rm -rf "$_tmpdir"' EXIT

  cd "$_tmpdir"
  git init -q
  git config user.email "test@test.com"
  git config user.name "Test"
  git commit --allow-empty -q -m "init"
  # Checkout a non-default branch.
  git checkout -q -b some-feature

  # Mock `gh` returns a branch name with a regex metacharacter.
  _bindir=$(mktemp -d)
  cat >"$_bindir/gh" <<'GHEOF'
#!/bin/bash
echo "fix+1"
GHEOF
  chmod +x "$_bindir/gh"

  # Push to that branch — should be denied (explicit refspec :fix+1 or branch name).
  payload='{"tool_name":"Bash","tool_input":{"command":"git push origin fix+1"}}'
  result=$(
    export PATH="$_bindir:$PATH"
    printf '%s' "$payload" | CLAUDE_BYPASS_PUSH_GUARD=0 bash "$PUSH_HOOK" 2>/dev/null || true
  )
  if printf '%s' "$result" | grep -q '"permissionDecision".*"deny"'; then
    echo "PASS metachar-branch-denied"
    exit 0
  else
    echo "FAIL metachar-branch-denied: expected deny, got allow (metachar in branch name may have caused grep error)"
    exit 1
  fi
) && pass=$((pass + 1)) || { fail=$((fail + 1)); true; }

# ---------------------------------------------------------------------------
# Test 3: Push to a non-default branch is still allowed (sanity check)
# ---------------------------------------------------------------------------
(
  _tmpdir=$(mktemp -d)
  trap 'rm -rf "$_tmpdir"' EXIT

  cd "$_tmpdir"
  git init -q
  git config user.email "test@test.com"
  git config user.name "Test"
  git commit --allow-empty -q -m "init"
  # Checkout a non-default branch so current branch != default.
  git checkout -q -b feature-branch

  _bindir=$(mktemp -d)
  cat >"$_bindir/gh" <<'GHEOF'
#!/bin/bash
echo "main"
GHEOF
  chmod +x "$_bindir/gh"

  payload='{"tool_name":"Bash","tool_input":{"command":"git push origin feature-branch"}}'
  result=$(
    export PATH="$_bindir:$PATH"
    printf '%s' "$payload" | CLAUDE_BYPASS_PUSH_GUARD=0 bash "$PUSH_HOOK" 2>/dev/null || true
  )
  if printf '%s' "$result" | grep -q '"permissionDecision".*"deny"'; then
    echo "FAIL feature-branch-allowed: expected allow, got deny"
    exit 1
  else
    echo "PASS feature-branch-allowed"
    exit 0
  fi
) && pass=$((pass + 1)) || { fail=$((fail + 1)); true; }

# ---------------------------------------------------------------------------
# Test 4: Non-push command on default branch is allowed (early-exit guard)
# ---------------------------------------------------------------------------
# The hook exits 0 early for any command not containing `git push`. If that
# early-exit were removed, the hook would reach the branch comparison and deny
# any command when current branch == default branch.
# This test sets up a repo checked out ON the default branch (so the
# current==default comparison would fire if the early-exit were absent) and
# runs a non-push command. The expected result is allow.
# Note: mock gh is NOT placed in PATH here so the hook falls back to
# `git show-ref` which finds "main" as a local branch.
(
  _tmpdir=$(mktemp -d)
  trap 'rm -rf "$_tmpdir"' EXIT

  cd "$_tmpdir"
  git init -q
  git config user.email "test@test.com"
  git config user.name "Test"
  git commit --allow-empty -q -m "init"
  # Stay on the default branch (main / whatever git init created).
  # The hook must see current == default so that removing the early-exit
  # would flip the result from allow to deny.
  _current=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)

  # Mock gh returns the same branch as the current branch, ensuring that
  # current == default so removing the early-exit would deny.
  _bindir=$(mktemp -d)
  cat >"$_bindir/gh" <<GHEOF
#!/bin/bash
echo "${_current}"
GHEOF
  chmod +x "$_bindir/gh"

  payload='{"tool_name":"Bash","tool_input":{"command":"echo hello"}}'
  result=$(
    export PATH="$_bindir:$PATH"
    printf '%s' "$payload" | CLAUDE_BYPASS_PUSH_GUARD=0 bash "$PUSH_HOOK" 2>/dev/null || true
  )
  if printf '%s' "$result" | grep -q '"permissionDecision".*"deny"'; then
    echo "FAIL non-push-command-allowed: expected allow for non-push command, got deny"
    exit 1
  else
    echo "PASS non-push-command-allowed"
    exit 0
  fi
) && pass=$((pass + 1)) || { fail=$((fail + 1)); true; }

echo ""
echo "$pass/$((pass + fail)) push-guard tests passed"
[ "$fail" -eq 0 ]
