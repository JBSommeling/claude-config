---
description: Run the pre-launch checklist via parallel fan-out to specialist personas, then synthesize a go/no-go decision
---

Run the shipping checklist.

`/ship` is a **fan-out orchestrator**. It runs four specialist personas in parallel against the current change, then merges their reports into a single go/no-go decision with a rollback plan. The personas operate independently — no shared state, no ordering — which is what makes parallel execution safe and useful here.

## Phase A — Parallel fan-out

Spawn four subagents concurrently using the Agent tool. **Issue all four Agent tool calls in a single assistant turn so they execute in parallel** — sequential calls defeat the purpose of this command.

Each call selects the specialist by its `name` — `subagent_type` on Claude Code, the agent name on Codex:

1. **`code-reviewer`** — Run a five-axis review (correctness, readability, architecture, security, performance) on the staged changes or recent commits. Output the standard review template.
2. **`security-auditor`** — Run a vulnerability and threat-model pass. Check OWASP Top 10, secrets handling, auth/authz, dependency CVEs. Output the standard audit report.
3. **`test-engineer`** — Analyze test coverage for the change. Identify gaps in happy path, edge cases, error paths, and concurrency scenarios. Output the standard coverage analysis.
4. **`maintainer-reviewer`** — Judge the change through the five-year maintenance lens and the house-consistency lens. Requires reading sibling files and convention documents before judging. Output the standard maintainer review.

In other harnesses without an Agent tool, invoke each persona's system prompt sequentially and treat their outputs as if returned in parallel — the merge phase still works.

Constraints (both platforms):
- Subagents cannot spawn other subagents — do not let one specialist delegate to another.
- Each subagent gets its own context window and returns only its report to this main session.

**Agent resolution.** Agents you define in your own configuration take precedence over the shipped versions — `/ship` picks up your customizations automatically. User-defined agents always win over the built-in definitions by design.

## Phase B — Merge in main context

Once all four reports are back, the main agent (not a sub-persona) synthesizes them:

1. **Code Quality** — Aggregate Critical/Important findings from `code-reviewer` and any failing tests, lint, or build output. Resolve duplicates between reviewers.
2. **Security** — Promote any Critical/High `security-auditor` findings to launch blockers. Cross-reference with `code-reviewer`'s security axis.
3. **Performance** — Pull from `code-reviewer`'s performance axis; cross-check Core Web Vitals if applicable.
4. **Maintainability and consistency** — Take Critical/Important findings from `maintainer-reviewer`. Its findings overlap `code-reviewer`'s architecture axis at the edges — count a shared finding once, keeping whichever report cites a precedent. Its "existing practice worth revisiting" observations are never ship blockers; list them as follow-ups.
5. **Accessibility** — Verify keyboard nav, screen reader support, contrast (not covered by the fan-out personas — handle directly here, or invoke the accessibility checklist).
6. **Infrastructure** — Env vars, migrations, monitoring, feature flags. Verify directly.
7. **Documentation** — README, ADRs, changelog. Verify directly.

## Phase C — Decision and rollback

Produce a single output:

```markdown
## Ship Decision: GO | NO-GO

### Blockers (must fix before ship)
- [Source persona: Critical finding + file:line]

### Recommended fixes (should fix before ship)
- [Source persona: Important finding + file:line]

### Acknowledged risks (shipping anyway)
- [Risk + mitigation]

### Rollback plan
- Trigger conditions: [what signals would prompt rollback]
- Rollback procedure: [exact steps]
- Recovery time objective: [target]

### Specialist reports (full)
- [code-reviewer report]
- [security-auditor report]
- [test-engineer report]
- [maintainer-reviewer report]
```

## Rules

1. The four Phase A personas run in parallel — never sequentially.
2. Personas do not call each other. The main agent merges in Phase B.
3. The rollback plan is mandatory before any GO decision.
4. If any persona returns a Critical finding, the default verdict is NO-GO unless the user explicitly accepts the risk.
5. **Skip the fan-out only if all of the following are true:** the change touches 2 files or fewer, the diff is under 50 lines, and it does not touch auth, payments, data access, or config/env. Otherwise, default to fan-out. `/ship` is designed for production-bound changes — when the blast radius is non-trivial, run the parallel review even if the diff looks small.
