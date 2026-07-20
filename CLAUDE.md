# Project Instructions

## Model Routing

You are running on Opus. You MUST delegate to subagents for all work that does not require Opus-level reasoning. Do NOT do grunt work yourself — you are a senior engineer who reviews and decides, not implements.

### Haiku subagents — MUST delegate immediately

- Reading files >300 lines
- Reading 3+ files to answer a question
- Generating boilerplate, tests, config files, fixtures
- Renaming, reformatting, or repetitive edits
- Documentation updates after a session
- Simple lookups ("what port does X use?")
- Running searches across the codebase

### Sonnet subagents — MUST delegate

- Implementing a well-defined plan
- Writing non-trivial code that follows existing patterns
- Fixing failing tests
- Refactoring with clear instructions
- Writing tests and test coverage analysis

**Model pinning.** The Sonnet tier is pinned to `claude-sonnet-4-6` (see the `implementer` and `test-engineer` definitions in `.claude/agents/`), not the bare `sonnet` alias. The alias now resolves to Sonnet 5, whose new tokenizer (~30% more tokens for the same text) and adaptive-thinking-on-by-default increase token spend for implementation work; pinning to 4.6 restores the cheaper behavior. Opus and Haiku tiers are unaffected.

### Opus subagents — SHOULD delegate unless context is already loaded

- Code reviews (use code-reviewer agent)
- Security audits (use security-auditor agent)

### Opus inline — MUST handle directly, never delegate

- Security-sensitive code (auth, encryption, validation)
- Architectural decisions
- Debugging complex or subtle bugs
- Reviewing Sonnet/Haiku output for correctness
- Planning and breaking down tasks
- Anything where getting it wrong is expensive
- When context is already loaded and re-reading via subagent would be wasteful

If a task fits a subagent category above, delegate it. Do NOT do it inline to save time — delegate to save tokens. The only valid reason to skip delegation is when you already have the full context loaded and spawning a subagent would mean re-reading the same files.

**Enforcement.** A `PreToolUse` hook (`~/.claude/hooks/enforce-delegation.sh`) blocks `Edit`, `Write`, `MultiEdit`, and `NotebookEdit` when called from the main Opus session. Subagent calls pass through (the hook detects them via the `agent_type` field). Memory writes under `~/.claude/projects/*/memory/` are also allowed. To bypass for a single shell session, start Claude with `CLAUDE_BYPASS_DELEGATION=1 claude ...` — use sparingly, and only when the edit is genuinely too trivial to delegate.

Before delegating, reduce input scope — pass specific functions or line ranges, not whole files.

After any Sonnet implementation, review the output yourself before considering the task done.

### Subagent escalation

If a delegated task fails or freezes, retry with next higher model immediately:
- Haiku failure → Sonnet
- Sonnet failure → Opus (do it yourself)

---

## Git Safety

A `PreToolUse` hook (`~/.claude/hooks/block-push-to-default-branch.sh`) blocks any `git push` whose target resolves to the repository's default branch. This hook is the sole guardrail. To bypass for a single session, set `CLAUDE_BYPASS_PUSH_GUARD=1`.

---

## Skills & Commands

Before starting a task, check if a relevant skill applies.
Read the full SKILL.md before proceeding.
Skills take priority over delegation — read the skill first, then decide how to delegate within it.

Available skills: check `~/.claude/skills/`
Available commands: check `~/.claude/commands/`

### Full pipeline

`/full-pipeline` runs: `/spec` → `/plan` → `/build` (loop) → `/validate` → `/review` → `/ship`. Checkpoints after spec and plan, then automatic.

`/full-pipeline-cycle` is a variant where Phase 5 runs `/review-cycle` (auto-fix loop, capped at 5 iterations), opens a PR with any residual findings posted as inline comments, and Phase 6 judges via three parallel subagents. Spec and plan checkpoints only — everything after the plan, including push and PR creation, runs automatically.

`/diagnose-full-pipeline-cycle` chains the two: it runs `/diagnose` (diagnose-only) to confirm the bug's root cause, then feeds that diagnosis into `/full-pipeline-cycle` to spec, plan, build, and open a PR with the fix.

Both pipelines save the approved spec and plan to `~/Desktop/<feature-slug>/` as `spec.md` and `plan.md`.
