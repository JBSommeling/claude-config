#!/usr/bin/env python3
"""Compute which PR diff lines accept inline comments and build review.json for the manual-pr-review form.

Usage: diff_anchors.py --diff pr.diff --findings findings.json --meta meta.json --out review.json [--context 3]
"""

import argparse
import json
import re
import sys
from pathlib import Path

STATUS_ORDER = {"blocking": 0, "recommendation": 1, "nitpick": 2}
LARGE_DIFF_CHANGED_LINES = 1000
MAX_TITLE_CHARS = 300
MAX_RECOMMENDATION_CHARS = 10000
C_ESCAPES = {"\\": b"\\", '"': b'"', "t": b"\t", "n": b"\n", "r": b"\r", "a": b"\a", "b": b"\b", "f": b"\f", "v": b"\v"}
OCTAL_ESCAPE = re.compile(r"[0-7]{1,3}")
HUNK_HEADER = re.compile(r"^@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@")


def unquote_git_path(text):
    """Decode a git C-quoted path ("caf\\303\\251.txt"); unquoted text is returned unchanged."""
    if not (len(text) >= 2 and text.startswith('"') and text.endswith('"')):
        return text
    inner = text[1:-1]
    decoded = bytearray()
    position = 0
    while position < len(inner):
        character = inner[position]
        if character != "\\" or position + 1 >= len(inner):
            decoded += character.encode("utf-8")
            position += 1
            continue
        octal_match = OCTAL_ESCAPE.match(inner, position + 1)
        if octal_match:
            decoded.append(int(octal_match.group(), 8) & 0xFF)
            position = octal_match.end()
        else:
            decoded += C_ESCAPES.get(inner[position + 1], inner[position + 1].encode("utf-8"))
            position += 2
    return decoded.decode("utf-8", errors="replace")


def diff_header_new_path(header_line):
    """Best-effort new path from a `diff --git` line; the `+++` line overrides it when present."""
    quoted_match = re.search(r' ("b/(?:[^"\\]|\\.)*")$', header_line)
    if quoted_match:
        return unquote_git_path(quoted_match.group(1))[2:]
    path_match = re.search(r" b/(.+)$", header_line)
    return path_match.group(1) if path_match else None


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
            header_path = diff_header_new_path(raw_line)
            if header_path is not None:
                current = files.setdefault(
                    header_path, {"valid_lines": set(), "hunks": [], "changed": 0}
                )
        elif not in_hunk and raw_line.startswith("+++ "):
            target = unquote_git_path(raw_line[4:].rstrip("\t\r"))
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


def finding_problem(finding):
    """Return why a finding is malformed, or None when it is valid."""
    if not isinstance(finding, dict):
        return "finding is not an object"
    if finding.get("status") not in STATUS_ORDER:
        return f"status must be one of {', '.join(STATUS_ORDER)}"
    path = finding.get("path")
    if not isinstance(path, str) or not path:
        return "path must be a non-empty string"
    line = finding.get("line")
    if isinstance(line, bool) or not isinstance(line, int) or line < 1:
        return "line must be an integer >= 1"
    title = finding.get("title")
    if not isinstance(title, str) or len(title) > MAX_TITLE_CHARS:
        return f"title must be a string of at most {MAX_TITLE_CHARS} characters"
    recommendation = finding.get("recommendation")
    if not isinstance(recommendation, str) or len(recommendation) > MAX_RECOMMENDATION_CHARS:
        return f"recommendation must be a string of at most {MAX_RECOMMENDATION_CHARS} characters"
    reviewers = finding.get("reviewers", [])
    if not isinstance(reviewers, list) or not all(isinstance(name, str) for name in reviewers):
        return "reviewers must be a list of strings"
    return None


def build_review(diff_text, findings, meta, context=3):
    files = parse_diff(diff_text)
    issues = []
    drop_warnings = []
    for finding_number, finding in enumerate(findings, start=1):
        problem = finding_problem(finding)
        if problem:
            message = f"Dropped finding #{finding_number}: {problem}"
            drop_warnings.append(message)
            print(message, file=sys.stderr)
            continue
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
            "status": finding["status"],
            "reviewers": list(finding.get("reviewers", [])),
            "path": finding["path"],
            "line": finding["line"],
            "title": finding["title"],
            "recommendation": finding["recommendation"],
            "postable": reason is None,
            "unpostableReason": reason,
            "hunk": hunk,
        })
    issues.sort(key=lambda issue: (STATUS_ORDER.get(issue["status"], 99), issue["path"], issue["line"]))
    for position, issue in enumerate(issues, start=1):
        issue["id"] = f"I{position}"
    issues = [{"id": issue.pop("id"), **issue} for issue in issues]

    warnings = list(meta.get("warnings", [])) + drop_warnings
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
