---
description: Loop /review → fix findings until all five axes are green, then offer commit & push
---

Run the five-axis code review on the current changes, then fix findings and re-review in a loop until the review comes back clean.

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

3. **Fix** — Delegate the fixes to the `implementer` subagent (Sonnet). Pass only the specific findings (file, line, recommendation) — do not pass whole files. After implementer returns, briefly verify the diff yourself before re-reviewing.

4. **Safety cap** — If the loop has run 5 iterations without converging, stop and summarize the remaining findings for the user to decide.

## After the loop

Summarize:
- Iterations run
- Findings fixed per axis
- Any residual Suggestions left unaddressed

Then propose the full ship sequence to the user — commit, push, open PR, run `/review-pr` on it. Per global git-safety rules, all four are write operations and require explicit approval. State exactly what will run before waiting:

- `git add` (list specific files, not `.` or `-A`)
- `git commit -m "<proposed message>"`
- `git push` (and `--set-upstream origin <branch>` if the branch has no upstream)
- `gh pr create --title "<title>" --body "<body>"` against the project's main branch
- `/review-pr <new PR number>`

If approval for commit/push was already granted earlier in the session for these changes, skip re-asking for those two — but always ask before `gh pr create` and `/review-pr`, since PRs are visible to others.

After `gh pr create` returns the PR URL, extract the PR number and invoke `/review-pr <number>`. That command will post inline findings on GitHub. Report the PR URL and the review URL back to the user.
