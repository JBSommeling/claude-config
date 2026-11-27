#!/usr/bin/env python3
"""Check that every DEC-nnn id cited under context/ is defined exactly once."""

import argparse
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import frontmatter  # noqa: E402

ID_PATTERN = re.compile(r"DEC-\d+")
DEFINITION_PATTERN = re.compile(r"^\s*(?:\|\s*|#{1,6}\s+)(DEC-\d+)\b")


def find_decisions_file(root, profile):
    preferred = frontmatter.specs_dir(root, profile) / "DECISIONS.md"
    if preferred.is_file():
        return preferred
    context_dir = root / "context"
    if context_dir.is_dir():
        return next(iter(sorted(context_dir.rglob("DECISIONS.md"))), None)
    return None


def scan(path, root, definitions, citations):
    relative = path.relative_to(root).as_posix()
    text = path.read_text(encoding="utf-8")
    for line_number, line in enumerate(text.splitlines(), start=1):
        definition = DEFINITION_PATTERN.match(line) if path.name == "DECISIONS.md" else None
        defined_span = definition.span(1) if definition else None
        if definition:
            definitions.setdefault(definition.group(1), []).append(f"{relative}:{line_number}")
        for match in ID_PATTERN.finditer(line):
            if match.span() != defined_span:
                citations.append((relative, line_number, match.group()))


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", default=".", help="target repo root (default: cwd)")
    arguments = parser.parse_args(argv)

    root = Path(arguments.root).resolve()
    profile = frontmatter.read_profile(root / "AGENTS.md")
    try:
        decisions_file = find_decisions_file(root, profile)
    except frontmatter.ProfileError as error:
        print(str(error), file=sys.stderr)
        return 2
    if decisions_file is None:
        print("no DECISIONS.md found; nothing to check")
        return 0

    files = set((root / "context").rglob("*.md")) if (root / "context").is_dir() else set()
    files = {path for path in files if not path.is_symlink()}
    files.add(decisions_file)
    definitions, citations, failures = {}, [], []
    for path in sorted(files):
        try:
            scan(path, root, definitions, citations)
        except UnicodeDecodeError:
            failures.append(f"{path.relative_to(root).as_posix()}: not valid UTF-8")
    for decision_id, locations in sorted(definitions.items()):
        if len(locations) > 1:
            failures.append(f"{decision_id} is defined more than once: {' and '.join(locations)}")
    for relative, line_number, decision_id in citations:
        if decision_id not in definitions:
            failures.append(f"{relative}:{line_number}: {decision_id} is cited but not defined")
    for message in failures:
        print(message)
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
