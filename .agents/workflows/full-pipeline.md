---
description: Full pipeline with no local review round — spec, plan, build, validate, draft PR, judge
---

Run the full development pipeline — spec, plan, build, validate — then open a draft PR and let Phase 6 judge it. There is no local review round: the review on the PR branch is the only one, and after its blockers are fixed the pipeline stops.

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

Do not proceed to Phase 5 until validation is fully green.

**Cross-repo (when `repos=` is absent, the above is the complete phase — skip this block).**

When the plan carries `[repo: <name>]` tags, run the validation steps above in each participating repo. Every repo must be fully green before the pipeline proceeds to Phase 5.

## Phase 5 — Push and open draft PR (automatic)

No review runs here. Phase 6 reviews the PR — that is the pipeline's only review pass.

### Step 0 — Branch safety precheck

Before reviewing, verify the current branch is not the repository's default branch (typically `main` or `master`):

```bash
default_branch=$(git ls-remote --symref origin HEAD 2>/dev/null \
  | awk '/^ref:/ { gsub("refs/heads/", "", $2); print $2; exit }')
if [ -z "$default_branch" ]; then
  remote_url=$(git remote get-url origin 2>/dev/null)
  if echo "$remote_url" | grep -q "github.com"; then
    default_branch=$(gh repo view --json defaultBranchRef \
      -q .defaultBranchRef.name 2>/dev/null)
  fi
fi
current_branch=$(git rev-parse --abbrev-ref HEAD)
```

`git ls-remote --symref` resolves the default branch host-agnostically; the `gh` fallback runs only for GitHub remotes, because `gh repo view` always errors on Azure DevOps ("none of the git remotes … point to a known GitHub host").

If `current_branch == default_branch`, automatically create a feature branch (`git checkout -b <suggested-name>`, deriving the name from the Phase 1 spec) and continue Phase 5 on the new branch. Do not push a PR from the default branch into itself.

**Fail-closed.** If neither method resolves the default branch — `git ls-remote` returns no `ref:` line and either the remote is not GitHub or `gh repo view` errors — treat that as unsafe and stop the pipeline. Do not fall back to assuming `main`. The PreToolUse hook `block-push.sh` provides a second layer of protection at the harness level, but the precheck must still refuse on indeterminate state.

### Step 1 — Report and prepare PR

Present to the user as a report (do not pause or wait for input):
- PR title (derived from the Phase 1 spec — describes the feature, not just the last commit)
- PR body (derived from the spec + the accumulated commit log since the branch diverged from the default branch)
- Target branch (always the repo default branch)

Then continue directly to Step 2 without waiting for approval.

### Step 2 — Push and open draft PR

Everything is already committed by this point (Phase 3 task commits, Phase 4 validation-fix commits). Step 2 is pure publication:

1. `git push` (with `--set-upstream origin <branch>` if no upstream)
2. Detect the remote host: `git remote get-url origin`. Open a draft PR — **always `--draft`**, no exceptions:
   - `github.com` → `gh pr create --draft --title "<derived title>" --body "<derived body>"`
   - `dev.azure.com` → `az repos pr create --draft --repository <repo-name> --source-branch <branch> --target-branch <default-branch> --title "<derived title>" --description "<derived body>"`
3. Capture the PR number and URL for Phase 6.

Do not run `git add` or `git commit` here — the tree must already be clean.
The PR is opened as a draft and stays a draft — never mark it ready for review.

**Cross-repo (when `repos=` is absent, the above is the complete step — skip this block).**

**Partial-failure policy:** All commits are already in from Phases 3 and 4. Do not push any repo until every participating repo has passed validation — a half-pushed cross-repo change is harder to roll back than an unpushed one.

When the plan carries `[repo: <name>]` tags, repeat steps 1–3 for each participating repo in dependency order. Use a literal absolute path in every git command: `git -C /absolute/path/to/repo push ...` — never a shell variable (same reason as Phase 3). PR bodies must cross-link all participating repos, state the merge order, and include "N of M — depends on <PR URL>" for each repo with upstream dependencies. Merge order is stated, never enforced.

## Phase 6 — Judge the PR and fix blockers (automatic)

### Step 1 — Judge

Spawn three subagents in parallel against the **PR's current state** (not the local working tree):

1. **code-reviewer** — five-axis review on the PR diff
2. **security-auditor** — vulnerability and threat-model pass
3. **test-engineer** — coverage gap analysis

Merge all reports into a GO/NO-GO recommendation with:
- Blockers (must fix before merge)
- Recommended fixes
- Acknowledged risks
- Rollback plan

Post the merged findings as inline PR review comments on the PR opened in Phase 5, using the `/review-pr` posting mechanism:
- Build payload with `line` + `side: "RIGHT"` (never `position`)
- Re-validate each line against the PR diff; drop any that don't match, log the drop
- Post via `gh api repos/{owner}/{repo}/pulls/{number}/reviews`

Post the GO/NO-GO summary as a top-level PR comment.

### Step 2 — Fix the important findings

Fix every **Blocker**, plus any **Recommended fix** that is straightforward and low-risk. Leave the rest on the PR for the human reviewer — they are already posted as inline comments.

Delegate every fix to the `implementer` subagent — pass only the specific findings (file, line, recommendation), never whole files. After the implementer returns, verify the diff yourself, then commit and push to the PR branch:

```bash
git add <specific files touched by the fixes>
git commit -m "judge fixes (<N> blockers, <M> recommended)"
git push
```

Re-run the test suite before pushing — the fixes must not regress Phase 4's green state.

**Stop here.** Do not re-run the judges, do not run `/review`, do not loop. One review pass against the PR is the whole review budget for this pipeline. If a fix in Step 2 is too large or too risky to land safely, do not fix it — say so in a reply on its PR comment and leave it for the human.

Present the final ship decision and PR URL to the user. Do not auto-merge — merge is a human decision.

## Rules

1. Always run phases in order: spec → plan → build → validate → PR → judge.
2. Checkpoint phases (spec, plan) require explicit user approval before continuing.
3. Everything after the plan checkpoint runs automatically without pausing, including the Phase 5 push and draft-PR creation.
4. If the user provides a spec or plan upfront, skip to the appropriate phase.
5. Commit after each task in the build phase, not at the end.
6. There is no local review round. Phase 6 is the only review, it runs exactly once, and the pipeline ends after its blockers are fixed — never re-review, never loop.
7. Phase 6 never auto-merges and never un-drafts. The draft PR stays open for the human to promote, review, and merge.
