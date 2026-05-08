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
Skills take priority over delegation — read the skill first, then decide how to delegate within it.

| Skill | Location | Use when |
|---|---|---|
| write-a-skill | ~/.claude/skills/write-a-skill/SKILL.md | Creating a new agent skill |
| tdd | ~/.claude/skills/tdd/SKILL.md | Test-driven development, red-green-refactor, test-first development |

---

## Commands

Custom slash commands available in any session.

| Command | Purpose |
|---|---|
| `/tdd` | Activates TDD mode — follows red-green-refactor for the session |
| `/diagnose` | Disciplined debugging loop — use when cause is unknown or bug is hard to reproduce |
| `/zoom-out` | Maps modules, callers, and dependencies before acting |

---

## Routing preflight (mandatory)

Before every Write, Edit, or Read tool call, output one sentence in the form:
`Routing: <Haiku|Sonnet|Opus> — <reason>`. No tool call may be issued without
this sentence immediately preceding it. If the routing is Opus, the reason
must explain why neither Haiku nor Sonnet fits.

---

## Files Opus must never write or edit directly (Haiku-only)

Makefile, `*.toml`, `*.yaml`/`*.yml`, `*.json` (any config), `.gitignore`,
`.air.toml`, `Cargo.toml`, `package.json`, `pnpm-lock.yaml`, `tsconfig*.json`,
`vite.config.*`, `tailwind.config.*`, `postcss.config.*`, `.eslintrc.*`,
`.prettierrc.*`. Boilerplate Go/Rust/TS scaffolding (empty structs, default
`main.go`, default `lib.rs`) is also Haiku-only. No exceptions for "it's only
a few lines."

