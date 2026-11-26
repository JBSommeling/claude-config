#!/usr/bin/env python3
"""Validate a submitted manual-pr-review results.json and post the kept comments to the PR.

Usage:
  post_review.py --review review.json --results results.json --host github --repo owner/name --number N [--dry-run]
  post_review.py --review review.json --results results.json --host azure --org-url URL --project P --repository R --number N [--dry-run]
"""

import argparse
import json
import re
import subprocess
import sys
import tempfile
from pathlib import Path

from diff_anchors import parse_diff

MAX_BODY_CHARS = 10000
VALID_ACTIONS = {"post", "skip"}
AZURE_API_VERSION = "7.1"
GITHUB_REPO_PATTERN = re.compile(r"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$")
CONTROL_CHARACTER = re.compile(r"[\x00-\x1f\x7f]")


class ValidationError(Exception):
    pass


def validate_results(review, results):
    """Return [{id, path, line, body}] for decisions to post; raise ValidationError on any problem."""
    if not isinstance(results, dict):
        raise ValidationError("results must be a JSON object")
    if results.get("reviewId") != review.get("reviewId"):
        raise ValidationError("reviewId does not match review.json")
    if results.get("status") != "submitted":
        raise ValidationError("status must be 'submitted'")
    decisions = results.get("decisions")
    if not isinstance(decisions, list):
        raise ValidationError("decisions must be a list")

    issues_by_id = {issue["id"]: issue for issue in review["issues"]}
    seen_ids = set()
    comments = []
    for decision in decisions:
        if not isinstance(decision, dict):
            raise ValidationError("each decision must be an object")
        decision_id = decision.get("id")
        if decision_id not in issues_by_id:
            raise ValidationError(f"unknown issue id: {decision_id!r}")
        if decision_id in seen_ids:
            raise ValidationError(f"duplicate decision for {decision_id}")
        seen_ids.add(decision_id)
        action = decision.get("action")
        if action not in VALID_ACTIONS:
            raise ValidationError(f"{decision_id}: action must be 'post' or 'skip'")
        if action == "skip":
            continue
        issue = issues_by_id[decision_id]
        if not issue.get("postable"):
            raise ValidationError(f"{decision_id}: cannot post on an unpostable issue")
        body = decision.get("body", "")
        if not isinstance(body, str):
            raise ValidationError(f"{decision_id}: body must be a string")
        if len(body) > MAX_BODY_CHARS:
            raise ValidationError(f"{decision_id}: body exceeds {MAX_BODY_CHARS} characters")
        if not body.strip():
            body = issue.get("recommendation")
            if not isinstance(body, str) or not body.strip():
                raise ValidationError(f"{decision_id}: no comment given and the issue has no recommendation")
        comments.append({"id": decision_id, "path": issue["path"], "line": issue["line"], "body": body})
    return comments


def parse_skip_ids(raw_skip_ids, comments):
    """Return the set of ids to drop; each must be a comment currently being posted."""
    skip_ids = {item.strip() for item in (raw_skip_ids or "").split(",") if item.strip()}
    posting_ids = {comment["id"] for comment in comments}
    for skip_id in sorted(skip_ids - posting_ids):
        raise ValidationError(f"--skip-ids: {skip_id} is not a comment being posted")
    return skip_ids


def validate_line_overrides(overrides, comments, files):
    """Check overrides are {posted id: right-side line of that comment's path}."""
    if not isinstance(overrides, dict):
        raise ValidationError("line overrides must be a JSON object")
    comments_by_id = {comment["id"]: comment for comment in comments}
    for override_id, line in overrides.items():
        if override_id not in comments_by_id:
            raise ValidationError(f"line override {override_id}: not a comment being posted")
        if isinstance(line, bool) or not isinstance(line, int):
            raise ValidationError(f"line override {override_id}: line must be an integer")
        check_right_side_line(override_id, comments_by_id[override_id]["path"], line, files)


def check_right_side_line(comment_id, path, line, files):
    file_info = files.get(path)
    if file_info is None or line not in file_info["valid_lines"]:
        raise ValidationError(f"{comment_id}: line {line} of {path} is not a right-side line of the diff")


def github_payload(head_sha, comments):
    return {
        "commit_id": head_sha,
        "event": "COMMENT",
        "comments": [
            {"path": comment["path"], "line": comment["line"], "side": "RIGHT", "body": comment["body"]}
            for comment in comments
        ],
    }


def azure_thread(comment):
    position = {"line": comment["line"], "offset": 1}
    return {
        "comments": [{"parentCommentId": 0, "content": comment["body"], "commentType": 1}],
        "status": 1,
        "threadContext": {
            "filePath": "/" + comment["path"],
            "rightFileStart": dict(position),
            "rightFileEnd": dict(position),
        },
    }


def run_with_payload_file(payload, build_command, runner):
    """Write payload to a temp file, run the command built from its path, always delete the file."""
    with tempfile.NamedTemporaryFile(
        "w", encoding="utf-8", suffix=".json", prefix="manual-pr-review-", delete=False
    ) as payload_file:
        json.dump(payload, payload_file, ensure_ascii=True)
        payload_path = Path(payload_file.name)
    try:
        return runner(build_command(str(payload_path)), capture_output=True, text=True, encoding="utf-8")
    finally:
        payload_path.unlink(missing_ok=True)


def post(host, comments, head_sha=None, repo=None, number=None, org_url=None, project=None,
         repository=None, dry_run=False, runner=subprocess.run):
    report = {"host": host, "posted": 0, "failed": 0, "failures": []}
    if not comments:
        return report

    if host == "github":
        payload = github_payload(head_sha, comments)
        if dry_run:
            print(json.dumps(payload, indent=2, ensure_ascii=False))
            return report
        completed = run_with_payload_file(
            payload,
            lambda path: ["gh", "api", f"repos/{repo}/pulls/{number}/reviews", "-X", "POST", "--input", path],
            runner,
        )
        if completed.returncode == 0:
            report["posted"] = len(comments)
        else:
            report["failed"] = len(comments)
            for comment in comments:
                report["failures"].append({"id": comment["id"], "error": (completed.stderr or "").strip()})
        return report

    for comment in comments:
        payload = azure_thread(comment)
        if dry_run:
            print(json.dumps(payload, indent=2, ensure_ascii=False))
            continue
        completed = run_with_payload_file(
            payload,
            lambda path: [
                "az", "devops", "invoke", "--area", "git", "--resource", "pullRequestThreads",
                "--route-parameters", f"project={project}", f"repositoryId={repository}",
                f"pullRequestId={number}", "--http-method", "POST", "--in-file", path,
                "--api-version", AZURE_API_VERSION, "--organization", org_url,
            ],
            runner,
        )
        if completed.returncode == 0:
            report["posted"] += 1
        else:
            report["failed"] += 1
            report["failures"].append({"id": comment["id"], "error": (completed.stderr or "").strip()})
    return report


def validate_target(arguments, review):
    """Reject a PR number that disagrees with review.json and host values that could act as CLI options."""
    if arguments.number != int(review["pr"]["number"]):
        raise ValidationError(
            f"--number {arguments.number} does not match review.json PR number {review['pr']['number']}"
        )
    if arguments.host == "github":
        if not GITHUB_REPO_PATTERN.match(arguments.repo):
            raise ValidationError("--repo must look like owner/name")
        return
    for option, value in (("--org-url", arguments.org_url), ("--project", arguments.project),
                          ("--repository", arguments.repository)):
        if not value or value.startswith("-") or CONTROL_CHARACTER.search(value):
            raise ValidationError(f"{option} must be non-empty, not start with '-', and have no control characters")
    if not arguments.org_url.startswith("https://"):
        raise ValidationError("--org-url must start with https://")


def read_json_file(path, label):
    try:
        return json.loads(Path(path).read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        raise ValidationError(f"cannot read {label} ({path}): {error}")


def read_text_file(path, label):
    try:
        return Path(path).read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError) as error:
        raise ValidationError(f"cannot read {label} ({path}): {error}")


def build_parser():
    parser = argparse.ArgumentParser(description="Post curated review comments to a PR.")
    parser.add_argument("--review", required=True)
    parser.add_argument("--results", required=True)
    parser.add_argument("--host", required=True, choices=["github", "azure"])
    parser.add_argument("--number", required=True, type=int)
    parser.add_argument("--repo", help="GitHub owner/name")
    parser.add_argument("--org-url", help="Azure DevOps organization URL")
    parser.add_argument("--project", help="Azure DevOps project")
    parser.add_argument("--repository", help="Azure DevOps repository")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--diff", help="PR diff; every posted line is re-checked against it")
    parser.add_argument("--line-overrides", help='JSON file {"I3": 58}; requires --diff')
    parser.add_argument("--skip-ids", help="Comma-separated ids to drop from the posting set")
    return parser


def main(argv=None, runner=subprocess.run):
    parser = build_parser()
    arguments = parser.parse_args(argv)
    if arguments.host == "github" and not arguments.repo:
        parser.error("--repo is required for github")
    if arguments.host == "azure" and not (arguments.org_url and arguments.project and arguments.repository):
        parser.error("--org-url, --project and --repository are required for azure")

    results_path = Path(arguments.results)
    try:
        review = read_json_file(arguments.review, "review.json")
        results = read_json_file(arguments.results, "results.json")
        validate_target(arguments, review)
        comments = validate_results(review, results)
        if arguments.line_overrides and not arguments.diff:
            raise ValidationError("--line-overrides requires --diff")
        skip_ids = parse_skip_ids(arguments.skip_ids, comments)
        comments = [comment for comment in comments if comment["id"] not in skip_ids]
        if arguments.diff:
            files = parse_diff(read_text_file(arguments.diff, "diff"))
            if arguments.line_overrides:
                overrides = read_json_file(arguments.line_overrides, "line overrides")
                validate_line_overrides(overrides, comments, files)
                comments = [{**comment, "line": overrides.get(comment["id"], comment["line"])} for comment in comments]
            for comment in comments:
                check_right_side_line(comment["id"], comment["path"], comment["line"], files)
    except ValidationError as error:
        print(f"Validation failed: {error}", file=sys.stderr)
        return 2

    report = post(
        arguments.host, comments, head_sha=review["pr"]["headSha"], repo=arguments.repo,
        number=arguments.number, org_url=arguments.org_url, project=arguments.project,
        repository=arguments.repository, dry_run=arguments.dry_run, runner=runner,
    )
    skipped = sum(1 for decision in results["decisions"] if decision["action"] == "skip")
    unpostable = sum(1 for issue in review["issues"] if not issue.get("postable"))
    report.update({"skipped": skipped, "unpostable": unpostable, "dryRun": arguments.dry_run})
    if not arguments.dry_run:
        report_path = results_path.parent / "post-report.json"
        report_path.write_text(json.dumps(report, indent=2, ensure_ascii=False), encoding="utf-8")
    print(f"posted={report['posted']} skipped={skipped} unpostable={unpostable} failed={report['failed']}")
    for failure in report["failures"]:
        print(f"FAILED {failure['id']}: {failure['error']}", file=sys.stderr)
    return 1 if report["failed"] else 0


if __name__ == "__main__":
    sys.exit(main())
