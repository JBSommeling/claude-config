---
description: Review a GitHub PR and post inline comments with correct line references
---

Invoke the code-review skill. Review a GitHub PR across all five axes and post findings as inline comments on GitHub.

## Input

$ARGUMENTS should be a PR number (e.g. `42`) or URL (e.g. `https://github.com/owner/repo/pull/42`). If empty, detect from current branch via `gh pr view --json number`.

## Steps

### 1. Gather context

```bash
gh pr diff <number>
gh pr view <number> --json title,body,headRefOid,baseRefName,headRefName,files
```

Save the `headRefOid` as COMMIT_SHA — needed for posting the review.

### 2. Dispatch review

Spawn a `code-reviewer` subagent with:
- The full diff
- PR title and description
- The five-axis review framework (correctness, readability, architecture, security, performance)

The reviewer MUST return structured JSON output in this format:

```json
{
  "summary": "Overall review summary",
  "verdict": "ship | fix-first | discuss",
  "findings": [
    {
      "severity": "Critical | Important | Suggestion | Nit",
      "axis": "correctness | readability | architecture | security | performance",
      "path": "relative/file/path",
      "line": 42,
      "body": "Description of finding and fix recommendation"
    }
  ]
}
```

Each finding's `line` MUST be a line number that exists in the RIGHT side of the diff (new file version). The reviewer must verify this by checking the diff hunks — only lines that appear in the diff with a `+` prefix or unchanged context line (` ` prefix) within a hunk are valid targets.

### 3. Validate line numbers

Before posting, verify every finding's line number is valid:

```bash
gh pr diff <number> | python3 -c "
import sys, json, re

diff = sys.stdin.read()
valid = {}  # {path: set of valid right-side line numbers}
current_file = None
right_line = 0

for line in diff.split('\n'):
    if line.startswith('diff --git'):
        m = re.search(r' b/(.+)$', line)
        if m:
            current_file = m.group(1)
            valid[current_file] = set()
    elif line.startswith('@@'):
        m = re.search(r'\+(\d+)', line)
        if m:
            right_line = int(m.group(1))
    elif current_file:
        if line.startswith('+') or line.startswith(' '):
            valid.setdefault(current_file, set()).add(right_line)
            right_line += 1
        elif line.startswith('-'):
            pass  # deleted line, no right-side increment
        else:
            right_line += 1

# Read findings from stdin... but we pipe diff. Use a file instead.
print(json.dumps({k: sorted(v) for k, v in valid.items()}))
"
```

Drop any finding whose path:line is not in the valid set. Log dropped findings as a warning.

### 4. Post review on GitHub

Use the GitHub API to post a review with inline comments. ALWAYS use `line` + `side` parameters, NEVER use `position`.

```bash
gh api repos/{owner}/{repo}/pulls/{number}/reviews \
  -X POST \
  --input <(cat <<'PAYLOAD'
{
  "commit_id": "<COMMIT_SHA>",
  "event": "COMMENT",
  "body": "<summary table with axes and verdict>",
  "comments": [
    {
      "path": "relative/file/path",
      "line": 42,
      "side": "RIGHT",
      "body": "**<Severity> (<Axis>):** <finding>"
    }
  ]
}
PAYLOAD
)
```

Format the review body as:

```
## Code Review — 5-Axis

| Axis | Rating |
|------|--------|
| Correctness | ✅ Pass / ⚠️ Issues |
| Readability | ✅ Pass / ⚠️ Issues |
| Architecture | ✅ Pass / ⚠️ Issues |
| Security | ✅ Pass / ⚠️ Issues |
| Performance | ✅ Pass / ⚠️ Issues |

**Verdict: <ship | fix-first | discuss>**
```

Format each inline comment as:
```
**<Severity> (<Axis>):** <description>

<code suggestion if applicable>
```

### 5. Report

Output the review URL and a summary of findings posted vs. dropped.

## Rules

- NEVER use `position` parameter — always `line` + `side: "RIGHT"`
- Only comment on lines that exist in the diff (validated in step 3)
- Follow severity labels from code-review skill: Critical, Important, Suggestion, Nit
- Don't rubber-stamp — "LGTM" without evidence helps no one
- Large PRs (1000+ lines): note in review body, suggest splitting
- If no findings, post a clean review with passing axes and "Ship it"
