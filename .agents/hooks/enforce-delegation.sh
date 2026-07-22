#!/bin/bash
# enforce-delegation.sh
#
# PreToolUse hook that blocks file-mutating actions from the main Opus session,
# forcing delegation to the `implementer` subagent (Sonnet) per the Model
# Routing rules in CLAUDE.md.
#
# Covers two evasion vectors:
#   1. The Edit/Write/MultiEdit/NotebookEdit tools (the obvious path).
#   2. Bash commands that write files — redirections (`>`/`>>`), in-place
#      editors (`sed -i`, `perl -i`, `gawk -i inplace`), `tee`, `dd of=`,
#      heredocs into files, and inline interpreter writes (python/node/etc.).
#      This is the path agents slip to once vector 1 is denied.
#
# Subagent calls carry `agent_id`/`agent_type` fields and pass through. Memory writes
# from the main session and redirections to temp paths are allowed. A
# CLAUDE_BYPASS_DELEGATION=1 env var provides a manual escape hatch.

set -euo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$HOOK_DIR/lib/common.sh"

hook_init

# Manual override — set CLAUDE_BYPASS_DELEGATION=1 to disable enforcement
# for a single session when delegation overhead clearly exceeds the edit.
if hook_bypass CLAUDE_BYPASS_DELEGATION; then exit 0; fi

# Subagent calls carry agent_id (the canonical distinguisher per the Claude
# Code hooks docs) and agent_type; allow them through. Match on either so a
# subagent is detected even if a given version or invocation path populates
# only one of the two fields.
if hook_is_subagent; then exit 0; fi

TOOL_NAME=$(hook_tool_name)

SUFFIX="Delegate the edit to the \`implementer\` subagent (Sonnet) via the Agent tool — pass the file path and the exact change. See ~/.claude/CLAUDE.md → Model Routing. To bypass for a single session, set CLAUDE_BYPASS_DELEGATION=1."

# --- Bash vector: detect file-mutating commands ---
if hook_is_shell_tool "$TOOL_NAME"; then
  CMD=$(hook_cmd)
  [ -z "$CMD" ] && exit 0

  # In-place editors and file-writing utilities (sed -i / perl -i /
  # gawk -i inplace / tee / dd of=).
  if printf '%s' "$CMD" | grep -Eq '(^|[[:space:];&|(])(sed[[:space:]]+([^|]*[[:space:]])?(-[a-zA-Z]*i|--in-place)|perl[[:space:]]+[^|]*-[a-zA-Z]*i|gawk[[:space:]]+-i[[:space:]]+inplace|tee([[:space:]]|$)|dd[[:space:]]+[^|]*of=)'; then
    hook_deny "Blocked: this Bash command writes files via an in-place editor (sed -i / perl -i / tee / dd). $SUFFIX"
  fi

  # Inline interpreter file writes (python -c / node -e / ruby -e / perl -e
  # opening a file for writing).
  if printf '%s' "$CMD" | grep -Eq '(python3?|node|ruby|perl)[[:space:]]+-[a-zA-Z]*(c|e)' \
     && printf '%s' "$CMD" | grep -Eq "open\([^)]*['\"][wax]|writeFile|File\.write|fs\.write"; then
    hook_deny "Blocked: this Bash command writes a file from an inline interpreter script. $SUFFIX"
  fi

  # Output redirection into a non-temporary path (also catches heredocs into
  # files). Temp paths and the standard devices are exempt.
  #
  # Strip escaped quotes then quoted spans first: a '>' inside a string
  # literal (e.g. a commit message with an email <addr>, a markdown quote,
  # or an escaped \"...\" example) is not a real shell redirection. Real
  # output redirects sit outside quotes, so removing the (possibly
  # escaped) quoted content avoids false-positives without weakening the
  # check — e.g. `echo "code" > file.py` still leaves `> file.py` exposed.
  # Strip heredoc bodies then arrow operators before scanning for redirections.
  # sed is line-oriented and cannot track multi-line quoting context; any '>'
  # inside a heredoc body would be a false-positive redirect.  We run an awk
  # pass to remove body lines while keeping the line that contains '<<' itself
  # (e.g. "cat <<EOF > file" is preserved and still caught — the real write
  # vector redirects on the '<<' line, which is never stripped).  Arrow
  # operators '->' and '=>' are not shell redirections; they are removed to
  # avoid false-positives from prose such as ".claude/skills -> .agents/skills".
  # Two-pass awk: collect all lines first, then walk the array so we only skip
  # a heredoc body when the terminator line genuinely exists later in the input.
  # This closes bypass 1 (unterminated marker strips remaining lines) and
  # partially closes bypass 2 (quoted <<TOKEN that happens to have a matching
  # terminator later would still be treated as a real heredoc opener — that
  # residual case is highly contrived and accepted as a known limitation).
  SCAN=$(printf '%s' "$CMD" \
    | awk '{L[NR]=$0} END{
        i=1
        while(i<=NR){
          line=L[i]
          # check for heredoc opener on this line
          tok=""
          tmp=line
          if(match(tmp,/<<-?[[:space:]]*'"'"'?[A-Za-z_][A-Za-z0-9_]*'"'"'?/)){
            tok=substr(tmp,RSTART,RLENGTH)
            sub(/^<<-?[[:space:]]*/,"",tok)
            gsub(/'"'"'/,"",tok)
            sub(/[[:space:]].*$/,"",tok)
          }
          print line
          if(tok!=""){
            # search forward for terminator
            found=0
            for(j=i+1;j<=NR;j++){
              t=L[j]; gsub(/^[[:space:]]+|[[:space:]]+$/,"",t)
              if(t==tok){found=j;break}
            }
            if(found>0){
              # skip body lines i+1 .. found (terminator itself also skipped)
              i=found+1
              continue
            }
            # no terminator found: do NOT skip anything — just keep going
          }
          i++
        }
      }' \
    | sed 's/[-=]>//g' \
    | sed 's/\\"//g' \
    | sed "s/'[^']*'//g" \
    | sed 's/"[^"]*"//g')
  while IFS= read -r target; do
    [ -z "$target" ] && continue
    case "$target" in
      /dev/null|/dev/stdout|/dev/stderr) continue ;;
      /tmp/*|/var/tmp/*|/private/tmp/*|/var/folders/*) continue ;;
      *) hook_deny "Blocked: this Bash command redirects output into a file ($target). $SUFFIX" ;;
    esac
  done < <(printf '%s' "$SCAN" | grep -oE '>>?[[:space:]]*[^[:space:]<>&|;)]+' | sed -E 's/^>>?[[:space:]]*//')

  exit 0
fi

# --- File-editing tools: Edit / Write / MultiEdit / NotebookEdit ---
# Memory writes from the main session are part of the auto-memory system
# and must be allowed. Path shape: ~/.claude/projects/*/memory/*
FILE_PATH=$(hook_edit_path)
case "$FILE_PATH" in
  */.claude/projects/*/memory/*) exit 0 ;;
esac

hook_deny "Direct $TOOL_NAME from the main Opus session is blocked. Delegate to the \`implementer\` subagent (Sonnet) via the Agent tool — pass the file path ($FILE_PATH) and the exact change to make. See ~/.claude/CLAUDE.md → Model Routing → Sonnet subagents. To bypass for a single session, set CLAUDE_BYPASS_DELEGATION=1."
