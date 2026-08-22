#!/bin/bash
# enforce-draft-pr.sh
#
# PreToolUse hook that keeps pull requests in draft. CLAUDE.md → Pull requests
# states the rule absolutely: every PR is opened as a draft, and promoting one
# out of draft is the human's call.
#
# Logic:
#   1. If bypassed (CLAUDE_BYPASS_DRAFT_PR=1), allow.
#   2. If the tool is not the Bash shell tool, allow.
#   3. Split the command on ; && || | so each segment is judged on its own.
#   4. Deny `gh pr create` / `az repos pr create` unless that same segment
#      carries a draft flag, and deny `gh pr ready` outright.
#
# Unlike the commit and delegation guards this applies to every caller. A
# non-draft PR is visible to other people the moment it exists, so the
# orchestrator is no more entitled to open one than a subagent is.
#
# Override: set CLAUDE_BYPASS_DRAFT_PR=1 to disable for a single session.

set -euo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$HOOK_DIR/lib/common.sh"

hook_init

if hook_bypass CLAUDE_BYPASS_DRAFT_PR; then exit 0; fi

TOOL_NAME=$(hook_tool_name)
if ! hook_is_shell_tool "$TOOL_NAME"; then exit 0; fi

COMMAND=$(hook_cmd)
[ -z "$COMMAND" ] && exit 0

SUFFIX="Every pull request is opened as a draft, and only a human promotes it. See your project instructions file → Pull requests. To bypass for a single session, set CLAUDE_BYPASS_DRAFT_PR=1."

# One segment per line so a draft flag in one command cannot excuse a
# create in another. Backslash-newline continuations are collapsed first.
SEGMENTS=$(printf '%s' "$COMMAND" \
  | awk '{ if (/\\$/) { sub(/\\$/, ""); printf "%s", $0 } else { print } }' \
  | tr -s '[:space:]' ' ' \
  | sed 's/&&/\n/g; s/||/\n/g; s/[;&|]/\n/g')

while IFS= read -r seg; do
  [ -z "$seg" ] && continue

  # `gh pr ready` — promoting out of draft is never an agent's call.
  if printf '%s' "$seg" | grep -Eq '(^| )gh( +[^ ]+)* +pr +ready( |$)'; then
    hook_deny "Blocked: \`gh pr ready\` promotes a pull request out of draft. $SUFFIX"
  fi

  # A draft flag anywhere in this segment clears its create. `--draft=false`
  # is an explicit opt-out and never counts.
  _has_draft=1
  printf '%s' "$seg" | grep -Eq '(^| )(--draft([ =]+(true|1))?|-d)( |$)' || _has_draft=0
  printf '%s' "$seg" | grep -Eq '(^| )--draft[ =]+(false|0)( |$)' && _has_draft=0

  if printf '%s' "$seg" | grep -Eq '(^| )gh( +[^ ]+)* +pr +create( |$)' && [ "$_has_draft" -eq 0 ]; then
    hook_deny "Blocked: \`gh pr create\` without \`--draft\`. $SUFFIX"
  fi

  if printf '%s' "$seg" | grep -Eq '(^| )az +repos +pr +create( |$)' && [ "$_has_draft" -eq 0 ]; then
    hook_deny "Blocked: \`az repos pr create\` without \`--draft true\`. $SUFFIX"
  fi
done <<EOF
$SEGMENTS
EOF

exit 0
