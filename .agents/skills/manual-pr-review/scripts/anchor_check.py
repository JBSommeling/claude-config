#!/usr/bin/env python3
"""Mechanically verify that every comment about to be posted points at the line it was written for.

Usage: anchor_check.py --review review.json --results results.json --diff pr.diff --out anchor-check.json
Exit codes: 0 all checks pass, 3 a mechanical check failed (file still written), 2 validation error.
"""

import argparse
import json
import sys
from pathlib import Path

from diff_anchors import excerpt_for, parse_diff
from post_review import ValidationError, read_json_file, validate_results

WHOLE_HUNK = 10**9


def stored_anchor_text(issue):
    for row in issue.get("hunk", []):
        if row.get("anchor"):
            return row["text"]
    return None


def diff_text_at_line(file_info, line):
    for hunk in file_info["hunks"]:
        for row in hunk[1:]:
            if row["newLine"] == line:
                return row["text"]
    return None


def body_source_by_id(results):
    return {
        decision["id"]: "comment" if decision.get("body", "").strip() else "recommendation"
        for decision in results["decisions"] if decision["action"] == "post"
    }


def check_comments(review, results, files):
    issues_by_id = {issue["id"]: issue for issue in review["issues"]}
    sources = body_source_by_id(results)
    entries = []
    for comment in validate_results(review, results):
        issue = issues_by_id[comment["id"]]
        file_info = files.get(comment["path"])
        line_valid = file_info is not None and comment["line"] in file_info["valid_lines"]
        anchor_text = stored_anchor_text(issue)
        text_matches = (
            line_valid and anchor_text is not None
            and diff_text_at_line(file_info, comment["line"]) == anchor_text
        )
        entries.append({
            **comment,
            "bodySource": sources[comment["id"]],
            "title": issue.get("title"),
            "anchorText": anchor_text,
            "lineValid": line_valid,
            "textMatches": text_matches,
            "hunk": excerpt_for(file_info, comment["line"], WHOLE_HUNK) if line_valid else [],
        })
    return entries


def main(argv=None):
    parser = argparse.ArgumentParser(description="Check comment anchors against the PR diff.")
    for option in ("--review", "--results", "--diff", "--out"):
        parser.add_argument(option, required=True)
    arguments = parser.parse_args(argv)
    try:
        review = read_json_file(arguments.review, "review.json")
        results = read_json_file(arguments.results, "results.json")
        diff_text = Path(arguments.diff).read_text(encoding="utf-8")
        entries = check_comments(review, results, parse_diff(diff_text))
    except (ValidationError, OSError, UnicodeDecodeError) as error:
        print(f"Validation failed: {error}", file=sys.stderr)
        return 2
    Path(arguments.out).write_text(json.dumps(entries, indent=2, ensure_ascii=False), encoding="utf-8")
    failing = [entry for entry in entries if not (entry["lineValid"] and entry["textMatches"])]
    for entry in failing:
        print(
            f"{entry['id']} {entry['path']}:{entry['line']} "
            f"lineValid={entry['lineValid']} textMatches={entry['textMatches']}"
        )
    print(f"{len(entries)} comments checked, {len(failing)} failing -> {arguments.out}")
    return 3 if failing else 0


if __name__ == "__main__":
    sys.exit(main())
