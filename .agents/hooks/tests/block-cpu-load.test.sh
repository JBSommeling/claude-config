#!/bin/bash
# tests/block-cpu-load.test.sh — regression suite for block-cpu-load.sh
#
# Feeds JSON on stdin to the hook and asserts whether a "deny" envelope is
# emitted. Exits non-zero on failure.

set -uo pipefail

HOOK_SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/block-cpu-load.sh"
FAILURES=0
TOTAL=0

# run_hook <command> [tool_name] [extra VAR=val env pairs]
run_hook() {
  local command_text="$1"
  local tool_name="${2:-Bash}"
  local extra_env="${3:-}"
  local json
  json=$(jq -n --arg tool "$tool_name" --arg cmd "$command_text" \
    '{"tool_name":$tool,"tool_input":{"command":$cmd}}')
  # shellcheck disable=SC2086
  printf '%s' "$json" | env $extra_env bash "$HOOK_SCRIPT" 2>/dev/null
}

check() {
  local label="$1" expected="$2" output="$3" got
  TOTAL=$((TOTAL + 1))
  if printf '%s' "$output" | grep -q '"deny"'; then got="deny"; else got="allow"; fi
  if [ "$got" = "$expected" ]; then
    printf 'PASS: %s\n' "$label"
  else
    printf 'FAIL: %s — expected %s, got %s\n' "$label" "$expected" "$got"
    printf '      output: %s\n' "$output"
    FAILURES=$((FAILURES + 1))
  fi
}

expect_deny()  { check "deny:  $1" deny  "$(run_hook "$1")"; }
expect_allow() { check "allow: $1" allow "$(run_hook "$1")"; }

# --- stress tools ---
expect_deny 'stress --cpu 8 --timeout 60'
expect_deny 'stress-ng --cpu 4'
expect_deny 'sudo stress-ng --cpu 4'
expect_deny 'nohup stress --cpu 2 &'
expect_deny 'nice -n 10 stress --cpu 2'
expect_deny 'timeout 30 stress-ng --cpu 2'
expect_deny 'echo start && stress --cpu 1'
expect_deny 'make build; stress --cpu 1'
expect_deny 'true || stress-ng --cpu 1'
expect_deny 'ls | stress --cpu 1'
expect_deny '(stress --cpu 1)'
expect_deny '/usr/bin/stress --cpu 1'

# --- yes to /dev/null ---
expect_deny 'yes > /dev/null'
expect_deny 'yes >/dev/null &'
expect_deny 'yes y > /dev/null'
expect_deny 'yes   >   /dev/null'
expect_deny 'for n in 1 2 3 4; do yes > /dev/null & done'

# --- fork bombs ---
expect_deny ':(){ :|:& };:'
expect_deny ':() { : | : & } ; :'
expect_deny 'bomb(){ bomb|bomb& };bomb'
expect_deny 'bomb ( ) {  bomb | bomb &  } ; bomb'

# --- empty busy loops ---
expect_deny 'while true; do :; done'
expect_deny 'while :; do :; done'
expect_deny 'while true; do true; done'
expect_deny 'while [ 1 ]; do :; done'
expect_deny 'for ((;;)); do :; done'
expect_deny 'until false; do :; done'
expect_deny 'while true;do :;done'
expect_deny 'while  true;  do  :;  done &'
expect_deny "$(printf 'while true\ndo\n  :\ndone')"

# --- dd ---
expect_deny 'dd if=/dev/zero of=/dev/null'
expect_deny 'dd if=/dev/urandom of=/dev/null'
expect_deny 'dd of=/dev/null if=/dev/zero'
expect_deny 'dd if=/dev/zero bs=1m of=/dev/null'
expect_deny 'dd if=/dev/urandom of=/dev/null bs=1m count=100000000'

# --- hash / compress burners ---
expect_deny 'cat /dev/urandom | gzip > /dev/null'
expect_deny 'cat /dev/zero | xz > /dev/null'
expect_deny 'cat /dev/urandom | md5sum > /dev/null'
expect_deny 'cat /dev/urandom > /dev/null'
expect_deny 'md5 < /dev/zero'
expect_deny 'sha256sum /dev/zero'
expect_deny 'shasum -a 256 /dev/urandom'
expect_deny 'md5sum /dev/urandom'

# --- benchmarks ---
expect_deny 'openssl speed'
expect_deny 'openssl speed -multi 8 rsa2048'
expect_deny 'sysbench cpu run'
expect_deny 'sysbench --test=cpu run'
expect_deny 'sysbench --threads=8 cpu run'

# --- inline interpreter loops ---
expect_deny 'python -c "while True: pass"'
expect_deny 'python3 -c "while 1: pass"'
expect_deny "python3 -c 'while True:  pass'"
expect_deny "node -e 'while(true){}'"
expect_deny "node -e 'while (1) { }'"
expect_deny "node -e 'for(;;){}'"
expect_deny "perl -e 'while(1){}'"
expect_deny "perl -e '1 while 1'"
expect_deny "ruby -e 'while(true){}'"
expect_deny "ruby -e 'for ( ; ; ) {}'"
expect_deny 'npm test -- -c ci && cat /dev/urandom > /dev/null'
expect_deny 'ls -n ; sha256sum /dev/zero'
expect_deny 'head -5 file.txt; cat /dev/urandom | gzip > /dev/null'

# --- allowed: legitimate loops ---
expect_allow 'while true; do curl -s localhost:8080/health; sleep 5; done'
expect_allow 'while ! pg_isready; do sleep 1; done'
expect_allow 'while true; do :; sleep 1; done'
expect_allow 'until false; do sleep 2; done'
expect_allow 'for n in 1 2 3; do echo "$n"; done'

# --- allowed: lookalikes and ordinary commands ---
expect_allow 'yes | apt-get install foo'
expect_allow 'yes | some-installer'
expect_allow 'git log --grep stress'
expect_allow 'git log --grep=stress-ng'
expect_allow 'grep stress file.txt'
expect_allow 'cat stress-notes.md'
expect_allow 'vim stress-test.md'
expect_allow 'echo I felt stressed today'
expect_allow 'npm test'
expect_allow 'make -j8'
expect_allow 'cargo build --release'
expect_allow 'head -c 100 /dev/urandom | base64'
expect_allow 'head -c 1000 /dev/urandom | md5'
expect_allow 'dd if=/dev/zero of=disk.img bs=1m count=10'
expect_allow 'python3 -c "print(1)"'
expect_allow 'node -e "console.log(1)"'
expect_allow 'openssl rand -hex 16'
expect_allow 'openssl s_client -connect example.com:443'
expect_allow 'sysbench fileio run'
expect_allow 'cat /dev/urandom | head -c 10 | gzip > /dev/null'
expect_allow 'npm test && head -c 100 /dev/urandom | base64'

# --- tool name and bypass ---
check "allow: non-shell tool with matching text" allow \
  "$(run_hook 'stress --cpu 8' Read)"
check "allow: CLAUDE_BYPASS_CPU_LOAD_GUARD=1" allow \
  "$(run_hook 'stress --cpu 8' Bash 'CLAUDE_BYPASS_CPU_LOAD_GUARD=1')"
check "allow: CODEX_BYPASS_CPU_LOAD_GUARD=1" allow \
  "$(run_hook 'stress --cpu 8' Bash 'CODEX_BYPASS_CPU_LOAD_GUARD=1')"
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
