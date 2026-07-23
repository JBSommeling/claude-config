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
xfail=0
total=0

# ---------------------------------------------------------------------------
# run_suite LABEL SCRIPT MIN_TESTS
#   Run a sub-suite script, fold its PASS/FAIL lines into global counters,
#   surface stderr, and fail if:
#     • the script exits non-zero with no PASS/FAIL output (silent crash), or
#     • it reports fewer than MIN_TESTS PASS/FAIL lines (too few tests ran).
# ---------------------------------------------------------------------------
run_suite() {
  local label="$1" script="$2" min_tests="$3"
  local _tmpout _suite_exit _suite_count _line
  _tmpout=$(mktemp)
  bash "$script" > "$_tmpout" 2>&1
  _suite_exit=$?
  _suite_count=0
  while IFS= read -r _line; do
    echo "$_line"
    case "$_line" in
      "PASS "*)
        pass=$((pass + 1))
        total=$((total + 1))
        _suite_count=$((_suite_count + 1))
        ;;
      "FAIL "*)
        fail=$((fail + 1))
        total=$((total + 1))
        _suite_count=$((_suite_count + 1))
        ;;
    esac
  done < "$_tmpout"
  rm -f "$_tmpout"
  # Crash guard: non-zero exit with no output means the suite died silently.
  if [ "$_suite_exit" -ne 0 ] && [ "$_suite_count" -eq 0 ]; then
    echo "FAIL $label (sub-suite crashed with exit $_suite_exit and no PASS/FAIL output)"
    fail=$((fail + 1))
    total=$((total + 1))
  fi
  # Minimum-count guard: too few tests means something is silently skipped.
  if [ "$_suite_count" -lt "$min_tests" ]; then
    echo "FAIL $label (expected at least $min_tests tests, got $_suite_count — possible silent skip or crash)"
    fail=$((fail + 1))
    total=$((total + 1))
  fi
}

for json_file in "$FIXTURES_DIR"/*.json; do
  name="$(basename "$json_file" .json)"

  # Apply optional substring filter
  if [ -n "$FILTER" ] && [[ "$name" != *"$FILTER"* ]]; then
    continue
  fi

  expect_file="$FIXTURES_DIR/${name}.expect"
  if [ ! -f "$expect_file" ]; then
    echo "FAIL $name (no .expect file — every fixture must have a paired .expect)"
    fail=$((fail + 1))
    total=$((total + 1))
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
  # HOOK_ADAPTER_ALLOW_OVERRIDE=1 is set whenever HOOK_ADAPTER is non-empty (C1 fix):
  # the new companion-var requirement prevents a single innocuous env var from being
  # an override channel, while still allowing the test runner's deliberate overrides.
  _HOOK_ADAPTER_ALLOW_OVERRIDE=0
  [ -n "$HOOK_ADAPTER_VALUE" ] && _HOOK_ADAPTER_ALLOW_OVERRIDE=1
  stdout=$(CLAUDE_BYPASS_DELEGATION=0 CLAUDE_BYPASS_PUSH_GUARD=0 CLAUDE_BYPASS_COMMIT_GUARD=0 \
    CODEX_ENFORCE_DELEGATION="$_CODEX_ENFORCE_DELEGATION" HOOK_ADAPTER="$HOOK_ADAPTER_VALUE" \
    HOOK_ADAPTER_ALLOW_OVERRIDE="$_HOOK_ADAPTER_ALLOW_OVERRIDE" \
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

  # Check for .xfail marker — a fixture marked xfail is a known limitation.
  # XFAIL (actual != expected, marker present): report but do not count as failure.
  # Unexpected PASS (actual == expected, marker present): FAIL loudly so the
  # limitation is noticed and the .xfail marker can be removed.
  xfail_file="$FIXTURES_DIR/${name}.xfail"
  is_xfail=false
  [ -f "$xfail_file" ] && is_xfail=true

  total=$((total + 1))
  if [ "$actual" = "$expected" ]; then
    if $is_xfail; then
      echo "FAIL $name (unexpected PASS — marked xfail; remove .xfail if the limitation is fixed)"
      fail=$((fail + 1))
    else
      echo "PASS $name"
      pass=$((pass + 1))
    fi
  else
    if $is_xfail; then
      echo "XFAIL $name (known limitation: expected $expected, got $actual)"
      xfail=$((xfail + 1))
    else
      echo "FAIL $name (expected $expected, got $actual)"
      fail=$((fail + 1))
    fi
  fi
done

# ---------------------------------------------------------------------------
# Common-guards unit tests (HOOK_ADAPTER allowlist, jq-missing fail-closed)
# ---------------------------------------------------------------------------
echo ""
echo "--- Common-guards tests ---"
COMMON_GUARDS_TEST="$REPO_ROOT/tests/test-common-guards.sh"

if [ -f "$COMMON_GUARDS_TEST" ]; then
  run_suite "common-guards" "$COMMON_GUARDS_TEST" 6
else
  echo "SKIP common-guards tests (tests/test-common-guards.sh not found)"
fi

# ---------------------------------------------------------------------------
# Platform-neutrality tests
# ---------------------------------------------------------------------------
echo ""
echo "--- Platform-neutrality tests ---"
NEUTRALITY_TEST="$REPO_ROOT/tests/test-platform-neutrality.sh"

if [ -f "$NEUTRALITY_TEST" ]; then
  run_suite "platform-neutrality" "$NEUTRALITY_TEST" 12
else
  echo "SKIP platform-neutrality tests (tests/test-platform-neutrality.sh not found)"
fi

# ---------------------------------------------------------------------------
# Agent assembly tests
# ---------------------------------------------------------------------------
echo ""
echo "--- Agent assembly tests ---"
ASSEMBLY_TEST="$REPO_ROOT/tests/test-agent-assembly.sh"

if [ -f "$ASSEMBLY_TEST" ]; then
  run_suite "agent-assembly" "$ASSEMBLY_TEST" 10
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
  run_suite "ledger" "$LEDGER_TEST" 6
else
  echo "SKIP ledger tests (tests/test-ledger.sh not found)"
fi

# ---------------------------------------------------------------------------
# Codex skills install test
# ---------------------------------------------------------------------------
echo ""
echo "--- Codex skills install test ---"
CODEX_SKILLS_TEST="$REPO_ROOT/tests/test-codex-skills.sh"

if [ -f "$CODEX_SKILLS_TEST" ]; then
  run_suite "codex-skills" "$CODEX_SKILLS_TEST" 5
else
  echo "SKIP codex-skills test (tests/test-codex-skills.sh not found)"
fi

# ---------------------------------------------------------------------------
# Codex adapter unit tests (path parsing)
# ---------------------------------------------------------------------------
echo ""
echo "--- Codex adapter unit tests ---"
ADAPTER_TEST="$REPO_ROOT/tests/test-codex-adapter.sh"

if [ -f "$ADAPTER_TEST" ]; then
  run_suite "codex-adapter" "$ADAPTER_TEST" 6
else
  echo "SKIP codex-adapter tests (tests/test-codex-adapter.sh not found)"
fi

# ---------------------------------------------------------------------------
# Codex transform tests (adjacent slash-command substitution)
# ---------------------------------------------------------------------------
echo ""
echo "--- Codex transform tests ---"
TRANSFORM_TEST="$REPO_ROOT/tests/test-codex-transform.sh"

if [ -f "$TRANSFORM_TEST" ]; then
  run_suite "codex-transform" "$TRANSFORM_TEST" 3
else
  echo "SKIP codex-transform tests (tests/test-codex-transform.sh not found)"
fi

# ---------------------------------------------------------------------------
# Push guard integration tests (H2: forged origin/HEAD, metacharacter branch)
# ---------------------------------------------------------------------------
echo ""
echo "--- Push guard integration tests ---"
PUSH_GUARD_TEST="$REPO_ROOT/tests/test-push-guard.sh"

if [ -f "$PUSH_GUARD_TEST" ]; then
  run_suite "push-guard" "$PUSH_GUARD_TEST" 4
else
  echo "SKIP push-guard tests (tests/test-push-guard.sh not found)"
fi

# ---------------------------------------------------------------------------
# Install regression test (FR2)
# ---------------------------------------------------------------------------
echo ""
echo "--- Install regression test ---"
INSTALL_TEST="$REPO_ROOT/tests/test-install.sh"

if [ -f "$INSTALL_TEST" ]; then
  run_suite "install" "$INSTALL_TEST" 15
else
  echo "SKIP install test (tests/test-install.sh not found)"
fi

# ---------------------------------------------------------------------------
# Install oracle self-check (end-to-end negative tests: proves the oracle can fail)
# ---------------------------------------------------------------------------
echo ""
echo "--- Install oracle self-check ---"
INSTALL_SELFCHECK_TEST="$REPO_ROOT/tests/test-install-selfcheck.sh"

if [ -f "$INSTALL_SELFCHECK_TEST" ]; then
  run_suite "install-selfcheck" "$INSTALL_SELFCHECK_TEST" 3
else
  echo "SKIP install-selfcheck test (tests/test-install-selfcheck.sh not found)"
fi

echo ""
if [ "$xfail" -gt 0 ]; then
  echo "$pass/$total passed ($xfail known failure(s) — XFAIL)"
else
  echo "$pass/$total passed"
fi

if [ "$fail" -gt 0 ]; then
  exit 1
fi
exit 0
