#!/usr/bin/env bash
# tests/test-ledger.sh — integration tests for the delegation ledger hooks.
#
# Unlike the fixture-based tests in run.sh, the ledger is stateful: events
# accumulate across multiple hook invocations in a single session. These tests
# exercise multi-step sequences that cannot be captured in a single payload.
#
# Scenarios:
#   A — edit with no prior spawn  → report flags 1 undelegated edit
#   B — spawn, then edit          → report shows all delegated, flags nothing
#   C — spawn, edit, close, edit  → report flags 1 undelegated (second edit)
#   D — malformed payload         → exits 0, emits no deny envelope
#
# Usage: bash tests/test-ledger.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LEDGER_RECORD="$REPO_ROOT/.agents/hooks/ledger-record.sh"
LEDGER_CLOSE="$REPO_ROOT/.agents/hooks/ledger-close.sh"
LEDGER_REPORT="$REPO_ROOT/.agents/hooks/ledger-report.sh"

# Isolated TMPDIR so tests never touch real ledger state.
TEST_TMPDIR="$(mktemp -d)"
export TMPDIR="$TEST_TMPDIR"

# Use Codex adapter for all scenarios (ledger is a Codex-specific feature).
export HOOK_ADAPTER="adapter-codex.sh"

pass=0
fail=0

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

run_hook() {
  local script="$1"
  local payload="$2"
  printf '%s' "$payload" | bash "$script" 2>/dev/null
}

assert_contains() {
  local label="$1"
  local output="$2"
  local pattern="$3"
  if echo "$output" | grep -q "$pattern"; then
    echo "  ok: $label"
    return 0
  else
    echo "  FAIL: $label"
    echo "        expected pattern: $pattern"
    echo "        actual output:    $output"
    return 1
  fi
}

assert_not_contains() {
  local label="$1"
  local output="$2"
  local pattern="$3"
  if ! echo "$output" | grep -q "$pattern"; then
    echo "  ok: $label"
    return 0
  else
    echo "  FAIL: $label"
    echo "        unexpected pattern: $pattern"
    echo "        actual output:      $output"
    return 1
  fi
}

clean_session() {
  local session_id="$1"
  local ledger_dir="${TMPDIR}/codex-delegation-ledger"
  rm -f "$ledger_dir/${session_id}.jsonl" "$ledger_dir/${session_id}.depth"
}

# ---------------------------------------------------------------------------
# Scenario A — edit with no prior spawn → report flags 1 undelegated edit
# ---------------------------------------------------------------------------
echo "Scenario A: edit with no spawn"
SID="test-session-a"
clean_session "$SID"

scenario_ok=true

EDIT_PAYLOAD="{\"tool_name\":\"apply_patch\",\"session_id\":\"${SID}\",\"tool_input\":{\"command\":\"*** Update File: foo.py\n--- foo.py\n+++ foo.py\n@@ -1 +1 @@\n-old\n+new\"}}"
run_hook "$LEDGER_RECORD" "$EDIT_PAYLOAD" > /dev/null

REPORT_PAYLOAD="{\"session_id\":\"${SID}\"}"
report_out=$(run_hook "$LEDGER_REPORT" "$REPORT_PAYLOAD")

assert_contains "A: report mentions undelegated" "$report_out" "undelegated" || scenario_ok=false
assert_contains "A: report mentions foo.py"      "$report_out" "foo.py"      || scenario_ok=false

if $scenario_ok; then
  echo "PASS Scenario A"
  pass=$((pass + 1))
else
  echo "FAIL Scenario A"
  fail=$((fail + 1))
fi

# ---------------------------------------------------------------------------
# Scenario B — spawn then edit → all delegated, no warning
# ---------------------------------------------------------------------------
echo ""
echo "Scenario B: spawn then edit"
SID="test-session-b"
clean_session "$SID"

scenario_ok=true

SPAWN_PAYLOAD="{\"tool_name\":\"spawn_agent\",\"session_id\":\"${SID}\"}"
run_hook "$LEDGER_RECORD" "$SPAWN_PAYLOAD" > /dev/null

EDIT_PAYLOAD="{\"tool_name\":\"apply_patch\",\"session_id\":\"${SID}\",\"tool_input\":{\"command\":\"*** Update File: bar.py\n--- bar.py\n+++ bar.py\n@@ -1 +1 @@\n-old\n+new\"}}"
run_hook "$LEDGER_RECORD" "$EDIT_PAYLOAD" > /dev/null

REPORT_PAYLOAD="{\"session_id\":\"${SID}\"}"
report_out=$(run_hook "$LEDGER_REPORT" "$REPORT_PAYLOAD")

assert_contains     "B: report says delegated"        "$report_out" "delegated"  || scenario_ok=false
assert_not_contains "B: report does not warn"         "$report_out" "undelegated" || scenario_ok=false

if $scenario_ok; then
  echo "PASS Scenario B"
  pass=$((pass + 1))
else
  echo "FAIL Scenario B"
  fail=$((fail + 1))
fi

# ---------------------------------------------------------------------------
# Scenario C — spawn, edit, close, then another edit → 1 undelegated
# ---------------------------------------------------------------------------
echo ""
echo "Scenario C: spawn, edit, close, edit"
SID="test-session-c"
clean_session "$SID"

scenario_ok=true

SPAWN_PAYLOAD="{\"tool_name\":\"spawn_agent\",\"session_id\":\"${SID}\"}"
run_hook "$LEDGER_RECORD" "$SPAWN_PAYLOAD" > /dev/null

EDIT1_PAYLOAD="{\"tool_name\":\"apply_patch\",\"session_id\":\"${SID}\",\"tool_input\":{\"command\":\"*** Update File: baz.py\n--- baz.py\n+++ baz.py\n@@ -1 +1 @@\n-old\n+new\"}}"
run_hook "$LEDGER_RECORD" "$EDIT1_PAYLOAD" > /dev/null

CLOSE_PAYLOAD="{\"session_id\":\"${SID}\"}"
run_hook "$LEDGER_CLOSE" "$CLOSE_PAYLOAD" > /dev/null

EDIT2_PAYLOAD="{\"tool_name\":\"apply_patch\",\"session_id\":\"${SID}\",\"tool_input\":{\"command\":\"*** Update File: qux.py\n--- qux.py\n+++ qux.py\n@@ -1 +1 @@\n-old\n+new\"}}"
run_hook "$LEDGER_RECORD" "$EDIT2_PAYLOAD" > /dev/null

REPORT_PAYLOAD="{\"session_id\":\"${SID}\"}"
report_out=$(run_hook "$LEDGER_REPORT" "$REPORT_PAYLOAD")

assert_contains "C: report warns of undelegated" "$report_out" "undelegated" || scenario_ok=false
assert_contains "C: report mentions qux.py"      "$report_out" "qux.py"      || scenario_ok=false
assert_contains "C: count is 1"                  "$report_out" "1 undelegated" || scenario_ok=false

if $scenario_ok; then
  echo "PASS Scenario C"
  pass=$((pass + 1))
else
  echo "FAIL Scenario C"
  fail=$((fail + 1))
fi

# ---------------------------------------------------------------------------
# Scenario D — malformed payload → exits 0, no deny envelope
# ---------------------------------------------------------------------------
echo ""
echo "Scenario D: malformed payload"
SID="test-session-d"
clean_session "$SID"

scenario_ok=true

MALFORMED='{not: valid json at all'
ledger_exit=0
ledger_out=$(printf '%s' "$MALFORMED" | bash "$LEDGER_RECORD" 2>/dev/null) || ledger_exit=$?

if [ "$ledger_exit" -ne 0 ]; then
  echo "  FAIL: expected exit 0, got $ledger_exit"
  scenario_ok=false
else
  echo "  ok: exits 0 on malformed payload"
fi

if echo "$ledger_out" | grep -q '"permissionDecision"'; then
  echo "  FAIL: emitted deny envelope — must never deny"
  scenario_ok=false
else
  echo "  ok: no deny envelope emitted"
fi

if $scenario_ok; then
  echo "PASS Scenario D"
  pass=$((pass + 1))
else
  echo "FAIL Scenario D"
  fail=$((fail + 1))
fi

# ---------------------------------------------------------------------------
# Scenario E — session_id with path-traversal characters cannot escape the
# ledger directory. A malicious session_id like "../../../tmp/escape" must be
# sanitised to a safe name before use in any file path.
# ---------------------------------------------------------------------------
echo ""
echo "Scenario E: session_id path traversal"

scenario_ok=true

MALICIOUS_SID="../../../tmp/escape"

EDIT_PAYLOAD="{\"tool_name\":\"apply_patch\",\"session_id\":\"${MALICIOUS_SID}\",\"tool_input\":{\"command\":\"*** Update File: x.py\\n--- x.py\\n+++ x.py\\n@@ -1 +1 @@\\n-old\\n+new\"}}"
run_hook "$LEDGER_RECORD" "$EDIT_PAYLOAD" > /dev/null

ledger_dir="${TEST_TMPDIR}/codex-delegation-ledger"

# The escaped path would be: $ledger_dir/../../../tmp/escape.jsonl
# Resolve it to check if it exists outside the ledger dir.
escaped_resolved="${TEST_TMPDIR}/escape.jsonl"
if [ -f "$escaped_resolved" ]; then
  echo "  FAIL: path traversal succeeded — file exists at $escaped_resolved"
  scenario_ok=false
else
  echo "  ok: no path traversal (file not found outside ledger dir)"
fi

# The sanitized session_id replaces / and . with _: "______tmp_escape"
sanitized_sid=$(printf '%s' "$MALICIOUS_SID" | sed 's/[^A-Za-z0-9_-]/_/g')
sanitized_file="${ledger_dir}/${sanitized_sid}.jsonl"
if [ -f "$sanitized_file" ]; then
  echo "  ok: sanitized session_id ledger file found at expected path"
else
  echo "  FAIL: expected sanitized ledger file not found at $sanitized_file"
  scenario_ok=false
fi

if $scenario_ok; then
  echo "PASS Scenario E"
  pass=$((pass + 1))
else
  echo "FAIL Scenario E"
  fail=$((fail + 1))
fi

# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------
rm -rf "$TEST_TMPDIR"

echo ""
total=$((pass + fail))
echo "${pass}/${total} passed"

if [ "$fail" -gt 0 ]; then
  exit 1
fi
exit 0
