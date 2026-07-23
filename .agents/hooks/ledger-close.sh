#!/bin/bash
# ledger-close.sh — SubagentStop hook that decrements the delegation counter.
#
# This hook is OBSERVATIONAL ONLY. It never denies and always exits 0.
# A missed SubagentStop event means the depth counter stays elevated, which
# causes subsequent edits to be recorded as delegated when they are not —
# a silent miss (under-reporting). ledger-report.sh detects a non-zero depth
# at session end and emits a prominent warning to surface this condition.
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
  mkdir -p -m 700 "$ledger_dir"

  ledger_file="$ledger_dir/${session_id}.jsonl"
  depth_file="$ledger_dir/${session_id}.depth"

  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  # Read and decrement depth, flooring at 0.
  depth=0
  if [ -f "$depth_file" ]; then
    raw=$(cat "$depth_file" 2>/dev/null || echo 0)
    [[ "$raw" =~ ^[0-9]+$ ]] || raw=0
    depth="$raw"
  fi
  if [ "$depth" -gt 0 ]; then
    depth=$(( depth - 1 ))
  fi
  echo "$depth" > "$depth_file"

  jq -n \
    --arg ts  "$ts" \
    --arg sid "$session_id" \
    --argjson dep "$depth" \
    '{"event":"subagent_stop","session_id":$sid,"depth_after":$dep,"timestamp":$ts}' \
    >> "$ledger_file"
) 2>/dev/null

exit 0
