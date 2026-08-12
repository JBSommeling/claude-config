---

## Code Conventions

These apply to every agent and every edit, in every project.

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
