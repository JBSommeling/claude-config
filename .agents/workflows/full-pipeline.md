---
description: Full pipeline with no local review round — spec, plan, build, validate, draft PR, judge
---

Run the full development pipeline — spec, plan, build, validate, simplify — then open a draft PR and let Phase 6 judge it. There is no local review round: the review on the PR branch is the only one, and after its blockers are fixed the pipeline stops.

## Arguments

`$ARGUMENTS` may include `repos=<path>` to run the pipeline across sibling repositories. When present, follow `/cross-repo` for every phase that has a section there. When absent, no discovery runs, no cross-repo work happens, and the rest of this file is complete on its own.

## Phase 1 — Spec (checkpoint)

Invoke the spec-driven-development skill. Write a structured specification for the requested feature.

When the spec is complete, present it to the user and ask for approval before continuing. Do not proceed until the user approves or requests changes. Iterate on the spec until approved.

Once approved, derive a kebab-case slug from the spec's feature title, create the directory `~/Desktop/<slug>/` (create it if it does not exist), and save the approved spec there as `spec.md`. Remember this directory for Phase 2.

## Phase 2 — Plan (checkpoint)

Invoke the planning-and-task-breakdown skill. Break the approved spec into ordered tasks with acceptance criteria and dependency ordering.

When the plan is complete, present it to the user and ask for approval before continuing. Do not proceed until the user approves or requests changes. Iterate on the plan until approved.

Once approved, save the approved plan as `plan.md` in the same `~/Desktop/<slug>/` directory created in Phase 1.

## Phase 3 — Build (automatic)

Before committing anything, invoke `/branch-preflight` for the primary repo. If it refuses or fails closed, stop the pipeline.

Invoke the incremental-implementation and tdd skills. For each task in the approved plan:

1. Read the task's acceptance criteria
2. Write a failing test (RED)
3. Implement minimum code to pass (GREEN)
4. Refactor if needed
5. Run full test suite — verify no regressions
6. Orchestrator commits directly inline via `git add` / `git commit` (Bash) after reviewing the diff — do not spawn a subagent solely to commit
7. Move to next task

If any task fails, follow debugging-and-error-recovery. Do not stop the pipeline — fix and continue.

**Cross-repo:** when running with `repos=`, also follow the matching section in `/cross-repo`.

## Phase 3b — Simplify (automatic)

Invoke `/code-simplify`, scoped to the code this pipeline run produced. Commit the result separately from the task commits — a reviewer can then read the feature commits without the cleanup mixed in.

Simplification runs before the validation gate so Phase 4 covers it. The pass runs tests inline after each change but never the build, linter, or type check, and one gate after all code changes is enough.

If the skill made no changes, there is nothing to commit.

**Cross-repo:** when running with `repos=`, also follow the matching section in `/cross-repo`.

## Phase 4 — Validate (automatic)

After all tasks are built and simplified, invoke `/validate`. Do not proceed until it reports fully green.

## Phase 5 — Push and open draft PR (automatic)

No review runs here. Phase 6 reviews the PR — that is the pipeline's only review pass.

### Step 0 — Branch safety precheck

Invoke `/branch-preflight` again to re-verify the repo before pushing. If it refuses or fails closed, stop the pipeline.

### Step 1 — Report and prepare PR

Present to the user as a report (do not pause or wait for input):
- PR title (derived from the Phase 1 spec — describes the feature, not just the last commit)
- PR body (derived from the spec + the accumulated commit log since the branch diverged from the default branch)
- Target branch (always the repo default branch)

Then continue directly to Step 2 without waiting for approval.

### Step 2 — Push and open draft PR

Everything is already committed by this point (Phase 3 task commits, Phase 3b simplification commit, Phase 4 validation-fix commits). Step 2 is pure publication:

1. `git push` (with `--set-upstream origin <branch>` if no upstream)
2. Derive `$pr_title` from the Phase 1 spec and write the PR body to a temporary file `$pr_body_file`. Parse the remote host: `remote_host=$(git remote get-url origin | sed 's|^[a-z]*://||; s|^[^@]*@||; s|[:/].*||')`. Open a draft PR — **always `--draft`**, no exceptions. Derived titles and bodies are passed via files or variables, never interpolated into the command string:
   - `remote_host` is `github.com`, or `gh auth status --hostname "$remote_host"` exits 0 → `gh pr create --draft --title "$pr_title" --body-file "$pr_body_file"`
   - `remote_host` is `dev.azure.com`, ends with `.visualstudio.com`, or is `vs-ssh.visualstudio.com` → `pr_body=$(cat "$pr_body_file")`, then `az repos pr create --draft true --repository <repo-name> --source-branch <branch> --target-branch <default-branch> --title "$pr_title" --description "$pr_body"`. Requires `--organization` and `--project` unless `az devops configure --defaults` has been set.
   - Any other host → stop and report. Do not improvise a PR command; draft-PR creation is not defined for this host.
3. Capture the PR number and URL for Phase 6.

Do not run `git add` or `git commit` here — the tree must already be clean.
The PR is opened as a draft and stays a draft — never mark it ready for review.

**Cross-repo:** when running with `repos=`, also follow the matching section in `/cross-repo`.

## Phase 6 — Judge the PR and fix blockers (automatic)

### Step 1 — Judge

Spawn four subagents in parallel against the **PR's current state** (not the local working tree).

1. **code-reviewer** — five-axis review on the PR diff
2. **security-auditor** — vulnerability and threat-model pass
3. **test-engineer** — coverage gap analysis
4. **maintainer-reviewer** — the five-year maintenance lens and the house-consistency lens

Merge the reports into a GO/NO-GO recommendation with:
- Blockers (must fix before merge)
- Recommended fixes
- Acknowledged risks
- Rollback plan

`maintainer-reviewer` overlaps `code-reviewer`'s architecture axis at the edges — count a shared finding once, keeping whichever report cites a precedent. Its "existing practice worth revisiting" observations are never blockers for this PR; carry them into the report as follow-up suggestions.

Post merged findings as inline review comments on the PR, using the `/review-pr` posting mechanism:
- Build payload with `line` + `side: "RIGHT"` (never `position`)
- Re-validate each line against that PR's diff; drop any that don't match, log the drop
- Post via `gh api repos/{owner}/{repo}/pulls/{number}/reviews`

Posting is GitHub-only. If the PR was opened on Azure DevOps, do not attempt to post — print the findings to the user instead, labelled with the PR URL.

Post the GO/NO-GO summary as a top-level comment on the PR.

**Cross-repo:** when running with `repos=`, also follow the matching section in `/cross-repo`.

### Step 2 — Fix the important findings

Fix every **Blocker**, plus any **Recommended fix** that is straightforward and low-risk. Leave the rest on the PR for the human reviewer — they are already posted as inline comments.

Delegate every fix to the `implementer` subagent — pass only the specific findings (file, line, recommendation), never whole files. After the implementer returns, verify the diff yourself, then commit and push to the PR branch:

```bash
git add <specific files touched by the fixes>
git commit -m "judge fixes (<N> blockers, <M> recommended)"
git push
```

Invoke `/validate` before pushing the fixes — they must not regress the green state Phase 4 established.

**Stop here.** Do not re-run the judges, do not run `/review`, do not loop. One review pass against the PR is the whole review budget for this pipeline. If a fix in Step 2 is too large or too risky to land safely, do not fix it — say so in a reply on its PR comment and leave it for the human.

Present the ship decision and PR URL to the user. Do not auto-merge — merge is a human decision.

## Rules

1. Always run phases in order: spec → plan → build → simplify → validate → PR → judge.
2. Checkpoint phases (spec, plan) require explicit user approval before continuing.
3. Everything after the plan checkpoint runs automatically without pausing, including the Phase 5 push and draft-PR creation.
4. If the user provides a spec or plan upfront, skip to the appropriate phase.
5. Commit after each task in the build phase, not at the end.
6. There is no local review round. Phase 6 is the only review, it runs exactly once, and the pipeline ends after its blockers are fixed — never re-review, never loop.
7. Phase 6 never auto-merges and never un-drafts. The draft PR stays open for the human to promote, review, and merge.
