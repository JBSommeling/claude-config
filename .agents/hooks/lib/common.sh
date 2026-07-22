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

if [ -n "${HOOK_ADAPTER:-}" ] && [ -f "$_HOOK_LIB_DIR/$HOOK_ADAPTER" ]; then
  # Explicit adapter override — used by the test runner for platform-specific
  # fixture sets (e.g. codex-* fixtures set HOOK_ADAPTER=adapter-codex.sh).
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
