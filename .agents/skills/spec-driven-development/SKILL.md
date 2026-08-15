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

## Cross-Repo Context (optional)

**Skip this section entirely when `repos=` is absent.** No discovery, no subagents, no extra spec sections — this is the most important rule.

When `repos=<path>` appears in `$ARGUMENTS`:

- Relative paths resolve against `$HOME` (`Development/tba` → `$HOME/Development/tba`); absolute and `~/`-prefixed paths are used as-is. The path is used exactly as given — on case-sensitive filesystems the case must match exactly.
- If the resolved path does not exist or contains no git repositories, skip discovery and continue as a single-repo run without failing.
- The primary repo is always `$PWD`; it is not overridable.
- Discover candidates: direct children of `<path>` that contain a `.git` entry at their own root. `*.worktrees` directories have no `.git` at their own root and are excluded without special-casing. `$PWD` is always excluded from candidates — it is the primary repo and always participates.

**Scan — up to 10 read-only subagents in parallel, on the cheap search tier:**

- Pass feature keywords extracted from the user's request; each scanner greps for them. Keyword-scoped grep keeps output bounded — scanners do not summarise the whole repo.
- Each scanner returns: repo name, one-line purpose, stack, public surface (API routes, exported packages, published or consumed events), and a relevance verdict of `none` / `low` / `high` with supporting evidence.
- Drop `none` repos immediately. They do not appear in the spec or any downstream phase.
- If the candidate count exceeds 10, scan the first 10 and report the remainder as unscanned — they are not silently dropped.
- Scanners are read-only: they report, they do not edit.

### Phase 1: Specify

**Surface assumptions immediately:**
```
ASSUMPTIONS I'M MAKING:
1. This is a web application (not native mobile)
2. Authentication uses session-based cookies
3. Database is PostgreSQL (based on existing schema)
→ Correct me now or I'll proceed with these.
```

**Write a spec. Areas 1–6 always apply; include area 7 when `repos=` was supplied:**

1. **Objective** — What, why, for whom, success criteria
2. **Commands** — Full executable commands (build, test, lint, dev)
3. **Project Structure** — Where source, tests, and docs live
4. **Code Style** — One real code snippet showing style beats paragraphs describing it
5. **Testing Strategy** — Framework, locations, coverage expectations
6. **Boundaries:**
   - Always do: [non-negotiable rules]
   - Ask first: [needs human approval]
   - Never do: [hard constraints]
7. **Repo Allocation** *(when `repos=` was supplied)* — per participating repo: what changes there, why it belongs there rather than elsewhere, and the contract it exposes or consumes.

When a Repo Allocation is present, tag acceptance criteria per repo so "done" is defined for each one. The spec checkpoint is where the user confirms the allocation — it is the architectural decision in the change.

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
