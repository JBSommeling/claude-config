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
#     identical to Claude Code. "bash" (lowercase) and "shell" are also accepted
#     defensively in hook_is_shell_tool in case a future release changes casing.
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
#
# WARNING — CODEX_ENFORCE_DELEGATION=1 footgun:
#   Setting this flag makes hook_caller return "root" when agent_id/agent_type
#   are both absent, turning the delegation guard into a deny for every single
#   edit — including from subagents, if they also lack those fields (the likely
#   case, since the entire reason the tri-state exists is that the field is
#   absent for ALL callers). Do NOT enable unless you have confirmed that a real
#   subagent payload on your Codex release actually contains agent_id or
#   agent_type. Enabling it blindly makes the harness unusable.

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
#   1. OpenAI apply_patch rename:  "*** Move to: <path>"  (destination wins)
#   2. OpenAI apply_patch envelope: "*** Update File: <path>",
#      "*** Add File: <path>", "*** Delete File: <path>"
#   3. Unified diff fallback: "+++ b/<path>", "+++ a/<path>", or "+++ <path>"
#      If "+++ /dev/null" (deletion hunk), fall back to the "---" line.
#
# Returns the FIRST path found, with a leading "a/" or "b/" stripped.
# Trailing whitespace (including CR for CRLF safety) is trimmed.
# Tab-separated diff timestamps are stripped from unified-diff paths.
# Leading whitespace before "***" is tolerated (some Codex output indents).
# Echoes empty if no path is found.
# Uses grep/sed/cut; POSIX-compatible, works with macOS BSD tools.
hook_edit_path() {
  local cmd
  cmd=$(hook_json '.tool_input.command // empty')
  [ -z "$cmd" ] && return 0

  local path

  # "*** Move to: <path>" takes priority — the rename destination is where
  # content lands, not the source. Allow leading whitespace.
  path=$(printf '%s' "$cmd" \
    | grep -m1 -E '^[[:space:]]*\*\*\* Move to: .+' \
    | sed -E 's/^[[:space:]]*\*\*\* Move to: //' \
    | sed 's/[[:space:]]*$//')
  if [ -n "$path" ]; then
    echo "$path"
    return 0
  fi

  # apply_patch envelope: Update File / Add File / Delete File.
  # Allow leading whitespace; trim trailing whitespace and CRLF.
  path=$(printf '%s' "$cmd" \
    | grep -m1 -E '^[[:space:]]*\*\*\* (Update File|Add File|Delete File): .+' \
    | sed -E 's/^[[:space:]]*\*\*\* (Update File|Add File|Delete File): //' \
    | sed 's/[[:space:]]*$//')
  if [ -n "$path" ]; then
    echo "$path"
    return 0
  fi

  # Unified diff: "+++ b/<path>", "+++ a/<path>", or "+++ <path>".
  # Strip both "a/" and "b/" prefixes; cut at first tab to remove timestamps.
  path=$(printf '%s' "$cmd" \
    | grep -m1 -E '^\+\+\+ ' \
    | sed -E 's#^\+\+\+ (a/|b/)?##' \
    | cut -f1)
  if [ -n "$path" ] && [ "$path" != "/dev/null" ]; then
    echo "$path"
    return 0
  fi

  # "+++ /dev/null" signals a deletion hunk; the real path is on the "---" line.
  # Also strip "a/" or "b/" prefix there; cut at first tab for timestamps.
  path=$(printf '%s' "$cmd" \
    | grep -m1 -E '^--- ' \
    | sed -E 's#^--- (a/|b/)?##' \
    | cut -f1)
  if [ -n "$path" ] && [ "$path" != "/dev/null" ]; then
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
#   1. OpenAI apply_patch envelope: all "*** Update/Add/Delete File: <path>" lines,
#      with "*** Move to: <path>" replacing the preceding source path for renames.
#   2. Unified diff fallback: all "+++ b/<path>", "+++ a/<path>", or "+++ <path>"
#      lines; "+++ /dev/null" falls back to the preceding "---" path.
#
# Leading whitespace before "***" is tolerated.
# Trailing whitespace (including CR) and tab-separated timestamps are stripped.
# Both "a/" and "b/" leading prefixes are stripped.
# Echoes empty if no paths are found.
hook_edit_paths() {
  local cmd
  cmd=$(hook_json '.tool_input.command // empty')
  [ -z "$cmd" ] && return 0

  # Collect apply_patch envelope lines (all, not just first).
  # "*** Move to: <dst>" renames the preceding file: BOTH the source and the
  # destination are reported so a move into a memory path cannot exempt the
  # non-memory source file (C4 fix).
  local envelope_paths diff_paths
  envelope_paths=$(printf '%s' "$cmd" \
    | awk '
      /^[[:space:]]*\*\*\* (Update File|Add File|Delete File):/ {
        if (have_pending) print pending
        path = $0
        sub(/^[[:space:]]*\*\*\* (Update File|Add File|Delete File): /, "", path)
        sub(/[[:space:]]*$/, "", path)
        pending = path
        have_pending = 1
        next
      }
      /^[[:space:]]*\*\*\* Move to:/ {
        path = $0
        sub(/^[[:space:]]*\*\*\* Move to: /, "", path)
        sub(/[[:space:]]*$/, "", path)
        if (have_pending) print pending
        print path
        have_pending = 0
        next
      }
      END { if (have_pending) print pending }
    ')

  # Also scan unified-diff blocks.  A patch may contain BOTH envelope headers
  # and unified-diff hunks (adversarial or mixed-format payloads), so we always
  # check both sections and return the union rather than short-circuiting on
  # envelope paths.
  # Strip "a/" or "b/" prefix; cut at first tab to remove diff timestamps.
  # If "+++ /dev/null" (deletion), use the path from the preceding "---" line.
  diff_paths=$(printf '%s' "$cmd" \
    | awk '
      /^--- / {
        path = $0
        sub(/^--- a\//, "", path); sub(/^--- b\//, "", path); sub(/^--- /, "", path)
        sub(/\t.*$/, "", path)
        prev_minus = path
      }
      /^\+\+\+ / {
        path = $0
        sub(/^\+\+\+ a\//, "", path); sub(/^\+\+\+ b\//, "", path); sub(/^\+\+\+ /, "", path)
        sub(/\t.*$/, "", path)
        if (path == "/dev/null") {
          if (prev_minus != "/dev/null" && prev_minus != "") print prev_minus
        } else {
          print path
        }
        prev_minus = ""
      }
    ')

  # Return the union of both sections.
  if [ -n "$envelope_paths" ] || [ -n "$diff_paths" ]; then
    [ -n "$envelope_paths" ] && echo "$envelope_paths"
    [ -n "$diff_paths" ] && echo "$diff_paths"
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
# Accepts "Bash" (documented name), "bash" (lowercase variant), and "shell"
# (alternative name used in some Codex releases) so the push and commit guards
# do not fail open silently if the tool name casing changes.
hook_is_shell_tool() {
  case "$1" in
    Bash|bash|shell) return 0 ;;
    *) return 1 ;;
  esac
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
