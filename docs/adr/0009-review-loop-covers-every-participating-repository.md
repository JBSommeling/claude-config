# Review loop covers every participating repository

**Status:** Accepted
**Date:** 2026-08-16

Supersedes the review-scope consequence of [ADR-0008](0008-opt-in-cross-repo-scope-for-the-pipeline.md).

ADR-0008 confined the pipeline's local review round to the primary repository, offering "run the pipeline from within it" as the route to reviewing a sibling. That route does not review an existing change — it specs, plans, and builds a new one — so in practice sibling repositories reached their remotes having had no automated review at all. In an N-repo change that left N−1 diffs unreviewed.

Phase 5's review loop now runs once per participating repository. `/review-cycle` takes a `repo=<absolute path>` argument and drives every git command through `git -C <literal path>`, matching the convention Phase 3 already uses for cross-repo builds. Each repository returns its own residuals block, is validated and committed independently, and receives its residuals on its own pull request.

The cost is linear in repository count and falls only on runs that pass `repos=`. ADR-0008's governing constraint — absent the parameter, behaviour is unchanged with no added cost — still holds.

## Considered Options

**Leave the v1 boundary in place** — Rejected: the documented workaround does not review the change under discussion, so the boundary meant no review rather than deferred review.

**A single review pass per sibling rather than the converging loop** — Rejected: cheaper, but holds sibling repositories to a weaker standard than the primary one for no principled reason.

**Extend Phase 6 judging per repository as well** — Deferred: judging posts through `gh api`, which does not serve Azure DevOps remotes, and its security, coverage, and maintenance lenses are a larger cost multiplier than the review loop. Phase 6 stays primary-repo-only and keeps printing its coverage warning.

## Consequences

Review cost scales with the number of participating repositories — the loop runs up to `cap` iterations in each. Every participating repository must end Phase 5 with a clean tree, so a sibling whose review fixes fail validation stops the pipeline before any repository is pushed. Residual posting remains GitHub-only; residuals for an Azure DevOps sibling are reported to the user rather than posted to its pull request. Phase 6 judging still covers the primary repository alone, so sibling pull requests carry a five-axis review but no security, coverage, or maintenance pass.
