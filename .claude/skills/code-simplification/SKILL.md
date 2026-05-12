---
name: code-simplification
description: Simplifies code for clarity. Use when refactoring code for clarity without changing behavior. Use when code works but is harder to read, maintain, or extend than it should be.
---

# Code Simplification

Reduce complexity while preserving exact behavior. The goal is not fewer lines — it's code that is easier to read, understand, modify, and debug.

## Five Principles

1. **Preserve behavior exactly** — same outputs, same errors, same side effects. If unsure, don't change it.
2. **Follow project conventions** — match the codebase style, not your preferences. Inconsistency is not simplification.
3. **Prefer clarity over cleverness** — explicit > compact when compact requires mental parsing.
4. **Maintain balance** — don't over-simplify. Removing a well-named helper makes call sites harder to read.
5. **Scope to what changed** — simplify recently modified code. Avoid drive-by refactors of unrelated code.

## Simplification Patterns

**Structural:**

| Pattern | Simplification |
|---------|----------------|
| Deep nesting (3+ levels) | Guard clauses or extract helper functions |
| Long functions (50+ lines) | Split into focused functions |
| Nested ternaries | Replace with if/else or lookup objects |
| Boolean parameter flags | Options objects or separate functions |
| Repeated conditionals | Extract to named predicate function |

**Naming:**

| Pattern | Simplification |
|---------|----------------|
| Generic names (`data`, `result`, `temp`) | Rename to describe content |
| Comments explaining "what" | Delete — code is clear enough |
| Comments explaining "why" | Keep — they carry intent code can't express |
| Misleading names | Rename to reflect actual behavior |

**Redundancy:**

| Pattern | Simplification |
|---------|----------------|
| Duplicated logic (5+ lines) | Extract to shared function |
| Dead code, commented-out blocks | Remove (after confirming truly dead) |
| Wrapper that adds no value | Inline it |
| Over-engineered patterns | Replace with direct approach |

## Process

### 1. Understand Before Touching (Chesterton's Fence)

Before removing anything, understand why it exists. Check git blame. If you can't answer why it was written this way, you're not ready to simplify.

### 2. Apply Changes Incrementally

One simplification at a time. Run tests after each. Submit refactoring separately from feature or bug fix changes.

### 3. Verify

- Is the simplified version genuinely easier to understand?
- Is the diff clean and reviewable?
- Did any tests need modification? (If yes, you likely changed behavior.)

## Red Flags

- Simplification that requires modifying tests to pass
- "Simplified" code that is longer or harder to follow
- Renaming to match your preferences rather than project conventions
- Removing error handling because "it makes the code cleaner"
- Simplifying code you don't fully understand
- Refactoring code outside the current task scope without being asked
