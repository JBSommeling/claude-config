---
description: Cross-repo rules for the pipeline commands — read only when a pipeline runs with repos=<path>
---

This file is a fragment read by `/full-pipeline` and `/full-pipeline-cycle` when they are invoked with `repos=<path>` — it is not a command to invoke on its own. Absent that parameter, none of it applies — single-repo runs skip this file entirely and follow the pipeline workflow file alone.

## Discovery and allocation

Only one path is supported. Relative paths resolve against `$HOME`; absolute and `~/` paths are used as given. The primary repo is always the repository containing the current working directory. Sibling repos are discovered as direct children of `<path>` that contain a `.git` entry. The spec allocates work across repos; the plan tags each task with its target repo; build and PR phases run per repo.

## Literal absolute paths

Every cross-repo git invocation uses a literal absolute path — never a shell variable. Literal paths provide uniformity (one rule covers all commands) and compatibility with the push guard's whitespace tokeniser. The guard inspects the raw command before the shell expands it, so a path held in a variable cannot resolve and the push is refused — a literal path avoids that. Later sections referring to "the literal-path rule" mean this.

## Phase 3 — Build

Before iterating repos, resolve every `[repo: <name>]` tag in the plan against the Repo Allocation approved at the spec checkpoint. If any tag has no match in the approved allocation, stop and report — do not create a branch or write in any repo not listed there.

When the plan carries `[repo: <name>]` tags, iterate repos in the plan's dependency order. For each repo:

1. Create a feature branch using a literal absolute path: `git -C /absolute/path/to/repo checkout -b <branch>` — per the literal-path rule.
2. Delegate that repo's tasks to the implementer subagent.
3. Orchestrator reviews the diff and commits inline using the same literal-path form — do not spawn a subagent solely to commit.
4. Invoke `/validate` for that repo before advancing to the next.

The orchestrator retains exclusive commit rights in every repo — this does not change per repo.

## Phase 3b — Simplify

When the plan carries `[repo: <name>]` tags, run the simplification pass in each participating repo, committing per repo using the literal-path rule.

## Phase 5 — Review loop (full-pipeline-cycle only)

When the plan carries `[repo: <name>]` tags, run the loop once per participating repo in the plan's dependency order, naming the repo explicitly: `/review-cycle cap=3 repo=/absolute/path/to/repo` — per the literal-path rule.

Each run returns its own residuals block. Keep them separate and tagged by repo: they belong to different pull requests. Every participating repo completes its loop before Step 2. A repo that caps with residuals does not stop the pipeline — its residuals travel to its own PR in Step 4.

After each participating repo's loop returns, the Step 1b `git status`, `git add`, and `git commit` commands require the `-C` flag with a literal absolute path — per the literal-path rule. The `-C` flag may be omitted for the primary repo.

## Phase 5 — Push and PR

Invoke `/branch-preflight` for every participating repo before pushing — not just the primary repo.

**Partial-failure policy:** All commits are already in from Phases 3, 3b, and 4. Do not push any repo until every participating repo has passed validation — a half-pushed cross-repo change is harder to roll back than an unpushed one.

When the plan carries `[repo: <name>]` tags:
- Repeat the push-and-PR steps for each participating repo in dependency order.
- Use a literal absolute path in every git command: `git -C /absolute/path/to/repo push ...` — per the literal-path rule.
- PR bodies cross-link only repos sharing the same host and organisation: use "N of M — depends on <PR URL>" for same-domain repos. For repos on a different host or org, substitute an opaque ordinal ("N of M") with no URL or repo name — publishing internal endpoints into an external PR body is irreversible. Flag a mixed-host run at the spec checkpoint.
- Merge order is stated in the PR body, never enforced automatically.

## Phase 5 — Post residuals (full-pipeline-cycle only)

Posting is GitHub-only. For a participating repo whose remote is Azure DevOps, do not attempt to post — print its residuals to the user instead, labelled with the repo name and its PR URL.

## Phase 6 — Judge

Phase 6 judges every participating repo's PR. The full judging set runs per repo, so agent count scales with repo count — state the total before spawning.

**Issue every Agent tool call, across every repo, in one assistant turn** — sequential calls defeat the purpose of parallel judging. Label each agent with its repo so its report can be attributed.

Merge each repo's reports into its own GO/NO-GO recommendation.

Decisions are per repo and independent — a NO-GO in one repo does not block the others. Two consequences follow, and both belong in the report. No judge sees more than one repo, so nothing in this phase evaluates the seams between them; a contract mismatch spanning two repos will not be found here. And merge order is stated in the PR bodies without being enforced, so acting on a single GO before its siblings are resolved can ship a partial change.

Automated comment posting via `gh api` is GitHub-only; for a repo whose remote is Azure DevOps, print its findings and its decision to the user instead of posting them.

**Fixing blockers (`/full-pipeline` only).** Fix each repo's blockers in that repo, and push to that repo's own PR branch. Use the `-C` form with a literal absolute path — per the literal-path rule:

```bash
git -C /absolute/path/to/repo add <specific files touched by the fixes>
git -C /absolute/path/to/repo commit -m "judge fixes (<N> blockers, <M> recommended)"
git -C /absolute/path/to/repo push
```

Invoke `/validate` for a repo before pushing its fixes. The one-pass rule still holds per repo — no judge re-runs anywhere.
