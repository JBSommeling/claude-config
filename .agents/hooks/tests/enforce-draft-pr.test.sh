#!/bin/bash
# tests/enforce-draft-pr.test.sh — regression suite for enforce-draft-pr.sh
#
# Feeds JSON on stdin to the hook and asserts whether a "deny" envelope is
# emitted. No git repo setup is needed — the hook never touches git.
# Exits non-zero on failure.

set -uo pipefail

HOOK_SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/enforce-draft-pr.sh"
FAILURES=0

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
run() {
  local cmd="$1"
  local extra_env="${2:-}"
  local json _tmp output
  json=$(jq -n --arg c "$cmd" '{"tool_name":"Bash","tool_input":{"command":$c}}')
  _tmp=$(mktemp)
  printf '%s' "$json" > "$_tmp"
  # shellcheck disable=SC2086
  output=$(env $extra_env bash "$HOOK_SCRIPT" < "$_tmp" 2>/dev/null)
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
# DENY cases
# ---------------------------------------------------------------------------

check "gh pr create --title x --body y → deny" deny \
  "$(run "gh pr create --title x --body y")"

check "gh pr create -t x -b y → deny" deny \
  "$(run "gh pr create -t x -b y")"

check "gh --repo owner/name pr create --title x → deny" deny \
  "$(run "gh --repo owner/name pr create --title x")"

check "gh pr ready 123 → deny" deny \
  "$(run "gh pr ready 123")"

check "gh pr ready → deny" deny \
  "$(run "gh pr ready")"

check "gh pr create --draft --title x && gh pr ready 5 → deny" deny \
  "$(run "gh pr create --draft --title x && gh pr ready 5")"

check "az repos pr create --repository r --source-branch b --target-branch main → deny" deny \
  "$(run "az repos pr create --repository r --source-branch b --target-branch main")"

check "gh pr create --draft=false --title x → deny" deny \
  "$(run "gh pr create --draft=false --title x")"

check "echo hi; gh pr create --title x → deny" deny \
  "$(run "echo hi; gh pr create --title x")"

# ---------------------------------------------------------------------------
# ALLOW cases
# ---------------------------------------------------------------------------

check "gh pr create --draft --title x --body y → allow" allow \
  "$(run "gh pr create --draft --title x --body y")"

check "gh pr create -d -t x → allow" allow \
  "$(run "gh pr create -d -t x")"

check "gh pr create --draft=true --title x → allow" allow \
  "$(run "gh pr create --draft=true --title x")"

check "az repos pr create --draft true --repository r --source-branch b --target-branch main → allow" allow \
  "$(run "az repos pr create --draft true --repository r --source-branch b --target-branch main")"

check "gh pr list → allow" allow \
  "$(run "gh pr list")"

check "gh pr view 123 → allow" allow \
  "$(run "gh pr view 123")"

check "git push origin feature → allow" allow \
  "$(run "git push origin feature")"

check "echo 'gh pr ready' (quoted, not an invocation) → allow" allow \
  "$(run "echo 'gh pr ready'")"

check "gh pr create --draft --title x && gh pr view 5 → allow" allow \
  "$(run "gh pr create --draft --title x && gh pr view 5")"

# ---------------------------------------------------------------------------
# Bypass env var
# ---------------------------------------------------------------------------

check "CLAUDE_BYPASS_DRAFT_PR=1 gh pr create --title x → allow" allow \
  "$(run "gh pr create --title x" "CLAUDE_BYPASS_DRAFT_PR=1")"

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
