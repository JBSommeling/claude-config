#!/bin/bash
# Scenario tests for cpu-watchdog.sh. Every tick runs with --dry-run on a fixture
# ps snapshot and an injected clock; no real signals or notifications are sent.

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WATCHDOG_SCRIPT="${TESTS_DIR}/../cpu-watchdog.sh"
FIXTURES_DIR="${TESTS_DIR}/fixtures"

WORK_ROOT="$(mktemp -d)"
STUB_BIN_DIR="${WORK_ROOT}/stub-bin"
STUB_MARKER="${WORK_ROOT}/osascript-was-called"
trap 'rm -rf "$WORK_ROOT"' EXIT

mkdir -p "$STUB_BIN_DIR"
printf '#!/bin/sh\ntouch "%s"\n' "$STUB_MARKER" > "${STUB_BIN_DIR}/osascript"
chmod +x "${STUB_BIN_DIR}/osascript"

checks_total=0
checks_passed=0
nonzero_exits=0

# --------------------------------------------------------------------------
# Assertions
# --------------------------------------------------------------------------
record_check() {
  local label="$1" passed="$2" detail="${3:-}"
  checks_total=$((checks_total + 1))
  if [ "$passed" = true ]; then
    checks_passed=$((checks_passed + 1))
    echo "PASS: ${label}"
  else
    echo "FAIL: ${label}"
    [ -n "$detail" ] && printf '      %s\n' "$detail"
  fi
}

assert_equals() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    record_check "$label" true
  else
    record_check "$label" false "expected [${expected}] got [${actual}]"
  fi
}

assert_contains() {
  local label="$1" haystack="$2" needle="$3"
  if printf '%s\n' "$haystack" | grep -Fq -- "$needle"; then
    record_check "$label" true
  else
    record_check "$label" false "missing [${needle}] in [${haystack}]"
  fi
}

assert_not_contains() {
  local label="$1" haystack="$2" needle="$3"
  if printf '%s\n' "$haystack" | grep -Fq -- "$needle"; then
    record_check "$label" false "unexpected [${needle}] in [${haystack}]"
  else
    record_check "$label" true
  fi
}

count_matches() {
  printf '%s\n' "$1" | grep -Fc -- "$2"
}

# signal_pids SIGNAL TEXT — pids of ACTION lines for SIGNAL, in printed order.
signal_pids() {
  printf '%s\n' "$2" | awk -v wanted_signal="$1" '$3 == wanted_signal { printf "%s ", $4 }'
}

# --------------------------------------------------------------------------
# Scenario harness
# --------------------------------------------------------------------------
new_scenario() {
  scenario_dir="$(mktemp -d "${WORK_ROOT}/scenario.XXXXXX")"
  scenario_state_dir="${scenario_dir}/watchdog/state"
  scenario_config="${scenario_dir}/config"
  scenario_log="${scenario_dir}/watchdog/watchdog.log"
  scenario_pause_file="${scenario_dir}/watchdog/paused"
  mkdir -p "${scenario_dir}/watchdog"
  last_output=""
  all_output=""
  echo ""
  echo "--- $1"
}

# tick FIXTURE NOW — run one dry-run tick; sets last_output and appends to all_output.
tick() {
  local fixture_name="$1" now_epoch="$2" fixture_path
  fixture_path="${FIXTURES_DIR}/${fixture_name}"
  [ -f "$fixture_path" ] || fixture_path="$fixture_name"
  last_output="$(PATH="${STUB_BIN_DIR}:${PATH}" bash "$WATCHDOG_SCRIPT" --dry-run \
    --ps-file "$fixture_path" --now "$now_epoch" --state-dir "$scenario_state_dir" \
    --config "$scenario_config" --ncpu 12 --uid 501 2>&1)"
  [ $? -eq 0 ] || nonzero_exits=$((nonzero_exits + 1))
  all_output+="${last_output}"$'\n'
}

assert_no_actions() {
  assert_not_contains "$1" "$all_output" "ACTION"
}

# --------------------------------------------------------------------------
# Scenarios
# --------------------------------------------------------------------------
new_scenario "no roots"
tick no-roots.txt 1000
tick no-roots.txt 1400
assert_no_actions "no agent roots: no actions"
assert_equals "no agent roots: no state written" "false" "$([ -e "${scenario_state_dir}/tracks" ] && echo true || echo false)"

new_scenario "non-agent processes at high CPU"
tick non-agent-high.txt 1000
tick non-agent-high.txt 1200
tick non-agent-high.txt 1400
assert_no_actions "user's own non-agent load is never acted on"

new_scenario "another uid is ignored"
tick other-uid.txt 1000
tick other-uid.txt 1200
tick other-uid.txt 1400
assert_no_actions "processes of another uid are ignored"

new_scenario "root itself at high CPU"
tick root-high.txt 1000
tick root-high.txt 1200
tick root-high.txt 1400
assert_no_actions "a busy root is never a target"

new_scenario "aggregate below threshold"
tick agg-below.txt 1000
tick agg-below.txt 1200
tick agg-below.txt 1400
assert_no_actions "aggregate of 800 under 900 does nothing"

new_scenario "sustained aggregate: warn then kill"
tick agg-high.txt 1000
tick agg-high.txt 1060
tick agg-high.txt 1119
assert_no_actions "no action at 119 s"
tick agg-high.txt 1120
assert_contains "warn at 120 s names the heaviest job pid and comm" "$last_output" "pid 210 (zsh)"
assert_contains "warn shows CPU percent" "$last_output" "2.8 of 12 cores (24%"
assert_contains "warn shows elapsed time" "$last_output" "2m00s"
tick agg-high.txt 1299
assert_not_contains "no kill at 299 s" "$last_output" "SIGTERM"
tick agg-high.txt 1300
assert_equals "kill at 300 s hits the heaviest job subtree, leaves first" "213 212 211 210 " "$(signal_pids SIGTERM "$last_output")"
assert_not_contains "sibling job subtrees are untouched" "$(signal_pids SIGTERM "$last_output")" "221"
assert_contains "kill sends a notification" "$last_output" "Stopped agent job pid 210 (zsh)"
assert_contains "log records the warning" "$(cat "$scenario_log")" "notify: Agent CPU load high for 2m00s"
assert_contains "log records the SIGTERM" "$(cat "$scenario_log")" "SIGTERM pid=213 comm=node job=210"
assert_contains "log lines start with an ISO timestamp" "$(head -n 1 "$scenario_log" | grep -E '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z ')" "high load began"

new_scenario "warn is not repeated within an episode"
for tick_epoch in 1000 1120 1150 1180 1210 1240 1270 1299; do
  tick agg-high.txt "$tick_epoch"
done
assert_equals "exactly one warning across the episode" "1" "$(count_matches "$all_output" "NOTIFY")"

new_scenario "a dip below threshold resets the timer"
tick agg-high.txt 1000
tick agg-high.txt 1100
tick agg-below.txt 1130
tick agg-high.txt 1160
tick agg-high.txt 1279
assert_no_actions "119 s after the dip: nothing yet"
tick agg-high.txt 1280
assert_contains "warn fires 120 s after the restart" "$last_output" "NOTIFY"
tick agg-high.txt 1300
tick agg-high.txt 1459
assert_not_contains "no kill until 300 s after the restart" "$all_output" "SIGTERM"
tick agg-high.txt 1460
assert_equals "kill 300 s after the restart" "213 212 211 210 " "$(signal_pids SIGTERM "$last_output")"

new_scenario "single job over JOB_CORES with aggregate under"
tick job-over.txt 1000
tick job-over.txt 1120
assert_contains "single heavy job warns" "$last_output" "pid 310 (sh) using 5.0 of 12 cores (42% of the machine)"
tick job-over.txt 1300
assert_equals "single heavy job is killed" "311 310 " "$(signal_pids SIGTERM "$last_output")"

new_scenario "MODE=notify never kills"
printf 'MODE=notify\n' > "$scenario_config"
tick agg-high.txt 1000
tick agg-high.txt 1120
tick agg-high.txt 1300
assert_contains "notify mode announces at the kill threshold" "$last_output" "nothing stopped"
tick agg-high.txt 1330
tick agg-high.txt 1900
assert_not_contains "notify mode sends no signals" "$all_output" "SIG"
assert_equals "notify mode: one warning plus one threshold notice" "2" "$(count_matches "$all_output" "NOTIFY")"

new_scenario "SIGKILL follow-up for a pid that is still alive"
tick agg-high.txt 1000
tick agg-high.txt 1300
assert_equals "SIGTERM first" "213 212 211 210 " "$(signal_pids SIGTERM "$last_output")"
assert_equals "no SIGKILL before the grace period" "" "$(signal_pids SIGKILL "$last_output")"
tick agg-high.txt 1305
assert_equals "still no SIGKILL at 5 s" "" "$(signal_pids SIGKILL "$last_output")"
tick agg-high.txt 1330
assert_equals "SIGKILL after the grace period, leaves first, for both jobs termed so far" "213 212 211 210 222 221 220 " "$(signal_pids SIGKILL "$last_output")"
assert_contains "log records the SIGKILL" "$(cat "$scenario_log")" "SIGKILL pid=213 comm=node job=210"

new_scenario "no SIGKILL when the pids exited after SIGTERM"
tick agg-high.txt 1000
tick agg-high.txt 1300
tick agg-high-after-term.txt 1330
assert_equals "exited pids get no SIGKILL" "" "$(signal_pids SIGKILL "$last_output")"
assert_contains "log notes the exits" "$(cat "$scenario_log")" "gone after SIGTERM"

new_scenario "PID reuse: same pid, different comm"
tick agg-high.txt 1000
tick agg-high.txt 1300
tick agg-high-pid-reuse.txt 1330
assert_equals "reused pid 213 is not signalled, the others are" "212 211 210 " "$(signal_pids SIGKILL "$last_output")"
assert_not_contains "no signal line mentions the reused pid" "$(printf '%s\n' "$last_output" | grep SIGKILL)" " 213 "

new_scenario "pause file"
touch "$scenario_pause_file"
tick agg-high.txt 1000
tick agg-high.txt 1120
tick agg-high.txt 1300
tick agg-high.txt 1400
assert_no_actions "paused: nothing happens"
assert_equals "paused is logged once within an hour" "1" "$(count_matches "$(cat "$scenario_log")" "paused")"
tick agg-high.txt 4700
assert_equals "paused is logged again after an hour" "2" "$(count_matches "$(cat "$scenario_log")" "paused")"
rm -f "$scenario_pause_file"
tick agg-high.txt 4800
tick agg-high.txt 4900
assert_no_actions "after resuming the timer starts fresh"

new_scenario "malformed config falls back to defaults"
cat > "$scenario_config" <<'EOF'
this line has no equals sign
WARN_AFTER=banana
KILL_AFTER=-5
LOAD_FRACTION=abc
JOB_CORES=
MODE=explode
GRACE=1.5
ROOT_NAMES=
UNKNOWN_KEY=whatever
EOF
tick agg-high.txt 1000
tick agg-high.txt 1119
assert_no_actions "defaults: nothing before 120 s"
tick agg-high.txt 1120
assert_contains "defaults: warn at 120 s" "$last_output" "NOTIFY"
tick agg-high.txt 1299
assert_not_contains "defaults: no kill before 300 s" "$last_output" "SIGTERM"
tick agg-high.txt 1300
assert_equals "defaults: kill at 300 s" "213 212 211 210 " "$(signal_pids SIGTERM "$last_output")"

new_scenario "config with shell metacharacters is never executed"
injection_marker="${scenario_dir}/injected"
cat > "$scenario_config" <<EOF
WARN_AFTER=\$(touch ${injection_marker})
KILL_AFTER=\`touch ${injection_marker}\`
MODE=kill; touch ${injection_marker}
ROOT_NAMES=claude \$(touch ${injection_marker})
LOAD_FRACTION=0.5;touch ${injection_marker}
; touch ${injection_marker}
\$(touch ${injection_marker})=1
EOF
tick agg-high.txt 1000
tick agg-high.txt 1120
tick agg-high.txt 1300
assert_equals "nothing in the config was executed" "false" "$([ -e "$injection_marker" ] && echo true || echo false)"
assert_equals "metacharacter values fall back to defaults" "213 212 211 210 " "$(signal_pids SIGTERM "$last_output")"

new_scenario "valid config is honoured"
printf 'WARN_AFTER=60\nKILL_AFTER=90\n' > "$scenario_config"
tick agg-high.txt 1000
tick agg-high.txt 1060
assert_contains "custom WARN_AFTER" "$last_output" "NOTIFY"
tick agg-high.txt 1090
assert_equals "custom KILL_AFTER" "213 212 211 210 " "$(signal_pids SIGTERM "$last_output")"

new_scenario "ROOT_NAMES is configurable"
printf 'ROOT_NAMES=codex\n' > "$scenario_config"
tick agg-high.txt 1000
tick agg-high.txt 1400
assert_no_actions "claude is not a root when ROOT_NAMES=codex"

new_scenario "two roots: claude and codex"
tick two-roots.txt 1000
tick two-roots.txt 1120
assert_contains "aggregate spans both roots; heaviest job is under codex" "$last_output" "pid 250 (sh) using 3.5 of 12 cores (29% of the machine)"
tick two-roots.txt 1300
assert_equals "kill targets the codex job subtree" "251 250 " "$(signal_pids SIGTERM "$last_output")"

new_scenario "state is cleared when roots disappear"
tick agg-high.txt 1000
tick no-roots.txt 1100
tick agg-high.txt 1130
tick agg-high.txt 1150
assert_no_actions "timer restarted after the roots vanished"

new_scenario "unreadable ps snapshot"
tick agg-high.txt 1000
tick "${scenario_dir}/missing-ps.txt" 1100
assert_no_actions "missing ps output: nothing happens"
assert_equals "missing ps output clears state" "false" "$([ -e "${scenario_state_dir}/tracks" ] && echo true || echo false)"

new_scenario "log is capped"
mkdir -p "${scenario_dir}/watchdog"
awk 'BEGIN { for (line_number = 1; line_number <= 30000; line_number++) printf "2026-01-01T00:00:00Z filler line %d padding padding padding\n", line_number }' > "$scenario_log"
tick agg-high.txt 1000
assert_equals "oversized log is truncated to 500 lines" "500" "$(wc -l < "$scenario_log" | tr -d ' ')"

new_scenario "machine saturated by user apps plus modest agents"
tick machine-busy.txt 1000
tick machine-busy.txt 1119
assert_no_actions "machine: nothing at 119 s"
tick machine-busy.txt 1120
assert_contains "machine: warn at 120 s" "$last_output" "NOTIFY"
assert_contains "machine: warn names the condition" "$last_output" "machine=10"
assert_contains "machine: warn shows agent cores" "$last_output" "agents=4.5 cores"
tick machine-busy.txt 1299
assert_not_contains "machine: no kill at 299 s" "$last_output" "SIGTERM"
tick machine-busy.txt 1300
assert_equals "machine: kill hits the heaviest agent job subtree" "211 210 " "$(signal_pids SIGTERM "$last_output")"
assert_not_contains "machine: user apps are never signalled" "$all_output" " 600 "
assert_not_contains "machine: other user apps are never signalled" "$all_output" " 601 "
assert_contains "machine: log records the condition" "$(cat "$scenario_log")" "high load began: total=4.5 of 12 cores (38%) jobs=3 machine="

new_scenario "machine busy without a real agent share"
tick machine-busy-few-agents.txt 1000
tick machine-busy-few-agents.txt 1200
tick machine-busy-few-agents.txt 1400
tick machine-busy-few-agents.txt 5000
assert_no_actions "machine at 98% with agents under 2 cores does nothing"

new_scenario "machine dip resets the timer"
tick machine-busy-250.txt 1000
tick machine-busy-250.txt 1100
tick machine-moderate-250.txt 1130
tick machine-busy-250.txt 1160
tick machine-busy-250.txt 1279
assert_no_actions "machine: 119 s after the dip nothing yet"
tick machine-busy-250.txt 1280
assert_contains "machine: warn 120 s after the restart" "$last_output" "NOTIFY"
tick machine-busy-250.txt 1459
assert_not_contains "machine: no kill before 300 s after the restart" "$all_output" "SIGTERM"
tick machine-busy-250.txt 1460
assert_equals "machine: kill 300 s after the restart" "211 210 " "$(signal_pids SIGTERM "$last_output")"

new_scenario "machine condition in notify mode"
printf 'MODE=notify\n' > "$scenario_config"
tick machine-busy.txt 1000
tick machine-busy.txt 1120
tick machine-busy.txt 1300
assert_contains "machine notify: announces at the kill threshold" "$last_output" "nothing stopped"
tick machine-busy.txt 1900
assert_not_contains "machine notify: no signals" "$all_output" "SIG"

new_scenario "custom MACHINE_FRACTION is honoured"
printf 'MACHINE_FRACTION=0.7\n' > "$scenario_config"
tick machine-moderate-250.txt 1000
tick machine-moderate-250.txt 1120
assert_contains "MACHINE_FRACTION=0.7 fires at 79% machine" "$last_output" "machine=79%"

new_scenario "custom MACHINE_AGENT_CORES is honoured"
printf 'MACHINE_AGENT_CORES=1\n' > "$scenario_config"
tick machine-busy-few-agents.txt 1000
tick machine-busy-few-agents.txt 1120
assert_contains "MACHINE_AGENT_CORES=1 fires with 1 agent core" "$last_output" "agents=1.0 cores"

new_scenario "decimal MACHINE_AGENT_CORES"
printf 'MACHINE_AGENT_CORES=3.5\n' > "$scenario_config"
tick machine-busy-250.txt 1000
tick machine-busy-250.txt 1400
assert_no_actions "MACHINE_AGENT_CORES=3.5 ignores 2.5 agent cores"

new_scenario "invalid machine config falls back to defaults"
printf 'MACHINE_FRACTION=0\nMACHINE_AGENT_CORES=0.5\n' > "$scenario_config"
tick machine-moderate-250.txt 1000
tick machine-moderate-250.txt 1400
tick machine-busy-few-agents.txt 1430
tick machine-busy-few-agents.txt 1800
assert_no_actions "MACHINE_FRACTION=0 and MACHINE_AGENT_CORES=0.5 are rejected"
printf 'MACHINE_FRACTION=1.5\nMACHINE_AGENT_CORES=abc\n' > "$scenario_config"
tick machine-busy-few-agents.txt 2000
tick machine-busy-few-agents.txt 2400
assert_no_actions "MACHINE_FRACTION=1.5 and MACHINE_AGENT_CORES=abc are rejected"

new_scenario "launchd.err is capped"
launchd_err="${scenario_dir}/watchdog/launchd.err"
awk 'BEGIN { for (line_number = 1; line_number <= 8000; line_number++) printf "stderr filler line %d padding padding padding\n", line_number }' > "$launchd_err"
tick agg-below.txt 1000
assert_equals "oversized launchd.err is truncated to 200 lines" "200" "$(wc -l < "$launchd_err" | tr -d ' ')"
assert_contains "launchd.err keeps the newest lines" "$(tail -n 1 "$launchd_err")" "line 8000 "

new_scenario "small launchd.err is untouched"
launchd_err="${scenario_dir}/watchdog/launchd.err"
awk 'BEGIN { for (line_number = 1; line_number <= 300; line_number++) printf "short %d\n", line_number }' > "$launchd_err"
tick agg-below.txt 1000
assert_equals "small launchd.err keeps all 300 lines" "300" "$(wc -l < "$launchd_err" | tr -d ' ')"

new_scenario "missing log and launchd.err stay silent"
tick agg-below.txt 1000
assert_equals "tick without launchd.err or log prints nothing" "" "$last_output"

new_scenario "watchdog inside an agent job is never targeted"
self_fixture="${FIXTURES_DIR}/self-in-agent-job.txt"
for tick_now in 1000 1300; do
  last_output="$(PATH="${STUB_BIN_DIR}:${PATH}" bash "$WATCHDOG_SCRIPT" --dry-run \
    --ps-file "$self_fixture" --now "$tick_now" --state-dir "$scenario_state_dir" \
    --config "$scenario_config" --ncpu 12 --uid 501 --self-pid 213 2>&1)"
done
assert_contains "self job: the other heavy job is targeted" "$last_output" "SIGTERM 242"
assert_not_contains "self job: its ancestry is never signalled" "$last_output" "SIGTERM 211"
assert_not_contains "self job: its member 212 is never signalled" "$last_output" "SIGTERM 212"
assert_not_contains "self job: the watchdog pid is never signalled" "$last_output" "SIGTERM 213"

# --------------------------------------------------------------------------
# Global invariants and summary
# --------------------------------------------------------------------------
echo ""
echo "--- invariants"
assert_equals "every tick exited 0" "0" "$nonzero_exits"
assert_equals "dry-run never invoked osascript" "false" "$([ -e "$STUB_MARKER" ] && echo true || echo false)"
bash -n "$WATCHDOG_SCRIPT" && record_check "bash -n cpu-watchdog.sh" true || record_check "bash -n cpu-watchdog.sh" false
bash -n "${TESTS_DIR}/../../../install.sh" && record_check "bash -n install.sh" true || record_check "bash -n install.sh" false

echo ""
echo "${checks_passed} of ${checks_total} checks passed"
[ "$checks_passed" -eq "$checks_total" ]
