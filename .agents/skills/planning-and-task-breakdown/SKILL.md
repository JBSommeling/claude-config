---
name: planning-and-task-breakdown
description: Breaks work into ordered tasks. Use when you have a spec or clear requirements and need to break work into implementable tasks. Use when a task feels too large to start, when you need to estimate scope, or when parallel work is possible.
---

# Planning and Task Breakdown

Decompose work into small, verifiable tasks with explicit acceptance criteria. Every task should be small enough to implement, test, and verify in a single focused session.

## The Planning Process

### Step 1: Enter Plan Mode

Before writing any code, operate in read-only mode:
- Read the spec and relevant codebase sections
- Identify existing patterns and conventions
- Map dependencies between components
- Note risks and unknowns

**Do NOT write code during planning.** The output is a plan document.

### Step 2: Map Dependencies

Implementation order follows the dependency graph bottom-up. Build foundations first.

### Step 3: Slice Vertically

Build one complete feature path at a time, not all database then all API then all UI.

Each vertical slice delivers working, testable functionality:
```
Task 1: User can create an account (schema + API + UI)
Task 2: User can log in (auth + API + UI)
Task 3: User can create a task (schema + API + UI)
```

### Step 4: Write Tasks

Each task needs:

```markdown
## Task [N]: [Short descriptive title]

**Acceptance criteria:**
- [ ] [Specific, testable condition]
- [ ] [Specific, testable condition]

**Verification:**
- [ ] Tests pass
- [ ] Build succeeds

**Dependencies:** [Task numbers or "None"]
**Estimated scope:** [S: 1-2 files | M: 3-5 files | L: 5+ files — break down further]
```

### Step 5: Add Checkpoints

After every 2-3 tasks, add a verification checkpoint:
```markdown
## Checkpoint: After Tasks 1-3
- [ ] All tests pass
- [ ] Application builds
- [ ] Core flow works end-to-end
```

## Task Sizing

| Size | Files | Agent handles well? |
|------|-------|---------------------|
| **S** | 1-2 | Yes |
| **M** | 3-5 | Yes |
| **L** | 5-8 | Break it down further |
| **XL** | 8+ | Must break down |

Break a task down when: >3 acceptance criteria, touches 2+ independent subsystems, or "and" appears in the title.

## Parallelization

- **Safe:** Independent feature slices, tests for implemented features, docs
- **Sequential:** Migrations, shared state, dependency chains
- **Needs coordination:** Features sharing an API contract (define contract first)

## Red Flags

- Starting implementation without a written task list
- Tasks without acceptance criteria
- No verification steps
- All tasks are L/XL-sized
- No checkpoints between tasks
- Dependency order not considered
