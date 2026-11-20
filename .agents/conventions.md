---

## Code Conventions

These apply to every agent and every edit, in every project.

### Naming

Every name introduced by a change — variables, constants, parameters, fields, functions,
types, loop and destructuring bindings — states what it holds or does. A reader who lands
on the line cold should not have to scroll to work out what it means.

**Not acceptable:** single letters (`i`, `k`, `v`, `a`, `b`, `e`), cryptic truncations
(`usr`, `cnt`, `res`), and index-suffixed placeholders (`data2`, `tmp`, `foo`). Length is
not the goal — `count` beats `numberOfItemsCurrentlyInTheCollection`.

**Narrow exceptions:** notation the ecosystem already reads as precise — coordinates
(`x`, `y`, `z`), a discard binding (`_`), the language's own conventions (`self`, `this`).

This governs names the change defines. Renaming untouched surrounding code is a separate
decision, not a side effect of the edit.

### Comment length

Inline comments and prose-only docblocks are capped at 2-3 lines.

**Applies to:** `//`, `#`, `--`, `<!-- -->` comments, and doc comments whose body is
plain prose.

**Does not apply to:** docblocks carrying structured API documentation — blocks with
`@param`, `@return`, `@throws`, `@deprecated`, or equivalent JSDoc/PHPDoc/KDoc tags —
plus license headers, generated-file banners, and machine-read annotations. Those run
as long as their tags require.

**When an explanation needs more than 3 lines**, it does not belong inline. Pick one:

- Refactor so it needs less explaining: better names, an extracted function, a
  narrower interface.
- Move the prose into project documentation and leave a one-line comment pointing
  at it.

Comments earn their lines by explaining *why*. Never pad to the cap, and never restate
what the code already says.

### Comment content

Comments describe the code as it stands, never how it got there. Never reference commit
SHAs, earlier commits, ticket or issue IDs, PR numbers, or "changed in <X>" history in
inline comments or docblocks.

**Applies to:** every comment form covered above, including structured docblocks — a
`@deprecated` or `@see` tag carries no ticket reference either.

That history lives in the commit message, the PR, and the tracker, where it stays
accurate. Copied into a comment it rots on the first refactor and tells the next reader
nothing about what the code does.

### Pull requests

Every pull request is opened as a draft — `gh pr create --draft ...` — with no exceptions.

Promoting a PR out of draft is the human's call. No agent marks a PR ready for review, and
no workflow does it automatically.

## Machine Safety

### No artificial CPU load

Never start artificial CPU load on the machine: no stress tools (`stress`, `stress-ng`),
`yes > /dev/null`, busy loops, fork bombs, or synthetic benchmarks run to saturate cores.
This holds even when reproducing a performance problem or testing behaviour under load —
if a task seems to need it, stop and ask the human instead. The `block-cpu-load.sh`
hook enforces the common patterns.

Ordinary work that happens to use CPU — builds, test suites, linters — is allowed, but
watch it. If a test run, a build, or work running in parallel drives CPU load high
(sustained load average above the core count, or the machine turning sluggish), stop
it and report to the human what was running and the load you saw. Then continue in a
way that keeps the load down: fewer workers or test shards, serial instead of parallel
runs, or a narrower subset first. Never add parallelism to finish faster.

A runtime watchdog kills agent-started jobs that hold high CPU for minutes; see
`docs/watchdog/cpu-watchdog.md`.
