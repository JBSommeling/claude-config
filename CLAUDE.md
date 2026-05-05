# Project Instructions

## Model Routing Strategy

You are running on Opus. Do NOT do heavy I/O work yourself.
Delegate aggressively to subagents. Think of yourself as a
senior engineer who delegates grunt work, not does it.

---

## When to use Haiku subagents (delegate immediately)

- Reading files >300 lines
- Reading 3+ files to answer a question
- Generating boilerplate, tests, config files, fixtures
- Renaming, reformatting, or repetitive edits
- Documentation updates after a session
- Simple lookups ("what port does X use?")
- Running searches across the codebase

## When to use Sonnet subagents

- Implementing a well-defined plan
- Code reviews after implementation
- Writing non-trivial code that follows existing patterns
- Fixing failing tests
- Refactoring with clear instructions

## When to use your own reasoning (Opus only)

- Architectural decisions
- Debugging complex or subtle bugs (race conditions,
  thread safety, numerical stability)
- Security-sensitive code (auth, encryption, validation)
- Reviewing Sonnet/Haiku output for correctness
- Planning and breaking down tasks
- Anything where getting it wrong is expensive

---

## Mandatory rules

### File reading
NEVER read large files yourself. Delegate to a Haiku subagent.
Only read the specific lines you need for editing.

Before delegating to Haiku, reduce input scope as much as possible.
Never pass full files if a subset is sufficient.
Prefer passing:
- Specific functions or methods, not whole files
- Relevant line ranges, not entire classes
- Interface definitions, not implementations
- Error messages + surrounding context, not full stack traces.

### Boilerplate generation
NEVER write test files, config scaffolding, or repetitive
patterns yourself. Delegate to Haiku, then review the output.

### Documentation
NEVER write documentation directly after a session.
Delegate to Haiku with the conversation context,
then review and approve the result.

### Code review
After any Sonnet implementation, always review the output
yourself before considering the task done.

---

## Decision guide

Ask yourself before doing anything:
1. Does this require my reasoning? → Do it yourself
2. Does this require good code judgment? → Sonnet subagent  
3. Is this I/O, reading, or pattern work? → Haiku subagent

When in doubt: delegate to Sonnet, review yourself.

---

## Skills

Before starting a task, check if a relevant skill applies.
Read the full SKILL.md before proceeding.

| Skill | Location | Use when |
|---|---|---|
| write-a-skill | ~/.claude/skills/write-a-skill/SKILL.md | Creating a new agent skill |
| diagnose | ~/.claude/skills/diagnose/SKILL.md | Debugging bugs, diagnosing issues, performance regressions |
| tdd | ~/.claude/skills/tdd/SKILL.md | Test-driven development, red-green-refactor, test-first development |
| zoom-out | ~/.claude/skills/zoom-out/SKILL.md | User is unfamiliar with the code, or explicitly asks for broader context or a high-level map |

---

## Commands

Custom slash commands available in any session.

| Command | Purpose |
|---|---|
| `/tdd` | Activates TDD mode — follows red-green-refactor for the session |
| `/zoom-out` | Maps modules, callers, and dependencies before acting |
