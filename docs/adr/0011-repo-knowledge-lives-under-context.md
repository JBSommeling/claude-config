# Repo knowledge lives under `context/`, shaped by a Repo profile

**Status:** Accepted
**Date:** 2026-11-27

The repositories the pipelines work in scatter their knowledge across `docs/`, `docs/adr/`, root files and the Desktop, so neither agents nor people know where to look or what is current. We define one layout for repositories that adopt our guidelines. Agent tooling lives in `.claude/` (rules, agents, skills, evals), written for that repo and never symlinked. All knowledge lives under `context/`: `specs/`, `standards/`, `design-system/`, `adr/` and `process/`, plus `legacy/` for a migration repo and `current/` for a brownfield repo. A migration repo nests `specs/`, `standards/` and `design-system/` under `context/target/`, because there every kind of knowledge exists for both the old and the new app. ADRs always live in `context/adr/`, never `docs/adr/`. A Repo profile at the top of `AGENTS.md` marks a repo as adopted and states its type, its platforms (Claude-only by default), where its specs live, and every convention that overrides our standard; anything not listed follows the standard. `/initialize-repo` audits a repo against this layout, proposes moves for approval, and applies them on a branch with a draft PR. The full layout ships with that skill as `REPO-STRUCTURE.md`. This repo is the installer, not an adopted repo, and keeps its own layout.

## Considered Options

**Keep `docs/adr/`** — no skill changes, but a second top-level home for knowledge and a second place for agents to search.

**One layout with `target/` in every repo** — uniform paths, but in a greenfield or brownfield repo `target/` has nothing to contrast with and is an empty level.

**Infer the repo type from its folders** — no marker to maintain, but no explicit adoption decision and nowhere to record overrides.

**`.agents/` as the default tooling home** — shared with Codex, but Claude Code does not read `.agents/` for skills, agents or rules, so every Claude-only repo would need a copy step.

## Consequences

`/grill`, `/improve-architecture` and the `maintainer-reviewer` agent must read ADRs from `context/adr/`. Spec paths differ by repo type, so agents find specs through the indexes linked from `AGENTS.md`. Repos without a Repo profile are untouched: the pipelines behave as before and ask before creating `context/`. A repo that sets `Platforms: both` keeps `.agents/` as source and copies it into `.claude/`, with a CI freshness check.
