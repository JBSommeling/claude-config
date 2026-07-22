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

# hook_edit_paths — echo all target file paths from the patch, one per line.
# Unlike hook_edit_path (which returns only the first match), this returns
# every path found in the patch so multi-file patches can be fully inspected.
#
# Supported formats (checked in order):
#   1. OpenAI apply_patch envelope: all "*** Update/Add/Delete File: <path>" lines
#   2. Unified diff fallback: all "+++ b/<path>" or "+++ <path>" lines
#
# Echoes empty if no paths are found.
hook_edit_paths() {
  local cmd
  cmd=$(hook_json '.tool_input.command // empty')
  [ -z "$cmd" ] && return 0

  # Try apply_patch envelope lines first (all, not just first)
  local paths
  paths=$(printf '%s' "$cmd" \
    | grep -E '^\*\*\* (Update File|Add File|Delete File): .+' \
    | sed -E 's/^\*\*\* (Update File|Add File|Delete File): //')
  if [ -n "$paths" ]; then
    echo "$paths"
    return 0
  fi

  # Fall back to unified diff "+++ b/<path>" or "+++ <path>"
  printf '%s' "$cmd" \
    | grep -E '^\+\+\+ ' \
    | sed -E 's|^\+\+\+ (b/)?||'
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

# hook_caller — echo one of: subagent, root, unknown.
#
# On Codex, agent_id / agent_type are UNVERIFIED (see header). Their absence
# does not reliably indicate the root session, so "unknown" is returned instead
# of "root" when neither field is present.
#
#   subagent  — agent_id or agent_type is non-empty (auto-activates when
#               Codex exposes a worker-unique identifier in production)
#   root      — neither field present AND CODEX_ENFORCE_DELEGATION=1 (strict
#               mode for users who have verified their release populates them)
#   unknown   — neither field present and strict mode is off (default); guards
#               treat this as permissive to avoid blocking the orchestrator
#               (see ADR 0003)
hook_caller() {
  local agent_id agent_type
  agent_id=$(hook_json '.agent_id // empty')
  agent_type=$(hook_json '.agent_type // empty')

  if [ -n "$agent_id" ] || [ -n "$agent_type" ]; then
    echo "subagent"
    return 0
  fi

  if [ "${CODEX_ENFORCE_DELEGATION:-0}" = "1" ]; then
    echo "root"
  else
    echo "unknown"
  fi
}

# hook_is_subagent — backward-compatible wrapper; succeeds when hook_caller
# returns "subagent".
hook_is_subagent() {
  [ "$(hook_caller)" = "subagent" ]
}

# hook_session_id — echo the session id from the payload, or empty if absent.
# The field name is identical to Claude Code (verified: session_id).
hook_session_id() {
  hook_json '.session_id // empty'
}
