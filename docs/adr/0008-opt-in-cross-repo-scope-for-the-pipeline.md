# Opt-in cross-repo scope for the pipeline

**Status:** Accepted — review- and judging-scope consequences superseded by [ADR-0009](0009-review-and-judging-cover-every-participating-repository.md)
**Date:** 2026-08-15

The pipeline operated only on the repository it was launched from, silently isolating every feature there even when the change genuinely spanned repositories. An optional `repos=<path>` parameter makes sibling repositories — identified as direct children holding a `.git` entry, excluding worktree containers without special-casing — visible to the spec phase, which allocates work across them; the plan orders tasks contract-first; build and PR phases run per repo, with PR creation dispatching on the remote host (`gh` for GitHub, `az repos` for Azure DevOps).

A single parameter grants both context and write access; a separate read-only mode was judged unnecessary surface for v1. The primary repo is the repository containing the current working directory and is not overridable, reducing invocation complexity.

Absent the parameter, behaviour is unchanged with no added cost — the governing constraint. Enforcement is by convention: agent tool grants are unchanged and the spec checkpoint, where the allocation is confirmed, is the control point.

## Considered Options

**Always scan sibling repositories** — Rejected: imposes discovery cost and context on every run; the majority are single-repo.

**Read-only context with a separate write-authorisation flag** — Rejected for v1; the allocation checkpoint already puts a human in the loop before anything is written.

**A write-scoping PreToolUse hook restricting edits to the approved repo set** — Rejected for v1; duplicates a trust model that already governs single-repo runs on the same reasoning.

## Consequences

One parameter now carries write authorisation across several repositories; correct placement of changes depends on the spec checkpoint being read rather than rubber-stamped; multi-repo changes land as several draft PRs whose merge order matters and is stated in their bodies rather than enforced. PR creation recognises two remote hosts — GitHub (`gh`) and Azure DevOps (`az repos`); any other remote stops the pipeline rather than improvising. Cross-repo delivery depends on the push guard resolving `git -C <path> push` against the target repository; without that, the guard evaluates the session repository instead, leaving the cross-repo push unguarded.

The local review round and judging phase cover the primary repository only; sibling repositories reach their remotes having had no automated review pass — a deliberate v1 boundary, with review of each achieved by running the pipeline from within it. The per-repo branch-safety precheck resolves the default branch from its remote rather than the local tracking ref, which is written at clone time and writable by local commands; offline runs therefore cannot push — availability was traded for correctness.
