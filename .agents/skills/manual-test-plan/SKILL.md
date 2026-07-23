---
name: manual-test-plan
description: Generate a full manual testing plan from the changes on the current branch. Asks which tools are available (browser, API client, CLI, DB, events/queues, logs), then writes a per-step plan with literal expected outputs — JSON payloads, log lines, event bodies, exit codes. Use when the user says "make a test plan", "manual testing plan", "how do I test these changes", or before shipping a branch that needs QA verification.
---

# Manual Test Plan

Generate a manual testing plan grounded in the actual diff on the current branch. Output is a single markdown file a QA engineer can execute without asking the developer questions.

## Workflow

Follow phases in order. Do not skip.

### Phase 1 — Ask change scope

Ask which scope to plan against:
1. Branch diff vs main (`git diff main...HEAD`)
2. Uncommitted changes only (staged + unstaged)
3. Branch + uncommitted
4. Specific commit range (`<base>..<head>`)
5. Last commit (`git diff HEAD~1..HEAD`)

Wait for the answer.

### Phase 2 — Read the diff (delegate to `reader`)

Delegate to the `reader` agent. Pass the exact git command. Ask for:
- One-line summary per changed file (new endpoint, modified schema, added migration, etc.)
- Test-surface signals: new routes, new env vars, new migrations, new/changed events, changed validation, modified auth, new feature flags, new CLI flags, modified response shapes
- Structured summary under 400 words — never raw diff

### Phase 3 — Ask about tools

Ask which tools are available. Default catalog:
- **Browser** + DevTools
- **API client** (curl / Postman / HTTPie / Bruno — which?)
- **CLI / shell** (which binaries?)
- **Database client** (psql / mysql / TablePlus — which DB?)
- **Event/queue inspector** (Kafka UI / SQS console / webhook.site / ngrok)
- **Logs / observability** (tail / Datadog / Grafana / Sentry)
- **Anything else?** — catch project-specific tools (Stripe CLI, AWS CLI, kubectl, flag dashboards)

### Phase 4 — Clarify ambiguous test surfaces

Based on the diff summary, ask 1–4 targeted questions only where the plan would otherwise be wrong. Skip if the diff is self-explanatory.

Examples:
- "The new `/refund` endpoint reads `customer.tier` — test free-tier and paid-tier, or only one?"
- "Migration adds NOT NULL column with default — include backfill verification?"
- "Event `OrderShipped` was renamed — which consumers need re-verification?"

### Phase 5 — Ask save path

Ask for output path. Suggest defaults based on what exists in the repo (`./testing-plans/<branch>.md`, `./docs/testing/<branch>.md`, `tmp/test-plan-<branch>.md`). Do not write until confirmed.

### Phase 6 — Generate the plan

Required sections:

1. **Header** — branch, base commit, date, 1-paragraph change summary
2. **Prerequisites / setup** (always) — env vars, feature flags, seed data, services to start, accounts/roles, migrations, fixtures
3. **Test sections**, one per logical change area, each containing:
   - **Happy path** — main intended flow
   - **Edge cases** — boundaries, empty/null, large inputs, concurrency
   - **Negative cases** — invalid inputs, auth failures, expected errors
   - **Regression checks** — adjacent untouched features the changed code touches
4. **Cleanup / teardown** — reset state, remove test data, disable flags

Each step uses:

````
#### Step N.M — <short title>
**Tool:** <browser | curl | psql | kafka-ui | ...>
**Action:**
<exact command, click sequence, or request payload>

**Expected output:**
```<json|text|sql|log>
<literal expected output — actual JSON body, log line, row count, exit code, event payload>
```

**Pass criteria:** <what must match for this step to pass>
````

Non-deterministic values (timestamps, IDs) use placeholders: `<ISO-8601 timestamp>`, `<UUID>` — never literal example values that could be mistaken for required matches.

If the expected output cannot be determined from the diff alone, write `**Expected output:** TBD — confirm with developer`. Do not invent.

### Phase 7 — Write and confirm

Delegate the file write to the `implementer` agent with the filled-in plan. Then report:
- Path written
- Number of test steps
- Any sections marked TBD

## Quality bar

A QA engineer who has never seen this code must be able to execute the plan without asking the developer questions. "Verify the response looks correct" is a failure — show the exact expected payload.

## Delegation

- Phase 2 (diff reading) → `reader` agent
- Phase 6 file write → `implementer` agent
- Phases 1, 3, 4, 5, 7 → main agent (user interaction / judgment)
