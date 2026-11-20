#!/bin/bash
# block-cpu-load.sh — PreToolUse guard against agent-started CPU load: deny, ask or allow.
# Tiers, command-position rules and known limits: docs/hooks/block-cpu-load.md.
# Bypass for one session: CLAUDE_BYPASS_CPU_LOAD_GUARD=1 or CODEX_BYPASS_CPU_LOAD_GUARD=1.

set -uo pipefail
set -f

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$HOOK_DIR/lib/common.sh"

hook_init

if hook_bypass CLAUDE_BYPASS_CPU_LOAD_GUARD; then exit 0; fi
if hook_bypass CODEX_BYPASS_CPU_LOAD_GUARD; then exit 0; fi

TOOL_NAME=$(hook_tool_name)
if ! hook_is_shell_tool "$TOOL_NAME"; then exit 0; fi

RAW_COMMAND=$(hook_cmd)
[ -n "$RAW_COMMAND" ] || exit 0

# --- state ---
ASK_REASON=""
INDIRECT_SOURCE=""
JOB_LIMIT=""
NORMALISED=""
BARE_VIEW=""
STATEMENTS=""
POSITIONAL_TOKENS=""
STAGE_PREFIX=""
STAGE_WORD=""
STAGE_WORD_RAW=""
STAGE_ARGS=""

# --- patterns ---
SPACE='[[:space:]]'
NON_SPACE='[^[:space:]]'
NON_JOB_START='[^$0-9[:space:]]'
PATH_PREFIX="(${NON_SPACE}*/)?"
ASSIGNMENT="[A-Za-z_][A-Za-z0-9_]*=${NON_SPACE}*"
FLAG_WORD="-${NON_SPACE}*${SPACE}+"

# Wrappers that may sit between a command separator and the real command.
WRAPPER_SUDO="(sudo|doas)${SPACE}+(-[ugprtCDRUT]${SPACE}+${NON_SPACE}+${SPACE}+|${FLAG_WORD})*"
WRAPPER_PLAIN="(nohup|exec|command|builtin|time|setsid|nocorrect|noglob|stdbuf|arch)${SPACE}+(${FLAG_WORD})*"
WRAPPER_IONICE="ionice${SPACE}+(-[cnpPt]${SPACE}+[0-9]+${SPACE}+|${FLAG_WORD})*"
WRAPPER_ENV="env${SPACE}+(-[uCS]${SPACE}+${NON_SPACE}+${SPACE}+|${FLAG_WORD}|${ASSIGNMENT}${SPACE}+)*"
WRAPPER_NICE="nice${SPACE}+(-n${SPACE}+-?[0-9]+${SPACE}+|${FLAG_WORD})*"
WRAPPER_TIMEOUT="timeout${SPACE}+(-[sk]${SPACE}+${NON_SPACE}+${SPACE}+|${FLAG_WORD})*[0-9.]+[smhd]?${SPACE}+"
WRAPPER_CAFFEINATE="caffeinate${SPACE}+(-[tw]${SPACE}+[0-9]+${SPACE}+|${FLAG_WORD})*"
WRAPPER_TASKPOLICY="taskpolicy${SPACE}+(-[cdgp]${SPACE}+${NON_SPACE}+${SPACE}+|${FLAG_WORD})*"
WRAPPER_XARGS="xargs${SPACE}+(-[IJnPLsEda]${SPACE}+${NON_SPACE}+${SPACE}+|${FLAG_WORD})*"
WRAPPER_PARALLEL="parallel${SPACE}+(-[jnNSa]${SPACE}+${NON_SPACE}+${SPACE}+|--(jobs|max-procs)${SPACE}+${NON_SPACE}+${SPACE}+|${FLAG_WORD})*"
WRAPPER_WATCH="watch${SPACE}+(-n${SPACE}+[0-9.]+${SPACE}+|${FLAG_WORD})*"
WRAPPER_SHELL="(bash|sh|zsh|dash|ksh)${SPACE}+(-[A-Za-z]+${SPACE}+)*-[A-Za-z]*c${SPACE}+"
WRAPPER_EVAL="eval${SPACE}+"
WRAPPER_KEYWORD="(do|then|else|elif|if|while|until|!)${SPACE}+"
WRAPPER_PREFIX_RE="^(${WRAPPER_KEYWORD}|${ASSIGNMENT}${SPACE}+|${PATH_PREFIX}(${WRAPPER_SUDO}|${WRAPPER_PLAIN}|${WRAPPER_IONICE}|${WRAPPER_ENV}|${WRAPPER_NICE}|${WRAPPER_TIMEOUT}|${WRAPPER_CAFFEINATE}|${WRAPPER_TASKPOLICY}|${WRAPPER_XARGS}|${WRAPPER_PARALLEL}|${WRAPPER_WATCH}|${WRAPPER_SHELL}|${WRAPPER_EVAL}))*"

RANDOM_SOURCE_RE='/dev/(zero|urandom|random)([^[:alnum:]_/.-]|$)'
NULL_SINK_RE="(^|[^0-9>])(@@|1)?>>?${SPACE}*/dev/null|>@@${SPACE}*/dev/null|of=/dev/null"

LOOP_HEAD="${SPACE}*;?${SPACE}*do(${SPACE}+|;)${SPACE}*;?${SPACE}*"
INFINITE_HEADS="(while${SPACE}+(true|:|1|\[${SPACE}+1${SPACE}+\]|\[\[${SPACE}+1${SPACE}+\]\])|until${SPACE}+(false|\[${SPACE}+0${SPACE}+\])|for${SPACE}*\(\(${SPACE}*;${SPACE}*;${SPACE}*\)\))"
EMPTY_LOOP_RE="${INFINITE_HEADS}${LOOP_HEAD}(:|true)${SPACE}*;?${SPACE}*done"
INFINITE_LOOP_RE="${INFINITE_HEADS}${LOOP_HEAD}"
LOOP_PAUSE_RE='(^|[^[:alnum:]_-])(sleep|wait|read|timeout)([^[:alnum:]_-]|$)'
LOOP_BODY_RE='[^[:space:];:]'

FORK_NAME='[A-Za-z_:.][A-Za-z0-9_:.-]*'
FORK_BOMB_RE="(${FORK_NAME})${SPACE}*\(${SPACE}*\)${SPACE}*\{${SPACE}*(${FORK_NAME})${SPACE}*\|${SPACE}*(${FORK_NAME})${SPACE}*&"
FORK_BOMB_KEYWORD_RE="function${SPACE}+(${FORK_NAME})${SPACE}*(\(${SPACE}*\))?${SPACE}*\{${SPACE}*(${FORK_NAME})${SPACE}*\|${SPACE}*(${FORK_NAME})${SPACE}*&"

INTERPRETER_RE="(^|[^[:alnum:]_.-])(python[0-9.]*|nodejs|node|deno|bun|ruby|perl|php)${SPACE}+([^|]*${SPACE})?(-[A-Za-z]*[cerE]|eval)${SPACE}+(.*)\$"
INFINITE_CODE_RE="(while${SPACE}*\(?${SPACE}*(True|true|1)([^[:alnum:]_]|\$)|for${SPACE}*\(${SPACE}*;${SPACE}*;${SPACE}*\)|loop${SPACE}*\{|loop${SPACE}+do([^[:alnum:]_]|\$)|1${SPACE}+while${SPACE}+1([^[:alnum:]_]|\$))"
CODE_PAUSE_RE='(^|[^[:alnum:]_])(sleep|setTimeout|setInterval|await|input|read|break)([^[:alnum:]_]|$)'

SUSPICIOUS_NAME_RE='(^|[-_:./])(bench|benchmark|benchmarks|loadtest|load-test|load_test|load:test|stress|stresstest|stress-test|perf-test|perftest|performance|soak|spike|burn|torture|flood)([-_:./]|$)'

# --- decisions ---
report_deny() {
  local subject="this command starts"
  [ -z "$INDIRECT_SOURCE" ] || subject="${INDIRECT_SOURCE} starts"
  hook_deny "Blocked: ${subject} artificial CPU load (${1}). Agents must not stress the machine; ask the human if a load test is genuinely needed. To bypass for a single session, set CLAUDE_BYPASS_CPU_LOAD_GUARD=1."
}

record_ask() {
  [ -n "$ASK_REASON" ] || ASK_REASON="$1"
}

# Soft asks (parallelism, loops) only apply to the command itself, not to resolved script bodies.
report_soft_ask() {
  [ -z "$INDIRECT_SOURCE" ] || return 0
  record_ask "$1"
}

is_load_tool_name() {
  case "$1" in
    k6|wrk|wrk2|ab|hey|vegeta|autocannon|siege|jmeter|jmeter.sh|locust|artillery|oha|bombardier|h2load|gatling|gatling.sh|tsung|drill|ddosify) return 0 ;;
  esac
  return 1
}

# is_help_invocation <tool> <args> — succeed when the invocation only asks for help or version.
is_help_invocation() {
  local tool="$1" token first_token=""
  for token in $2; do
    case "$token" in
      --help|-h|--version|-V|version|help) return 0 ;;
    esac
    [ -n "$first_token" ] || first_token=$token
  done
  [ "$tool" = "k6" ] && [ "$first_token" = "inspect" ]
}

# report_load_tool <tool> <args> — a load-test tool: ask directly, deny when found inside a script.
report_load_tool() {
  if is_help_invocation "$1" "$2"; then return 0; fi
  if [ -n "$INDIRECT_SOURCE" ]; then report_deny "load-test tool ${1}"; fi
  record_ask "${1} is a load-test tool and can keep the CPU saturated. Approve only if the human wants this load."
}

ask_if_suspicious_name() {
  if printf '%s' "$2" | grep -Eiq -- "$SUSPICIOUS_NAME_RE"; then
    record_ask "${1} '${2}' looks like a load, stress or benchmark job."
  fi
}

# --- normalisation ---
normalise_command() {
  local text="$1" newline=$'\n' backslash='\' view substitution
  text=${text//$'\r'/ }
  text=${text//"$backslash$newline"/ }
  text=${text//"$newline"/;}
  text=${text//$'\t'/ }
  while [[ $text == *"  "* ]]; do text=${text//  / }; done
  NORMALISED=$text
  view=${text//\'/}
  view=${view//\"/}
  view=${view//\\/}
  case "$view" in
    *'$('*|*'`'*)
      for substitution in '$(nproc)' '$(nproc --all)' '$(sysctl -n hw.ncpu)' '$(sysctl -n hw.logicalcpu)' \
        '$(sysctl -n hw.physicalcpu)' '$(getconf _NPROCESSORS_ONLN)' '`nproc`' '`sysctl -n hw.ncpu`'; do
        view=${view//"$substitution"/2}
      done ;;
  esac
  BARE_VIEW=$view
}

# split_statements <view> — one statement per line; pipes stay inside a statement.
split_statements() {
  local view="$1" separator
  view=${view//'&>'/'@@>'}
  view=${view//'>&'/'>@@'}
  view=${view//'&&'/';'}
  view=${view//'||'/';'}
  for separator in '&' '(' ')' '{' '}' '`' '!' ';'; do
    view=${view//"$separator"/$'\n'}
  done
  STATEMENTS=$view
}

# resolve_stage <stage> — peel wrappers; sets STAGE_PREFIX, STAGE_WORD(_RAW) and STAGE_ARGS.
resolve_stage() {
  local stage="$1" first rest needs_regex=0
  STAGE_PREFIX=""
  case "$stage" in
    'command -v'*|'command -V'*|'command -p -v'*)
      STAGE_WORD=""; STAGE_WORD_RAW=""; STAGE_ARGS=""; return 0 ;;
  esac
  first=${stage%%[[:space:]]*}
  case "$first" in *=*) needs_regex=1 ;; esac
  case "${first##*/}" in
    sudo|doas|nohup|exec|command|builtin|time|setsid|nocorrect|noglob|stdbuf|arch|ionice|env|nice|timeout|caffeinate|taskpolicy|xargs|parallel|watch|bash|sh|zsh|dash|ksh|eval|do|then|else|elif|if|while|until|'!')
      needs_regex=1 ;;
  esac
  if [ "$needs_regex" -eq 1 ] && [[ $stage =~ $WRAPPER_PREFIX_RE ]]; then
    STAGE_PREFIX=${BASH_REMATCH[0]}
  fi
  rest=${stage:${#STAGE_PREFIX}}
  STAGE_WORD_RAW=${rest%%[[:space:]]*}
  STAGE_ARGS=${rest#"$STAGE_WORD_RAW"}
  STAGE_ARGS=${STAGE_ARGS# }
  STAGE_WORD=${STAGE_WORD_RAW##*/}
}

# collect_positional <args> <flags whose next token is a value> — sets POSITIONAL_TOKENS.
collect_positional() {
  local token skip_next=0 value_flags=" $2 "
  POSITIONAL_TOKENS=""
  for token in $1; do
    if [ "$skip_next" -eq 1 ]; then skip_next=0; continue; fi
    case "$token" in
      --) break ;;
      -*) case "$value_flags" in *" $token "*) skip_next=1 ;; esac ;;
      *=*) ;;
      *) POSITIONAL_TOKENS="$POSITIONAL_TOKENS $token" ;;
    esac
  done
}

# --- parallelism ---
load_job_limit() {
  local cores
  [ -z "$JOB_LIMIT" ] || return 0
  cores=$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null)
  case "$cores" in ''|*[!0-9]*) cores=8 ;; esac
  JOB_LIMIT=$((cores * 2))
}

# check_numeric_jobs <label> <text> <flag regex group> <zero denies 0|1>
check_numeric_jobs() {
  local label="$1" text="$2" flag_regex="$3" zero_denies="$4" digits
  [[ $text =~ (^|${SPACE})${flag_regex}[=[:space:]]*([0-9]+)(${SPACE}|$) ]] || return 0
  digits=${BASH_REMATCH[3]}
  digits=${digits#"${digits%%[!0]*}"}
  if [ -z "$digits" ]; then
    [ "$zero_denies" -eq 1 ] && report_deny "${label} 0 means unbounded parallelism"
    return 0
  fi
  load_job_limit
  if [ "${#digits}" -gt 9 ] || [ "$digits" -gt "$JOB_LIMIT" ]; then
    report_soft_ask "${label} ${digits} is above twice the core count (${JOB_LIMIT})."
  fi
}

check_make_jobs() {
  local args="$1"
  check_numeric_jobs "make -j" "$args" '(-j|--jobs)' 1
  if [[ $args =~ (^|${SPACE})(-j|--jobs)(${SPACE}+${NON_JOB_START}|${SPACE}*$) ]]; then
    report_deny "make -j without a job count means unbounded parallelism"
  fi
}

check_prefix_parallelism() {
  [ -n "$STAGE_PREFIX" ] || return 0
  case "$STAGE_PREFIX" in *xargs*) check_numeric_jobs "xargs -P" "$STAGE_PREFIX" '(-P|--max-procs)' 1 ;; esac
  case "$STAGE_PREFIX" in *parallel*) check_numeric_jobs "parallel -j" "$STAGE_PREFIX" '(-j|--jobs)' 1 ;; esac
}

# --- indirect execution (one level, nothing is executed or sourced) ---
# current_dir is a local of scan_text, visible here through dynamic scoping.
ensure_current_dir() {
  [ -z "$current_dir" ] || return 0
  current_dir=$(hook_json '.cwd // empty')
  [ -n "$current_dir" ] || current_dir=$PWD
}

run_body_scan() {
  local body="$1" label="$2" body_dir="$3" previous_source=$INDIRECT_SOURCE
  INDIRECT_SOURCE=$label
  scan_text "$body" "$body_dir"
  INDIRECT_SOURCE=$previous_source
}

inspect_package_script() {
  local script_name="$1" file body=""
  ensure_current_dir
  file="$current_dir/package.json"
  if [ -f "$file" ]; then
    body=$(jq -r --arg name "$script_name" \
      '[.scripts["pre"+$name], .scripts[$name], .scripts["post"+$name]] | map(select(type == "string")) | join("\n")' \
      "$file" 2>/dev/null)
  fi
  [ -z "$body" ] || run_body_scan "$body" "package.json script '${script_name}'" "$current_dir"
  ask_if_suspicious_name "script" "$script_name"
}

inspect_composer_script() {
  local script_name="$1" file body=""
  ensure_current_dir
  file="$current_dir/composer.json"
  if [ -f "$file" ]; then
    body=$(jq -r --arg name "$script_name" \
      '(.scripts[$name] // empty) | if type == "array" then map(tostring) | join("\n") else tostring end' \
      "$file" 2>/dev/null)
  fi
  [ -z "$body" ] || run_body_scan "$body" "composer.json script '${script_name}'" "$current_dir"
  ask_if_suspicious_name "script" "$script_name"
}

inspect_make_target() {
  local target="$1" make_dir="$2" makefile="$3" candidate body=""
  if [[ $target =~ ^[A-Za-z0-9_.-]+$ ]]; then
    if [ -z "$makefile" ]; then
      for candidate in GNUmakefile makefile Makefile; do
        if [ -f "$make_dir/$candidate" ]; then makefile="$make_dir/$candidate"; break; fi
      done
    fi
    if [ -n "$makefile" ] && [ -f "$makefile" ]; then
      body=$(LC_ALL=C awk -v target="$target" '
        /^[^ \t#.][^:=]*:/ && !/^[^:]*:=/ {
          name = $0; sub(/:.*/, "", name)
          in_target = 0
          count = split(name, names, /[ \t]+/)
          for (index_of_name = 1; index_of_name <= count; index_of_name++) if (names[index_of_name] == target) in_target = 1
          next
        }
        in_target && /^\t/ { recipe = $0; sub(/^\t[@+-]*/, "", recipe); print recipe; next }
        in_target && /^[ \t]*(#.*)?$/ { next }
        { in_target = 0 }
      ' "$makefile" 2>/dev/null)
    fi
  fi
  [ -z "$body" ] || run_body_scan "$body" "make target '${target}'" "$make_dir"
  ask_if_suspicious_name "make target" "$target"
}

inspect_script_file() {
  local script_path="$1" require_file="$2" file body=""
  ensure_current_dir
  file=${script_path/#\~/$HOME}
  case "$file" in /*) ;; *) file="$current_dir/$file" ;; esac
  if [ -f "$file" ] && [ -r "$file" ]; then
    body=$(LC_ALL=C head -c 65536 < "$file" 2>/dev/null | LC_ALL=C sed -e '/^[[:space:]]*#/d' 2>/dev/null)
    [ -z "$body" ] || run_body_scan "$body" "script '${script_path}'" "${file%/*}"
  elif [ "$require_file" -eq 1 ]; then
    return 0
  fi
  ask_if_suspicious_name "script" "$script_path"
}

check_make_targets() {
  local args="$1" make_dir makefile="" target
  ensure_current_dir
  make_dir=$current_dir
  if [[ $args =~ (^|${SPACE})(-C|--directory)[=[:space:]]*(${NON_SPACE}+) ]]; then
    make_dir=${BASH_REMATCH[3]}
    case "$make_dir" in /*) ;; *) make_dir="$current_dir/$make_dir" ;; esac
  fi
  if [[ $args =~ (^|${SPACE})(-f|--file|--makefile)[=[:space:]]*(${NON_SPACE}+) ]]; then
    makefile=${BASH_REMATCH[3]}
    case "$makefile" in /*) ;; *) makefile="$make_dir/$makefile" ;; esac
  fi
  collect_positional "$args" "-C --directory -f --file --makefile -I --include-dir -o --old-file -W --what-if -l --load-average -j --jobs"
  for target in $POSITIONAL_TOKENS; do
    inspect_make_target "$target" "$make_dir" "$makefile"
  done
}

# check_runner — resolve one level of indirection for npm, yarn, composer, make, scripts and friends.
check_runner() {
  local word="$STAGE_WORD" args="$STAGE_ARGS" script_name="" token
  [ -z "$INDIRECT_SOURCE" ] || return 0
  case "$word" in
    npm)
      collect_positional "$args" "--prefix --workspace -w --cache --userconfig"
      set -- $POSITIONAL_TOKENS
      case "${1:-}" in
        run|run-script|rum|urn) script_name=${2:-} ;;
        test|t|tst) script_name=test ;;
        start|stop|restart) script_name=$1 ;;
      esac
      [ -z "$script_name" ] || inspect_package_script "$script_name" ;;
    yarn|pnpm)
      collect_positional "$args" "--cwd --filter -F --dir -C"
      set -- $POSITIONAL_TOKENS
      case "${1:-}" in
        dlx) check_package_runner_tool "${2:-}" "$args" ;;
        run) script_name=${2:-} ;;
        *) script_name=${1:-} ;;
      esac
      [ -z "$script_name" ] || [ "${1:-}" = "dlx" ] || inspect_package_script "$script_name" ;;
    bun)
      collect_positional "$args" "--cwd"
      set -- $POSITIONAL_TOKENS
      if [ "${1:-}" = "run" ] && [ -n "${2:-}" ]; then inspect_package_script "$2"; fi ;;
    composer)
      collect_positional "$args" "-d --working-dir"
      set -- $POSITIONAL_TOKENS
      case "${1:-}" in
        run-script|run) script_name=${2:-} ;;
        *) script_name=${1:-} ;;
      esac
      [ -z "$script_name" ] || inspect_composer_script "$script_name" ;;
    just|task)
      collect_positional "$args" "-f --justfile -d --working-directory -t --taskfile --dir"
      for token in $POSITIONAL_TOKENS; do ask_if_suspicious_name "recipe" "$token"; done ;;
    php)
      collect_positional "$args" "-d -c -f"
      set -- $POSITIONAL_TOKENS
      if [ "${1:-}" = "artisan" ] && [ -n "${2:-}" ]; then ask_if_suspicious_name "artisan command" "$2"; fi ;;
    bash|sh|zsh)
      collect_positional "$args" "-o -O --rcfile --init-file"
      set -- $POSITIONAL_TOKENS
      if [ -n "${1:-}" ]; then inspect_script_file "$1" 1; fi ;;
  esac
}

# check_package_runner_tool <first positional> <args> — npx-style runners that fetch and run a tool.
check_package_runner_tool() {
  local tool_name="$1"
  tool_name=${tool_name##*/}
  tool_name=${tool_name%%@*}
  if is_load_tool_name "$tool_name"; then report_load_tool "$tool_name" "$2"; fi
}

check_npx() {
  collect_positional "$STAGE_ARGS" "-p --package -c --call"
  set -- $POSITIONAL_TOKENS
  check_package_runner_tool "${1:-}" "$STAGE_ARGS"
}

check_container_run() {
  local token tool_name
  [[ $STAGE_ARGS =~ (^|${SPACE})run(${SPACE}|$) ]] || return 0
  for token in $STAGE_ARGS; do
    tool_name=${token##*/}
    tool_name=${tool_name%%[:@]*}
    if is_load_tool_name "$tool_name" || [ "$tool_name" = "stress" ] || [ "$tool_name" = "stress-ng" ]; then
      report_load_tool "$tool_name" "$STAGE_ARGS"
      return 0
    fi
  done
}

# handle_cd — track a literal `cd dir` so later runners resolve against the right directory.
handle_cd() {
  local target
  set -- $STAGE_ARGS
  target=${1:-}
  [ "$target" != "--" ] || target=${2:-}
  case "$target" in ''|-*|*'$'*|*'@@'*) return 0 ;; esac
  ensure_current_dir
  target=${target/#\~/$HOME}
  case "$target" in /*) current_dir=$target ;; *) current_dir="$current_dir/$target" ;; esac
}

# --- per-stage tool checks ---
check_stage() {
  local word="$STAGE_WORD" args="$STAGE_ARGS"
  case "$word" in
    stress|stress-ng) report_deny "stress tool" ;;
    xmrig|cpuminer*|minerd|ethminer|t-rex) report_deny "crypto miner" ;;
    geekbench*) report_deny "geekbench benchmark" ;;
    7z|7za|7zz|7zr)
      if [[ $args =~ ^(${FLAG_WORD})*b(${SPACE}|$) ]]; then report_deny "7z benchmark mode"; fi ;;
    openssl)
      if [[ $args =~ ^speed(${SPACE}|$) ]]; then report_deny "openssl speed"; fi ;;
    sysbench)
      if [[ $args =~ (^|${SPACE})(cpu|--test=cpu)(${SPACE}|$) ]]; then report_deny "sysbench cpu"; fi ;;
    dd)
      if [[ $args =~ if=/dev/(zero|urandom|random)(${SPACE}|$) ]] && [[ $args == *of=/dev/null* ]]; then
        report_deny "dd between /dev/zero|urandom and /dev/null"
      fi ;;
    make|gmake)
      check_make_jobs "$args"
      if [ -z "$INDIRECT_SOURCE" ]; then check_make_targets "$args"; fi ;;
    ninja) check_numeric_jobs "ninja -j" "$args" '(-j)' 0 ;;
    cmake)
      if [[ $args == *--build* ]]; then check_numeric_jobs "cmake --parallel" "$args" '(-j|--parallel)' 0; fi ;;
    npx|bunx|pnpx) check_npx ;;
    docker|podman|docker-compose|podman-compose) check_container_run ;;
    cd|pushd) handle_cd ;;
    k6|wrk|wrk2|ab|hey|vegeta|autocannon|siege|jmeter|jmeter.sh|locust|artillery|oha|bombardier|h2load|gatling|gatling.sh|tsung|drill|ddosify)
      report_load_tool "$word" "$args" ;;
    npm|yarn|pnpm|bun|composer|just|task|php|bash|sh|zsh) check_runner ;;
  esac
  case "$STAGE_WORD_RAW" in ./*|../*) [ -n "$INDIRECT_SOURCE" ] || inspect_script_file "$STAGE_WORD_RAW" 0 ;; esac
  check_prefix_parallelism
}

# --- whole-text checks ---
check_fork_bomb() {
  local remaining="$1" attempts=0 matched
  while [ "$attempts" -lt 8 ] && [[ $remaining =~ $FORK_BOMB_RE ]]; do
    matched=${BASH_REMATCH[0]}
    if [ "${BASH_REMATCH[1]}" = "${BASH_REMATCH[2]}" ] && [ "${BASH_REMATCH[2]}" = "${BASH_REMATCH[3]}" ]; then
      report_deny "fork bomb"
    fi
    remaining=${remaining#*"$matched"}
    attempts=$((attempts + 1))
  done
  remaining=$1
  attempts=0
  while [ "$attempts" -lt 8 ] && [[ $remaining =~ $FORK_BOMB_KEYWORD_RE ]]; do
    matched=${BASH_REMATCH[0]}
    if [ "${BASH_REMATCH[1]}" = "${BASH_REMATCH[3]}" ] && [ "${BASH_REMATCH[3]}" = "${BASH_REMATCH[4]}" ]; then
      report_deny "fork bomb"
    fi
    remaining=${remaining#*"$matched"}
    attempts=$((attempts + 1))
  done
}

check_shell_loops() {
  local text="$1" matched body
  if [[ $text =~ $EMPTY_LOOP_RE ]]; then report_deny "empty busy loop"; fi
  if [[ $text =~ $INFINITE_LOOP_RE ]]; then
    matched=${BASH_REMATCH[0]}
    body=${text#*"$matched"}
    body=${body%done*}
    if [[ $body =~ $LOOP_BODY_RE ]] && ! [[ $body =~ $LOOP_PAUSE_RE ]]; then
      report_soft_ask "a literal infinite shell loop with no sleep, wait, read or timeout can run unattended."
    fi
  fi
}

check_interpreter_loops() {
  local text="$1" code
  [[ $text =~ $INTERPRETER_RE ]] || return 0
  code=${BASH_REMATCH[5]}
  if [[ $code =~ $INFINITE_CODE_RE ]] && ! [[ $code =~ $CODE_PAUSE_RE ]]; then
    report_deny "inline interpreter infinite loop"
  fi
}

# --- scan ---
# scan_text <text> <starting dir, may be empty> — walks statements, then pipeline stages.
scan_text() {
  local text="$1" current_dir="$2"
  local bare statements statement stage
  local has_limiter has_cruncher yes_seen yes_stage_null yes_pipe_cruncher yes_pipe_sink
  local statement_null statement_source
  local -a stage_list
  normalise_command "$text"
  bare=$BARE_VIEW
  split_statements "$bare"
  statements=$STATEMENTS

  while IFS= read -r statement; do
    statement=${statement#"${statement%%[![:space:]]*}"}
    [ -n "$statement" ] || continue
    has_limiter=0; has_cruncher=0; yes_seen=0; yes_stage_null=0
    yes_pipe_cruncher=0; yes_pipe_sink=0; statement_null=0; statement_source=0
    if [[ $statement =~ $NULL_SINK_RE ]]; then statement_null=1; fi
    if [[ $statement =~ $RANDOM_SOURCE_RE ]]; then statement_source=1; fi

    IFS='|' read -r -a stage_list <<< "$statement"
    for stage in "${stage_list[@]}"; do
      stage=${stage#"${stage%%[![:space:]]*}"}
      [ -n "$stage" ] || continue
      resolve_stage "$stage"
      case "$STAGE_WORD" in
        yes)
          yes_seen=1
          if [[ $stage =~ $NULL_SINK_RE ]]; then yes_stage_null=1; fi ;;
        head) has_limiter=1 ;;
        dd) if [[ $STAGE_ARGS == *count=* ]]; then has_limiter=1; fi ;;
        pv)
          if [[ $STAGE_ARGS =~ (^|${SPACE})(-S|--stop-at-size)([=[:space:]0-9]|$) ]]; then has_limiter=1; fi
          if [ "$yes_seen" -eq 1 ]; then yes_pipe_sink=1; fi ;;
        cat|tee|wc|tr) if [ "$yes_seen" -eq 1 ]; then yes_pipe_sink=1; fi ;;
        gzip|bzip2|xz|zstd|lz4|pigz|lzma|brotli|md5|md5sum|shasum|sha[0-9]*|cksum|b2sum|b3sum|xxhsum|crc32)
          has_cruncher=1
          if [ "$yes_seen" -eq 1 ]; then yes_pipe_cruncher=1; fi ;;
        openssl)
          if [[ $STAGE_ARGS =~ ^(dgst|enc|sha1|sha224|sha256|sha384|sha512|md5|base64)(${SPACE}|$) ]]; then
            has_cruncher=1
            if [ "$yes_seen" -eq 1 ]; then yes_pipe_cruncher=1; fi
          fi ;;
      esac
      check_stage
    done

    if [ "$has_limiter" -eq 0 ]; then
      if [ "$statement_source" -eq 1 ] && { [ "$has_cruncher" -eq 1 ] || [ "$statement_null" -eq 1 ]; }; then
        report_deny "unbounded /dev/zero|urandom stream into a compressor, hash or /dev/null"
      fi
      if [ "$yes_seen" -eq 1 ] && { [ "$yes_stage_null" -eq 1 ] || [ "$yes_pipe_cruncher" -eq 1 ] \
        || { [ "$yes_pipe_sink" -eq 1 ] && [ "$statement_null" -eq 1 ]; }; }; then
        report_deny "yes piped into a discarded or hashing sink"
      fi
    fi
  done <<< "$statements"

  check_fork_bomb "$bare"
  case "$bare" in
    *python*|*node*|*deno*|*bun*|*ruby*|*perl*|*php*) check_interpreter_loops "$bare" ;;
  esac
  case "$bare" in
    *while*|*until*|*for*) check_shell_loops "$bare" ;;
  esac
}

scan_text "$RAW_COMMAND" ""

if [ -n "$ASK_REASON" ]; then hook_ask "$ASK_REASON"; fi
exit 0
