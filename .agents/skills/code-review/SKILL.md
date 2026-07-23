---
name: code-review
description: Conducts code review — inline or via dispatched subagent. Use before merging any change, after completing major features, or when reviewing code written by yourself, another agent, or a human.
---

# Code Review

**Approval standard:** Approve when the change definitely improves overall code health, even if it isn't perfect. Don't block because it isn't how you would have written it.

**Core principle:** Review early, review often.

## The Five-Axis Review

### 1. Correctness
- Does it match the spec or task requirements?
- Are edge cases handled (null, empty, boundary values)?
- Are error paths handled (not just happy path)?
- Do tests cover the change adequately?

### 2. Readability
- Are names descriptive and consistent with project conventions?
- Is control flow straightforward?
- Could this be done in fewer lines without sacrificing clarity?
- Are abstractions earning their complexity?
- Any dead code artifacts (unused variables, commented-out blocks)?

### 3. Architecture
- Does it follow existing patterns or introduce a justified new one?
- Does it maintain clean module boundaries?
- Is the abstraction level appropriate?

### 4. Security
- Is user input validated and sanitized?
- Are secrets kept out of code, logs, and version control?
- Is auth checked where needed?
- Are SQL queries parameterized?
- Is external data treated as untrusted?

### 5. Performance
- Any N+1 query patterns?
- Any unbounded loops or unconstrained data fetching?
- Any missing pagination on list endpoints?

## Severity Labels

| Prefix | Meaning | Author Action |
|--------|---------|---------------|
| *(none)* | Required change | Must address before merge |
| **Critical:** | Blocks merge | Security vulnerability, data loss, broken functionality |
| **Nit:** | Minor, optional | Author may ignore |
| **Optional:** | Suggestion | Worth considering but not required |
| **FYI** | Informational | No action needed |

## Review Modes

### Inline Review (quick check during development)

Review the current changes directly in this session:

1. **Context** — Understand intent before looking at code
2. **Tests first** — Tests reveal intent and coverage gaps
3. **Implementation** — Walk through with five axes in mind
4. **Categorize** — Label every finding with severity
5. **Verify** — Check tests pass, build succeeds

### Dispatched Review (formal pre-merge)

Spawn a `code-reviewer` subagent for independent review. The reviewer gets git context, not your session history — keeps it focused on the work product.

**Steps:**
1. Get git range: `BASE_SHA=$(git rev-parse origin/main)` and `HEAD_SHA=$(git rev-parse HEAD)`
2. Dispatch `code-reviewer` agent with: description of changes, requirements/spec, BASE_SHA, HEAD_SHA
3. Act on feedback: fix Critical immediately, fix Important before proceeding, note Minor for later

**When to dispatch vs. inline:**
- Quick changes during development → inline
- Before merge to main → dispatch
- After completing major feature → dispatch
- When stuck and want fresh perspective → dispatch

## Acting on Feedback

- Fix Critical issues immediately
- Fix Important issues before proceeding
- Note Minor issues for later
- Push back if reviewer is wrong (with technical reasoning)

## Change Sizing

```
~100 lines changed  → Good. Reviewable in one sitting.
~300 lines changed  → Acceptable if it's a single logical change.
~1000 lines changed → Too large. Split it.
```

## Rules

- Don't rubber-stamp. "LGTM" without evidence of review helps no one.
- Don't soften real issues. Quantify problems when possible.
- Don't accept "I'll clean it up later" — require cleanup before merge.
- Separate refactoring from feature work in the diff.
- Large PRs (1000+ lines): ask the author to split.

## Red Flags

- PRs merged without any review
- "LGTM" without evidence of actual review
- Security-sensitive changes without security-focused review
- No regression tests with bug fix PRs
- Skipping review because "it's simple"
- Ignoring Critical issues or proceeding with unfixed Important issues
