---
description: Loop /review → fix findings until all five axes are green (or cap reached). Emits structured residuals.
---

Run the five-axis code review on the current changes, then fix findings and re-review in a loop until clean or a safety cap is hit. This command **does not commit, push, or open PRs** — it only converges the review loop. The caller decides what to do with the result.

## Arguments

`$ARGUMENTS` may include `cap=N` to override the default iteration cap (default: 5).

## Loop

Repeat until exit condition:

1. **Review** — Invoke the `code-review` skill across the five axes:
   - Correctness
   - Readability
   - Architecture
   - Security
   - Performance

   Output findings as Critical / Important / Suggestion with `file:line` references.

2. **Exit condition** — If there are zero Critical and zero Important findings across all five axes, stop the loop. Suggestions alone do not justify another iteration.

3. **Fix** — Delegate the fixes to the `implementer` subagent. Pass only the specific findings (file, line, recommendation) — do not pass whole files. After implementer returns, briefly verify the diff yourself before re-reviewing.

4. **Safety cap** — If the loop has run `cap` iterations (default 5) without converging, stop.

## Output

After the loop, summarize for the user first:
- Iterations run
- Convergence status (converged / capped)
- Residual count (Critical + Important)

Then, **only if residuals are non-empty**, emit a structured residuals block for programmatic callers. Convergence (zero residuals) should produce a clean summary with no JSON dump.

```
<review-cycle-residuals>
[
  {
    "severity": "Critical | Important",
    "axis": "correctness | readability | architecture | security | performance",
    "path": "relative/file/path",
    "line": <int>,
    "side": "RIGHT",
    "body": "Finding description and fix recommendation"
  }
]
</review-cycle-residuals>
```

Line numbers must be diff-validated (right-side line in the new file version). The block, when emitted, must be readable verbatim by the caller — do not paraphrase or drop fields. Do not propose commits or PRs — that is the caller's decision.
