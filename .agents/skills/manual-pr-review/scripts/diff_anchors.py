#!/usr/bin/env python3
"""Compute which PR diff lines accept inline comments and build review.json for the manual-pr-review form.

Usage: diff_anchors.py --diff pr.diff --findings findings.json --meta meta.json --out review.json [--context 3]
"""

import argparse
import json
import re
import sys
from pathlib import Path

SEVERITY_ORDER = {"Critical": 0, "Important": 1, "Suggestion": 2, "Nit": 3}
LARGE_DIFF_CHANGED_LINES = 1000
HUNK_HEADER = re.compile(r"^@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@")


def parse_diff(diff_text):
    """Return {new_path: {"valid_lines": set, "hunks": [[entry, ...]], "changed": int}}."""
    files = {}
    current = None
    old_line = new_line = 0
    in_hunk = False
    for raw_line in diff_text.split("\n"):
        if raw_line.startswith("diff --git"):
            current = None
            in_hunk = False
            path_match = re.search(r" b/(.+)$", raw_line)
            if path_match:
                current = files.setdefault(
                    path_match.group(1), {"valid_lines": set(), "hunks": [], "changed": 0}
                )
        elif not in_hunk and raw_line.startswith("+++ "):
            target = raw_line[4:].strip()
            if target == "/dev/null":
                continue
            if target.startswith("b/") and current is not None:
                new_path = target[2:]
                existing = [path for path, info in files.items() if info is current]
                if existing and existing[0] != new_path:
                    del files[existing[0]]
                    files[new_path] = current
        elif current is None:
            continue
        elif raw_line.startswith("@@"):
            header_match = HUNK_HEADER.match(raw_line)
            if not header_match:
                in_hunk = False
                continue
            old_line = int(header_match.group(1))
            new_line = int(header_match.group(2))
            in_hunk = True
            current["hunks"].append([
                {"kind": "header", "oldLine": None, "newLine": None, "text": raw_line, "anchor": False}
            ])
        elif not in_hunk or raw_line.startswith("\\"):
            continue
        elif raw_line.startswith("+"):
            current["valid_lines"].add(new_line)
            current["changed"] += 1
            current["hunks"][-1].append(
                {"kind": "add", "oldLine": None, "newLine": new_line, "text": raw_line[1:], "anchor": False}
            )
            new_line += 1
        elif raw_line.startswith("-"):
            current["changed"] += 1
            current["hunks"][-1].append(
                {"kind": "del", "oldLine": old_line, "newLine": None, "text": raw_line[1:], "anchor": False}
            )
            old_line += 1
        elif raw_line.startswith(" "):
            current["valid_lines"].add(new_line)
            current["hunks"][-1].append(
                {"kind": "context", "oldLine": old_line, "newLine": new_line, "text": raw_line[1:], "anchor": False}
            )
            old_line += 1
            new_line += 1
    return files


def excerpt_for(file_info, line, context):
    for hunk in file_info["hunks"]:
        body = hunk[1:]
        positions = [index for index, entry in enumerate(body) if entry["newLine"] == line]
        if not positions:
            continue
        anchor_index = positions[0]
        start = max(0, anchor_index - context)
        end = min(len(body), anchor_index + context + 1)
        excerpt = [dict(entry) for entry in body[start:end]]
        excerpt[anchor_index - start]["anchor"] = True
        return [dict(hunk[0])] + excerpt
    return []


def build_review(diff_text, findings, meta, context=3):
    files = parse_diff(diff_text)
    issues = []
    for finding in findings:
        file_info = files.get(finding["path"])
        hunk = []
        reason = None
        if file_info is None:
            reason = "file not in diff"
        elif finding["line"] not in file_info["valid_lines"]:
            reason = "line not on the new side of the diff"
        else:
            hunk = excerpt_for(file_info, finding["line"], context)
        issues.append({
            "severity": finding["severity"],
            "reviewers": list(finding.get("reviewers", [])),
            "path": finding["path"],
            "line": finding["line"],
            "title": finding["title"],
            "recommendation": finding["recommendation"],
            "postable": reason is None,
            "unpostableReason": reason,
            "hunk": hunk,
        })
    issues.sort(key=lambda issue: (SEVERITY_ORDER.get(issue["severity"], 99), issue["path"], issue["line"]))
    for position, issue in enumerate(issues, start=1):
        issue["id"] = f"I{position}"
    issues = [{"id": issue.pop("id"), **issue} for issue in issues]

    warnings = list(meta.get("warnings", []))
    changed_lines = sum(info["changed"] for info in files.values())
    if changed_lines > LARGE_DIFF_CHANGED_LINES:
        warnings.append(
            f"Large diff: {changed_lines} changed lines (over {LARGE_DIFF_CHANGED_LINES}); review coverage may be shallow"
        )
    return {"reviewId": meta["reviewId"], "pr": meta["pr"], "warnings": warnings, "issues": issues}


def main(argv=None):
    parser = argparse.ArgumentParser(description="Build review.json from a PR diff and findings.")
    parser.add_argument("--diff", required=True)
    parser.add_argument("--findings", required=True)
    parser.add_argument("--meta", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--context", type=int, default=3)
    arguments = parser.parse_args(argv)

    diff_text = Path(arguments.diff).read_text(encoding="utf-8")
    findings = json.loads(Path(arguments.findings).read_text(encoding="utf-8"))
    meta = json.loads(Path(arguments.meta).read_text(encoding="utf-8"))
    review = build_review(diff_text, findings, meta, arguments.context)
    Path(arguments.out).write_text(json.dumps(review, indent=2, ensure_ascii=False), encoding="utf-8")
    unpostable = sum(1 for issue in review["issues"] if not issue["postable"])
    print(f"{len(review['issues'])} issues ({unpostable} unpostable) -> {arguments.out}")


if __name__ == "__main__":
    sys.exit(main())
