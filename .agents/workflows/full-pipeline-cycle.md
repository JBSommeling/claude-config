---
description: Full pipeline with auto-converging review loop — spec, plan, build, validate, converge (loop + draft PR), judge
---

Run the full development pipeline with a convergence-based review loop — spec, plan, build, validate — where Phase 5 auto-fixes until clean (or capped), opens a draft PR, and Phase 6 judges the cleaned-up state.

## Arguments

`$ARGUMENTS` may include `repos=<path>` to make the pipeline aware of sibling repositories under that path. Only one path is supported. Relative paths resolve against `$HOME`; absolute and `~/` paths are used as given. The primary repo is always the repository containing the current working directory.

When present:
- Sibling repos are discovered as direct children of `<path>` that contain a `.git` entry.
- The spec allocates work across repos; the plan tags each task with its target repo; build and PR phases run per repo.

When absent, no discovery runs and no cross-repo work is performed — the pipeline is otherwise unaffected.

## Phase 1 — Spec (checkpoint)

Invoke the spec-driven-development skill. Write a structured specification for the requested feature.

When the spec is complete, present it to the user and ask for approval before continuing. Do not proceed until the user approves or requests changes. Iterate on the spec until approved.

Once approved, derive a kebab-case slug from the spec's feature title, create the directory `~/Desktop/<slug>/` (create it if it does not exist), and save the approved spec there as `spec.md`. Remember this directory for Phase 2.

## Phase 2 — Plan (checkpoint)

Invoke the planning-and-task-breakdown skill. Break the approved spec into ordered tasks with acceptance criteria and dependency ordering.

When the plan is complete, present it to the user and ask for approval before continuing. Do not proceed until the user approves or requests changes. Iterate on the plan until approved.

Once approved, save the approved plan as `plan.md` in the same `~/Desktop/<slug>/` directory created in Phase 1.

## Phase 3 — Build (automatic)

Invoke the incremental-implementation and tdd skills. For each task in the approved plan:

1. Read the task's acceptance criteria
2. Write a failing test (RED)
3. Implement minimum code to pass (GREEN)
4. Refactor if needed
5. Run full test suite — verify no regressions
6. Orchestrator commits directly inline via `git add` / `git commit` (Bash) after reviewing the diff — do not spawn a subagent solely to commit
7. Move to next task

If any task fails, follow debugging-and-error-recovery. Do not stop the pipeline — fix and continue.

**Cross-repo (when `repos=` is absent, the above is the complete phase — skip this block).**

Before iterating repos, resolve every `[repo: <name>]` tag in the plan against the Repo Allocation approved at the spec checkpoint. If any tag has no match in the approved allocation, stop and report — do not create a branch or write in any repo not listed there.

When the plan carries `[repo: <name>]` tags, iterate repos in the plan's dependency order. For each repo:

1. Create a feature branch using a literal absolute path: `git -C /absolute/path/to/repo checkout -b <branch>`. Never use a shell variable — literal paths on every cross-repo git invocation provide uniformity (one rule covers all commands) and compatibility with the push guard's whitespace tokeniser. The guard inspects the raw command before the shell expands it, so a path held in a variable cannot resolve and the push is refused — a literal path avoids that.
2. Delegate that repo's tasks to the implementer subagent.
3. Orchestrator reviews the diff and commits inline using the same literal-path form — do not spawn a subagent solely to commit.
4. Run the Phase 4 validation steps for that repo before advancing to the next.

Orchestrator retains exclusive commit rights in every repo per `docs/adr/0004` — this does not change per repo.

## Phase 4 — Validate (automatic)

After all tasks are built, invoke `/validate`. Do not proceed until it reports fully green.

## Phase 5 — Converge (automatic)

### Step 0 — Branch safety precheck

Before running the loop, verify the current branch is not the repository's default branch (typically `main` or `master`):

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

If `current_branch == default_branch`, automatically create a feature branch (`git checkout -b <suggested-name>`, deriving the name from the Phase 1 spec) and continue Phase 5 on the new branch. Do not push a PR from the default branch into itself.

**Fail-closed.** If all three arms fail — `git ls-remote` returns no `ref:` line, `gh` is not authenticated for this host, and `git symbolic-ref` finds no cached tracking ref — stop the pipeline. Do not fall back to assuming `main`. `block-push.sh` provides a second layer of protection at the harness level for both single-repo and cross-repo pushes — the guard resolves `-C` and evaluates the repository actually being pushed. The precheck must still refuse on indeterminate state.

**Cross-repo (when `repos=` is absent, the above is the complete step — skip this block).**

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

### Step 1 — Loop

Invoke `/review-cycle cap=5`. The cycle runs the five-axis review → fix loop, capped at 5 iterations, and returns a `<review-cycle-residuals>` block. Exit condition: zero Critical and zero Important findings, OR cap reached. The review round covers the primary repo's working tree only.

### Step 1b — Commit review fixes

`/review-cycle` delegates fixes to the implementer subagent, which leaves changes uncommitted in the working tree. After the loop returns, check if the tree is dirty:

```bash
if [ -n "$(git status --porcelain)" ]; then
  # commit the review-cycle fixes as one tidy commit
  git add <specific files touched by the loop>
  git commit -m "review-cycle fixes (<iterations> iterations, <N> residuals)"
fi
```

This maintains the invariant — like Phases 3 and 4 — that every step ends with a clean tree. After Step 1b, no further commits happen in Phase 5.

### Step 2 — Report and prepare PR

Parse the residuals block if present (it is only emitted when residuals are non-empty; absence means converged with zero residuals). Present to the user as a report (do not pause or wait for input):
- Iterations run, convergence status (converged / capped)
- Residuals list (if any) — these will be posted as PR comments
- PR title (derived from the Phase 1 spec — describes the feature, not just the last commit)
- PR body (derived from the spec + the accumulated commit log since the branch diverged from the default branch)
- Target branch (always the repo default branch)

Then continue directly to Step 3 without waiting for approval.

### Step 3 — Push and open draft PR

Everything is already committed by this point (Phase 3 task commits, Phase 4 validation-fix commits, Phase 5 Step 1b review-fix commit). Step 3 is pure publication:

1. `git push` (with `--set-upstream origin <branch>` if no upstream)
2. Derive `$pr_title` from the Phase 1 spec and write the PR body to a temporary file `$pr_body_file`. Parse the remote host: `remote_host=$(git remote get-url origin | sed 's|^[a-z]*://||; s|^[^@]*@||; s|[:/].*||')`. Open a draft PR — **always `--draft`**, no exceptions. Derived titles and bodies are passed via files or variables, never interpolated into the command string:
   - `remote_host` is `github.com`, or `gh auth status --hostname "$remote_host"` exits 0 → `gh pr create --draft --title "$pr_title" --body-file "$pr_body_file"`
   - `remote_host` is `dev.azure.com`, ends with `.visualstudio.com`, or is `vs-ssh.visualstudio.com` → `pr_body=$(cat "$pr_body_file")`, then `az repos pr create --draft true --repository <repo-name> --source-branch <branch> --target-branch <default-branch> --title "$pr_title" --description "$pr_body"`. Requires `--organization` and `--project` unless `az devops configure --defaults` has been set.
   - Any other host → stop and report. Do not improvise a PR command; draft-PR creation is not defined for this host.
3. Capture the PR number and URL for Phase 6.

Do not run `git add` or `git commit` here — the tree must already be clean.
The PR is opened as a draft and stays a draft — never mark it ready for review.

**Cross-repo (when `repos=` is absent, the above is the complete step — skip this block).**

**Partial-failure policy:** All commits are already in from Phases 3 and 4. Do not push any repo until every participating repo has passed validation — a half-pushed cross-repo change is harder to roll back than an unpushed one.

When the plan carries `[repo: <name>]` tags:
- Repeat items 1–3 above for each participating repo in dependency order.
- Use a literal absolute path in every git command: `git -C /absolute/path/to/repo push ...` — never a shell variable (same reason as Phase 3).
- PR bodies cross-link only repos sharing the same host and organisation: use "N of M — depends on <PR URL>" for same-domain repos. For repos on a different host or org, substitute an opaque ordinal ("N of M") with no URL or repo name — publishing internal endpoints into an external PR body is irreversible. Flag a mixed-host run at the spec checkpoint.
- Merge order is stated in the PR body, never enforced automatically.

### Step 4 — Post residuals (if any)

If a `<review-cycle-residuals>` block was emitted by Phase 5 Step 1, post each finding as an inline review comment on the new PR using the `/review-pr` posting mechanism:
- Parse `<review-cycle-residuals>` JSON verbatim
- Build payload with `line` + `side: "RIGHT"` (never `position`)
- Re-validate each line against the PR diff; drop any that don't match, log the drop
- Post via `gh api repos/{owner}/{repo}/pulls/{number}/reviews`

## Phase 6 — Judge (automatic)

**Scope.** Phase 6 judges the primary repo's PR only. Automated comment posting via `gh api` is GitHub-only and does not apply to Azure DevOps PRs. To review sibling-repo PRs, run the pipeline from inside that repo.

**Cross-repo warning (when `repos=` is present).** After posting the GO/NO-GO summary, print an explicit warning listing every sibling-repo PR from this pipeline run that received no automated review pass. In an N-repo change, N−1 repos reach their remotes without Phase 6 coverage.

Spawn four subagents in parallel against the **PR's current state** (not the local working tree). **Issue all four Agent tool calls in one assistant turn** — sequential calls defeat the purpose of parallel judging.

1. **code-reviewer** — five-axis review on the PR diff
2. **security-auditor** — vulnerability and threat-model pass
3. **test-engineer** — coverage gap analysis
4. **maintainer-reviewer** — the five-year maintenance lens and the house-consistency lens

Merge all reports into a GO/NO-GO recommendation with:
- Blockers (must fix before merge)
- Recommended fixes
- Acknowledged risks
- Rollback plan

`maintainer-reviewer` overlaps `code-reviewer`'s architecture axis at the edges — count a shared finding once, keeping whichever report cites a precedent. Its "existing practice worth revisiting" observations are never blockers for this PR; carry them into the report as follow-up suggestions.

Post the merged findings as inline PR review comments on the PR opened in Phase 5, using the same `/review-pr` posting mechanism. Post the GO/NO-GO summary as a top-level PR comment.

Present the final ship decision and PR URL to the user. Do not auto-merge — merge is a human decision.

## Rules

1. Always run phases in order: spec → plan → build → validate → converge → judge.
2. Checkpoint phases (spec, plan) require explicit user approval before continuing.
3. Everything after the plan checkpoint runs automatically without pausing, including the Phase 5 push and draft-PR creation.
4. If the user provides a spec or plan upfront, skip to the appropriate phase.
5. Commit after each task in the build phase, not at the end.
6. Phase 6 never auto-merges and never un-drafts. The draft PR stays open for the human to promote, review, and merge.
