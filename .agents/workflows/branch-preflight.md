---
description: Verify the current branch is not the repository's default branch before any push
---

Verify the current branch is not the repository's default branch (typically `main` or `master`):

```bash
remote_url=$(git remote get-url origin 2>/dev/null)
remote_host=$(printf '%s' "$remote_url" \
  | sed 's|^[a-z]*://||; s|^[^@]*@||; s|[:/].*||')
default_branch=$(GIT_TERMINAL_PROMPT=0 git ls-remote --symref origin HEAD 2>/dev/null \
  | awk '/^ref:/ { sub("^refs/heads/", "", $2); print $2; exit }')
if [ -z "$default_branch" ] && [ -n "$remote_host" ]; then
  if [ "$remote_host" = "github.com" ] || gh auth status --hostname "$remote_host" >/dev/null 2>&1; then
    default_branch=$(gh repo view --json defaultBranchRef \
      -q .defaultBranchRef.name 2>/dev/null)
  fi
fi
if [ -z "$default_branch" ]; then
  local_ref=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null \
    | awk '{ sub("^refs/remotes/origin/", "", $1); print $1; exit }')
  if [ -n "$local_ref" ]; then
    echo "REFUSED: default branch resolved only from local cache (refs/remotes/origin/HEAD) — ls-remote and gh both failed; cannot authorise push." >&2
    exit 1
  fi
fi
if [ -z "$default_branch" ]; then
  echo "FAIL-CLOSED: cannot determine default branch" >&2
  exit 1
fi
current_branch=$(git rev-parse --abbrev-ref HEAD)
```

`git ls-remote --symref` (with `GIT_TERMINAL_PROMPT=0` to prevent a prompt hang) resolves the default branch host-agnostically. The `gh` fallback runs only when `remote_host` is non-empty and `gh auth status` confirms authentication — this covers `github.com` and GitHub Enterprise; it does not run for Azure DevOps or when `origin` is absent. The `symbolic-ref` arm is advisory: if it is the sole source, the precheck refuses rather than trusting a stale cache.

If `current_branch == default_branch`, automatically create a feature branch (`git checkout -b <suggested-name>`, deriving the name from the approved spec) and continue on the new branch. Do not push a PR from the default branch into itself.

**Fail-closed.** If all three arms fail — `git ls-remote` returns no `ref:` line, `gh` is not authenticated for this host, and `git symbolic-ref` finds no cached tracking ref — stop the pipeline. Do not fall back to assuming `main`. `block-push.sh` provides a second layer of protection at the harness level for both single-repo and cross-repo pushes — the guard resolves `-C` and evaluates the repository actually being pushed. The precheck must still refuse on indeterminate state.

**Cross-repo (when `repos=` is absent, the above is the complete check — skip this block).**

Run the precheck for every participating repo before any push proceeds. `gh repo view OWNER/REPO` accepts an owner/repo positional argument and works from any directory — derive it from the repo's remote URL; both `repo_host` and `repo_slug` must be non-empty before invoking it (an empty positional argument silently resolves the session directory's repository instead). For each repo, run the complete guard using literal absolute paths — never shell variables:

```bash
repo_remote_url=$(git -C /absolute/path/to/repo remote get-url origin 2>/dev/null)
repo_host=$(printf '%s' "$repo_remote_url" \
  | sed 's|^[a-z]*://||; s|^[^@]*@||; s|[:/].*||')
repo_slug=$(printf '%s' "$repo_remote_url" \
  | sed 's|^[a-z]*://[^/]*/||; s|^[^@]*@[^:/]*[:/]||; s|\.git$||')
default_branch=$(GIT_TERMINAL_PROMPT=0 git -C /absolute/path/to/repo ls-remote --symref origin HEAD 2>/dev/null \
  | awk '/^ref:/ { sub("^refs/heads/", "", $2); print $2; exit }')
if [ -z "$default_branch" ] && [ -n "$repo_host" ] && [ -n "$repo_slug" ]; then
  if [ "$repo_host" = "github.com" ] || gh auth status --hostname "$repo_host" >/dev/null 2>&1; then
    default_branch=$(gh repo view "$repo_slug" --json defaultBranchRef \
      -q .defaultBranchRef.name 2>/dev/null)
  fi
fi
if [ -z "$default_branch" ]; then
  local_ref=$(git -C /absolute/path/to/repo symbolic-ref refs/remotes/origin/HEAD 2>/dev/null \
    | awk '{ sub("^refs/remotes/origin/", "", $1); print $1; exit }')
  if [ -n "$local_ref" ]; then
    echo "REFUSED: default branch for /absolute/path/to/repo resolved only from local cache — ls-remote and gh both failed; cannot authorise push." >&2
    exit 1
  fi
fi
if [ -z "$default_branch" ]; then
  echo "FAIL-CLOSED: cannot determine default branch for /absolute/path/to/repo" >&2
  exit 1
fi
current_branch=$(git -C /absolute/path/to/repo rev-parse --abbrev-ref HEAD)
```

Apply the fail-closed rule per repo:
- If `ls-remote` and `gh` both fail and only the local cache (`symbolic-ref`) responded: refuse — the cached ref can be stale or forged.
- If all arms fail and no default branch is determined: stop the pipeline.
- If `current_branch == default_branch`: stop the pipeline and report — do not auto-create a branch. Phase 3 already committed to this sibling repo; running `checkout -b` now would leave the default branch carrying those commits and diverged from origin.

No repo is pushed until every participating repo passes its own precheck.
