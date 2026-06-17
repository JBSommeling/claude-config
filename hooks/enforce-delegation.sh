#!/bin/bash
# enforce-delegation.sh
#
# PreToolUse hook that blocks file-mutating actions from the main Opus session,
# forcing delegation to the `implementer` subagent (Sonnet) per the Model
# Routing rules in CLAUDE.md.
#
# Covers two evasion vectors:
#   1. The Edit/Write/MultiEdit/NotebookEdit tools (the obvious path).
#   2. Bash commands that write files — redirections (`>`/`>>`), in-place
#      editors (`sed -i`, `perl -i`, `gawk -i inplace`), `tee`, `dd of=`,
#      heredocs into files, and inline interpreter writes (python/node/etc.).
#      This is the path agents slip to once vector 1 is denied.
#
# Subagent calls carry an `agent_type` field and pass through. Memory writes
# from the main session and redirections to temp paths are allowed. A
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

TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // "Edit"')

# Emit a deny decision with the given reason and exit.
deny() {
  jq -n --arg reason "$1" '
  {
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $reason
    }
  }'
  exit 0
}

SUFFIX="Delegate the edit to the \`implementer\` subagent (Sonnet) via the Agent tool — pass the file path and the exact change. See ~/.claude/CLAUDE.md → Model Routing. To bypass for a single session, set CLAUDE_BYPASS_DELEGATION=1."

# --- Bash vector: detect file-mutating commands ---
if [ "$TOOL_NAME" = "Bash" ]; then
  CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty')
  [ -z "$CMD" ] && exit 0

  # In-place editors and file-writing utilities (sed -i / perl -i /
  # gawk -i inplace / tee / dd of=).
  if printf '%s' "$CMD" | grep -Eq '(^|[[:space:];&|(])(sed[[:space:]]+([^|]*[[:space:]])?(-[a-zA-Z]*i|--in-place)|perl[[:space:]]+[^|]*-[a-zA-Z]*i|gawk[[:space:]]+-i[[:space:]]+inplace|tee([[:space:]]|$)|dd[[:space:]]+[^|]*of=)'; then
    deny "Blocked: this Bash command writes files via an in-place editor (sed -i / perl -i / tee / dd). $SUFFIX"
  fi

  # Inline interpreter file writes (python -c / node -e / ruby -e / perl -e
  # opening a file for writing).
  if printf '%s' "$CMD" | grep -Eq '(python3?|node|ruby|perl)[[:space:]]+-[a-zA-Z]*(c|e)' \
     && printf '%s' "$CMD" | grep -Eq "open\([^)]*['\"][wax]|writeFile|File\.write|fs\.write"; then
    deny "Blocked: this Bash command writes a file from an inline interpreter script. $SUFFIX"
  fi

  # Output redirection into a non-temporary path (also catches heredocs into
  # files). Temp paths and the standard devices are exempt.
  while IFS= read -r target; do
    [ -z "$target" ] && continue
    case "$target" in
      /dev/null|/dev/stdout|/dev/stderr) continue ;;
      /tmp/*|/var/tmp/*|/private/tmp/*|/var/folders/*) continue ;;
      *) deny "Blocked: this Bash command redirects output into a file ($target). $SUFFIX" ;;
    esac
  done < <(printf '%s' "$CMD" | grep -oE '>>?[[:space:]]*[^[:space:]<>&|;)]+' | sed -E 's/^>>?[[:space:]]*//')

  exit 0
fi

# --- File-editing tools: Edit / Write / MultiEdit / NotebookEdit ---
# Memory writes from the main session are part of the auto-memory system
# and must be allowed. Path shape: ~/.claude/projects/*/memory/*
FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty')
case "$FILE_PATH" in
  */.claude/projects/*/memory/*) exit 0 ;;
esac

deny "Direct $TOOL_NAME from the main Opus session is blocked. Delegate to the \`implementer\` subagent (Sonnet) via the Agent tool — pass the file path ($FILE_PATH) and the exact change to make. See ~/.claude/CLAUDE.md → Model Routing → Sonnet subagents. To bypass for a single session, set CLAUDE_BYPASS_DELEGATION=1."
