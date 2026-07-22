#!/bin/bash
# enforce-commit-ownership.sh
#
# PreToolUse hook that blocks `git commit` from subagent sessions,
# ensuring that only the orchestrator (main Opus session) may commit.
#
# This is the mirror image of enforce-delegation.sh: that hook blocks
# file-editing tools from the root session; this hook blocks commits
# from subagents. Together they enforce the two-party protocol described
# in CLAUDE.md → Git Safety: the orchestrator reviews, then commits inline.
#
# Logic:
#   1. If bypassed (CLAUDE_BYPASS_COMMIT_GUARD=1), allow.
#   2. If the tool is not the Bash shell tool, allow.
#   3. If the command does not contain the substring "git commit", allow.
#   4. If hook_caller returns "subagent" (agent_id or agent_type present), deny.
#   5. Otherwise allow — covers both "root" (orchestrator) and "unknown"
#      (Codex with unverified identity; treated permissively per ADR 0003).
#
# Known limitation: the "git commit" match is a substring check. A command
# that merely mentions the phrase (e.g. `git log --grep "git commit"`) from
# a subagent would also be denied. This is acceptable: subagents should not
# be committing in any form, so false positives in that direction are safe.
#
# Override: set CLAUDE_BYPASS_COMMIT_GUARD=1 to disable for a single session.

set -euo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$HOOK_DIR/lib/common.sh"

hook_init

if hook_bypass CLAUDE_BYPASS_COMMIT_GUARD; then exit 0; fi

TOOL_NAME=$(hook_tool_name)
if ! hook_is_shell_tool "$TOOL_NAME"; then exit 0; fi

COMMAND=$(hook_cmd)

# Detect 'git commit' as the git subcommand, normalizing whitespace and
# skipping git global options (-C <path>, -c <k=v>, --git-dir=, --work-tree=,
# --namespace=) so that `git -C . commit` and `git  commit` (double space)
# are not bypasses (M2 fix).  The substring match `*"git commit"*` used
# previously failed both of those forms.
_GIT_SUBCOMMAND=$(printf '%s' "$COMMAND" \
  | tr -s '[:space:]' ' ' \
  | awk '{
      for (i = 1; i <= NF; i++) {
        if ($i == "git") {
          i++
          while (i <= NF) {
            if ($i == "-C" || $i == "-c") { i += 2 }
            else if ($i ~ /^(--git-dir=|--work-tree=|--namespace=)/) { i++ }
            else break
          }
          if (i <= NF) print $i
          break
        }
      }
    }' 2>/dev/null || true)

if [ "$_GIT_SUBCOMMAND" != "commit" ]; then
  exit 0
fi

# Denies only when hook_caller returns "subagent". Both "root" and "unknown"
# are allowed through. "unknown" is treated permissively so a Codex
# orchestrator — whose identity cannot be verified in the PreToolUse payload —
# can still commit (see ADR 0003).
caller=$(hook_caller)
if [ "$caller" = "subagent" ]; then
  hook_deny "Blocked: only the orchestrator may commit. A subagent attempted \`git commit\`. Return the diff to the orchestrator and let it review and commit inline. See your project instructions file → Git Safety. To bypass for a single session, set CLAUDE_BYPASS_COMMIT_GUARD=1."
fi

exit 0
