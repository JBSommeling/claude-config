#!/bin/bash
# ledger-report.sh — Stop hook that reports the session's delegation ledger.
#
# Reads the session's JSONL ledger, counts delegated vs undelegated edits,
# and emits a human-readable summary on stdout.
#
# If all edits were delegated (or there were none), prints a clean summary.
# If any edits occurred outside an active delegation window, prints a warning
# block listing each one's timestamp and path.
#
# NOTE: A missed SubagentStop event leaves the depth counter elevated, causing
# subsequent edits to be recorded as delegated when they were not — a silent
# miss (under-reporting), NOT a false positive. If the depth counter is non-zero
# at session end, a prominent warning is printed to make the silent miss visible.
#
# The .depth state file is removed at the end. The .jsonl ledger is kept for
# inspection.
#
# This hook is OBSERVATIONAL ONLY. Always exits 0.
#
# Bypass: set CODEX_LEDGER_DISABLE=1 to disable for a single session.

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$HOOK_DIR/lib/common.sh"

hook_init

hook_bypass CODEX_LEDGER_DISABLE && exit 0

(
  session_id=$(hook_session_id)
  session_id="${session_id:-unknown-session}"
  # Sanitize: replace any character outside A-Za-z0-9_- with _ to prevent
  # path traversal (e.g. a session_id containing "../" would escape the dir).
  session_id=$(printf '%s' "$session_id" | sed 's/[^A-Za-z0-9_-]/_/g')

  ledger_dir="${TMPDIR:-/tmp}/codex-delegation-ledger"
  ledger_file="$ledger_dir/${session_id}.jsonl"
  depth_file="$ledger_dir/${session_id}.depth"

  # Read depth before removing the state file, so we can warn if it is non-zero.
  depth_at_end=0
  if [ -f "$depth_file" ]; then
    raw=$(cat "$depth_file" 2>/dev/null || echo 0)
    [[ "$raw" =~ ^[0-9]+$ ]] && depth_at_end="$raw"
  fi

  # Clean up depth state file regardless of whether the ledger exists.
  rm -f "$depth_file"

  if [ ! -f "$ledger_file" ]; then
    echo "Delegation ledger: no events recorded for session ${session_id}."
    exit 0
  fi

  # Count total edits and undelegated edits using jq.
  total_edits=$(jq -r 'select(.event=="edit")' "$ledger_file" 2>/dev/null | jq -s 'length' 2>/dev/null || echo 0)
  undelegated_count=$(jq -r 'select(.event=="edit" and .delegated==false)' "$ledger_file" 2>/dev/null | jq -s 'length' 2>/dev/null || echo 0)

  # Warn if the depth counter is non-zero at session end: a SubagentStop was
  # missed, so edits inside the unclosed window were recorded as delegated when
  # they may not have been — a silent miss (under-reporting).
  if [ "$depth_at_end" -gt 0 ]; then
    echo "Delegation ledger WARNING: ${depth_at_end} delegation window(s) left open at session end."
    echo "A SubagentStop event was missed. Edits recorded as delegated during"
    echo "unclosed window(s) may actually be undelegated — under-reporting possible."
    echo ""
  fi

  if [ "$undelegated_count" -eq 0 ]; then
    echo "Delegation ledger: ${total_edits} edit(s), all delegated."
    exit 0
  fi

  echo "Delegation ledger WARNING: ${undelegated_count} undelegated edit(s) detected."
  echo "These edits occurred while no delegation was active, which may indicate"
  echo "the orchestrator edited directly without spawning a subagent."
  echo "CAVEAT: a missed SubagentStop event leaves depth elevated, causing edits"
  echo "inside that window to appear delegated (silent miss, not false positive)."
  echo ""
  echo "Undelegated edits:"

  jq -r 'select(.event=="edit" and .delegated==false) | "  \(.timestamp)  \(.path)"' \
    "$ledger_file" 2>/dev/null

) 2>/dev/null

exit 0
