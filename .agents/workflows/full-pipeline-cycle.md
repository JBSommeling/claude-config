---
description: Full pipeline with auto-converging review loop — spec, plan, build, validate, converge (loop + PR), judge
---

Run the full development pipeline with a convergence-based review loop. Same shape as `/full-pipeline` but Phase 5 loops auto-fixes until clean (or capped), opens a PR, and Phase 6 judges the cleaned-up state.

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

## Phase 4 — Validate (automatic)

After all tasks are built, run a full validation pass:

1. Run the complete test suite — all tests must pass, not just per-task tests
2. Run build/compile check — verify the project builds cleanly
3. Run linter/formatter if configured in the project
4. Check for type errors if the project uses a type system

If any step fails, fix the issue and re-run validation until everything passes. Orchestrator commits each fix directly inline via `git add` / `git commit` (Bash) — separate commit per fix, do not spawn a subagent solely to commit.

Do not proceed to review until validation is fully green.

## Phase 5 — Converge (automatic)

### Step 0 — Branch safety precheck

Before running the loop, verify the current branch is not the repository's default branch (typically `main` or `master`):

```bash
default_branch=$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name)
current_branch=$(git rev-parse --abbrev-ref HEAD)
```

If `current_branch == default_branch`, automatically create a feature branch (`git checkout -b <suggested-name>`, deriving the name from the Phase 1 spec) and continue Phase 5 on the new branch. Do not push a PR from the default branch into itself.

**Fail-closed.** If `gh repo view` errors (not authenticated, no remote, no GitHub repo) or returns an empty default branch, treat that as unsafe and stop the pipeline. Do not fall back to assuming `main`. The PreToolUse hook `block-push-to-default-branch.sh` provides a second layer of protection at the harness level, but the precheck must still refuse on indeterminate state.

### Step 1 — Loop

Invoke `/review-cycle cap=5`. The cycle runs the five-axis review → fix loop, capped at 5 iterations, and returns a `<review-cycle-residuals>` block. Exit condition: zero Critical and zero Important findings, OR cap reached.

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

### Step 3 — Push and open PR

Everything is already committed by this point (Phase 3 task commits, Phase 4 validation-fix commits, Phase 5 Step 1b review-fix commit). Step 3 is pure publication:

1. `git push` (with `--set-upstream origin <branch>` if no upstream)
2. `gh pr create --title "<derived title>" --body "<derived body>"`
3. Capture the PR number and URL for Phase 6.

Do not run `git add` or `git commit` here — the tree must already be clean.

### Step 4 — Post residuals (if any)

If a `<review-cycle-residuals>` block was emitted by Phase 5 Step 1, post each finding as an inline review comment on the new PR using the `/review-pr` posting mechanism:
- Parse `<review-cycle-residuals>` JSON verbatim
- Build payload with `line` + `side: "RIGHT"` (never `position`)
- Re-validate each line against the PR diff; drop any that don't match, log the drop
- Post via `gh api repos/{owner}/{repo}/pulls/{number}/reviews`

## Phase 6 — Judge (automatic)

Spawn three subagents in parallel against the **PR's current state** (not the local working tree):

1. **code-reviewer** — five-axis review on the PR diff
2. **security-auditor** — vulnerability and threat-model pass
3. **test-engineer** — coverage gap analysis

Merge all reports into a GO/NO-GO recommendation with:
- Blockers (must fix before merge)
- Recommended fixes
- Acknowledged risks
- Rollback plan

Post the merged findings as inline PR review comments on the PR opened in Phase 5, using the same `/review-pr` posting mechanism. Post the GO/NO-GO summary as a top-level PR comment.

Present the final ship decision and PR URL to the user. Do not auto-merge — merge is a human decision.

## Rules

1. Always run phases in order: spec → plan → build → validate → converge → judge.
2. Checkpoint phases (spec, plan) require explicit user approval before continuing.
3. Everything after the plan checkpoint runs automatically without pausing, including the Phase 5 push and PR creation.
4. If the user provides a spec or plan upfront, skip to the appropriate phase.
5. Commit after each task in the build phase, not at the end.
6. Phase 6 never auto-merges. The PR stays open for human review and merge.
