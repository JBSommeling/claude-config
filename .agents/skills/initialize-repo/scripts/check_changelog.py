#!/usr/bin/env python3
"""Require a changelog entry (CHANGELOG.md or a changes/ fragment) on a change."""

import argparse
import subprocess
import sys
from pathlib import Path


def changed_files(root, base_ref):
    """Return files added, copied, modified or renamed since base_ref, or None on git failure."""
    try:
        result = subprocess.run(
            ["git", "-C", str(root), "diff", "--name-only", "--diff-filter=ACMR",
             "--relative", f"{base_ref}...HEAD"],
            capture_output=True, text=True,
        )
    except OSError as error:
        print(f"cannot run git: {error}", file=sys.stderr)
        return None
    if result.returncode != 0:
        print(f"git diff against {base_ref!r} failed: {result.stderr.strip()}", file=sys.stderr)
        return None
    return set(result.stdout.split("\n")) - {""}


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", default=".", help="target repo root (default: cwd)")
    parser.add_argument("--base", help="git ref the change is compared against")
    parser.add_argument("--skip", action="store_true", help="skip the check (no-changelog label)")
    arguments = parser.parse_args(argv)

    if arguments.skip:
        print("changelog check skipped")
        return 0
    if not arguments.base:
        print("--base is required unless --skip is given", file=sys.stderr)
        return 2
    changed = changed_files(Path(arguments.root).resolve(), arguments.base)
    if changed is None:
        return 2
    if "CHANGELOG.md" in changed or any(name.startswith("changes/") for name in changed):
        return 0
    print(
        "No changelog entry: add one under Unreleased in CHANGELOG.md, add a fragment "
        "in changes/, or label the PR no-changelog."
    )
    return 1


if __name__ == "__main__":
    sys.exit(main())
