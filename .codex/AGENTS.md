# Project Instructions

## Model Routing

You are the orchestrator. You MUST delegate to specialist agents for all work that does not require high-reasoning orchestration. Do NOT do grunt work yourself — you plan, review, and decide; specialists implement.

### Low-effort agents — MUST delegate immediately

- Reading files
- Reading multiple files to answer a question
- Generating boilerplate, tests, config files, fixtures
- Renaming, reformatting, or repetitive edits
- Documentation updates after a session
- Simple lookups ("what port does X use?")
- Running searches across the codebase

### Medium-effort agents — MUST delegate

- Implementing a well-defined plan
- Writing non-trivial code that follows existing patterns
- Fixing failing tests
- Refactoring with clear instructions
- Writing tests and test coverage analysis

### High-effort agents — SHOULD delegate unless context is already loaded

- Code reviews (use code-reviewer agent)
- Security audits (use security-auditor agent)

### Orchestrator inline — MUST handle directly, never delegate

- Security-sensitive code (auth, encryption, validation)
- Architectural decisions
- Debugging complex or subtle bugs
- Reviewing specialist output for correctness
- Planning and breaking down tasks
- Anything where getting it wrong is expensive
- When context is already loaded and re-reading via subagent would be wasteful

If a task fits a specialist category above, delegate it. Do NOT do it inline to save time — delegate to save tokens. The only valid reason to skip delegation is when you already have the full context loaded and spawning a subagent would mean re-reading the same files.

Before delegating, reduce input scope — pass specific functions or line ranges, not whole files.

After any medium-effort implementation, review the output yourself before considering the task done.

### Subagent escalation

If a delegated task fails or freezes, retry with the next higher reasoning effort immediately:
- Low-effort failure → medium effort
- Medium-effort failure → orchestrator (do it yourself)

---

## Delegation Contract

**This is a behavioural rule enforced by convention and the ledger report, not by a blocking hook.**

The orchestrator plans and decomposes tasks into well-defined units. Specialist agents implement those units. The orchestrator reviews the output and commits the result. No specialist agent ever commits directly.

Specifically:
1. The orchestrator identifies what needs to be done and produces a clear plan.
2. The orchestrator spawns specialist agents to execute discrete, well-defined steps.
3. The orchestrator reviews every diff before accepting it.
4. The orchestrator runs `git add` and `git commit` inline, never via a specialist.

Violating this contract — an agent editing files without an active delegation window, or committing directly — will appear in the ledger report at the end of the session.

### Enforcement model

> **Current:** Detective, due to current Codex payload limitations.
> **Upgrade path:** If Codex exposes a worker-unique identifier, `adapter-codex.sh` enables preventive enforcement with no change to shared policy or repository structure.
> **Not available:** Root sandboxing, by design — the orchestrator must retain commit access.

On Claude Code, the delegation guard is preventive: a `PreToolUse` hook distinguishes orchestrator from subagent via `agent_id` / `agent_type` in the hook payload and blocks edits from the wrong level. On Codex, those fields are not reliably present in the shipped release (see ADR 0003). Shipping preventive enforcement against unverified fields risks blocking every subagent edit. We therefore ship delegation enforcement as detective: the ledger appends records on `PreToolUse` for `apply_patch` and `spawn_agent`, and reports at `Stop` any edits occurring outside a delegation window.

**Fail-open on unknown callers.** The shared `enforce-delegation.sh` guard denies only when the caller resolves to `root`; both `subagent` and `unknown` callers pass. On Codex in the default (non-strict) mode, `agent_id`/`agent_type` are absent so *every* caller resolves to `unknown` — meaning the preventive path is inert for delegation and the ledger is the sole delegation check. This is intentional (ADR 0003): blocking on unverified identity would break every legitimate subagent edit. Do not read "delegation is enforced on Codex" as "undelegated edits are blocked on Codex" — they are recorded and reported, not prevented.

---

## Git Safety

A `PreToolUse` hook (`~/.codex/hooks/block-push.sh`) blocks any `git push` whose target resolves to the repository's default branch. This hook is the sole guardrail. To bypass for a single session, set `CODEX_BYPASS_PUSH_GUARD=1`.

**Commits.** The orchestrator commits directly, inline, via `git add` / `git commit` after reviewing the implementer's diff. Never spawn an agent whose sole purpose is to run a commit — delegating a commit-only task wastes a full context-load for a one-line command.

---

## Skills & Commands

Before starting a task, check if a relevant skill applies.
Read the full SKILL.md before proceeding.
Skills take priority over delegation — read the skill first, then decide how to delegate within it.

Available skills: check `~/.agents/skills/`

Invoke a skill via `$skillname` — for example, `$full-pipeline-cycle` to run the full delivery pipeline.

### Full pipeline

`$full-pipeline-cycle` runs the full development pipeline with a convergence-based review loop: spec, plan, build, validate, then Phase 5 auto-fixes until clean (or capped), opens a PR, and Phase 6 judges via three parallel subagents. Spec and plan checkpoints only — everything after the plan, including push and PR creation, runs automatically.

`$diagnose-full-pipeline-cycle` chains the two: it runs `$diagnose` (diagnose-only) to confirm the bug's root cause, then feeds that diagnosis into `$full-pipeline-cycle` to spec, plan, build, and open a PR with the fix.

Both save the approved spec and plan to `~/Desktop/<feature-slug>/` as `spec.md` and `plan.md`.
