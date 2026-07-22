#!/usr/bin/env bash
# tests/test-codex-adapter.sh — unit tests for adapter-codex.sh hook_edit_path
# and hook_edit_paths path-parsing logic.
#
# These tests set HOOK_INPUT directly and call the parsing functions from the
# sourced adapter, avoiding the need to run the full hook pipeline.
#
# Usage: bash tests/test-codex-adapter.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

pass=0
fail=0

# ---------------------------------------------------------------------------
# Load the Codex adapter so hook_edit_path / hook_edit_paths are available.
# Set HOOK_ADAPTER before sourcing common.sh so it picks up the Codex adapter.
# ---------------------------------------------------------------------------
export HOOK_ADAPTER="adapter-codex.sh"
# HOOK_INPUT is read directly by hook_json; no need to call hook_init.
HOOK_INPUT=""

# shellcheck source=../.agents/hooks/lib/common.sh
source "$REPO_ROOT/.agents/hooks/lib/common.sh"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# make_patch_payload CMD — emit a JSON payload with tool_input.command = CMD.
# Uses jq to ensure correct JSON escaping of special characters.
make_patch_payload() {
  jq -n --arg cmd "$1" '{"tool_name":"apply_patch","tool_input":{"command":$cmd}}'
}

check_edit_path() {
  local label="$1"
  local cmd="$2"
  local expected="$3"

  HOOK_INPUT=$(make_patch_payload "$cmd")
  local actual
  actual=$(hook_edit_path)

  if [ "$actual" = "$expected" ]; then
    echo "PASS $label"
    pass=$((pass + 1))
  else
    echo "FAIL $label"
    echo "  expected: '$expected'"
    echo "  actual:   '$actual'"
    fail=$((fail + 1))
  fi
}

check_edit_paths() {
  local label="$1"
  local cmd="$2"
  local expected="$3"   # newline-separated expected paths

  HOOK_INPUT=$(make_patch_payload "$cmd")
  local actual
  actual=$(hook_edit_paths)

  if [ "$actual" = "$expected" ]; then
    echo "PASS $label"
    pass=$((pass + 1))
  else
    echo "FAIL $label"
    echo "  expected: $(printf '%s' "$expected" | head -5)"
    echo "  actual:   $(printf '%s' "$actual"   | head -5)"
    fail=$((fail + 1))
  fi
}

# ---------------------------------------------------------------------------
# hook_edit_path tests (single-path)
# ---------------------------------------------------------------------------
echo "--- hook_edit_path ---"

# Table row 1: trailing whitespace trimmed (including CRLF)
check_edit_path \
  "trailing-whitespace" \
  "*** Update File: src/a.py   " \
  "src/a.py"

# Table row 2: leading whitespace before *** tolerated
check_edit_path \
  "leading-whitespace" \
  "  *** Update File: src/a.py" \
  "src/a.py"

# Table row 3: unified-diff timestamp (tab-separated) stripped
# Use ANSI-C quoting ($'...') so \t becomes a literal tab without calling printf
# (macOS bash printf rejects format strings starting with --- as invalid options).
check_edit_path \
  "diff-timestamp-stripped" \
  $'+++ b/x.py\t2026-01-02' \
  "x.py"

# Table row 4: +++ /dev/null falls back to --- path (deletion hunk)
check_edit_path \
  "devnull-fallback" \
  $'--- a/del.py\t2026-01-01\n+++ /dev/null\t2026-01-02' \
  "del.py"

# Move to: reports destination, not source
check_edit_path \
  "move-to-destination" \
  "$(printf '*** Update File: old.py\n*** Move to: new.py')" \
  "new.py"

# a/ prefix stripped (not just b/)
check_edit_path \
  "a-prefix-stripped" \
  "+++ a/foo.py" \
  "foo.py"

# ---------------------------------------------------------------------------
# hook_edit_paths tests (multi-path)
# ---------------------------------------------------------------------------
echo ""
echo "--- hook_edit_paths ---"

# Multiple envelope lines
# Use ANSI-C quoting ($'...') for literal newlines (avoids printf --- ambiguity)
check_edit_paths \
  "multi-envelope" \
  $'*** Update File: a.py\n*** Update File: b.py' \
  $'a.py\nb.py'

# Move to: reports BOTH the source and the destination so a move into a
# memory path cannot exempt the non-memory source file (N1 fix).
check_edit_paths \
  "multi-with-move" \
  $'*** Update File: a.py\n*** Update File: b.py\n*** Move to: c.py' \
  $'a.py\nb.py\nc.py'

# Unified diff: +++ /dev/null falls back to --- path
check_edit_paths \
  "unified-devnull-fallback" \
  $'--- a/del.py\n+++ /dev/null\n--- a/keep.py\n+++ b/keep.py' \
  $'del.py\nkeep.py'

# Unified diff: both a/ and b/ prefixes stripped
check_edit_paths \
  "unified-ab-prefix" \
  $'--- a/foo.py\n+++ b/foo.py' \
  "foo.py"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
total=$((pass + fail))
echo "${pass}/${total} passed"

[ "$fail" -eq 0 ] && exit 0 || exit 1
