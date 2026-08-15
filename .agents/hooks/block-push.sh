#!/bin/bash
# block-push.sh
#
# PreToolUse hook that blocks `git push` to the repository's default branch
# (typically main/master). Belt-and-suspenders alongside the in-prompt
# branch checks in /full-pipeline-cycle Phase 5 Step 0.
#
# Heuristic:
#   1. Parse the git subcommand by tokenizing (skipping global flags: -C, -c,
#      --git-dir=, --work-tree=, --namespace=) so `git -C repo push` and
#      `git  push` (double space) are not bypasses.
#   2. Resolve REPO_DIR from -C flags (composed sequentially), --work-tree=,
#      a leading `cd <path> &&` prefix, or default to `.`.  All subsequent
#      git queries run as `git -C "$REPO_DIR" ...` to target the right repo.
#   3. Determine the default branch via:
#        a. `git ls-remote --symref origin HEAD` — authoritative and
#           host-agnostic (works on GitHub, Azure DevOps, etc.); the remote
#           cannot be tampered with by a local git command, unlike symbolic-ref.
#        b. `gh repo view` — GitHub-specific fallback for offline ls-remote.
#        c. `git symbolic-ref refs/remotes/origin/HEAD` — local, fast, but
#           writable by an unhooked `git symbolic-ref` command.
#        d. Conventional name scan (main / master).
#        e. Fail closed — deny if the default branch cannot be determined.
#   4. Deny if --all or --mirror is present (both push the default branch).
#   5. Tokenize the push arguments positionally to collect all refspecs.
#      Grepping the raw command string for the branch name cannot work across
#      `-C`, double spaces, and `cd X &&` prefixes. Every refspec is checked;
#      deny if any matches the default branch exactly or ends in :<default>.
#      A leading + (force-push) is stripped before comparison.
#   6. Deny if no explicit refspec and the current branch is the default branch.
#   7. Otherwise allow.
#
# Bounded waits use background + poll (not GNU `timeout`) for macOS portability.
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

# Detect 'git push' as the git subcommand, normalizing whitespace and skipping
# git global options so `git -C repo push` and `git  push` (double space) are
# caught. Mirrors the pattern used for 'git commit' in enforce-commit-ownership.sh.
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

if [ "$_GIT_SUBCOMMAND" != "push" ]; then
  exit 0
fi

# Resolve the target repository directory so all git queries run against the
# correct repo, not the hook's cwd (which may differ on cross-repo pushes).
REPO_DIR="."

# Step 1: leading `cd <path> &&` sets a baseline working directory.
_CD_DIR=$(printf '%s' "$COMMAND" \
  | sed -n 's|^[[:space:]]*cd[[:space:]]\{1,\}\([^&]*\)[[:space:]]*&&.*|\1|p' \
  | sed 's/[[:space:]]*$//' | head -1 || true)
if [ -n "$_CD_DIR" ]; then
  REPO_DIR="$_CD_DIR"
fi

# Step 2: git -C flags compose on top, each relative to the previous REPO_DIR.
_C_DIRS=$(printf '%s' "$COMMAND" \
  | tr -s '[:space:]' ' ' \
  | awk '{
      for (i = 1; i <= NF; i++) {
        if ($i == "-C" && i+1 <= NF) { print $(i+1); i++ }
      }
    }' 2>/dev/null || true)
if [ -n "$_C_DIRS" ]; then
  while IFS= read -r _c_path; do
    [ -z "$_c_path" ] && continue
    case "$_c_path" in
      /*) REPO_DIR="$_c_path" ;;
      *)  REPO_DIR="${REPO_DIR%/}/$_c_path" ;;
    esac
  done <<< "$_C_DIRS"
fi

# Step 3: --work-tree= is the explicit worktree path; takes final precedence.
_WORK_TREE=$(printf '%s' "$COMMAND" \
  | grep -o -- '--work-tree=[^[:space:]]*' \
  | head -1 | sed 's/--work-tree=//' 2>/dev/null || true)
if [ -n "$_WORK_TREE" ]; then
  REPO_DIR="$_WORK_TREE"
fi

# Determine default branch.
# Priority: ls-remote → gh → symbolic-ref → name scan → fail closed.
DEFAULT_BRANCH=""

# ls-remote reads the remote HEAD symref directly from the server — not locally
# forgeable. A portable bounded wait avoids stalling on a slow network.
_ls_tmp=$(mktemp)
git -C "$REPO_DIR" ls-remote --symref origin HEAD >"$_ls_tmp" 2>/dev/null &
_ls_pid=$!
_ls_waited=0
while [ "$_ls_waited" -lt 5 ] && kill -0 "$_ls_pid" 2>/dev/null; do
  sleep 1
  _ls_waited=$((_ls_waited + 1))
done
if kill -0 "$_ls_pid" 2>/dev/null; then
  kill "$_ls_pid" 2>/dev/null
  wait "$_ls_pid" 2>/dev/null || true
else
  wait "$_ls_pid" 2>/dev/null || true
fi
DEFAULT_BRANCH=$(grep -m1 '^ref:[[:space:]]' "$_ls_tmp" 2>/dev/null \
  | sed 's|^ref:[[:space:]]*refs/heads/||; s/[[:space:]].*//') || true
rm -f "$_ls_tmp"

# gh repo view falls back to the GitHub API; runs in REPO_DIR so it picks up
# the correct remote. Uses the same bounded-wait pattern for macOS portability.
if [ -z "$DEFAULT_BRANCH" ] && command -v gh >/dev/null 2>&1; then
  _gh_tmp=$(mktemp)
  (cd "$REPO_DIR" 2>/dev/null \
    && gh repo view --json defaultBranchRef -q .defaultBranchRef.name) \
    >"$_gh_tmp" 2>/dev/null &
  _gh_pid=$!
  _gh_waited=0
  while [ "$_gh_waited" -lt 5 ] && kill -0 "$_gh_pid" 2>/dev/null; do
    sleep 1
    _gh_waited=$((_gh_waited + 1))
  done
  if kill -0 "$_gh_pid" 2>/dev/null; then
    kill "$_gh_pid" 2>/dev/null
    wait "$_gh_pid" 2>/dev/null || true
  else
    wait "$_gh_pid" 2>/dev/null || true
  fi
  DEFAULT_BRANCH=$(cat "$_gh_tmp" 2>/dev/null | tr -d '[:space:]' || true)
  rm -f "$_gh_tmp"
fi

# git symbolic-ref is local and fast but writable by an unhooked git command.
if [ -z "$DEFAULT_BRANCH" ]; then
  DEFAULT_BRANCH=$(git -C "$REPO_DIR" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null \
    | sed 's|refs/remotes/origin/||' || true)
fi

if [ -z "$DEFAULT_BRANCH" ]; then
  for candidate in main master; do
    if git -C "$REPO_DIR" show-ref --verify --quiet "refs/heads/$candidate"; then
      DEFAULT_BRANCH="$candidate"
      break
    fi
  done
fi

if [ -z "$DEFAULT_BRANCH" ]; then
  hook_deny "Cannot determine repository default branch — refusing git push as a safety precaution. Set CLAUDE_BYPASS_PUSH_GUARD=1 to override."
fi

CURRENT_BRANCH=$(git -C "$REPO_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")

EXPLICIT_HIT=0

# --all and --mirror always push all branches including the default.
if printf '%s' "$COMMAND" | grep -Eq -- '(^|[[:space:]])--all([[:space:]]|$)'; then
  EXPLICIT_HIT=1
fi
if printf '%s' "$COMMAND" | grep -Eq -- '(^|[[:space:]])--mirror([[:space:]]|$)'; then
  EXPLICIT_HIT=1
fi

# Tokenize the arguments that follow `push` to collect all refspecs positionally.
# The first non-flag token after global options and the subcommand is the remote;
# every subsequent non-flag token is a refspec. All are printed, one per line.
_REFSPECS=$(printf '%s' "$COMMAND" \
  | tr -s '[:space:]' ' ' \
  | awk '{
      in_git=0; past_push=0; got_remote=0
      for (i=1; i<=NF; i++) {
        if (!in_git) {
          if ($i == "git") in_git=1
          continue
        }
        if (!past_push) {
          if ($i == "-C" || $i == "-c") { i++; continue }
          if ($i ~ /^(--git-dir=|--work-tree=|--namespace=)/) { continue }
          if ($i == "push") { past_push=1; continue }
          continue
        }
        if ($i ~ /^-/) {
          if ($i == "--receive-pack" || $i == "--exec" || $i == "--repo" ||
              $i == "-o" || $i == "--push-option" || $i == "--recurse-submodules") {
            i++
          }
          continue
        }
        if (!got_remote) { got_remote=1; continue }
        print $i
      }
    }' 2>/dev/null || true)

# Check every refspec: deny if any resolves to the default branch.
if [ -n "$_REFSPECS" ]; then
  while IFS= read -r _refspec; do
    [ -z "$_refspec" ] && continue
    _stripped="${_refspec#\+}"
    if [ "$_stripped" = "$DEFAULT_BRANCH" ]; then
      EXPLICIT_HIT=1
    fi
    _dest="${_stripped##*:}"
    if [ "$_stripped" != "$_dest" ] && [ "$_dest" = "$DEFAULT_BRANCH" ]; then
      EXPLICIT_HIT=1
    fi
  done <<< "$_REFSPECS"
fi

if [ "$EXPLICIT_HIT" -eq 0 ] && [ "$CURRENT_BRANCH" != "$DEFAULT_BRANCH" ]; then
  exit 0
fi

hook_deny "Blocked: \`git push\` would target the default branch \`${DEFAULT_BRANCH}\`. Current branch: \`${CURRENT_BRANCH}\`. Command: \`${COMMAND}\`. Open a PR instead. To bypass for a single session, set CLAUDE_BYPASS_PUSH_GUARD=1."
