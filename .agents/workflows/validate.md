---
description: Run the full validation pass — test suite, build, linter, type check — fixing until green
---

Run a full validation pass over the current working tree:

1. Run the complete test suite — all tests must pass, not just per-task tests
2. Run build/compile check — verify the project builds cleanly
3. Run linter/formatter if configured in the project
4. Check for type errors if the project uses a type system

If any step fails, fix the issue and re-run validation until everything passes. Orchestrator commits each fix directly inline via `git add` / `git commit` (Bash) — separate commit per fix, do not spawn a subagent solely to commit.

Do not report success until validation is fully green.

**Cross-repo (when `repos=` is absent, the above is the complete pass — skip this block).**

When the plan carries `[repo: <name>]` tags, run the validation steps above in each participating repo. Every repo must be fully green before validation is considered complete.
