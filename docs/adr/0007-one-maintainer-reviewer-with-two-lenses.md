# One maintainer reviewer carrying two lenses

**Status:** Accepted
**Date:** 2026-08-15

The pipeline judging phases fan out to `code-reviewer`, `security-auditor`, and `test-engineer`. All three ask whether the change is correct; none asks whether it is worth owning. Two questions were missing: would a human author consider this reasonable to maintain for five years, and is it consistent with the practices of *this* codebase rather than with generic best practice. Both could have been separate agents, or lenses on a `test-engineer` fan-out the way `/test-adversarial` splits its four. They are instead one agent, `maintainer-reviewer`, holding both lenses, because both need the same expensive context and neither can be answered without it: to judge either question the agent must first read two or three existing siblings of every changed file plus the project's convention documents. Splitting the lenses pays that baseline read twice for one judgement. The judging phases grow by one agent, not two. The lenses stay separate inside the report — five-year concerns and consistency findings are listed apart — so a reader can act on one without the other.

## Consequences

Every consistency finding must cite a precedent `file:line` or be reclassified as a new pattern, which is what keeps the agent from emitting generic advice — the failure mode that left this lens missing in the first place. `code-reviewer`'s architecture axis overlaps at the edges, so the merge step dedupes and `maintainer-reviewer` is instructed to reference rather than restate the correctness, security, and coverage axes. Accepted risk that one agent under-weights one of its two lenses on a large diff; the revisit trigger is a report that repeatedly returns findings from only one section, at which point split into `maintainability-reviewer` and `consistency-reviewer` and pay the second baseline read.
