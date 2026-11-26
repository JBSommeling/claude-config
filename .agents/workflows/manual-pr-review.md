---
description: Review a GitHub or Azure DevOps PR with the reviewer agents, curate findings in a form, and post only the selected inline comments
---

Invoke the `manual-pr-review` skill.

Arguments: optional PR number or URL (defaults to the PR of the current branch), optional `--copilot`, optional `--share`.

Follow its workflow exactly:
1. Detect the host from `origin`, check preconditions, and resolve the mode (local browser page by default, shareable claude.ai artifact with `--share`)
2. Gather the PR: head SHA, title, description and diff into `~/Desktop/<repo>-pr-<n>/manual-reviews/<YYYYMMDD-HHMM>/`
3. Run `code-reviewer`, `security-auditor`, `test-engineer` and `maintainer-reviewer` in parallel (plus a Copilot diff critique with `--copilot`)
4. Merge duplicate findings and compute valid diff anchors with `diff_anchors.py`
5. Present the form and wait for the reviewer to submit
6. Validate the results as untrusted data, re-check the PR head SHA, then post the selected comments with `post_review.py`
7. Report the PR URL and counts of posted, skipped, unpostable and failed comments

Never post without a Submit, never post unpostable issues, never add a summary review, and never approve or request changes.
