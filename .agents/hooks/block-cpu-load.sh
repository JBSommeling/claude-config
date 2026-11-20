#!/bin/bash
# block-cpu-load.sh
#
# PreToolUse hook that blocks shell commands which start artificial CPU load:
# stress tools, `yes > /dev/null`, fork bombs, empty busy loops, `dd` between
# /dev/zero|urandom and /dev/null, hash/compress burners, CPU benchmarks, and
# inline-interpreter infinite loops. Enforces "No artificial CPU load" in
# .agents/conventions.md.
#
# Heuristic: the command is whitespace-normalised, then matched against one
# extended regex per pattern. Tools (stress, yes, dd, ...) only match at command
# position: start of string or after ; && || | & ( do/then/else and the
# sudo/nohup/nice/timeout wrappers.
#
# Known limitations:
#   - String matching only. Obfuscated commands and load generators hidden in
#     script files are not caught.
#   - Quoted mentions of these exact patterns (echo, commit messages, PR bodies)
#     are false denies; the hook cannot tell intent from context.
#
# Override: set CLAUDE_BYPASS_CPU_LOAD_GUARD=1 (or CODEX_BYPASS_CPU_LOAD_GUARD=1)
# to disable for a single session.

set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$HOOK_DIR/lib/common.sh"

hook_init

if hook_bypass CLAUDE_BYPASS_CPU_LOAD_GUARD; then exit 0; fi
if hook_bypass CODEX_BYPASS_CPU_LOAD_GUARD; then exit 0; fi

TOOL_NAME=$(hook_tool_name)
if ! hook_is_shell_tool "$TOOL_NAME"; then exit 0; fi

COMMAND=$(hook_cmd | tr -s '[:space:]' ' ')

# Command position: start, or after a separator, optionally behind wrappers.
WRAPPERS='((sudo|nohup|exec|command|time|env|nice([[:space:]]+-n?[[:space:]]*-?[0-9]+)?|timeout[[:space:]]+[0-9.]+[smhd]?)[[:space:]]+)*'
AT_COMMAND="(^|[;&|(]|[[:space:]](do|then|else))[[:space:]]*${WRAPPERS}([^[:space:];&|(]*/)?"

# Source and sink words shared by the burner patterns.
RANDOM_SOURCE='/dev/(zero|urandom)'
HASH_TOOLS='(md5|md5sum|sha[0-9]*sum|shasum|cksum|b2sum)'
NO_OP_BODY='(:|true)[[:space:]]*(;|[[:space:]])[[:space:]]*done'
LOOP_HEAD='[[:space:]]*(;|[[:space:]])[[:space:]]*do[[:space:]]+'

deny_if() {
  local label="$1" pattern="$2" subject="${3:-$COMMAND}"
  if printf '%s' "$subject" | grep -Eq -- "$pattern"; then
    hook_deny "Blocked: this command starts artificial CPU load (${label}). Agents must not stress the machine; ask the human if a load test is genuinely needed. To bypass for a single session, set CLAUDE_BYPASS_CPU_LOAD_GUARD=1."
  fi
}

deny_if "stress tool" \
  "${AT_COMMAND}(stress|stress-ng)([[:space:]]|\$)"

deny_if "yes > /dev/null" \
  "${AT_COMMAND}yes([[:space:]]+[^|;&<>]*)?[0-9&]?>>?[[:space:]]*/dev/null"

deny_if "fork bomb" \
  '([A-Za-z_:][A-Za-z0-9_:]*)[[:space:]]*\([[:space:]]*\)[[:space:]]*\{[[:space:]]*\1[[:space:]]*\|[[:space:]]*\1[[:space:]]*&'

deny_if "empty busy loop" \
  "while[[:space:]]+(true|:|1|\[[[:space:]]+1[[:space:]]+\]|\[\[[[:space:]]+1[[:space:]]+\]\])${LOOP_HEAD}${NO_OP_BODY}"
deny_if "empty busy loop" \
  "for[[:space:]]*\(\([[:space:]]*;[[:space:]]*;[[:space:]]*\)\)${LOOP_HEAD}${NO_OP_BODY}"
deny_if "empty busy loop" \
  "until[[:space:]]+(false|\[[[:space:]]+0[[:space:]]+\])${LOOP_HEAD}${NO_OP_BODY}"

deny_if "dd between /dev/zero|urandom and /dev/null" \
  "${AT_COMMAND}dd([[:space:]]+[^;&|]*)?if=${RANDOM_SOURCE}([[:space:]][^;&|]*)?of=/dev/null"
deny_if "dd between /dev/zero|urandom and /dev/null" \
  "${AT_COMMAND}dd([[:space:]]+[^;&|]*)?of=/dev/null([[:space:]][^;&|]*)?if=${RANDOM_SOURCE}"

deny_if "openssl speed" "${AT_COMMAND}openssl[[:space:]]+speed([[:space:]]|\$)"
deny_if "sysbench cpu" \
  "${AT_COMMAND}sysbench[[:space:]]+([^;&|]*[[:space:]])?(cpu|--test=cpu)([[:space:]]|\$)"

# Burners read an unbounded random/zero stream; a size limit in the same segment makes them finite.
# Segments split on ; && || and a lone & (redirections like 2>&1 and &> are protected).
SEGMENTS=$(printf '%s' "$COMMAND" \
  | sed -e 's/>&/@GTAMP@/g' -e 's/&>/@AMPGT@/g' -e 's/&&/;/g' -e 's/||/;/g' -e 's/&/;/g' \
        -e 's/@GTAMP@/>\&/g' -e 's/@AMPGT@/\&>/g' \
  | tr ';' '\n')
while IFS= read -r segment; do
  segment="${segment#"${segment%%[![:space:]]*}"}"
  if printf '%s' "$segment" | grep -Eq -- '(^|[[:space:]])(head|-c|-n|--bytes)[[:space:]]|count='; then
    continue
  fi
  deny_if "random/zero stream into compressor or hash discarded to /dev/null" \
    "${RANDOM_SOURCE}([[:space:]]*\|[^;&]*)?[[:space:]]*\|[[:space:]]*(gzip|bzip2|xz|zstd|openssl|${HASH_TOOLS})([[:space:]][^;&|]*)?>[[:space:]]*/dev/null" "$segment"
  deny_if "random/zero stream discarded to /dev/null" \
    "${AT_COMMAND}cat[[:space:]]+${RANDOM_SOURCE}[[:space:]]*>[[:space:]]*/dev/null" "$segment"
  deny_if "hash tool fed from /dev/zero|urandom" \
    "${AT_COMMAND}${HASH_TOOLS}([[:space:]]+[^|;&<>]*)?[[:space:]]*(<[[:space:]]*)?${RANDOM_SOURCE}([[:space:]]|[;&|]|\$)" "$segment"
done <<< "$SEGMENTS"

deny_if "python infinite empty loop" \
  '(^|[^[:alnum:]_.-])python[0-9.]*[[:space:]].*-c[[:space:]].*while[[:space:]]+(True|1)[[:space:]]*:[[:space:]]*pass'
deny_if "interpreter infinite empty loop" \
  '(^|[^[:alnum:]_.-])(node|nodejs|perl|ruby)[[:space:]].*-e[[:space:]].*(while[[:space:]]*\([[:space:]]*(true|1)[[:space:]]*\)[[:space:]]*\{[[:space:]]*\}|for[[:space:]]*\([[:space:]]*;[[:space:]]*;[[:space:]]*\)[[:space:]]*\{[[:space:]]*\}|1[[:space:]]+while[[:space:]]+1)'

exit 0
