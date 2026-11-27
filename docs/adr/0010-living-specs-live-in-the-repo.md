# Living specs live in the repo

**Status:** Accepted
**Date:** 2026-11-27

Repos had no agreed place for specs: the pipelines write one spec per change to `~/Desktop/<feature-slug>/spec.md`, where neither agents nor teammates can find it again. We adopt the principle that the spec is the source of truth: when spec and code disagree, the spec is fixed first, then the code. A source of truth must describe the present, so a spec describes how its part of the system must behave now and is updated in place, never rewritten per change. Specs live in `context/specs/`, or `context/target/specs/` in a migration repo. Answered questions are recorded once as `DEC-` rows in `DECISIONS.md` next to the specs and cited by ID. A change updates the spec it touches in the same PR as the code. The spec's format stays whatever the `/spec` skill produces; this decision covers only where specs live and how they relate.

## Considered Options

**One spec per change on the Desktop** — the current behaviour. Nobody else can find the spec, and after several changes no single document says what is true.

**A new spec format with typed screen and feature specs, frontmatter gates and mockups** — rejected for now to keep one spec format, the one `/spec` already produces.

## Consequences

The spec path differs by repo type, so agents find specs through the indexes linked from `AGENTS.md` rather than a hard-coded path. `DECISIONS.md` grows quickly and needs a CI check for duplicate and dangling `DEC-` IDs; a branch that merges second renumbers its new IDs. Areas of a brownfield repo without a spec keep the code as their truth until the first change touching them writes one. `/spec` and the pipelines save specs at the Repo profile's `Specs:` path and fall back to their previous locations in repos without a profile.
