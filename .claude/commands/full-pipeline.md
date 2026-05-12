---
description: Full development pipeline — spec, plan, build, review, ship. Checkpoints after spec and plan.
---

Run the full development pipeline for the user's feature request. Follow each phase in order.

## Phase 1 — Spec (checkpoint)

Invoke the spec-driven-development skill. Write a structured specification for the requested feature.

When the spec is complete, present it to the user and ask for approval before continuing. Do not proceed until the user approves or requests changes. Iterate on the spec until approved.

## Phase 2 — Plan (checkpoint)

Invoke the planning-and-task-breakdown skill. Break the approved spec into ordered tasks with acceptance criteria and dependency ordering.

When the plan is complete, present it to the user and ask for approval before continuing. Do not proceed until the user approves or requests changes. Iterate on the plan until approved.

## Phase 3 — Build (automatic)

Invoke the incremental-implementation and tdd skills. For each task in the approved plan:

1. Read the task's acceptance criteria
2. Write a failing test (RED)
3. Implement minimum code to pass (GREEN)
4. Refactor if needed
5. Run full test suite — verify no regressions
6. Commit with descriptive message
7. Move to next task

If any task fails, follow debugging-and-error-recovery. Do not stop the pipeline — fix and continue.

## Phase 4 — Validate (automatic)

After all tasks are built, run a full validation pass:

1. Run the complete test suite — all tests must pass, not just per-task tests
2. Run build/compile check — verify the project builds cleanly
3. Run linter/formatter if configured in the project
4. Check for type errors if the project uses a type system

If any step fails, fix the issue and re-run validation until everything passes. Commit fixes separately with clear messages.

Do not proceed to review until validation is fully green.

## Phase 5 — Review (automatic)

Invoke the code-review skill. Run a five-axis review (correctness, readability, architecture, security, performance) on all changes since the pipeline started.

If Critical findings are found, fix them before proceeding. Important findings: fix if straightforward, otherwise note for the ship decision.

## Phase 6 — Ship (automatic)

Spawn three subagents in parallel:

1. **code-reviewer** — five-axis review on final state
2. **security-auditor** — vulnerability and threat-model pass
3. **test-engineer** — coverage gap analysis

Merge all reports into a GO/NO-GO decision with:
- Blockers (must fix)
- Recommended fixes
- Acknowledged risks
- Rollback plan

Present the final ship decision to the user.

## Rules

1. Always run phases in order: spec → plan → build → validate → review → ship.
2. Checkpoint phases (spec, plan) require explicit user approval before continuing.
3. Automatic phases (build, validate, review, ship) run without pausing.
4. If the user provides a spec or plan upfront, skip to the appropriate phase.
5. Commit after each task in the build phase, not at the end.
