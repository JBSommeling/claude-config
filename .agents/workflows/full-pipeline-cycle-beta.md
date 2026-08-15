---
description: BETA — Full pipeline with adversarial test lenses in the judging phase (costs more agents than full-pipeline-cycle)
---

> **BETA variant of `/full-pipeline-cycle`.**
> One substantive change: Phase 6 replaces the single `test-engineer` judge with four adversarial lenses, running six judging agents in parallel instead of three. This costs more agent invocations. Everything else — Phases 1 to 5, the checkpoints, the branch precheck, and the residual posting — is identical to the original.

Run the full development pipeline with a convergence-based review loop — spec, plan, build, validate — where Phase 5 auto-fixes until clean (or capped), opens a draft PR, and Phase 6 judges the cleaned-up state with adversarial test lenses.

## Arguments

`$ARGUMENTS` may include `repos=<path>` to make the pipeline aware of sibling repositories under that path. Only one path is supported. Relative paths resolve against `$HOME`; absolute and `~/` paths are used as given. The primary repo is always the current working directory.

When present:
- Sibling repos are discovered as direct children of `<path>` that contain a `.git` entry.
- The spec allocates work across repos; the plan tags each task with its target repo; build and PR phases run per repo.

When absent, the pipeline behaves exactly as it does today — no discovery, no added cost.

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

When the plan carries `[repo: <name>]` tags, iterate repos in the plan's dependency order. For each repo:

1. Create a feature branch using a literal absolute path: `git -C /absolute/path/to/repo checkout -b <branch>`. Never use a shell variable — the `block-push.sh` hook reads the raw command string before expansion, so `git -C "$REPO" push` fails closed with "Cannot determine repository default branch".
2. Delegate that repo's tasks to the implementer subagent.
3. Orchestrator reviews the diff and commits inline using the same literal-path form — do not spawn a subagent solely to commit.
4. Run the Phase 4 validation steps for that repo before advancing to the next.

Orchestrator retains exclusive commit rights in every repo per `docs/adr/0004` — this does not change per repo.

## Phase 4 — Validate (automatic)

After all tasks are built, run a full validation pass:

1. Run the complete test suite — all tests must pass, not just per-task tests
2. Run build/compile check — verify the project builds cleanly
3. Run linter/formatter if configured in the project
4. Check for type errors if the project uses a type system

If any step fails, fix the issue and re-run validation until everything passes. Orchestrator commits each fix directly inline via `git add` / `git commit` (Bash) — separate commit per fix, do not spawn a subagent solely to commit.

Do not proceed to review until validation is fully green.

**Cross-repo (when `repos=` is absent, the above is the complete phase — skip this block).**

When the plan carries `[repo: <name>]` tags, run the validation steps above in each participating repo. Every repo must be fully green before the pipeline proceeds.

## Phase 5 — Converge (automatic)

### Step 0 — Branch safety precheck

Before running the loop, verify the current branch is not the repository's default branch (typically `main` or `master`):

```bash
default_branch=$(git ls-remote --symref origin HEAD 2>/dev/null \
  | awk '/^ref:/ { sub("^refs/heads/", "", $2); print $2; exit }')
if [ -z "$default_branch" ]; then
  remote_url=$(git remote get-url origin 2>/dev/null)
  if echo "$remote_url" | grep -qE '(^|[@/])github\.com[:/]'; then
    default_branch=$(gh repo view --json defaultBranchRef \
      -q .defaultBranchRef.name 2>/dev/null)
  fi
fi
if [ -z "$default_branch" ]; then
  echo "FAIL-CLOSED: cannot determine default branch" >&2
  exit 1
fi
current_branch=$(git rev-parse --abbrev-ref HEAD)
```

`git ls-remote --symref` resolves the default branch host-agnostically; the `gh` fallback runs only for GitHub remotes, because `gh repo view` always errors on Azure DevOps ("none of the git remotes … point to a known GitHub host").

If `current_branch == default_branch`, automatically create a feature branch (`git checkout -b <suggested-name>`, deriving the name from the Phase 1 spec) and continue Phase 5 on the new branch. Do not push a PR from the default branch into itself.

**Fail-closed.** If neither method resolves the default branch — `git ls-remote` returns no `ref:` line and either the remote is not GitHub or `gh repo view` errors — treat that as unsafe and stop the pipeline. Do not fall back to assuming `main`. The PreToolUse hook `block-push.sh` provides a second layer of protection at the harness level, but the precheck must still refuse on indeterminate state.

**Cross-repo (when `repos=` is absent, the above is the complete step — skip this block).**

Run the precheck for every participating repo before any push proceeds. For each repo, resolve its default branch and current branch using literal absolute paths — never shell variables:

```bash
git -C /absolute/path/to/repo ls-remote --symref origin HEAD
git -C /absolute/path/to/repo rev-parse --abbrev-ref HEAD
```

Apply the same fail-closed rule: if the default branch cannot be determined for any repo, stop the pipeline. No repo is pushed until its own precheck passes.

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
2. Detect the remote host: `git remote get-url origin`. Open a draft PR — **always `--draft`**, no exceptions:
   - `github.com` → `gh pr create --draft --title "<derived title>" --body "<derived body>"`
   - `dev.azure.com` → `az repos pr create --draft true --repository <repo-name> --source-branch <branch> --target-branch <default-branch> --title "<derived title>" --description "<derived body>"`. Requires `--organization` and `--project` unless `az devops configure --defaults` has been set.
   - Any other host → stop and report. Do not improvise a PR command; draft-PR creation is not defined for this host.
3. Capture the PR number and URL for Phase 6.

Do not run `git add` or `git commit` here — the tree must already be clean.
The PR is opened as a draft and stays a draft — never mark it ready for review.

**Cross-repo (when `repos=` is absent, the above is the complete step — skip this block).**

**Partial-failure policy:** All commits are already in from Phases 3 and 4. Do not push any repo until every participating repo has passed validation — a half-pushed cross-repo change is harder to roll back than an unpushed one.

When the plan carries `[repo: <name>]` tags:
- Repeat steps 1–3 for each participating repo in dependency order.
- Use a literal absolute path in every git command: `git -C /absolute/path/to/repo push ...` — never a shell variable (same reason as Phase 3).
- PR bodies must cross-link all participating repos and include "N of M — depends on <PR URL>" for each repo with upstream dependencies.
- Merge order is stated in the PR body, never enforced automatically.

### Step 4 — Post residuals (if any)

If a `<review-cycle-residuals>` block was emitted by Phase 5 Step 1, post each finding as an inline review comment on the new PR using the `/review-pr` posting mechanism:
- Parse `<review-cycle-residuals>` JSON verbatim
- Build payload with `line` + `side: "RIGHT"` (never `position`)
- Re-validate each line against the PR diff; drop any that don't match, log the drop
- Post via `gh api repos/{owner}/{repo}/pulls/{number}/reviews`

## Phase 6 — Judge (automatic)

**Scope.** Phase 6 judges the primary repo's PR only. Automated comment posting via `gh api` is GitHub-only and does not apply to Azure DevOps PRs. To review sibling-repo PRs, run the pipeline from inside that repo.

Spawn all six agents in a single turn so they execute in parallel. **Issue all six Agent tool calls in one assistant turn — sequential calls defeat the purpose of parallel judging.**

Agents operate against the **PR's current state** (not the local working tree):

1. **code-reviewer** — five-axis review on the PR diff (unchanged from the original pipeline)
2. **security-auditor** — vulnerability and threat-model pass (unchanged from the original pipeline)
3. **test-engineer** with the **mutation lens** — mutate safety-critical lines so their behaviour is wrong; confirm the suite goes red. Report every surviving mutation with the exact line mutated and the test that should have caught it. Do not modify tracked files — mutate only copies in a temporary directory; confirm the repository is clean after mutation work.
4. **test-engineer** with the **vacuity lens** — for each test, determine whether it exercises the path its name claims, or reaches the expected result via an early return, a default, or an unrelated branch. List every test that passes for the wrong reason.
5. **test-engineer** with the **oracle distrust lens** — audit every baseline, golden file, and fixture. Flag any that were regenerated during the same change under review — they may encode a bug rather than the correct behaviour. Report what would have to be true for each oracle to be wrong.
6. **test-engineer** with the **blast radius lens** — map untested paths to the damage a failure in each would cause. Rank gaps by blast radius, not line count. A five-line auth check outranks a fifty-line formatter.

### Merge and report

Merge all agent reports into a GO/NO-GO recommendation. The merged report must:

- **Separate evidence-backed findings from reasoning-only findings.** Findings that carry proof — a surviving mutation with the exact line and test that should have caught it, a demonstrated vacuous test with a concrete example, a verified-compromised oracle — are listed first and outrank findings that are reasoning or inference alone. Label each finding as *Proven* or *Suspected*.
- List **Blockers** (must fix before merge), with evidence type noted
- List **Recommended fixes**
- List **Acknowledged risks**
- Include a **Rollback plan**

Post the merged findings as inline PR review comments on the PR opened in Phase 5, using the same `/review-pr` posting mechanism. Post the GO/NO-GO summary as a top-level PR comment.

Present the final ship decision and PR URL to the user. Do not auto-merge — merge is a human decision.

## Rules

1. Always run phases in order: spec → plan → build → validate → converge → judge.
2. Checkpoint phases (spec, plan) require explicit user approval before continuing.
3. Everything after the plan checkpoint runs automatically without pausing, including the Phase 5 push and draft-PR creation.
4. If the user provides a spec or plan upfront, skip to the appropriate phase.
5. Commit after each task in the build phase, not at the end.
6. Phase 6 never auto-merges and never un-drafts. The draft PR stays open for the human to promote, review, and merge.
