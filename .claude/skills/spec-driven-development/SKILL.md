---
name: spec-driven-development
description: Creates specs before coding. Use when starting a new project, feature, or significant change and no specification exists yet. Use when requirements are unclear, ambiguous, or only exist as a vague idea.
---

# Spec-Driven Development

Write a structured specification before writing any code. The spec defines what we're building, why, and how we'll know it's done.

## Gated Workflow

Four phases. Do not advance until current phase is validated by the user.

```
SPECIFY → PLAN → TASKS → IMPLEMENT
   ↓        ↓      ↓        ↓
 Review   Review  Review   Review
```

### Phase 1: Specify

**Surface assumptions immediately:**
```
ASSUMPTIONS I'M MAKING:
1. This is a web application (not native mobile)
2. Authentication uses session-based cookies
3. Database is PostgreSQL (based on existing schema)
→ Correct me now or I'll proceed with these.
```

**Write a spec covering six areas:**

1. **Objective** — What, why, for whom, success criteria
2. **Commands** — Full executable commands (build, test, lint, dev)
3. **Project Structure** — Where source, tests, and docs live
4. **Code Style** — One real code snippet showing style beats paragraphs describing it
5. **Testing Strategy** — Framework, locations, coverage expectations
6. **Boundaries:**
   - Always do: [non-negotiable rules]
   - Ask first: [needs human approval]
   - Never do: [hard constraints]

**Reframe vague requirements as testable success criteria:**
```
"Make the dashboard faster"
→ LCP < 2.5s on 4G, initial load < 500ms, CLS < 0.1
→ Are these the right targets?
```

### Phase 2: Plan

With validated spec, generate technical implementation plan:
- Major components and dependencies
- Implementation order
- Risks and mitigations
- What can parallelize vs. must be sequential

### Phase 3: Tasks

Break plan into discrete tasks. Each task:
- Completable in one focused session
- Has acceptance criteria
- Has verification step
- Touches ~5 files or fewer
- Ordered by dependency

### Phase 4: Implement

Execute tasks one at a time following the `incremental-implementation` and `tdd` skills. Load the right spec sections and source files at each step rather than flooding the context with the entire spec.

## Keeping the Spec Alive

- Update when decisions or scope change
- Commit the spec to version control
- Reference spec sections in PRs

## Red Flags

- Starting code without written requirements
- Implementing features not in any spec
- Making architectural decisions without documenting them
- Skipping the spec because "it's obvious"
