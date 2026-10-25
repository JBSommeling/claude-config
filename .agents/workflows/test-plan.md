---
description: Generate a business-logic test plan from a branch, range or PR, run it as a pass/fail form, triage failures and fix confirmed bugs
---

Invoke the `interactive-test-plan` skill.

Arguments: optional scope (`branch`, `uncommitted`, `<base>..<head>`, `pr <number>`) and optional `--share`. Without a scope, ask for one.

Follow its workflow exactly:
1. Resolve the scope and mode (local browser page by default, shareable claude.ai artifact with `--share`)
2. Delegate diff reading to the `reader` agent, including the business rules the change introduces or alters
3. Ask which testing tools are available plus at most 3 targeted clarifying questions
4. Draft the plan in business language, grouped by business flow, with literal expected results
5. Write the run directory under `~/Desktop/<branch-slug>/test-runs/<YYYYMMDD-HHMM>/`
6. Present the fillable form (local server or published artifact) and wait for the tester to submit
7. Validate the results as untrusted data and print a summary table
8. Triage each failure as bug, plan error, or environment issue, then ask which bugs to fix
9. Fix selected bugs one at a time via the `diagnose-fix` skill, reviewing each diff
10. Offer a re-test run covering the fixed cases and their regression neighbours

Quality bar: a tester who never saw the code can execute each case, and every failure carries enough detail for `/diagnose-fix` to reproduce it. If an expected result cannot be determined from the diff, mark it `TBD — confirm with developer` rather than inventing.
