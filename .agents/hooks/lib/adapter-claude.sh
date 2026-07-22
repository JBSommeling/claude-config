#!/bin/bash
# lib/adapter-claude.sh — Claude Code platform I/O adapter
#
# Sourced by common.sh. All reads go through HOOK_INPUT set by hook_init.
# Provides the hook_* I/O functions for the Claude Code tool schema.

# hook_tool_name — echo the current tool name, defaulting to "Edit" when absent.
# The "Edit" fallback matches the behaviour of enforce-delegation.sh line 39.
hook_tool_name() {
  hook_json '.tool_name // "Edit"'
}

# hook_cmd — echo the Bash tool's command string, or empty if absent.
hook_cmd() {
  hook_json '.tool_input.command // empty'
}

# hook_edit_path — echo the file-editing tool's target path, or empty if absent.
hook_edit_path() {
  hook_json '.tool_input.file_path // empty'
}

# hook_is_edit_tool <name> — succeed if name is a file-mutating tool.
hook_is_edit_tool() {
  case "$1" in
    Edit|Write|MultiEdit|NotebookEdit) return 0 ;;
    *) return 1 ;;
  esac
}

# hook_is_shell_tool <name> — succeed if name is the shell execution tool.
hook_is_shell_tool() {
  [ "$1" = "Bash" ]
}

# hook_caller — echo one of: subagent, root, unknown.
#
# On Claude Code, agent_id / agent_type are reliably absent for the main
# session and present for subagents, so absence is meaningful here and
# maps to "root" rather than "unknown".
#
#   subagent  — agent_id or agent_type is non-empty
#   root      — neither field is present (main Opus session)
#   unknown   — (never emitted by this adapter)
hook_caller() {
  local agent_id agent_type
  agent_id=$(hook_json '.agent_id // empty')
  agent_type=$(hook_json '.agent_type // empty')
  if [ -n "$agent_id" ] || [ -n "$agent_type" ]; then
    echo "subagent"
  else
    echo "root"
  fi
}

# hook_is_subagent — backward-compatible wrapper; succeeds when hook_caller
# returns "subagent".
hook_is_subagent() {
  [ "$(hook_caller)" = "subagent" ]
}
