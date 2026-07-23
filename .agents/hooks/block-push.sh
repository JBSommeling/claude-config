#!/bin/bash
# block-push.sh
#
# PreToolUse hook that blocks `git push` to the repository's default branch
# (typically main/master). Belt-and-suspenders alongside the in-prompt
# branch checks in /full-pipeline-cycle Phase 5 Step 0.
#
# Heuristic:
#   1. If the command is not a `git push`, allow.
#   2. Determine the default branch via `gh repo view` (network, authoritative),
#      falling back to `git symbolic-ref refs/remotes/origin/HEAD` (local, fast)
#      and then to "main"/"master".
#   3. If the push uses an explicit refspec ending in :<default-branch>, deny.
#   4. If no explicit refspec AND current branch is the default branch, deny.
#   5. Otherwise allow.
#
# H2 security fix: `gh repo view` is the PRIMARY source because the local
# symbolic-ref can be rewritten by an unhooked `git symbolic-ref` command.
# The local ref is kept as a fallback for offline/unavailable-gh scenarios.
# A short portable timeout prevents a slow network from stalling the hook.
# The DEFAULT_BRANCH value is escaped before interpolation into grep ERE so
# a metacharacter in the branch name cannot cause grep to error and fail open.
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

# Determine default branch.
# Priority: gh repo view (authoritative, cannot be forged by a local git op)
#   → git symbolic-ref (local, fast, but attacker-writable)
#   → conventional name scan (main / master)
#   → fail closed.
#
# gh is called with a portable bounded wait (background + poll) rather than
# the GNU-only `timeout` command so the hook works on macOS without coreutils.
# If gh is unavailable or times out, the hook degrades gracefully to the local
# fallback rather than stalling.
DEFAULT_BRANCH=""
if command -v gh >/dev/null 2>&1; then
  _gh_tmp=$(mktemp)
  gh repo view --json defaultBranchRef -q .defaultBranchRef.name \
    >"$_gh_tmp" 2>/dev/null &
  _gh_pid=$!
  _gh_waited=0
  while [ "$_gh_waited" -lt 5 ] && kill -0 "$_gh_pid" 2>/dev/null; do
    sleep 1
    _gh_waited=$((_gh_waited + 1))
  done
  if kill -0 "$_gh_pid" 2>/dev/null; then
    # Still running after 5 s — kill and use fallback.
    kill "$_gh_pid" 2>/dev/null
    wait "$_gh_pid" 2>/dev/null || true
  else
    wait "$_gh_pid" 2>/dev/null || true
  fi
  DEFAULT_BRANCH=$(cat "$_gh_tmp" 2>/dev/null | tr -d '[:space:]' || true)
  rm -f "$_gh_tmp"
fi
if [ -z "$DEFAULT_BRANCH" ]; then
  DEFAULT_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null \
    | sed 's|refs/remotes/origin/||' || true)
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

# Escape DEFAULT_BRANCH for safe interpolation into a grep ERE pattern (H2 fix).
# A branch name containing regex metacharacters (e.g. fix+1, feat[2]) would
# otherwise cause grep to error with rc 2, leaving EXPLICIT_HIT=0 and failing
# open (allowing a push to the default branch).
# Note: a single sed with a bracket class [.^$*...[\]...] is unreliable because
# [ and ] inside the class are parsed ambiguously; individual substitutions are
# used instead to guarantee each metacharacter is correctly escaped.
_SAFE_BRANCH=$(printf '%s' "$DEFAULT_BRANCH" \
  | sed 's/\./\\./g; s/\^/\\^/g; s/\$/\\$/g; s/\*/\\*/g; s/+/\\+/g; s/?/\\?/g; s/{/\\{/g; s/}/\\}/g; s/|/\\|/g; s/(/\\(/g; s/)/\\)/g; s/\[/\\[/g; s/\]/\\]/g')

# Detect explicit refspec ending in :<default-branch> or pushing default by name.
EXPLICIT_HIT=0
if printf '%s' "$COMMAND" | grep -Eq ":${_SAFE_BRANCH}([[:space:]]|$)"; then
  EXPLICIT_HIT=1
fi
if printf '%s' "$COMMAND" | grep -Eq "git push[[:space:]]+[^[:space:]]+[[:space:]]+${_SAFE_BRANCH}([[:space:]]|$)"; then
  EXPLICIT_HIT=1
fi

if [ "$EXPLICIT_HIT" -eq 0 ] && [ "$CURRENT_BRANCH" != "$DEFAULT_BRANCH" ]; then
  exit 0
fi

hook_deny "Blocked: \`git push\` would target the default branch \`${DEFAULT_BRANCH}\`. Current branch: \`${CURRENT_BRANCH}\`. Command: \`${COMMAND}\`. Open a PR instead. To bypass for a single session, set CLAUDE_BYPASS_PUSH_GUARD=1."
