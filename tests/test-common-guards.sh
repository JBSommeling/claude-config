#!/usr/bin/env bash
# tests/test-common-guards.sh — security checks in lib/common.sh
#
# Tests the three HOOK_ADAPTER deny paths, the jq-missing deny, and the
# required-helper completeness assertion.  None of these paths are exercisable
# via the normal fixture loop because they require specific env configurations
# or a modified lib/ directory that the fixture runner cannot provide.
#
# Each test runs as a subshell so that temp-dir cleanup is guaranteed even
# on failure.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DELEGATION_HOOK="$REPO_ROOT/.agents/hooks/enforce-delegation.sh"

# A minimal Claude-style Edit payload — enough for common.sh to initialise.
PAYLOAD='{"tool_name":"Edit","tool_input":{"file_path":"/tmp/test.txt"}}'

pass=0
fail=0

# ---------------------------------------------------------------------------
# Helper: run the delegation hook with given env, return "deny" or "allow".
# ---------------------------------------------------------------------------
_outcome() {
  local output
  output=$(printf '%s' "$PAYLOAD" | env "$@" \
    CLAUDE_BYPASS_DELEGATION=0 \
    bash "$DELEGATION_HOOK" 2>/dev/null || true)
  if printf '%s' "$output" | grep -q '"permissionDecision".*"deny"'; then
    printf 'deny'
  else
    printf 'allow'
  fi
}

# ---------------------------------------------------------------------------
# Test 1 — HOOK_ADAPTER set without HOOK_ADAPTER_ALLOW_OVERRIDE → deny
# ---------------------------------------------------------------------------
result=$(_outcome HOOK_ADAPTER=adapter-codex.sh HOOK_ADAPTER_ALLOW_OVERRIDE=0)
if [ "$result" = "deny" ]; then
  echo "PASS hook-adapter-missing-allow-override"
  pass=$((pass + 1))
else
  echo "FAIL hook-adapter-missing-allow-override (expected deny, got allow)"
  fail=$((fail + 1))
fi

# ---------------------------------------------------------------------------
# Test 2 — HOOK_ADAPTER value containing '/' → deny
# ---------------------------------------------------------------------------
result=$(_outcome HOOK_ADAPTER=../evil.sh HOOK_ADAPTER_ALLOW_OVERRIDE=1)
if [ "$result" = "deny" ]; then
  echo "PASS hook-adapter-slash-in-value"
  pass=$((pass + 1))
else
  echo "FAIL hook-adapter-slash-in-value (expected deny, got allow)"
  fail=$((fail + 1))
fi

# ---------------------------------------------------------------------------
# Test 3 — HOOK_ADAPTER value containing '..' → deny
# ---------------------------------------------------------------------------
result=$(_outcome HOOK_ADAPTER=adapter..sh HOOK_ADAPTER_ALLOW_OVERRIDE=1)
if [ "$result" = "deny" ]; then
  echo "PASS hook-adapter-dotdot-in-value"
  pass=$((pass + 1))
else
  echo "FAIL hook-adapter-dotdot-in-value (expected deny, got allow)"
  fail=$((fail + 1))
fi

# ---------------------------------------------------------------------------
# Test 4 — HOOK_ADAPTER value not in allowlist → deny
# ---------------------------------------------------------------------------
result=$(_outcome HOOK_ADAPTER=evil.sh HOOK_ADAPTER_ALLOW_OVERRIDE=1)
if [ "$result" = "deny" ]; then
  echo "PASS hook-adapter-not-in-allowlist"
  pass=$((pass + 1))
else
  echo "FAIL hook-adapter-not-in-allowlist (expected deny, got allow)"
  fail=$((fail + 1))
fi

# ---------------------------------------------------------------------------
# Test 5 — jq absent from PATH → deny (static envelope, no jq needed)
# ---------------------------------------------------------------------------
# Create a minimal PATH containing only dirname (needed by HOOK_DIR resolution)
# but not jq.  The guard at the top of common.sh must emit a static deny
# envelope without being able to call jq itself.
# /bin/bash is used as the explicit interpreter so the env PATH swap does not
# prevent bash from starting (the env PATH only affects PATH-based lookups
# inside the hook, not the bash binary itself which is given as an absolute path).
(
  _tmpdir=$(mktemp -d)
  trap 'rm -rf "$_tmpdir"' EXIT
  _bindir="$_tmpdir/bin"
  mkdir -p "$_bindir"
  # Symlink only dirname — enough for HOOK_DIR resolution, no jq.
  ln -s /usr/bin/dirname "$_bindir/dirname"

  result=$(printf '%s' "$PAYLOAD" | \
    env PATH="$_bindir" CLAUDE_BYPASS_DELEGATION=0 \
    /bin/bash "$DELEGATION_HOOK" 2>/dev/null || true)
  if printf '%s' "$result" | grep -q '"permissionDecision".*"deny"'; then
    echo "PASS jq-missing-deny"
    exit 0
  else
    echo "FAIL jq-missing-deny (expected deny when jq is absent from PATH, got allow)"
    exit 1
  fi
) && pass=$((pass + 1)) || { fail=$((fail + 1)); true; }

# ---------------------------------------------------------------------------
# Test 6 — adapter missing a required function → deny
# ---------------------------------------------------------------------------
# Create a temp lib/ directory with a real copy of common.sh but a stub
# adapter.sh that defines all required functions EXCEPT hook_edit_path.
# common.sh's completeness check must catch the gap and deny.
(
  _tmpdir=$(mktemp -d)
  trap 'rm -rf "$_tmpdir"' EXIT

  mkdir -p "$_tmpdir/lib"
  cp "$REPO_ROOT/.agents/hooks/lib/common.sh" "$_tmpdir/lib/common.sh"

  # Stub adapter: defines every required function except hook_edit_path.
  cat > "$_tmpdir/lib/adapter.sh" <<'ADAPTER'
#!/bin/bash
hook_tool_name()      { echo "Edit"; }
hook_cmd()            { echo ""; }
# hook_edit_path is deliberately omitted to test the completeness guard
hook_edit_paths()     { echo ""; }
hook_is_shell_tool()  { [ "$1" = "Bash" ]; }
hook_caller()         { echo "root"; }
ADAPTER

  # Minimal wrapper hook that uses _tmpdir as its HOOK_DIR.
  cat > "$_tmpdir/test-hook.sh" <<HOOKEOF
#!/bin/bash
set -euo pipefail
HOOK_DIR="$_tmpdir"
source "\$HOOK_DIR/lib/common.sh"
hook_init
exit 0
HOOKEOF

  result=$(printf '%s' "$PAYLOAD" | bash "$_tmpdir/test-hook.sh" 2>/dev/null || true)
  if printf '%s' "$result" | grep -q '"permissionDecision".*"deny"'; then
    echo "PASS adapter-missing-required-function"
    exit 0
  else
    echo "FAIL adapter-missing-required-function (expected deny when adapter is incomplete, got allow)"
    exit 1
  fi
) && pass=$((pass + 1)) || { fail=$((fail + 1)); true; }

echo ""
echo "$pass/$((pass + fail)) common-guards tests passed"
[ "$fail" -eq 0 ]
