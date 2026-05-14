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

### Opus subagents — MUST delegate

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

Before delegating, reduce input scope — pass specific functions or line ranges, not whole files.

After any Sonnet implementation, review the output yourself before considering the task done.

### Subagent escalation

If a delegated task fails or freezes, retry with next higher model immediately:
- Haiku failure → Sonnet
- Sonnet failure → Opus (do it yourself)

---

## Skills & Commands

Before starting a task, check if a relevant skill applies.
Read the full SKILL.md before proceeding.
Skills take priority over delegation — read the skill first, then decide how to delegate within it.

Available skills: check `~/.claude/skills/`
Available commands: check `~/.claude/commands/`

### Full pipeline

`/full-pipeline` runs: `/spec` → `/plan` → `/build` (loop) → `/validate` → `/review` → `/ship`. Checkpoints after spec and plan, then automatic.
