---
description: Run adversarial test lenses in parallel to find coverage gaps with proof, then merge findings ranked by blast radius
---

Run the adversarial test framings.

`test-adversarial` is a **fan-out orchestrator**. It spawns four `test-engineer` agents concurrently, each assigned a single adversarial lens, then merges their findings into a ranked list of proven and suspected gaps. The agents operate independently — no shared state, no ordering — which makes parallel execution safe and useful.

## Phase A — Parallel fan-out

Spawn four subagents concurrently using the Agent tool. **Issue all four Agent tool calls in a single assistant turn so they execute in parallel** — sequential calls defeat the purpose of this workflow.

Each call selects `test-engineer` by name and assigns one lens:

1. **Mutation lens** — Change a safety-critical line so its behaviour is wrong; confirm the suite goes red. Report every surviving mutation with the exact line mutated and the test that should have caught it.
2. **Vacuity lens** — For each test, determine whether it exercises the path its name claims, or reaches the expected result via an early return, a default, or an unrelated branch. List every test that passes for the wrong reason.
3. **Oracle distrust lens** — Audit every baseline, golden file, and fixture. Flag any that were regenerated during the same change under review — they may encode a bug rather than the correct behaviour. Report what would have to be true for each oracle to be wrong.
4. **Coverage by blast radius lens** — Map untested paths to the damage a failure in each would cause. Rank gaps by blast radius, not line count. A five-line auth check outranks a fifty-line formatter.

A fifth lens — **differential** — is worth adding when a previous version exists to compare against. Spawn a fifth agent with that lens when a prior version is available; skip it and note the omission when it is not.

Constraints for all agents:
- Do not modify tracked files. Mutate only copies in a temporary directory.
- Confirm the repository is clean (no uncommitted changes to tracked files) after any mutation work.
- Return only the findings report — do not spawn further subagents.

## Phase B — Merge

Once all agents have returned, the main agent merges their reports:

1. **Deduplicate** — a gap identified by two lenses counts once; note both lenses in the finding.
2. **Classify** — separate proven gaps from suspected ones:
   - *Proven*: a surviving mutation (behaviour is wrong and no test caught it), or a demonstrated vacuous test (passes for the wrong reason with a concrete example).
   - *Suspected*: an untested path identified by blast radius or oracle distrust, where the gap is plausible but not demonstrated.
3. **Rank** — sort all findings by blast radius. Proven gaps outrank suspected gaps at the same blast-radius level, because they come with evidence.

## Phase C — Output

Produce a single ranked list:

```markdown
## Adversarial Test Findings

### Proven gaps (evidence attached)
1. **[Gap name]** — [Lens: mutation | vacuity] | [Evidence: what was mutated / what test passed wrongly] | [Concrete test that would close it]

### Suspected gaps (no proof yet)
2. **[Gap name]** — [Lens: oracle distrust | blast radius] | [Reasoning] | [Concrete test that would close it]

### Notes
- Differential lens: [applied / not applicable — reason]
- [Any other synthesis notes]
```

A surviving mutation outranks a missing-coverage opinion at the same blast-radius level, because it comes with proof. State this explicitly in the output when both types appear together.

## Rules

1. The four (or five) Phase A agents run in parallel — never sequentially.
2. Agents do not call each other. The main agent merges in Phase B.
3. A finding without evidence is a suggestion, not a proven gap. Label it accordingly.
4. Agents do not commit, push, or modify tracked files.
5. The repository must be in a clean state when Phase A begins and after each agent completes.
