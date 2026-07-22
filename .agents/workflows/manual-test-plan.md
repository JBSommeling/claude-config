---
description: Generate a full manual testing plan from the changes on the current branch — asks about available tools, writes per-step plan with literal expected outputs
---

Invoke the `manual-test-plan` skill.

Follow its workflow exactly:
1. Ask the user which change scope to plan against (branch / uncommitted / range / last commit)
2. Delegate diff reading to the `reader` agent
3. Ask which testing tools are available (browser, API client, CLI, DB, events/queues, logs, plus anything else)
4. Ask targeted clarifying questions only where the plan would otherwise be wrong
5. Ask the user where to save the plan
6. Generate the plan with prerequisites, happy path, edge cases, negative cases, regression checks, cleanup — each step with tool, action, literal expected output, and pass criteria
7. Delegate the file write to the `implementer` agent and report path, step count, and any TBD sections

Quality bar: a QA engineer who has never seen the code must be able to execute the plan without asking the developer questions. If expected output cannot be determined from the diff, mark it `TBD — confirm with developer` rather than inventing.
