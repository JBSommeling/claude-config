# Repo structure guidelines

The standard layout and documentation rules for repositories that adopt our guidelines. The `/initialize-repo` skill reads this file to audit and restructure a repo, and agents consult it in an Adopted repo to know where things live and what to keep current.

## Precedence

1. A repo's own convention wins when it is recorded in its Repo profile.
2. Anything the profile does not list follows this standard.
3. A repo without a Repo profile is not adopted: this file does not apply to it.

## Principles

- **Intent before code.** Agree on what to build and why before building it.
- **The spec is the source of truth.** When spec and code disagree, fix the spec first, then the code.
- **Every decision is written down with an ID.** An answered question is recorded once and cited by ID.
- **Spec and code move together.** When code changes what a Spec says, the Spec changes too, and a check catches drift.
- **Documentation is updated in the same PR as the change.** A follow-up docs PR does not count.

## Repo types

| Type | What it is | Knowledge and code | Rules |
|---|---|---|---|
| Migration | An old system being replaced by a new one. | `legacy/` holds the old code, read-only. `context/legacy/` records what the old app does: screen inventories, reviews, analytics, flow diagrams, capability map. `context/target/` holds the new app's specs, standards and design system. New code lives in `target-system/`. | Every legacy capability is mapped to a Spec or explicitly dropped. When the migration completes, archive `legacy/` and the repo becomes brownfield. |
| Greenfield | A new system with no predecessor. | No `legacy/` or `target/`. Code uses the framework's own layout. | Specs and ADRs come before code. |
| Brownfield | An existing system evolving in place. | `context/current/` holds architecture and known debt. | Where no Spec exists yet, the code is the truth; the first change touching an area writes its Spec. Never restructure existing code to fit this layout. Adopt gradually. |

## Layout

Greenfield and brownfield:

```
AGENTS.md          Repo profile + onboarding: repo map, commands, links to the indexes
CLAUDE.md          @AGENTS.md (plus Claude-only notes)
CHANGELOG.md       Unreleased + versions
changes/           changelog fragments (busy repos only)
CONTEXT.md         glossary
.claude/           rules/ (path-scoped), agents/, skills/, evals/ — written for this repo, never symlinked
context/
  README.md        generated index
  specs/           specs + DECISIONS.md (DEC- IDs)
  standards/       UX-PRINCIPLES.md (UXP- IDs)
  design-system/   tokens, components, brands
  adr/             architectural decisions (always here, never docs/adr/)
  process/         qa, links to project management
  current/         brownfield only
legacy/            migration only: old code, read-only
<code>             framework layout, or target-system/ in a migration repo
tools/             scripts the skills call
```

Migration variant: old-app knowledge goes in `context/legacy/`, and the new app's knowledge nests under `context/target/`:

```
context/
  README.md
  legacy/          what the old app does
  target/
    specs/         specs + DECISIONS.md
    standards/     UX-PRINCIPLES.md
    design-system/
  adr/             stays directly under context/
  process/         stays directly under context/
legacy/            old code, read-only
target-system/     new code
```

Two rules apply to every layout:

- A folder exists only once it has a document. No empty placeholder folders.
- Every folder answers one question. If a document does not fit the question of the folder it is in, it is in the wrong folder.

## Specs and decisions

### Specs

A Spec describes how its part of the system must behave now. It is updated in place; there is never one Spec per change. The format is whatever `/spec` produces. Specs live at the profile's `Specs:` path and get frontmatter when saved (see Indexes).

### Decisions

Decisions are `DEC-` rows in `DECISIONS.md`, next to the Specs. One row each: ID, decision, rationale, date, status or superseded-by.

- Cite a Decision by ID wherever it applies.
- IDs are never reused or renumbered after merge.
- A superseded row stays, with a pointer to its replacement.
- An Open question becomes a `DEC-` row when it is answered.
- A Spec that deliberately breaks a UX principle records the exception as a Decision.
- Parallel branches: CI rejects duplicate IDs, and the branch that merges second renumbers its new IDs.

### ADRs

ADRs live in `context/adr/`. Write one only for an architectural trade-off that is hard to reverse, surprising without context, and a real trade-off between options. Every other decision is a `DEC-` row.

## Rules

There are three kinds of rule, each with one place. Nothing else holds rules.

| Kind | Lives in | Identified by | Checked against | Owned by |
|---|---|---|---|---|
| UX principles | `context/standards/UX-PRINCIPLES.md` | `UXP-` IDs | Specs | Product and Design |
| Design system | `context/design-system/` | Document names | Specs | Design |
| Engineering rules | `.claude/rules/` | Rule file names | Code, in review | Engineering |

Engineering rules are path-scoped. Each rule file carries `paths:` frontmatter with globs, so it loads only when matching files are touched:

```yaml
---
paths:
  - "src/api/**/*.ts"
---
```

## Indexes and just-in-time loading

Every `context/` folder with documents has a generated `README.md` index, built by `tools/build_index.py`. Never edit an index by hand.

Agents load context just in time: read `AGENTS.md`, then the relevant index, then only the documents that index points to. An index holds prose describing each document, never code.

### Frontmatter

Every context document carries this frontmatter by default:

```yaml
---
title: Checkout flow
summary: How a customer moves from cart to confirmed order.
read-when: Changing checkout screens, payment, or order confirmation.
status: accepted
covers: ["src/checkout/**"]
---
```

| Field | Meaning |
|---|---|
| `title` | Document name shown in the index. |
| `summary` | One sentence on what the document says. |
| `read-when` | The situation in which an agent should open it. |
| `status` | `draft`, `accepted`, `superseded` or `archived`. |
| `covers` | Globs of the code the document describes. Used to detect drift. |

A repo overrides the field set with the profile's `Frontmatter:` line. A document without frontmatter is listed as Unindexed and warned about.

The check scripts read a small YAML subset: one `key: value` per line, with lists written inline as `[a, b]`. Nested maps and indented `- item` lists are rejected.

## Keeping documentation current

| When a change... | Update... |
|---|---|
| Alters user-visible behaviour | `CHANGELOG.md`, or a fragment in `changes/` |
| Implements or changes intended behaviour | The Spec for that behaviour |
| Makes an architectural choice | An ADR in `context/adr/`; supersede the old one if it is replaced |
| Changes commands, setup, layout or conventions | `AGENTS.md` and `.claude/rules/` |
| Adds, moves or removes a context document | Regenerate the indexes |
| Answers a question | A `DEC-` row |

### Enforcement

CI runs these checks through the GitHub Actions template `docs-checks.yml`:

| Check | Catches |
|---|---|
| `tools/build_index.py --check` | Stale or hand-edited indexes |
| `tools/check_docs.py` | Missing frontmatter, broken links, and a warning when code matched by `covers:` changed but its document did not |
| `tools/check_ids.py` | Duplicate or dangling `DEC-` IDs |
| `tools/check_changelog.py` | A PR with no changelog entry, unless it carries the `no-changelog` label |

Each PR description has one line: `Docs: updated <paths>` or `Docs: none needed: <reason>`. Reviewers check documentation alongside code.

## Changelog

- `CHANGELOG.md` lives at the repo root, where tools and people look for it. It replaces any releases folder.
- Format is Keep a Changelog: an Unreleased section and one section per version, with Added, Changed, Fixed and Removed groups.
- Entries describe the user-visible change, not the files touched.
- Each PR adds its own line under Unreleased.
- Busy repos, with several parallel PRs, use one fragment file per PR in `changes/`, merged into `CHANGELOG.md` at release.
- CI requires an entry unless the PR is labelled `no-changelog`.
- The profile can override the location.

## Repo profile

The Repo profile is the section `## Repo profile` at the top of `AGENTS.md`:

```markdown
## Repo profile
- Type: brownfield          # migration | greenfield | brownfield
- Platforms: claude         # claude | codex | both
- Specs: context/specs/
- Frontmatter: title, summary, read-when, status, covers
- Overrides: none
```

- `Overrides:` is free text for humans. The machine-read keys are `Type`, `Platforms`, `Specs` and `Frontmatter`.
- No profile means the repo is not adopted. Pipelines behave as before and ask before creating `context/`.

## Platforms

Claude-only is the default, with tooling in `.claude/`. Claude Code reads `CLAUDE.md`, `.claude/skills`, `.claude/agents` and `.claude/rules`; it does not read `.agents/`.

`AGENTS.md` is the shared onboarding file. `CLAUDE.md` imports it with `@AGENTS.md`, which works in every Claude setup.

| `Platforms:` | Tooling lives in | Notes |
|---|---|---|
| `claude` | `.claude/` | Default. |
| `codex` | `.agents/` | |
| `both` | `.agents/` is the source | A repo script copies it into `.claude/`. Copy, never symlink. CI checks the copy is fresh. |

## Where the pipelines save documents

- **Spec:** at the profile's `Specs:` path. Update the existing Spec, or add a new `<slug>.md`. It carries frontmatter, gets an index line, and is committed on the feature branch.
- **Plan:** `plan.md` stays at `~/Desktop/<slug>/`. It is an execution artefact and is out of date once the change merges.

## Adopting a repo

Run `/initialize-repo`:

1. Audit the repo against this standard.
2. Review the proposal at the checkpoint.
3. Apply it on a branch and open a draft PR.

The skill never moves code, never rewrites content and never deletes. Re-run it any time for a drift audit.
