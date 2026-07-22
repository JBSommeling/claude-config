#!/bin/bash
# ledger-record.sh — PreToolUse hook that records edit and delegation events.
#
# This hook is OBSERVATIONAL ONLY. It never denies a tool call and always
# exits 0. It is designed for the Codex platform where hook_caller returns
# "unknown" when no worker identity is present, so prevention guards fail
# open. The ledger provides after-the-fact detection instead.
#
# Ledger location: ${TMPDIR:-/tmp}/codex-delegation-ledger/<session_id>.jsonl
# Depth counter:   ${TMPDIR:-/tmp}/codex-delegation-ledger/<session_id>.depth
#
# Bypass: set CODEX_LEDGER_DISABLE=1 to disable for a single session.

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$HOOK_DIR/lib/common.sh"

hook_init

hook_bypass CODEX_LEDGER_DISABLE && exit 0

# All ledger work runs in a subshell so that any unexpected error cannot
# prevent the outer script from reaching `exit 0`. Stderr is suppressed so
# a broken ledger never produces user-visible noise.
(
  session_id=$(hook_session_id)
  session_id="${session_id:-unknown-session}"

  ledger_dir="${TMPDIR:-/tmp}/codex-delegation-ledger"
  mkdir -p "$ledger_dir"

  ledger_file="$ledger_dir/${session_id}.jsonl"
  depth_file="$ledger_dir/${session_id}.depth"

  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  tool=$(hook_tool_name)

  # Helper: read the current delegation depth (integer, defaults to 0).
  _read_depth() {
    local raw=0
    if [ -f "$depth_file" ]; then
      raw=$(cat "$depth_file" 2>/dev/null || echo 0)
      # Treat non-numeric values as 0 (fail toward false positives).
      [[ "$raw" =~ ^[0-9]+$ ]] || raw=0
    fi
    echo "$raw"
  }

  case "$tool" in
    spawn_agent|Agent)
      # Increment delegation depth and record the spawn event.
      depth=$(_read_depth)
      depth=$(( depth + 1 ))
      echo "$depth" > "$depth_file"

      jq -n \
        --arg ts       "$ts" \
        --arg tool     "$tool" \
        --arg sid      "$session_id" \
        --argjson dep  "$depth" \
        '{"event":"spawn","tool":$tool,"session_id":$sid,"depth":$dep,"timestamp":$ts}' \
        >> "$ledger_file"
      ;;
    *)
      if hook_is_edit_tool "$tool"; then
        depth=$(_read_depth)

        path=$(hook_edit_path)
        path="${path:-}"

        if [ "$depth" -eq 0 ]; then
          delegated_json="false"
        else
          delegated_json="true"
        fi

        jq -n \
          --arg ts            "$ts" \
          --arg tool          "$tool" \
          --arg sid           "$session_id" \
          --arg path          "$path" \
          --argjson delegated "$delegated_json" \
          '{"event":"edit","tool":$tool,"session_id":$sid,"delegated":$delegated,"path":$path,"timestamp":$ts}' \
          >> "$ledger_file"
      fi
      ;;
  esac
) 2>/dev/null

exit 0
