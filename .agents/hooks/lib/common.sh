#!/bin/bash
# lib/common.sh — shared harness for PreToolUse hooks
#
# Source this file at the top of every hook (after set options):
#
#   HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   source "$HOOK_DIR/lib/common.sh"
#
# After sourcing, call hook_init once to consume stdin, then use the
# hook_* helpers for all policy decisions.

# ---------------------------------------------------------------------------
# jq availability guard — every hook depends on jq for input parsing and for
# building deny envelopes.  If jq is absent, emit a static deny envelope
# (no jq needed) so the hook fails CLOSED rather than silently allowing.
# ---------------------------------------------------------------------------
if ! command -v jq >/dev/null 2>&1; then
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Hook dependency missing: jq is required but not found in PATH. Install jq to enable hook enforcement."}}\n'
  exit 0
fi

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

HOOK_INPUT=""

# ---------------------------------------------------------------------------
# Core helpers (defined before adapter loading so hook_deny is available)
# ---------------------------------------------------------------------------

# hook_init — read all of stdin once into HOOK_INPUT.
# Must be called exactly once, at the top of the hook, before any other call.
hook_init() {
  HOOK_INPUT=$(cat)
}

# hook_json <jq-filter> — run a jq filter against the stored input.
# Returns empty string on miss or parse error.
hook_json() {
  printf '%s' "$HOOK_INPUT" | jq -r "$1" 2>/dev/null || true
}

# hook_bypass <VARNAME> — succeed (return 0) if that env var equals "1".
# Safe under set -u even when the target variable is unset.
hook_bypass() {
  local varname="$1"
  local val="${!varname:-0}"
  [ "$val" = "1" ]
}

# hook_deny <reason> — emit the deny envelope on stdout and exit 0.
# Envelope is byte-identical to what the individual hooks previously emitted.
hook_deny() {
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

# hook_allow — exit 0 with no output (explicit allow).
hook_allow() {
  exit 0
}

# ---------------------------------------------------------------------------
# Adapter loading — resolved relative to this file's own directory so the
# hooks work regardless of the caller's cwd.
# ---------------------------------------------------------------------------

_HOOK_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -n "${HOOK_ADAPTER:-}" ]; then
  # Explicit adapter override — opt-in ONLY: requires HOOK_ADAPTER_ALLOW_OVERRIDE=1
  # as a companion env var so the override cannot be triggered by a single
  # innocuous variable (C1 fix).
  if [ "${HOOK_ADAPTER_ALLOW_OVERRIDE:-0}" != "1" ]; then
    hook_deny "Hook misconfiguration: HOOK_ADAPTER is set to '${HOOK_ADAPTER}' but HOOK_ADAPTER_ALLOW_OVERRIDE=1 is not set. Set both variables together to opt in to adapter override."
  fi
  # Reject any value containing '/' or '..' — only bare filenames are allowed.
  case "$HOOK_ADAPTER" in
    */*|*..*) hook_deny "Hook misconfiguration: HOOK_ADAPTER value '${HOOK_ADAPTER}' contains '/' or '..' — only bare filenames are allowed. Rejecting to prevent path traversal." ;;
  esac
  # Whitelist: accept only the two known adapter filenames.
  case "$HOOK_ADAPTER" in
    adapter-claude.sh|adapter-codex.sh) ;;
    *) hook_deny "Hook misconfiguration: HOOK_ADAPTER value '${HOOK_ADAPTER}' is not an allowed adapter name. Allowed values: adapter-claude.sh, adapter-codex.sh." ;;
  esac
  if [ ! -f "$_HOOK_LIB_DIR/$HOOK_ADAPTER" ]; then
    hook_deny "Hook misconfiguration: HOOK_ADAPTER '${HOOK_ADAPTER}' not found in ${_HOOK_LIB_DIR}."
  fi
  # shellcheck source=/dev/null
  source "$_HOOK_LIB_DIR/$HOOK_ADAPTER"
elif [ -f "$_HOOK_LIB_DIR/adapter.sh" ]; then
  # Install-time binding wins (lets admins swap platform adapters).
  # shellcheck source=/dev/null
  source "$_HOOK_LIB_DIR/adapter.sh"
elif [ -f "$_HOOK_LIB_DIR/adapter-claude.sh" ]; then
  # Default: Claude Code platform adapter shipped with the repo.
  # shellcheck source=/dev/null
  source "$_HOOK_LIB_DIR/adapter-claude.sh"
else
  # No adapter found — fail closed with a clear message.
  hook_deny "Hook misconfiguration: no platform adapter found in $_HOOK_LIB_DIR (expected adapter.sh or adapter-claude.sh). Cannot determine tool context."
fi

# ---------------------------------------------------------------------------
# Adapter completeness check — a zero-byte or partially-copied adapter may
# source cleanly but leave required helpers undefined, causing hooks to fail
# open with rc 127 rather than denying.  Assert every required function is
# present after sourcing (M1 fix).
# ---------------------------------------------------------------------------
for _fn in hook_tool_name hook_cmd hook_caller hook_edit_path hook_edit_paths hook_is_shell_tool; do
  declare -F "$_fn" >/dev/null 2>&1 || hook_deny "Hook misconfiguration: platform adapter is missing required function '${_fn}'. The adapter may be incomplete or corrupted — reinstall or check the adapter file in ${_HOOK_LIB_DIR}."
done
unset _fn
