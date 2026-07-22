---
description: BETA — Diagnose a bug, then run the adversarial-lens pipeline to spec, plan, build, and PR the fix
---

> **BETA variant of `/diagnose-full-pipeline-cycle`.**
> One substantive change: Stage 2 chains to `/full-pipeline-cycle-beta` instead of `/full-pipeline-cycle`. This means the judging phase uses six parallel agents with adversarial test lenses rather than three. Everything in Stage 1 is identical to the original.

Chain two existing commands to go from a reported bug all the way to a PR'd fix. Stage 1 diagnoses (no fix); Stage 2 specs, plans, builds, and ships the fix through the adversarial-lens pipeline.

## Stage 1 — Diagnose (via `/diagnose`)

Run `/diagnose` in its diagnose-only mode. Build a feedback loop, confirm the root cause through Phases 1–4, and run Phase 6 cleanup. Do NOT fix the bug here — Stage 2 owns the fix.

Capture the diagnosis for handoff to Stage 2:
- The confirmed root cause
- The evidence / reproduction that proves it
- The affected files and functions
- The feedback loop you built (Stage 2 reuses it as the failing test to verify the fix)

If Stage 1 cannot confirm a root cause (no reliable feedback loop, or the cause stays unresolved), STOP and report. Do not proceed to Stage 2 on a guess — a spec built on the wrong cause wastes the whole pipeline.

## Stage 2 — Fix (via `/full-pipeline-cycle-beta`)

Run `/full-pipeline-cycle-beta`, using the Stage 1 diagnosis as the feature request. The diagnosis is the input to Phase 1 — the pipeline specs and builds the FIX, not a new feature:

- **Phase 1 — Spec (checkpoint):** Specify the fix. Objective = eliminate the confirmed root cause. Acceptance criteria MUST include: the Stage 1 reproduction no longer reproduces, and a regression test exists at the correct seam. Feed in the affected files and the diagnosis evidence. Pauses for your approval, then saves `spec.md` to the Desktop folder.
- **Phase 2 — Plan (checkpoint):** Break the fix into ordered tasks. Pauses for your approval, then saves `plan.md` to the same Desktop folder.
- **Phases 3–6 (automatic):** Build (TDD — reuse the Stage 1 feedback loop as the failing test wherever possible), validate, converge (`/review-cycle` → push → open PR), and judge with adversarial test lenses. No further pauses; ends at an open PR for human merge.
