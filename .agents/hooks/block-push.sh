#!/bin/bash
# block-push.sh
#
# PreToolUse hook that blocks `git push` to the repository's default branch
# (typically main/master). Belt-and-suspenders alongside the in-prompt
# branch checks in /full-pipeline-cycle Phase 5 Step 0.
#
# Heuristic:
#   1. If the command is not a `git push`, allow.
#   2. Determine the default branch via `gh repo view`, then `git symbolic-ref
#      refs/remotes/origin/HEAD`, falling back to "main" then "master".
#   3. If the push uses an explicit refspec ending in :<default-branch>, deny.
#   4. If no explicit refspec AND current branch is the default branch, deny.
#   5. Otherwise allow.
#
# Override: set CLAUDE_BYPASS_PUSH_GUARD=1 to disable for a single session.

set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$HOOK_DIR/lib/common.sh"

hook_init

if hook_bypass CLAUDE_BYPASS_PUSH_GUARD; then exit 0; fi

TOOL_NAME=$(hook_tool_name)
if ! hook_is_shell_tool "$TOOL_NAME"; then exit 0; fi

COMMAND=$(hook_cmd)
case "$COMMAND" in
  *"git push"*) ;;
  *) exit 0 ;;
esac

# Determine default branch — try gh, then origin HEAD, then conventional names.
DEFAULT_BRANCH=$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name 2>/dev/null || true)
if [ -z "$DEFAULT_BRANCH" ]; then
  DEFAULT_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||' || true)
fi
if [ -z "$DEFAULT_BRANCH" ]; then
  for candidate in main master; do
    if git show-ref --verify --quiet "refs/heads/$candidate"; then
      DEFAULT_BRANCH="$candidate"
      break
    fi
  done
fi
if [ -z "$DEFAULT_BRANCH" ]; then
  # Fail-closed: if we cannot determine the default branch, refuse.
  hook_deny "Cannot determine repository default branch — refusing git push as a safety precaution. Set CLAUDE_BYPASS_PUSH_GUARD=1 to override."
fi

CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")

# Detect explicit refspec ending in :<default-branch> or pushing default by name.
EXPLICIT_HIT=0
if printf '%s' "$COMMAND" | grep -Eq ":${DEFAULT_BRANCH}([[:space:]]|$)"; then
  EXPLICIT_HIT=1
fi
if printf '%s' "$COMMAND" | grep -Eq "git push[[:space:]]+[^[:space:]]+[[:space:]]+${DEFAULT_BRANCH}([[:space:]]|$)"; then
  EXPLICIT_HIT=1
fi

if [ "$EXPLICIT_HIT" -eq 0 ] && [ "$CURRENT_BRANCH" != "$DEFAULT_BRANCH" ]; then
  exit 0
fi

hook_deny "Blocked: \`git push\` would target the default branch \`${DEFAULT_BRANCH}\`. Current branch: \`${CURRENT_BRANCH}\`. Command: \`${COMMAND}\`. Open a PR instead. To bypass for a single session, set CLAUDE_BYPASS_PUSH_GUARD=1."
