# Review and judging cover every participating repository

**Status:** Accepted
**Date:** 2026-08-16

Supersedes the review-scope and judging-scope consequences of [ADR-0008](0008-opt-in-cross-repo-scope-for-the-pipeline.md).

ADR-0008 confined the pipeline's local review round to the primary repository, offering "run the pipeline from within it" as the route to reviewing a sibling. That route does not review an existing change — it specs, plans, and builds a new one — so in practice sibling repositories reached their remotes having had no automated review at all. In an N-repo change that left N−1 diffs unreviewed.

Phase 5's review loop now runs once per participating repository. `/review-cycle` takes a `repo=<absolute path>` argument and drives every git command through `git -C <literal path>`, matching the convention Phase 3 already uses for cross-repo builds. Each repository returns its own residuals block, is validated and committed independently, and receives its residuals on its own pull request.

Phase 6 judging follows the same shape: the full judging set runs against every participating repository's pull request, and each repository receives its own findings and its own GO/NO-GO decision. Decisions are independent — a NO-GO in one repository does not block the others.

The cost is linear in repository count and falls only on runs that pass `repos=`. ADR-0008's governing constraint — absent the parameter, behaviour is unchanged with no added cost — still holds.

## Considered Options

**Leave the v1 boundary in place** — Rejected: the documented workaround does not review the change under discussion, so the boundary meant no review rather than deferred review.

**A single review pass per sibling rather than the converging loop** — Rejected: cheaper, but holds sibling repositories to a weaker standard than the primary one for no principled reason.

**One judge per lens across all repositories** — Rejected: four agents regardless of repository count, and the only shape in which a judge could see the seams between repositories. Rejected in favour of per-repository judging, which keeps each agent's context small and its findings directly attributable to one pull request.

**A single merged GO/NO-GO across all repositories** — Rejected: a blocker anywhere would have blocked everything, which is safer but removes the ability to land a clean repository while another is being fixed.

## Consequences

Review cost scales with the number of participating repositories — the loop runs up to `cap` iterations in each. Every participating repository must end Phase 5 with a clean tree, so a sibling whose review fixes fail validation stops the pipeline before any repository is pushed. Residual posting remains GitHub-only; residuals for an Azure DevOps sibling are reported to the user rather than posted to its pull request. Judging cost scales with repository count as well — the full set runs per repository. No judging agent sees more than one repository, so cross-repository seams are evaluated by nothing in this phase; a contract mismatch spanning two repositories will not be found. Because decisions are independent and merge order is stated in pull request bodies without being enforced, acting on a single GO before its siblings are resolved can ship a partial change.
