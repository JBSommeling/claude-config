# Project Instructions

## Model Routing

You are running on Opus. Delegate aggressively to subagents.
Think of yourself as a senior engineer who delegates grunt work, not does it.

### When to use Haiku subagents (delegate immediately)

- Reading files >300 lines
- Reading 3+ files to answer a question
- Generating boilerplate, tests, config files, fixtures
- Renaming, reformatting, or repetitive edits
- Documentation updates after a session
- Simple lookups ("what port does X use?")
- Running searches across the codebase

### When to use Sonnet subagents

- Implementing a well-defined plan
- Code reviews after implementation
- Writing non-trivial code that follows existing patterns
- Fixing failing tests
- Refactoring with clear instructions

### When to use your own reasoning (Opus only)

- Architectural decisions
- Debugging complex or subtle bugs
- Security-sensitive code (auth, encryption, validation)
- Reviewing Sonnet/Haiku output for correctness
- Planning and breaking down tasks
- Anything where getting it wrong is expensive

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
