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

  # Select hook based on fixture prefix
  case "$name" in
    delegation-*)
      hook="$DELEGATION_HOOK"
      ;;
    push-*)
      hook="$PUSH_HOOK"
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

  # Run the hook with bypass env vars forced off so developer's env can't skew results
  stdout=$(CLAUDE_BYPASS_DELEGATION=0 CLAUDE_BYPASS_PUSH_GUARD=0 \
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

echo ""
echo "$pass/$total passed"

if [ "$fail" -gt 0 ]; then
  exit 1
fi
exit 0
