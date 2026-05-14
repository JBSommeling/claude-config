#!/bin/bash
# enforce-delegation.sh
#
# PreToolUse hook that blocks Edit/Write/MultiEdit/NotebookEdit when invoked
# from the main Opus session, forcing delegation to the `implementer` subagent
# (Sonnet) per the Model Routing rules in CLAUDE.md.
#
# Subagent calls carry an `agent_type` field in the hook JSON input — when
# present, the call is allowed through. Memory writes from the main session
# are also allowed so the auto-memory system keeps working. A
# CLAUDE_BYPASS_DELEGATION=1 env var provides a manual escape hatch.

set -euo pipefail

INPUT=$(cat)

# Manual override — set CLAUDE_BYPASS_DELEGATION=1 to disable enforcement
# for a single session when delegation overhead clearly exceeds the edit.
if [ "${CLAUDE_BYPASS_DELEGATION:-0}" = "1" ]; then
  exit 0
fi

# Subagent calls include agent_type; allow them through.
AGENT_TYPE=$(printf '%s' "$INPUT" | jq -r '.agent_type // empty')
if [ -n "$AGENT_TYPE" ]; then
  exit 0
fi

# Memory writes from the main session are part of the auto-memory system
# and must be allowed. Path shape: ~/.claude/projects/*/memory/*
FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty')
case "$FILE_PATH" in
  */.claude/projects/*/memory/*) exit 0 ;;
esac

TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // "Edit"')

jq -n --arg tool "$TOOL_NAME" --arg path "$FILE_PATH" '
{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: (
      "Direct \($tool) from the main Opus session is blocked. " +
      "Delegate to the `implementer` subagent (Sonnet) via the Agent tool — " +
      "pass the file path (\($path)) and the exact change to make. " +
      "See ~/.claude/CLAUDE.md → Model Routing → Sonnet subagents. " +
      "To bypass for a single session, set CLAUDE_BYPASS_DELEGATION=1."
    )
  }
}'
