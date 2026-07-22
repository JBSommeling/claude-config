#!/bin/bash
# lib/adapter-codex.sh — OpenAI Codex platform I/O adapter
#
# Sourced by common.sh when HOOK_ADAPTER=adapter-codex.sh is set, or when
# adapter.sh or adapter-claude.sh are absent and this file is present.
# All reads go through HOOK_INPUT set by hook_init.
# Provides the hook_* I/O functions for the Codex tool schema.
#
# Verified facts (from Codex hooks docs, fetched 2026-07-22):
#   - Field names tool_name, tool_input, session_id, cwd, hook_event_name
#     are IDENTICAL to Claude Code.
#   - The shell tool is named "Bash", with the command in tool_input.command —
#     identical to Claude Code.
#   - File edits go through a tool reported as "apply_patch". The "Edit" and
#     "Write" names exist only as matcher aliases and never appear in tool_name.
#   - There is NO tool_input.file_path. For apply_patch, tool_input.command
#     holds raw patch text.
#   - MultiEdit and NotebookEdit do not exist on Codex.
#
# UNVERIFIED (present in Codex generated schema and source, but NOT listed on
# the documented release-behaviour page, which warns schema fields may be
# absent from a shipped release):
#   - agent_id / agent_type

# hook_tool_name — echo the current tool name, defaulting to "apply_patch"
# when absent. The "apply_patch" fallback is the Codex analogue of Claude's
# "Edit" fallback: a missing tool name should fall through to the edit path,
# not the allow path.
hook_tool_name() {
  hook_json '.tool_name // "apply_patch"'
}

# hook_cmd — echo the tool's command string, or empty if absent.
# For apply_patch, this contains raw patch text.
# For Bash, this contains the shell command.
hook_cmd() {
  hook_json '.tool_input.command // empty'
}

# hook_edit_path — parse the target file path from the patch text in
# tool_input.command. There is no tool_input.file_path on Codex.
#
# Supported formats (checked in order):
#   1. OpenAI apply_patch envelope: "*** Update File: <path>",
#      "*** Add File: <path>", "*** Delete File: <path>"
#   2. Unified diff fallback: "+++ b/<path>" or "+++ <path>"
#
# Returns the FIRST path found, with a leading "a/" or "b/" stripped.
# Echoes empty if no path is found.
# Uses grep/sed; POSIX-compatible, works with macOS BSD tools.
hook_edit_path() {
  local cmd
  cmd=$(hook_json '.tool_input.command // empty')
  [ -z "$cmd" ] && return 0

  # Try apply_patch envelope lines first
  local path
  path=$(printf '%s' "$cmd" \
    | grep -m1 -E '^\*\*\* (Update File|Add File|Delete File): .+' \
    | sed -E 's/^\*\*\* (Update File|Add File|Delete File): //')
  if [ -n "$path" ]; then
    echo "$path"
    return 0
  fi

  # Fall back to unified diff "+++ b/<path>" or "+++ <path>"
  path=$(printf '%s' "$cmd" \
    | grep -m1 -E '^\+\+\+ ' \
    | sed -E 's|^\+\+\+ (b/)?||')
  if [ -n "$path" ]; then
    echo "$path"
    return 0
  fi

  return 0
}

# hook_is_edit_tool <name> — succeed if name is a file-mutating tool.
# "apply_patch" is the canonical Codex file-edit tool.
# "Edit" and "Write" are accepted defensively in case a future release
# reports an alias.
hook_is_edit_tool() {
  case "$1" in
    apply_patch|Edit|Write) return 0 ;;
    *) return 1 ;;
  esac
}

# hook_is_shell_tool <name> — succeed if name is the shell execution tool.
hook_is_shell_tool() {
  [ "$1" = "Bash" ]
}

# hook_is_subagent — succeed if the invocation is from a worker/subagent
# rather than the root session.
#
# Behaviour:
#   1. Read .agent_id and .agent_type (UNVERIFIED fields — see header).
#      If EITHER is non-empty, return success (it is a subagent).
#   2. If BOTH are absent: check env var CODEX_ENFORCE_DELEGATION.
#      If it equals "1", return failure (treat as root — strict mode for
#      users who have verified their release populates neither field).
#      Otherwise return SUCCESS (treat as subagent — permissive default).
#
# The default is PERMISSIVE. Rationale (see also docs/adr/0003):
#   Codex cannot currently distinguish root from worker at PreToolUse when
#   neither agent_id nor agent_type is present in the payload. Defaulting
#   to strict would deny every edit and make Codex completely unusable.
#   Delegation enforcement on Codex is therefore detective, not preventive.
#   This function is the single flip point: once a worker-unique identifier
#   is confirmed to appear in production payloads, set CODEX_ENFORCE_DELEGATION=1
#   and the hook will switch to strict mode automatically.
hook_is_subagent() {
  local agent_id agent_type
  agent_id=$(hook_json '.agent_id // empty')
  agent_type=$(hook_json '.agent_type // empty')

  # If either field is present, we can positively identify a subagent.
  if [ -n "$agent_id" ] || [ -n "$agent_type" ]; then
    return 0
  fi

  # Neither field is present. Check strict mode opt-in.
  if [ "${CODEX_ENFORCE_DELEGATION:-0}" = "1" ]; then
    return 1  # strict mode: treat as root, deny edits
  fi

  return 0  # permissive default: treat as subagent, allow edits
}
