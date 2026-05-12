---
name: incremental-implementation
description: Delivers changes incrementally. Use when implementing any feature or change that touches more than one file. Use when a task feels too big to land in one step.
---

# Incremental Implementation

Build in thin vertical slices — implement one piece, test it, verify it, commit, then expand. Each increment leaves the system in a working, testable state.

## The Increment Cycle

```
Implement → Test → Verify → Commit → Next slice
```

For each slice:
1. **Implement** the smallest complete piece of functionality
2. **Test** — run the test suite (or write a test if none exists)
3. **Verify** — tests pass, build succeeds
4. **Commit** — descriptive message
5. **Next slice** — carry forward, don't restart

## Slicing Strategies

**Vertical slices (preferred):** One complete path through the stack per slice. Each delivers working end-to-end functionality.

**Risk-first:** Tackle the riskiest or most uncertain piece first. If it fails, you discover it before investing in the rest.

**Contract-first:** Define API contract first, then backend and frontend can develop in parallel against it.

## Rules

### Simplicity First
Before writing any code: "What is the simplest thing that could work?" Three similar lines is better than a premature abstraction. Implement the naive, obviously-correct version first.

### Scope Discipline
Touch only what the task requires. Don't clean up adjacent code, refactor imports in files you're not modifying, or add features not in the spec. If you notice something worth improving, note it — don't fix it.

### One Thing at a Time
Each increment changes one logical thing. Don't mix a new component, a refactor, and a config change in one commit.

### Keep It Compilable
After each increment, the project must build and existing tests must pass.

## Increment Checklist

After each increment:
- [ ] The change does one thing and does it completely
- [ ] All existing tests still pass
- [ ] The build succeeds
- [ ] The new functionality works as expected
- [ ] The change is committed with a descriptive message

## Red Flags

- More than 100 lines written without running tests
- Multiple unrelated changes in a single increment
- Skipping test/verify step to move faster
- Build or tests broken between increments
- Building abstractions before the third use case demands it
- Touching files outside task scope "while I'm here"
