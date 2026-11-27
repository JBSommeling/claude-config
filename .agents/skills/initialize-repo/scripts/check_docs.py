#!/usr/bin/env python3
"""Validate frontmatter, relative links and covers-drift of documents under context/."""

import argparse
import fnmatch
import re
import subprocess
import sys
import urllib.parse
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import build_index  # noqa: E402
import frontmatter  # noqa: E402

LINK_PATTERN = re.compile(r'\[[^\]]*\]\(([^)\s]+)(?:\s+"[^"]*")?\)')
INLINE_CODE_PATTERN = re.compile(r"(`+).*?\1")
FENCE_MARKERS = ("```", "~~~")
SKIPPED_SCHEMES = ("http://", "https://", "mailto:", "#")


class GitError(Exception):
    pass


def changed_files(root, base_ref):
    try:
        result = subprocess.run(
            ["git", "-C", str(root), "diff", "--name-only", "--relative", "--end-of-options", f"{base_ref}...HEAD"],
            capture_output=True, text=True,
        )
    except OSError as error:
        raise GitError(f"cannot run git: {error}")
    if result.returncode != 0:
        raise GitError(f"git diff against {base_ref!r} failed: {result.stderr.strip()}")
    return set(result.stdout.split("\n")) - {""}


def is_generated_index(text):
    return text.split("\n", 1)[0].strip() == build_index.BANNER


def link_targets(body):
    in_fence = False
    for line in body.splitlines():
        if line.lstrip().startswith(FENCE_MARKERS):
            in_fence = not in_fence
        elif not in_fence:
            yield from LINK_PATTERN.findall(INLINE_CODE_PATTERN.sub("", line))


def check_document(path, root, text, allowed_fields):
    """Return (failures, warnings, fields) for one document; fields is None when absent or malformed."""
    relative = path.relative_to(root).as_posix()
    failures, warnings = [], []
    try:
        fields, body = frontmatter.split_frontmatter(text)
    except frontmatter.FrontmatterError as error:
        return [f"{relative}: {error}"], warnings, None
    if fields is None:
        warnings.append(f"{relative}: unindexed (no frontmatter)")
    else:
        failures += [f"{relative}: missing field {name}" for name in allowed_fields if name not in fields]
        if isinstance(fields.get("covers"), str):
            warnings.append(f"warning: {relative}: covers should be a list")
        failures += [f"{relative}: unknown field {name}" for name in fields if name not in allowed_fields]
    for target in link_targets(body):
        if target.startswith(SKIPPED_SCHEMES):
            continue
        target_path = urllib.parse.unquote(target.split("#", 1)[0])
        base_dir = root if target_path.startswith("/") else path.parent
        if not (base_dir / target_path.lstrip("/")).exists():
            failures.append(f"{relative}: broken link target {target_path}")
    return failures, warnings, fields


def drift_warnings(documents, changed):
    warnings = []
    for relative, fields in documents:
        covers = (fields or {}).get("covers") or []
        if isinstance(covers, str):
            covers = [covers]
        touched = sorted(
            name for name in changed
            if any(fnmatch.fnmatch(name, pattern) for pattern in covers)
        )
        if touched and relative not in changed:
            warnings.append(
                f"warning: {relative} covers changed files but was not updated: {', '.join(touched)}"
            )
    return warnings


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", default=".", help="target repo root (default: cwd)")
    parser.add_argument("--base", help="git ref to diff against for covers-drift warnings")
    arguments = parser.parse_args(argv)

    root = Path(arguments.root).resolve()
    allowed_fields = frontmatter.required_fields(frontmatter.read_profile(root / "AGENTS.md"))
    context_dir = root / "context"
    failures, warnings, documents = [], [], []
    for path in sorted(context_dir.rglob("*.md")) if context_dir.is_dir() else []:
        if path.is_symlink():
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            failures.append(f"{path.relative_to(root).as_posix()}: not valid UTF-8")
            continue
        if is_generated_index(text):
            continue
        document_failures, document_warnings, fields = check_document(path, root, text, allowed_fields)
        failures += document_failures
        warnings += document_warnings
        documents.append((path.relative_to(root).as_posix(), fields))

    if arguments.base:
        try:
            warnings += drift_warnings(documents, changed_files(root, arguments.base))
        except GitError as error:
            print(str(error), file=sys.stderr)
            return 2

    for message in warnings:
        print(message)
    for message in failures:
        print(message)
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
