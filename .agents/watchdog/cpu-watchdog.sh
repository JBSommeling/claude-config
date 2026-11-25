#!/bin/bash
# cpu-watchdog.sh — one tick of the agent CPU watchdog; launchd runs it every 30 s.
# Design, thresholds and limitations: docs/watchdog/cpu-watchdog.md

set -u

usage_error() {
  echo "cpu-watchdog: $1" >&2
  exit 2
}

ps_file=""
ncpu=""
now=""
state_dir=""
config_file=""
dry_run=false
target_uid=""
self_pid=""

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) dry_run=true; shift ;;
    --ps-file|--ncpu|--now|--state-dir|--config|--uid|--self-pid)
      [ $# -ge 2 ] || usage_error "$1 needs a value"
      case "$1" in
        --ps-file)   ps_file="$2" ;;
        --ncpu)      ncpu="$2" ;;
        --now)       now="$2" ;;
        --state-dir) state_dir="$2" ;;
        --config)    config_file="$2" ;;
        --uid)       target_uid="$2" ;;
        --self-pid)  self_pid="$2" ;;
      esac
      shift 2
      ;;
    *) usage_error "unknown argument: $1" ;;
  esac
done

is_unsigned_integer() {
  printf '%s' "$1" | grep -Eq '^[0-9]{1,12}$'
}

if [ -z "$ncpu" ]; then
  ncpu="$(sysctl -n hw.ncpu 2>/dev/null || echo 1)"
fi
if [ -z "$now" ]; then now="$(date +%s)"; fi
if [ -z "$target_uid" ]; then target_uid="$(id -u)"; fi
if [ -z "$self_pid" ]; then self_pid="$$"; fi
is_unsigned_integer "$ncpu" && [ "$ncpu" -gt 0 ] || usage_error "invalid --ncpu: $ncpu"
is_unsigned_integer "$now" || usage_error "invalid --now: $now"
is_unsigned_integer "$target_uid" || usage_error "invalid --uid: $target_uid"
is_unsigned_integer "$self_pid" || usage_error "invalid --self-pid: $self_pid"
ncpu=$((10#$ncpu))
now=$((10#$now))
target_uid=$((10#$target_uid))
self_pid=$((10#$self_pid))

default_watchdog_dir="${HOME:-}/.claude/watchdog"
[ -n "$state_dir" ] || state_dir="${default_watchdog_dir}/state"
[ -n "$config_file" ] || config_file="${default_watchdog_dir}/config"
watchdog_dir="$(dirname "$state_dir")"
pause_file="${watchdog_dir}/paused"
log_file="${watchdog_dir}/watchdog.log"
launchd_err_file="${watchdog_dir}/launchd.err"
max_log_bytes=1048576
kept_log_lines=500
max_launchd_err_bytes=262144
kept_launchd_err_lines=200
pause_log_interval=3600

# Thresholds; config values override these when valid.
LOAD_FRACTION=0.75
JOB_CORES=4
MACHINE_FRACTION=0.9
MACHINE_AGENT_CORES=2
WARN_AFTER=120
KILL_AFTER=300
MODE=kill
ROOT_NAMES="claude codex"
GRACE=10

# --------------------------------------------------------------------------
# Logging and output
# --------------------------------------------------------------------------
iso_timestamp() {
  date -u -r "$now" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
    || date -u -d "@${now}" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
    || echo "epoch-${now}"
}

# truncate_to_tail FILE MAX_BYTES KEPT_LINES — keeps only the last lines of an oversized file.
truncate_to_tail() {
  local target_file="$1" max_bytes="$2" kept_lines="$3" file_bytes
  [ -f "$target_file" ] || return 0
  file_bytes="$(wc -c < "$target_file" 2>/dev/null | tr -d ' ')"
  if [ "${file_bytes:-0}" -gt "$max_bytes" ]; then
    tail -n "$kept_lines" "$target_file" > "${target_file}.tmp" 2>/dev/null \
      && mv "${target_file}.tmp" "$target_file"
  fi
}

rotate_log() {
  truncate_to_tail "$log_file" "$max_log_bytes" "$kept_log_lines"
}

log_event() {
  printf '%s %s\n' "$(iso_timestamp)" "$*" >> "$log_file" 2>/dev/null
  rotate_log
}

print_action() {
  if $dry_run; then
    echo "[dry-run] ACTION $*"
  else
    echo "ACTION $*"
  fi
}

format_duration() {
  local seconds="$1"
  if [ "$seconds" -ge 60 ]; then
    printf '%dm%02ds' $((seconds / 60)) $((seconds % 60))
  else
    printf '%ds' "$seconds"
  fi
}

# Reduces a process path to the basename with only [A-Za-z0-9._-] kept.
clean_comm() {
  local base_name="${1##*/}"
  printf '%s' "$base_name" | tr -c 'A-Za-z0-9._-' '_'
}

send_notification() {
  local message="$1" safe_message
  print_action "NOTIFY $message"
  log_event "notify: $message"
  $dry_run && return 0
  command -v osascript >/dev/null 2>&1 || return 0
  safe_message="$(printf '%s' "$message" | tr -d '"\\')"
  osascript -e "display notification \"${safe_message}\" with title \"CPU watchdog\"" \
    </dev/null >/dev/null 2>&1 || true
}

# --------------------------------------------------------------------------
# Config: plain KEY=value lines, validated, never sourced or evaluated
# --------------------------------------------------------------------------
trim_whitespace() {
  local text="$1"
  text="${text#"${text%%[![:space:]]*}"}"
  text="${text%"${text##*[![:space:]]}"}"
  printf '%s' "$text"
}

strip_matching_quotes() {
  local text="$1"
  case "$text" in
    \"*\") text="${text#\"}"; text="${text%\"}" ;;
    \'*\') text="${text#\'}"; text="${text%\'}" ;;
  esac
  printf '%s' "$text"
}

apply_config_value() {
  local key="$1" value="$2"
  case "$key" in
    LOAD_FRACTION)
      if printf '%s' "$value" | grep -Eq '^([0-9]+(\.[0-9]+)?|\.[0-9]+)$' \
         && awk -v candidate="$value" 'BEGIN { exit !(candidate > 0 && candidate <= 1) }'; then
        LOAD_FRACTION="$value"
      fi
      ;;
    JOB_CORES)
      if printf '%s' "$value" | grep -Eq '^[0-9]{1,4}$' && [ $((10#$value)) -ge 1 ]; then
        JOB_CORES=$((10#$value))
      fi
      ;;
    MACHINE_FRACTION)
      if printf '%s' "$value" | grep -Eq '^([0-9]+(\.[0-9]+)?|\.[0-9]+)$' \
         && awk -v candidate="$value" 'BEGIN { exit !(candidate > 0 && candidate <= 1) }'; then
        MACHINE_FRACTION="$value"
      fi
      ;;
    MACHINE_AGENT_CORES)
      if printf '%s' "$value" | grep -Eq '^([0-9]{1,4}(\.[0-9]+)?|\.[0-9]+)$' \
         && awk -v candidate="$value" 'BEGIN { exit !(candidate >= 1) }'; then
        MACHINE_AGENT_CORES="$value"
      fi
      ;;
    WARN_AFTER|KILL_AFTER|GRACE)
      if printf '%s' "$value" | grep -Eq '^[0-9]{1,9}$'; then
        printf -v "$key" '%s' "$((10#$value))"
      fi
      ;;
    MODE)
      case "$value" in kill|notify) MODE="$value" ;; esac
      ;;
    ROOT_NAMES)
      if printf '%s' "$value" | grep -Eq '^[A-Za-z0-9._ -]*[A-Za-z0-9._-][A-Za-z0-9._ -]*$'; then
        ROOT_NAMES="$value"
      fi
      ;;
  esac
}

load_config() {
  [ -r "$config_file" ] || return 0
  local line key value
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in *=*) ;; *) continue ;; esac
    key="$(trim_whitespace "${line%%=*}")"
    value="$(trim_whitespace "${line#*=}")"
    case "$key" in "" | "#"*) continue ;; esac
    value="$(strip_matching_quotes "$value")"
    apply_config_value "$key" "$value"
  done < "$config_file"
}

# --------------------------------------------------------------------------
# State: plain files in $state_dir
#   tracks   "<key> <since-epoch>" per high condition (agg, machine, job:<pid>:<comm>)
#   terms    "<pid> <comm> <sigterm-epoch> <job-pid>" awaiting the SIGKILL check
#   episode_warned / episode_notified   one-per-episode flags
#   paused_logged   epoch of the last "paused" log line
# --------------------------------------------------------------------------
clear_state() {
  rm -f "${state_dir}/tracks" "${state_dir}/terms" \
        "${state_dir}/episode_warned" "${state_dir}/episode_notified"
}

lookup_track_since() {
  awk -v wanted_key="$1" '$1 == wanted_key { print $2; exit }' "${state_dir}/tracks" 2>/dev/null
}

# --------------------------------------------------------------------------
# Process analysis: one awk pass over the ps snapshot
# Output: ROOTS n / TOTAL cpu / MACHINE cpu / AGG 0|1 / MACHINE_HIGH 0|1 / JOB pid cpu comm high / MEMBER job depth pid comm
# --------------------------------------------------------------------------
analyze_processes() {
  awk -v target_uid="$target_uid" -v root_names="$ROOT_NAMES" -v ncpu="$ncpu" \
      -v load_fraction="$LOAD_FRACTION" -v job_cores="$JOB_CORES" \
      -v machine_fraction="$MACHINE_FRACTION" -v machine_agent_cores="$MACHINE_AGENT_CORES" \
      -v self_pid="$self_pid" '
    function path_basename(path_text,    segment_count, segments, base_name) {
      segment_count = split(path_text, segments, "/")
      base_name = segments[segment_count]
      if (base_name == "") base_name = path_text
      return base_name
    }
    BEGIN {
      name_count = split(root_names, root_name_list, " ")
      for (name_position = 1; name_position <= name_count; name_position++)
        is_root_name[root_name_list[name_position]] = 1
    }
    $1 ~ /^[0-9]+$/ && $2 ~ /^[0-9]+$/ && $3 ~ /^[0-9]+$/ && $4 ~ /^[0-9.]+$/ {
      machine_cpu += $4
      any_parent_of[sprintf("%d", $1)] = sprintf("%d", $2)
      if ($3 + 0 != target_uid + 0 || $1 + 0 <= 1) next
      command_text = $0
      for (field_position = 1; field_position <= 4; field_position++) {
        sub(/^[ \t]+/, "", command_text)
        sub(/^[^ \t]+/, "", command_text)
      }
      sub(/^[ \t]+/, "", command_text)
      base_name = path_basename(command_text)
      pid = sprintf("%d", $1)
      parent_of[pid] = sprintf("%d", $2)
      cpu_of[pid] = $4 + 0
      if (base_name in is_root_name) is_root[pid] = 1
      gsub(/[^A-Za-z0-9._-]/, "_", base_name)
      if (base_name == "") base_name = "unknown"
      comm_of[pid] = base_name
    }
    END {
      agg_threshold = ncpu * 100 * load_fraction
      job_threshold = job_cores * 100
      machine_threshold = ncpu * 100 * machine_fraction
      machine_agent_threshold = machine_agent_cores * 100
      # The watchdog and its ancestors: any job containing them is never counted or targeted.
      self_key = sprintf("%d", self_pid)
      for (ancestor = self_key; ancestor != "" && !(ancestor in own_ancestry) && length(own_ancestry) < 200; ancestor = any_parent_of[ancestor])
        own_ancestry[ancestor] = 1
      for (pid in parent_of) {
        if (pid in is_root) { root_total++; continue }
        if (pid in own_ancestry) continue
        reaches_self = 0
        for (current = pid; current in any_parent_of && step_count < 200; current = any_parent_of[current]) {
          step_count++
          if (any_parent_of[current] == self_key) { reaches_self = 1; break }
        }
        step_count = 0
        if (reaches_self) continue
        current = pid
        depth = 0
        job = ""
        for (step = 0; step < 200; step++) {
          parent = parent_of[current]
          if (parent in is_root) { job = current; break }
          if (!(parent in parent_of)) break
          current = parent
          depth++
        }
        if (job == "") continue
        if (job in own_ancestry) continue
        job_of[pid] = job
        depth_of[pid] = depth
        job_cpu[job] += cpu_of[pid]
        total_cpu += cpu_of[pid]
      }
      printf "ROOTS %d\n", root_total
      printf "TOTAL %.1f\n", total_cpu
      printf "MACHINE %.1f\n", machine_cpu
      printf "AGG %d\n", (total_cpu >= agg_threshold) ? 1 : 0
      printf "MACHINE_HIGH %d\n", (machine_cpu >= machine_threshold && total_cpu >= machine_agent_threshold) ? 1 : 0
      for (job in job_cpu)
        printf "JOB %s %.1f %s %d\n", job, job_cpu[job], comm_of[job], (job_cpu[job] >= job_threshold) ? 1 : 0
      for (pid in job_of)
        printf "MEMBER %s %d %s %s\n", job_of[pid], depth_of[pid], pid, comm_of[pid]
    }
  '
}

is_agent_member() {
  printf '%s\n' "$member_lines" | awk -v wanted_pid="$1" -v wanted_comm="$2" \
    '$4 == wanted_pid && $5 == wanted_comm { found = 1 } END { exit found ? 0 : 1 }'
}

# --------------------------------------------------------------------------
# Signalling
# --------------------------------------------------------------------------
# Only descendants of a root with the recorded comm, owned by our uid, may be signalled.
safe_to_signal() {
  local target_pid="$1" target_comm="$2" live_comm live_uid
  case "$target_pid" in '' | *[!0-9]*) return 1 ;; esac
  [ "$target_pid" -gt 1 ] || return 1
  [ "$target_pid" -ne "$$" ] && [ "$target_pid" -ne "$PPID" ] || return 1
  is_agent_member "$target_pid" "$target_comm" || return 1
  if [ -z "$ps_file" ] && ! $dry_run; then
    live_comm="$(clean_comm "$(ps -o comm= -p "$target_pid" 2>/dev/null)")"
    live_uid="$(ps -o uid= -p "$target_pid" 2>/dev/null | tr -d ' ')"
    [ "$live_comm" = "$target_comm" ] && [ "$live_uid" = "$target_uid" ] || return 1
  fi
  return 0
}

send_signal() {
  local signal_name="$1" target_pid="$2" target_comm="$3" job_pid="$4"
  if ! safe_to_signal "$target_pid" "$target_comm"; then
    log_event "skipped SIG${signal_name} pid=${target_pid} comm=${target_comm}: failed safety check"
    return 1
  fi
  print_action "SIG${signal_name} ${target_pid} ${target_comm} job=${job_pid}"
  log_event "SIG${signal_name} pid=${target_pid} comm=${target_comm} job=${job_pid}"
  $dry_run || kill -s "$signal_name" "$target_pid" 2>/dev/null || true
  return 0
}

# Sends SIGTERM to the whole job subtree, deepest first, and queues SIGKILL checks.
terminate_job() {
  local job_pid="$1" member_depth member_pid member_comm
  while read -r _ member_depth member_pid member_comm; do
    [ -n "$member_pid" ] || continue
    if send_signal TERM "$member_pid" "$member_comm" "$job_pid"; then
      new_terms+="${member_pid} ${member_comm} ${now} ${job_pid}"$'\n'
    fi
  done < <(printf '%s\n' "$member_lines" | awk -v wanted_job="$job_pid" '$2 == wanted_job { print $2, $3, $4, $5 }' \
           | sort -k2,2nr -k3,3nr)
}

# SIGKILL for pids still alive (same pid and comm) once GRACE has passed since SIGTERM.
process_pending_terms() {
  local terms_file="${state_dir}/terms" remaining_terms="" term_pid term_comm term_epoch term_job waited
  [ -f "$terms_file" ] || return 0
  while read -r term_pid term_comm term_epoch term_job; do
    [ -n "$term_pid" ] || continue
    if ! is_agent_member "$term_pid" "$term_comm"; then
      log_event "pid=${term_pid} comm=${term_comm} gone after SIGTERM"
      continue
    fi
    excluded_jobs+="${term_job} "
    waited=$((now - term_epoch))
    if [ "$waited" -lt 0 ] || [ "$waited" -ge "$GRACE" ]; then
      send_signal KILL "$term_pid" "$term_comm" "$term_job"
    else
      remaining_terms+="${term_pid} ${term_comm} ${term_epoch} ${term_job}"$'\n'
    fi
  done < "$terms_file"
  if [ -n "$remaining_terms" ]; then
    printf '%s' "$remaining_terms" > "$terms_file"
  else
    rm -f "$terms_file"
  fi
}

# --------------------------------------------------------------------------
# One tick
# --------------------------------------------------------------------------
handle_pause() {
  local logged_file="${state_dir}/paused_logged" last_logged=""
  [ -f "$logged_file" ] && last_logged="$(cat "$logged_file" 2>/dev/null)"
  if ! is_unsigned_integer "$last_logged" || [ $((now - last_logged)) -ge "$pause_log_interval" ] \
     || [ "$last_logged" -gt "$now" ]; then
    log_event "paused: ${pause_file} exists, watchdog idle"
    printf '%s\n' "$now" > "$logged_file"
  fi
  clear_state
}

# Fills tracks, max_elapsed and the kill-eligibility variables from this tick's high conditions.
update_tracks() {
  local tracks_file="${state_dir}/tracks" new_tracks="" had_tracks=false
  local key since elapsed job_key
  [ -s "$tracks_file" ] && had_tracks=true
  max_elapsed=0
  whole_load_kill_eligible=false
  kill_eligible_jobs=" "
  while IFS= read -r key; do
    [ -n "$key" ] || continue
    since="$(lookup_track_since "$key")"
    if ! is_unsigned_integer "$since" || [ "$since" -gt "$now" ]; then since="$now"; fi
    new_tracks+="${key} ${since}"$'\n'
    elapsed=$((now - since))
    [ "$elapsed" -gt "$max_elapsed" ] && max_elapsed="$elapsed"
    if [ "$elapsed" -ge "$KILL_AFTER" ]; then
      if [ "$key" = agg ] || [ "$key" = machine ]; then
        whole_load_kill_eligible=true
      else
        job_key="${key#job:}"
        kill_eligible_jobs+="${job_key%%:*} "
      fi
    fi
  done <<< "$high_keys"

  if [ -n "$new_tracks" ]; then
    printf '%s' "$new_tracks" > "${tracks_file}.tmp" && mv "${tracks_file}.tmp" "$tracks_file"
    $had_tracks || log_event "high load began: total=$(describe_cpu_load "$total_cpu") jobs=$(printf '%s\n' "$job_lines" | grep -c .)${machine_summary:+ ${machine_summary}}"
  else
    rm -f "$tracks_file" "${state_dir}/episode_warned" "${state_dir}/episode_notified"
    $had_tracks && log_event "high load cleared"
  fi
}

# Picks the heaviest job that is eligible to be stopped and not already being stopped.
pick_kill_target() {
  local line_tag job_pid job_cpu job_comm job_is_high
  kill_target_line=""
  while read -r line_tag job_pid job_cpu job_comm job_is_high; do
    [ "$line_tag" = JOB ] || continue
    case "$excluded_jobs" in *" ${job_pid} "*) continue ;; esac
    if $whole_load_kill_eligible; then
      kill_target_line="$line_tag $job_pid $job_cpu $job_comm"
      return 0
    fi
    case "$kill_eligible_jobs" in
      *" ${job_pid} "*) kill_target_line="$line_tag $job_pid $job_cpu $job_comm"; return 0 ;;
    esac
  done <<< "$job_lines"
  return 0
}

# Formats a pcpu sum (100 = one core) as cores used plus a share of the whole machine.
# The optional second argument is appended inside the parentheses after the percent.
describe_cpu_load() {
  awk -v cpu_percent="$1" -v share_label="${2:-}" -v ncpu="$ncpu" \
    'BEGIN { printf "%.1f of %d cores (%.0f%%%s)", cpu_percent / 100, ncpu, cpu_percent / ncpu, share_label }'
}

describe_job() {
  local _ job_pid job_cpu job_comm
  read -r _ job_pid job_cpu job_comm _ <<< "$1"
  printf 'pid %s (%s) using %s' "$job_pid" "$job_comm" "$(describe_cpu_load "$job_cpu" " of the machine")"
}

tick() {
  local analysis ps_text high_keys line_tag job_pid job_cpu job_comm job_is_high
  local roots_count agg_high machine_high machine_cpu
  local duration job_description target_pid
  new_terms=""
  excluded_jobs=" "

  if [ -e "$pause_file" ]; then
    handle_pause
    return 0
  fi

  if [ -n "$ps_file" ]; then
    ps_text="$(cat "$ps_file" 2>/dev/null)" || { clear_state; return 0; }
  else
    ps_text="$(ps -Ao pid=,ppid=,uid=,pcpu=,comm= 2>/dev/null)" || { clear_state; return 0; }
  fi
  if [ -z "$ps_text" ]; then clear_state; return 0; fi

  analysis="$(printf '%s\n' "$ps_text" | analyze_processes)"
  roots_count="$(printf '%s\n' "$analysis" | awk '$1 == "ROOTS" { print $2 }')"
  if [ "${roots_count:-0}" -eq 0 ]; then clear_state; return 0; fi

  total_cpu="$(printf '%s\n' "$analysis" | awk '$1 == "TOTAL" { print $2 }')"
  agg_high="$(printf '%s\n' "$analysis" | awk '$1 == "AGG" { print $2 }')"
  machine_high="$(printf '%s\n' "$analysis" | awk '$1 == "MACHINE_HIGH" { print $2 }')"
  machine_cpu="$(printf '%s\n' "$analysis" | awk '$1 == "MACHINE" { print $2 }')"
  job_lines="$(printf '%s\n' "$analysis" | awk '$1 == "JOB"' | sort -k3,3nr -k2,2n)"
  member_lines="$(printf '%s\n' "$analysis" | awk '$1 == "MEMBER"')"

  high_keys=""
  machine_summary=""
  [ "$agg_high" = 1 ] && high_keys="agg"
  if [ "$machine_high" = 1 ]; then
    high_keys+=$'\n'"machine"
    machine_summary="$(awk -v machine_cpu="$machine_cpu" -v agent_cpu="$total_cpu" -v ncpu="$ncpu" \
      'BEGIN { printf "machine=%.0f%% agents=%.1f cores", machine_cpu / ncpu, agent_cpu / 100 }')"
  fi
  while read -r line_tag job_pid job_cpu job_comm job_is_high; do
    [ "$line_tag" = JOB ] || continue
    [ "$job_is_high" = 1 ] && high_keys+=$'\n'"job:${job_pid}:${job_comm}"
  done <<< "$job_lines"

  update_tracks
  process_pending_terms

  if [ -z "$high_keys" ]; then
    write_new_terms
    return 0
  fi

  duration="$(format_duration "$max_elapsed")"
  job_description="$(describe_job "$(printf '%s\n' "$job_lines" | head -n 1)")"

  if [ "$max_elapsed" -ge "$WARN_AFTER" ] && [ ! -e "${state_dir}/episode_warned" ]; then
    send_notification "Agent CPU load high for ${duration}. Heaviest job: ${job_description}.${machine_summary:+ (${machine_summary})}"
    : > "${state_dir}/episode_warned"
  fi

  if [ "$max_elapsed" -ge "$KILL_AFTER" ]; then
    pick_kill_target
    if [ -n "$kill_target_line" ]; then
      read -r _ target_pid _ <<< "$kill_target_line"
      job_description="$(describe_job "$kill_target_line")"
      if [ "$MODE" = kill ]; then
        terminate_job "$target_pid"
        send_notification "Stopped agent job ${job_description} after ${duration} of high load.${machine_summary:+ (${machine_summary})}"
      elif [ ! -e "${state_dir}/episode_notified" ]; then
        send_notification "Agent CPU load still high after ${duration}; nothing stopped (MODE=notify). Heaviest job: ${job_description}.${machine_summary:+ (${machine_summary})}"
        : > "${state_dir}/episode_notified"
      fi
    fi
  fi
  write_new_terms
}

write_new_terms() {
  [ -n "$new_terms" ] || return 0
  printf '%s' "$new_terms" >> "${state_dir}/terms"
}

main() {
  mkdir -p "$state_dir" 2>/dev/null || return 0
  truncate_to_tail "$launchd_err_file" "$max_launchd_err_bytes" "$kept_launchd_err_lines"
  load_config
  tick
}

main
exit 0
