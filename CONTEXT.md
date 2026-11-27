# claude-config

How the repositories that the pipelines and skills work in are structured, and the vocabulary those skills share when they talk about intent, decisions and documentation.

## Language

### Intent

**Spec**:
A document stating how one part of the system must behave right now, kept up to date rather than written once per change; when spec and code disagree, the spec wins and is fixed first.
_Avoid_: requirements doc, PRD, change request

**Decision**:
An answered question, recorded once with a `DEC-` ID and cited by every Spec it applies to.
_Avoid_: ruling, agreement

**Open question**:
A question a Spec still depends on; once answered it becomes a Decision.

**UX principle**:
A rule every screen must satisfy for its users, with a `UXP-` ID; a Spec that breaks one records the exception as a Decision.
_Avoid_: UX guideline, heuristic

**Engineering rule**:
A rule all code must satisfy, checked in review rather than against Specs.
_Avoid_: coding guideline, convention

### Repositories

**Migration repo**:
A repository holding an old system that is being replaced and the new system replacing it.

**Greenfield repo**:
A repository for a new system with no predecessor.

**Brownfield repo**:
A repository for an existing system that evolves in place.
_Avoid_: legacy repo

**Repo profile**:
The section at the top of a repo's `AGENTS.md` naming its repo type, where its specs live, and every convention that overrides our standard.

**Adopted repo**:
A repository with a Repo profile; only adopted repos are restructured or written into by the pipelines without asking.
_Avoid_: onboarded repo, managed repo
