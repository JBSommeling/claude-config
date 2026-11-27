---
description: Full pipeline with auto-converging review loop — spec, plan, build, validate, converge (loop + draft PR), judge
---

Run the full development pipeline with a convergence-based review loop — spec, plan, build, validate, simplify — where Phase 5 auto-fixes until clean (or capped), opens a draft PR, and Phase 6 judges the cleaned-up state.

## Arguments

`$ARGUMENTS` may include `repos=<path>` to run the pipeline across sibling repositories. When present, follow `/cross-repo` for every phase that has a section there. When absent, no discovery runs, no cross-repo work happens, and the rest of this file is complete on its own.

`$ARGUMENTS` may include `--copilot` to have GitHub Copilot's rubber duck critique the spec and plan before each checkpoint, and the PR diff during judging. When present, follow `/copilot-rubber-duck` in Phases 1, 2, and 6. When absent, no critique runs. It combines with `repos=<path>`.

## Phase 1 — Spec (checkpoint)

Invoke the spec-driven-development skill. Write a structured specification for the requested feature.

When the spec is complete, if `--copilot` was passed, run the rubber-duck critique per `/copilot-rubber-duck` and fold it in before presenting. Then present it to the user and ask for approval before continuing. Do not proceed until the user approves or requests changes. Iterate on the spec until approved.

Once approved, derive a kebab-case `<slug>` from the spec's title and create `~/Desktop/<slug>/` (create it if it does not exist), which Phase 2 uses for `plan.md`. Save the spec following "Where the Spec Is Saved" in the spec-driven-development skill. When the user declines adoption, or there is no Repo profile and they choose to keep the current location, save it as `~/Desktop/<slug>/spec.md`. A spec saved inside the repo is not committed in Phase 1. The first task commit also includes the spec file and its index update when Phase 1 saved the spec inside the repo.

## Phase 2 — Plan (checkpoint)

Invoke the planning-and-task-breakdown skill. Break the approved spec into ordered tasks with acceptance criteria and dependency ordering.

Each task names the first rung of the smallest-change ladder (below) that covers it — already in this codebase, standard library or platform feature, installed dependency, or new code — and the existing code it reuses. A task that would add an abstraction, option, or dependency the spec does not require is cut or merged before the plan is presented.

When the plan is complete, if `--copilot` was passed, run the rubber-duck critique per `/copilot-rubber-duck` and fold it in before presenting. Then present it to the user and ask for approval before continuing. Do not proceed until the user approves or requests changes. Iterate on the plan until approved.

Once approved, save the approved plan as `plan.md` in the `~/Desktop/<slug>/` directory created in Phase 1.

## Phase 3 — Build (automatic)

Before committing anything, invoke `/branch-preflight` for the primary repo. If it refuses or fails closed, stop the pipeline.

### Smallest-change ladder

Before writing code for a task, read the code it touches and list every place the change must reach — callers, tests, fixtures, config, exports. Then take the first rung that fully works:

1. Does it need to exist? Skip features, options, and flexibility the spec did not ask for.
2. Already in this codebase (a helper, component, service, pattern)? Use it the way the surrounding code does.
3. Standard library or a platform feature? Use it, unless the project has its own.
4. An installed dependency? Use it. Never add a dependency for a few lines.
5. Otherwise, the minimum code that works, in the structure the codebase already has.

Lazy about the solution, never about the change: finish every caller, test, and fixture the change breaks. Never cut validation at trust boundaries, error handling that prevents data loss, security, accessibility, or anything the spec requires. The ladder does not relax the TDD steps below — every task still starts with a failing test.

### Per task

Invoke the incremental-implementation and tdd skills. For each task in the approved plan:

1. Read the task's acceptance criteria
2. Write a failing test (RED)
3. Implement minimum code to pass (GREEN)
4. Refactor if needed
5. Run full test suite — verify no regressions
6. Orchestrator commits directly inline via `git add` / `git commit` (Bash) after reviewing the diff — do not spawn a subagent solely to commit. The first task commit also includes the spec file and its index update when Phase 1 saved the spec inside the repo.
7. Move to next task

If a task adds or changes motion code, also invoke the `animate` skill (web) or the `animate-expo` skill (React Native/Expo) for that task. Motion code means — React Native: imports from `react-native-reanimated`, `react-native-gesture-handler`, `moti`, or `Animated` from `react-native`; web: `motion`/`framer-motion`, or CSS `transition`, `animation`, `@keyframes`, WAAPI `element.animate`.

If any task fails, follow debugging-and-error-recovery. Do not stop the pipeline — fix and continue.

**Cross-repo:** when running with `repos=`, also follow the matching section in `/cross-repo`.

## Phase 3b — Simplify (automatic)

Invoke `/code-simplify`, scoped to the code this pipeline run produced. Commit the result separately from the task commits — a reviewer can then read the feature commits without the cleanup mixed in.

Simplification runs before the validation gate so Phase 4 covers it. The pass runs tests inline after each change but never the build, linter, or type check, and one gate after all code changes is enough.

If the skill made no changes, there is nothing to commit.

**Cross-repo:** when running with `repos=`, also follow the matching section in `/cross-repo`.

## Phase 4 — Validate (automatic)

After all tasks are built and simplified, invoke `/validate`. Do not proceed until it reports fully green.

## Phase 5 — Converge (automatic)

### Step 0 — Branch safety precheck

Invoke `/branch-preflight` again to re-verify the repo before pushing. If it refuses or fails closed, stop the pipeline.

### Step 1 — Loop

Invoke `/review-cycle cap=3` for the primary repo. The cycle runs the five-axis review → fix loop, capped at 3 iterations, and returns a `<review-cycle-residuals>` block. Exit condition: zero Critical and zero Important findings, OR cap reached.

**Cross-repo:** when running with `repos=`, also follow the matching section in `/cross-repo`.

### Step 1b — Validate and commit review fixes

`/review-cycle` delegates fixes to the implementer subagent, which leaves changes uncommitted in the working tree. After the loop returns, check whether the working tree is dirty:

```bash
if [ -n "$(git status --porcelain)" ]; then
  # the loop changed code — re-validate before committing
  # invoke /validate, fix any failure, then commit
  git add <specific files touched by the loop>
  git commit -m "review-cycle fixes (<iterations> iterations, <N> residuals)"
fi
```

When the tree is dirty, invoke `/validate` before committing and do not proceed until it reports fully green. Phase 4's green result covers the code as it stood before the review loop — the fixes the loop applied have been validated by nothing. When the tree is clean the loop changed no code, Phase 4's result still holds, and no re-run is needed.

This maintains the invariant — like Phases 3, 3b, and 4 — that every step ends with a clean tree in the repo. After Step 1b, no further commits happen in Phase 5.

**Cross-repo:** when running with `repos=`, also follow the matching section in `/cross-repo`.

### Step 2 — Report and prepare PR

Parse the residuals block if present (it is only emitted when residuals are non-empty; absence means converged with zero residuals). Present to the user as a report (do not pause or wait for input):
- Iterations run, convergence status (converged / capped)
- Residuals list (if any) — these will be posted as PR comments
- PR title (derived from the Phase 1 spec — describes the feature, not just the last commit)
- PR body (derived from the spec + the accumulated commit log since the branch diverged from the default branch)
- Target branch (always the repo default branch)

Then continue directly to Step 3 without waiting for approval.

### Step 3 — Push and open draft PR

Everything is already committed by this point (Phase 3 task commits, Phase 3b simplification commit, Phase 4 validation-fix commits, Phase 5 Step 1b review-fix commit). Step 3 is pure publication:

1. `git push` (with `--set-upstream origin <branch>` if no upstream)
2. Derive `$pr_title` from the Phase 1 spec and write the PR body to a temporary file `$pr_body_file`. Parse the remote host: `remote_host=$(git remote get-url origin | sed 's|^[a-z]*://||; s|^[^@]*@||; s|[:/].*||')`. Open a draft PR — **always `--draft`**, no exceptions. Derived titles and bodies are passed via files or variables, never interpolated into the command string:
   - `remote_host` is `github.com`, or `gh auth status --hostname "$remote_host"` exits 0 → `gh pr create --draft --title "$pr_title" --body-file "$pr_body_file"`
   - `remote_host` is `dev.azure.com`, ends with `.visualstudio.com`, or is `vs-ssh.visualstudio.com` → `pr_body=$(cat "$pr_body_file")`, then `az repos pr create --draft true --repository <repo-name> --source-branch <branch> --target-branch <default-branch> --title "$pr_title" --description "$pr_body"`. Requires `--organization` and `--project` unless `az devops configure --defaults` has been set.
   - Any other host → stop and report. Do not improvise a PR command; draft-PR creation is not defined for this host.
3. Capture the PR number and URL for Phase 6.

Do not run `git add` or `git commit` here — the tree must already be clean.
The PR is opened as a draft and stays a draft — never mark it ready for review.

**Cross-repo:** when running with `repos=`, also follow the matching section in `/cross-repo`.

### Step 4 — Post residuals (if any)

If Step 1 emitted a `<review-cycle-residuals>` block, post its findings as inline review comments on the PR using the `/review-pr` posting mechanism:
- Parse `<review-cycle-residuals>` JSON verbatim
- Build payload with `line` + `side: "RIGHT"` (never `position`)
- Re-validate each line against that PR's diff; drop any that don't match, log the drop
- Post via `gh api repos/{owner}/{repo}/pulls/{number}/reviews`

Posting is GitHub-only. If the PR was opened on Azure DevOps, do not attempt to post — print the findings to the user instead, labelled with the PR URL.

**Cross-repo:** when running with `repos=`, also follow the matching section in `/cross-repo`.

## Phase 6 — Judge (automatic)

Spawn the judging subagents in parallel against the **PR's current state** (not the local working tree) — four subagents, or three where `code-reviewer` is skipped per the note below.

1. **code-reviewer** — five-axis review on the PR diff. **Skip this agent when the Phase 5 Step 1 loop converged with zero Critical and zero Important findings** — the same agent passed the code moments earlier and the PR diff has not changed since. Run it when the loop hit its cap or left residuals.
2. **security-auditor** — vulnerability and threat-model pass
3. **test-engineer** — coverage gap analysis
4. **maintainer-reviewer** — the five-year maintenance lens and the house-consistency lens

If `--copilot` was passed, also run the diff critique per `/copilot-rubber-duck` alongside the subagents, and merge the findings that hold up into the report. It runs even when `code-reviewer` is skipped.

Merge the reports into a GO/NO-GO recommendation with:
- Blockers (must fix before merge)
- Recommended fixes
- Acknowledged risks
- Rollback plan

`maintainer-reviewer` overlaps `code-reviewer`'s architecture axis at the edges — count a shared finding once, keeping whichever report cites a precedent. Its "existing practice worth revisiting" observations are never blockers for this PR; carry them into the report as follow-up suggestions.

Post merged findings as inline review comments on the PR using the same `/review-pr` posting mechanism. Post the GO/NO-GO summary as a top-level comment on the PR. Posting is GitHub-only — for an Azure DevOps PR, print the findings and the decision to the user instead.

Present the ship decision and PR URL to the user. Do not auto-merge — merge is a human decision.

**Cross-repo:** when running with `repos=`, also follow the matching section in `/cross-repo`.

## Rules

1. Always run phases in order: spec → plan → build → simplify → validate → converge → judge.
2. Checkpoint phases (spec, plan) require explicit user approval before continuing.
3. Everything after the plan checkpoint runs automatically without pausing, including the Phase 5 push and draft-PR creation.
4. If the user provides a spec or plan upfront, skip to the appropriate phase.
5. Commit after each task in the build phase, not at the end.
6. Phase 6 never auto-merges and never un-drafts. The draft PR stays open for the human to promote, review, and merge.
