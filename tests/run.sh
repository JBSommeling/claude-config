#!/usr/bin/env bash
# tests/run.sh — dependency-free test runner for hook scripts
#
# Usage:
#   ./tests/run.sh              # run all fixtures
#   ./tests/run.sh <substring>  # run only fixtures whose name contains substring
#
# Requires: bash, jq (same dep as the hooks themselves)

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURES_DIR="$REPO_ROOT/tests/fixtures"
DELEGATION_HOOK="$REPO_ROOT/.agents/hooks/enforce-delegation.sh"
PUSH_HOOK="$REPO_ROOT/.agents/hooks/block-push.sh"
COMMIT_HOOK="$REPO_ROOT/.agents/hooks/enforce-commit-ownership.sh"

FILTER="${1:-}"

pass=0
fail=0
total=0

for json_file in "$FIXTURES_DIR"/*.json; do
  name="$(basename "$json_file" .json)"

  # Apply optional substring filter
  if [ -n "$FILTER" ] && [[ "$name" != *"$FILTER"* ]]; then
    continue
  fi

  expect_file="$FIXTURES_DIR/${name}.expect"
  if [ ! -f "$expect_file" ]; then
    echo "SKIP $name (no .expect file)"
    continue
  fi

  expected="$(cat "$expect_file" | tr -d '[:space:]')"

  # Select hook and adapter based on fixture prefix.
  # Fixtures beginning with "codex-" run against the Codex adapter by setting
  # HOOK_ADAPTER=adapter-codex.sh, which common.sh honours when choosing an adapter.
  HOOK_ADAPTER_VALUE=""
  case "$name" in
    codex-delegation-*)
      hook="$DELEGATION_HOOK"
      HOOK_ADAPTER_VALUE="adapter-codex.sh"
      ;;
    codex-push-*)
      hook="$PUSH_HOOK"
      HOOK_ADAPTER_VALUE="adapter-codex.sh"
      ;;
    codex-commit-*)
      hook="$COMMIT_HOOK"
      HOOK_ADAPTER_VALUE="adapter-codex.sh"
      ;;
    delegation-*)
      hook="$DELEGATION_HOOK"
      ;;
    push-*)
      hook="$PUSH_HOOK"
      ;;
    commit-*)
      hook="$COMMIT_HOOK"
      ;;
    *)
      echo "SKIP $name (unknown prefix, cannot map to hook)"
      continue
      ;;
  esac

  # Determine invocation: use direct exec if executable, otherwise invoke via bash.
  # The execute bit may be absent in the repo while the script is still valid bash.
  if [ -x "$hook" ]; then
    invoke="$hook"
  elif [ -f "$hook" ]; then
    invoke="bash $hook"
  else
    echo "ERROR $name (hook not found: $hook)"
    fail=$((fail + 1))
    total=$((total + 1))
    continue
  fi

  # Per-fixture Codex env override: if a <name>.codexenv sidecar file exists,
  # read CODEX_ENFORCE_DELEGATION from it. This lets individual fixtures test
  # strict mode (=1) or permissive mode (=0, the default) independently.
  # Example: codex-delegation-bash-redirect.codexenv sets CODEX_ENFORCE_DELEGATION=1
  # so the deny path is reachable, while codex-delegation-apply-patch uses the
  # default (0) to test the permissive-allow path.
  _CODEX_ENFORCE_DELEGATION=0
  codexenv_file="$FIXTURES_DIR/${name}.codexenv"
  if [ -f "$codexenv_file" ]; then
    _override=$(grep -m1 '^CODEX_ENFORCE_DELEGATION=' "$codexenv_file" 2>/dev/null | cut -d= -f2- || true)
    [ -n "$_override" ] && _CODEX_ENFORCE_DELEGATION="$_override"
  fi

  # Run the hook with bypass env vars forced off so developer's env can't skew results.
  # HOOK_ADAPTER selects the platform adapter; empty string means use the default (Claude Code).
  stdout=$(CLAUDE_BYPASS_DELEGATION=0 CLAUDE_BYPASS_PUSH_GUARD=0 CLAUDE_BYPASS_COMMIT_GUARD=0 \
    CODEX_ENFORCE_DELEGATION="$_CODEX_ENFORCE_DELEGATION" HOOK_ADAPTER="$HOOK_ADAPTER_VALUE" \
    $invoke < "$json_file" 2>/dev/null)
  exit_code=$?

  # Decision rule:
  #   deny  → stdout contains "permissionDecision": "deny" (with or without space)
  #         OR exit code is 2
  #   allow → otherwise
  if echo "$stdout" | grep -q '"permissionDecision"[[:space:]]*:[[:space:]]*"deny"' \
     || [ "$exit_code" -eq 2 ]; then
    actual="deny"
  else
    actual="allow"
  fi

  total=$((total + 1))
  if [ "$actual" = "$expected" ]; then
    echo "PASS $name"
    pass=$((pass + 1))
  else
    echo "FAIL $name (expected $expected, got $actual)"
    fail=$((fail + 1))
  fi
done

# ---------------------------------------------------------------------------
# Agent assembly tests
# ---------------------------------------------------------------------------
echo ""
echo "--- Agent assembly tests ---"
ASSEMBLY_TEST="$REPO_ROOT/tests/test-agent-assembly.sh"

if [ -f "$ASSEMBLY_TEST" ]; then
  while IFS= read -r line; do
    echo "$line"
    case "$line" in
      "PASS "*)
        pass=$((pass + 1))
        total=$((total + 1))
        ;;
      "FAIL "*)
        fail=$((fail + 1))
        total=$((total + 1))
        ;;
    esac
  done < <(bash "$ASSEMBLY_TEST" 2>/dev/null)
else
  echo "SKIP agent assembly tests (tests/test-agent-assembly.sh not found)"
fi

# ---------------------------------------------------------------------------
# Ledger integration tests
# ---------------------------------------------------------------------------
echo ""
echo "--- Ledger integration tests ---"
LEDGER_TEST="$REPO_ROOT/tests/test-ledger.sh"

if [ -f "$LEDGER_TEST" ]; then
  # Stream ledger test output line by line and fold PASS/FAIL into global counts.
  while IFS= read -r line; do
    echo "$line"
    case "$line" in
      "PASS "*)
        pass=$((pass + 1))
        total=$((total + 1))
        ;;
      "FAIL "*)
        fail=$((fail + 1))
        total=$((total + 1))
        ;;
    esac
  done < <(bash "$LEDGER_TEST" 2>/dev/null)
else
  echo "SKIP ledger tests (tests/test-ledger.sh not found)"
fi

# ---------------------------------------------------------------------------
# Install regression test (FR2)
# ---------------------------------------------------------------------------
echo ""
echo "--- Install regression test ---"
INSTALL_TEST="$REPO_ROOT/tests/test-install.sh"

if [ -f "$INSTALL_TEST" ]; then
  while IFS= read -r line; do
    echo "$line"
    case "$line" in
      "PASS "*)
        pass=$((pass + 1))
        total=$((total + 1))
        ;;
      "FAIL "*)
        fail=$((fail + 1))
        total=$((total + 1))
        ;;
    esac
  done < <(bash "$INSTALL_TEST" 2>/dev/null)
else
  echo "SKIP install test (tests/test-install.sh not found)"
fi

echo ""
echo "$pass/$total passed"

if [ "$fail" -gt 0 ]; then
  exit 1
fi
exit 0
