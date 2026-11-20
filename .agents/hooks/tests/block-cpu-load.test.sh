#!/bin/bash
# tests/block-cpu-load.test.sh — table-driven regression suite for block-cpu-load.sh
#
# Cases live in block-cpu-load.cases (expect<TAB>command). Each one is fed as JSON to the
# real hook; nothing in a case is ever executed. Fixture, mode and platform checks follow.

set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_SCRIPT="$(cd "$TESTS_DIR/.." && pwd)/block-cpu-load.sh"
CASES_FILE="$TESTS_DIR/block-cpu-load.cases"
FAILURES=0
TOTAL=0

SCRATCH_DIR=$(mktemp -d)
trap 'rm -rf "$SCRATCH_DIR"' EXIT
EMPTY_DIR="$SCRATCH_DIR/empty"
FIXTURE_DIR="$SCRATCH_DIR/project"
mkdir -p "$EMPTY_DIR" "$FIXTURE_DIR/scripts" "$FIXTURE_DIR/sub"

# run_hook <command> [tool_name] [extra VAR=val env pair] [cwd] [permission_mode]
run_hook() {
  local command_text="$1" tool_name="${2:-Bash}" extra_env="${3:-}"
  local working_dir="${4:-$EMPTY_DIR}" permission_mode="${5:-}"
  local payload
  payload=$(jq -n --arg tool "$tool_name" --arg cmd "$command_text" \
    --arg cwd "$working_dir" --arg mode "$permission_mode" \
    '{tool_name:$tool, tool_input:{command:$cmd}, cwd:$cwd}
     + (if $mode != "" then {permission_mode:$mode} else {} end)')
  # shellcheck disable=SC2086
  printf '%s' "$payload" | env -u CLAUDE_BYPASS_CPU_LOAD_GUARD -u CODEX_BYPASS_CPU_LOAD_GUARD \
    -u HOOK_ADAPTER -u HOOK_ADAPTER_ALLOW_OVERRIDE ${extra_env:-HOOK_TEST_NOOP=1} \
    bash "$HOOK_SCRIPT" 2>/dev/null
}

# classify_output <hook stdout> — echo deny, ask, allow, or invalid.
classify_output() {
  local decision
  if [ -z "$1" ]; then echo allow; return; fi
  decision=$(printf '%s' "$1" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
  case "$decision" in
    deny|ask) echo "$decision" ;;
    *) echo invalid ;;
  esac
}

# check <label> <expected> <hook stdout>
check() {
  local label="$1" expected="$2" output="$3" got
  TOTAL=$((TOTAL + 1))
  got=$(classify_output "$output")
  if [ "$got" = "$expected" ]; then
    printf 'PASS: %s\n' "$label"
  else
    printf 'FAIL: %s — expected %s, got %s\n' "$label" "$expected" "$got"
    printf '      output: %s\n' "$output"
    FAILURES=$((FAILURES + 1))
  fi
}

# expect_in_dir <expected> <command> <cwd> — one fixture-backed case.
expect_in_dir() {
  check "$1 (cwd fixture): $2" "$1" "$(run_hook "$2" Bash "" "$3")"
}

# --- table cases ---
while IFS=$'\t' read -r expected command_text; do
  case "$expected" in ''|'#'*) continue ;; esac
  command_text=${command_text//\\n/$'\n'}
  command_text=${command_text//\\r/$'\r'}
  command_text=${command_text//\\t/$'\t'}
  display_text=${command_text//$'\n'/\\n}
  display_text=${display_text//$'\r'/\\r}
  display_text=${display_text//$'\t'/\\t}
  check "$expected: $display_text" "$expected" "$(run_hook "$command_text")"
done < "$CASES_FILE"

# --- fixtures ---
cat > "$FIXTURE_DIR/package.json" <<'EOF'
{
  "name": "fixture",
  "scripts": {
    "test": "jest",
    "build": "tsc",
    "dev": "vite",
    "bench": "node bench.js",
    "load": "k6 run load.js",
    "ci": "npm test && npm run build"
  }
}
EOF
cat > "$FIXTURE_DIR/composer.json" <<'EOF'
{
  "name": "fixture/app",
  "scripts": {
    "stress": "php stress.php",
    "lint": ["phpcs src", "phpstan analyse"],
    "hammer": ["php prepare.php", "wrk -t4 -c100 http://localhost"]
  }
}
EOF
printf 'test:\n\t@echo testing\n\nbuild:\n\t@echo building\n\nloadtest:\n\t@wrk -t8 -c400 http://localhost\n\nbench:\n\t@echo measuring\n' \
  > "$FIXTURE_DIR/Makefile"
printf '#!/bin/bash\necho measuring\n' > "$FIXTURE_DIR/scripts/perf-test.sh"
printf '#!/bin/bash\necho setup\n' > "$FIXTURE_DIR/scripts/setup.sh"
printf '#!/bin/bash\n# innocent name, load tool inside\nk6 run load.js\n' > "$FIXTURE_DIR/scripts/innocent.sh"
printf '#!/bin/bash\n# mentions wrk only in a comment\necho ok\n' > "$FIXTURE_DIR/scripts/commented.sh"
chmod +x "$FIXTURE_DIR"/scripts/*.sh
cat > "$FIXTURE_DIR/sub/package.json" <<'EOF'
{ "scripts": { "load": "wrk -t2 -c10 http://localhost", "test": "jest" } }
EOF

expect_in_dir deny  'npm run load' "$FIXTURE_DIR"
expect_in_dir ask   'npm run bench' "$FIXTURE_DIR"
expect_in_dir allow 'npm run ci' "$FIXTURE_DIR"
expect_in_dir allow 'npm test' "$FIXTURE_DIR"
expect_in_dir allow 'npm run test' "$FIXTURE_DIR"
expect_in_dir allow 'npm run build' "$FIXTURE_DIR"
expect_in_dir allow 'npm run dev' "$FIXTURE_DIR"
expect_in_dir deny  'npm run-script load' "$FIXTURE_DIR"
expect_in_dir deny  'yarn load' "$FIXTURE_DIR"
expect_in_dir deny  'pnpm run load' "$FIXTURE_DIR"
expect_in_dir deny  'bun run load' "$FIXTURE_DIR"
expect_in_dir ask   'yarn bench' "$FIXTURE_DIR"
expect_in_dir deny  'make loadtest' "$FIXTURE_DIR"
expect_in_dir deny  'gmake loadtest' "$FIXTURE_DIR"
expect_in_dir ask   'make bench' "$FIXTURE_DIR"
expect_in_dir allow 'make test' "$FIXTURE_DIR"
expect_in_dir allow 'make' "$FIXTURE_DIR"
expect_in_dir allow 'make build' "$FIXTURE_DIR"
expect_in_dir allow 'make -j8 build' "$FIXTURE_DIR"
expect_in_dir ask   'make -C sub loadtest' "$FIXTURE_DIR"
expect_in_dir deny  './scripts/innocent.sh' "$FIXTURE_DIR"
expect_in_dir deny  'bash scripts/innocent.sh' "$FIXTURE_DIR"
expect_in_dir deny  'sh scripts/innocent.sh' "$FIXTURE_DIR"
expect_in_dir allow 'bash scripts/setup.sh' "$FIXTURE_DIR"
expect_in_dir allow './scripts/setup.sh' "$FIXTURE_DIR"
expect_in_dir allow './scripts/commented.sh' "$FIXTURE_DIR"
expect_in_dir ask   './scripts/perf-test.sh' "$FIXTURE_DIR"
expect_in_dir ask   'bash scripts/perf-test.sh' "$FIXTURE_DIR"
expect_in_dir allow 'bash scripts/does-not-exist.sh' "$FIXTURE_DIR"
expect_in_dir deny  'cd sub && npm run load' "$FIXTURE_DIR"
expect_in_dir deny  'cd sub; npm run load' "$FIXTURE_DIR"
expect_in_dir allow 'cd sub && npm test' "$FIXTURE_DIR"
expect_in_dir allow 'npm run load' "$FIXTURE_DIR/sub/../scripts"
expect_in_dir ask   'composer stress' "$FIXTURE_DIR"
expect_in_dir ask   'composer run-script stress' "$FIXTURE_DIR"
expect_in_dir deny  'composer hammer' "$FIXTURE_DIR"
expect_in_dir allow 'composer lint' "$FIXTURE_DIR"
expect_in_dir allow 'composer run-script lint' "$FIXTURE_DIR"
expect_in_dir allow 'npm run load' "$EMPTY_DIR"

# A package.json lookup must never execute or source anything: a hostile script body only gets scanned.
printf '{ "scripts": { "x": "echo $(touch %s/executed)" } }\n' "$SCRATCH_DIR" > "$EMPTY_DIR/package.json"
expect_in_dir allow 'npm run x' "$EMPTY_DIR"
TOTAL=$((TOTAL + 1))
if [ -e "$SCRATCH_DIR/executed" ]; then
  printf 'FAIL: runner resolution executed a script body\n'; FAILURES=$((FAILURES + 1))
else
  printf 'PASS: runner resolution never executes script bodies\n'
fi
rm -f "$EMPTY_DIR/package.json"

# --- ask mechanics: modes, platform, bypass ---
ASK_COMMAND='k6 run load.js'
check "ask: ask-tier command in default mode" ask "$(run_hook "$ASK_COMMAND")"
check "ask: acceptEdits mode keeps ask" ask "$(run_hook "$ASK_COMMAND" Bash "" "$EMPTY_DIR" acceptEdits)"
check "deny: ask-tier command under bypassPermissions" deny \
  "$(run_hook "$ASK_COMMAND" Bash "" "$EMPTY_DIR" bypassPermissions)"
check "deny: ask-tier command under dontAsk" deny \
  "$(run_hook "$ASK_COMMAND" Bash "" "$EMPTY_DIR" dontAsk)"
check "deny: deny-tier command under bypassPermissions" deny \
  "$(run_hook 'stress --cpu 8' Bash "" "$EMPTY_DIR" bypassPermissions)"

CODEX_PAYLOAD=$(jq -n --arg cmd "$ASK_COMMAND" --arg cwd "$EMPTY_DIR" \
  '{hook_event_name:"PreToolUse", session_id:"s1", cwd:$cwd, tool_name:"Bash", tool_input:{command:$cmd}}')
CODEX_OUTPUT=$(printf '%s' "$CODEX_PAYLOAD" | HOOK_ADAPTER=adapter-codex.sh HOOK_ADAPTER_ALLOW_OVERRIDE=1 \
  bash "$HOOK_SCRIPT" 2>/dev/null)
check "deny: ask-tier command on the Codex adapter" deny "$CODEX_OUTPUT"
TOTAL=$((TOTAL + 1))
if printf '%s' "$CODEX_OUTPUT" | jq -e '.hookSpecificOutput.permissionDecisionReason
    | startswith("Needs human approval, which cannot be prompted here: ")' >/dev/null 2>&1; then
  printf 'PASS: codex fallback deny carries the approval prefix\n'
else
  printf 'FAIL: codex fallback deny lacks the approval prefix: %s\n' "$CODEX_OUTPUT"; FAILURES=$((FAILURES + 1))
fi
CODEX_ALLOW_PAYLOAD=$(jq -n --arg cwd "$EMPTY_DIR" \
  '{hook_event_name:"PreToolUse", cwd:$cwd, tool_name:"Bash", tool_input:{command:"npm test"}}')
check "allow: ordinary command on the Codex adapter" allow \
  "$(printf '%s' "$CODEX_ALLOW_PAYLOAD" | HOOK_ADAPTER=adapter-codex.sh HOOK_ADAPTER_ALLOW_OVERRIDE=1 \
      bash "$HOOK_SCRIPT" 2>/dev/null)"

ASK_OUTPUT=$(run_hook "$ASK_COMMAND")
TOTAL=$((TOTAL + 1))
if printf '%s' "$ASK_OUTPUT" | jq -e '.hookSpecificOutput
    | (.hookEventName == "PreToolUse" and .permissionDecision == "ask"
       and (.permissionDecisionReason | length) > 0)' >/dev/null 2>&1; then
  printf 'PASS: ask output is a valid PreToolUse envelope\n'
else
  printf 'FAIL: ask output is not a valid envelope: %s\n' "$ASK_OUTPUT"; FAILURES=$((FAILURES + 1))
fi

check "allow: non-shell tool with matching text" allow "$(run_hook 'stress --cpu 8' Read)"
check "allow: CLAUDE_BYPASS_CPU_LOAD_GUARD=1" allow \
  "$(run_hook 'stress --cpu 8' Bash 'CLAUDE_BYPASS_CPU_LOAD_GUARD=1')"
check "allow: CODEX_BYPASS_CPU_LOAD_GUARD=1" allow \
  "$(run_hook 'stress --cpu 8' Bash 'CODEX_BYPASS_CPU_LOAD_GUARD=1')"
check "allow: bypass var skips the ask tier too" allow \
  "$(run_hook "$ASK_COMMAND" Bash 'CLAUDE_BYPASS_CPU_LOAD_GUARD=1')"
check "deny: bypass var set to 0 still denies" deny \
  "$(run_hook 'stress --cpu 8' Bash 'CLAUDE_BYPASS_CPU_LOAD_GUARD=0')"

printf '\n%d of %d checks passed.\n' "$((TOTAL - FAILURES))" "$TOTAL"
if [ "$FAILURES" -eq 0 ]; then
  printf 'All tests passed.\n'
  exit 0
else
  printf '%d test(s) failed.\n' "$FAILURES"
  exit 1
fi
