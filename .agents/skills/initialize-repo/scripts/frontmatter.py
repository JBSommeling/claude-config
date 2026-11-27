"""Minimal frontmatter and repo-profile reader shared by the repo check scripts.

Stdlib only so it can be copied into any target repo's tools/ folder.
"""

from pathlib import Path

DEFAULT_FIELDS = ("title", "summary", "read-when", "status", "covers")
DEFAULT_SPECS_DIR = "context/specs"
FENCE = "---"


class FrontmatterError(ValueError):
    """Raised when a frontmatter block uses syntax outside the supported subset."""


def unquote(value):
    if len(value) >= 2 and value[0] == value[-1] and value[0] in ("'", '"'):
        return value[1:-1]
    return value


def parse_flow_list(value):
    inner = value[1:-1].strip()
    if not inner:
        return []
    return [unquote(item.strip()) for item in inner.split(",")]


def parse_value(raw_value):
    value = raw_value.strip()
    if value.startswith("[") and value.endswith("]"):
        return parse_flow_list(value)
    return unquote(value)


def parse_block(block_lines, first_line_number):
    parsed = {}
    for offset, line in enumerate(block_lines):
        line_number = first_line_number + offset
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        if line[0] in (" ", "\t") or stripped.startswith("- ") or ":" not in stripped:
            raise FrontmatterError(f"line {line_number}: unsupported frontmatter syntax: {line!r}")
        key, _, raw_value = stripped.partition(":")
        parsed[key.strip()] = parse_value(raw_value)
    return parsed


def split_frontmatter(text):
    """Return (frontmatter dict or None, body text)."""
    lines = text.splitlines(keepends=True)
    if not lines or lines[0].rstrip("\r\n") != FENCE:
        return None, text
    for index in range(1, len(lines)):
        if lines[index].rstrip("\r\n") == FENCE:
            block = [line.rstrip("\r\n") for line in lines[1:index]]
            return parse_block(block, 2), "".join(lines[index + 1 :])
    raise FrontmatterError("line 1: frontmatter block is not terminated by '---'")


def parse_frontmatter(text):
    return split_frontmatter(text)[0]


def read_profile(agents_md):
    """Read the '## Repo profile' bullets of AGENTS.md, or None when absent."""
    path = Path(agents_md)
    if not path.is_file():
        return None
    profile = None
    for line in path.read_text().splitlines():
        if line.startswith("## "):
            if profile is not None:
                break
            if line[3:].strip().lower() == "repo profile":
                profile = {}
            continue
        if profile is None or not line.lstrip().startswith("- ") or ":" not in line:
            continue
        key, _, raw_value = line.lstrip()[2:].partition(":")
        value = raw_value.split("#", 1)[0].strip()
        profile[key.strip().lower()] = value
    return profile


def required_fields(profile):
    if profile and profile.get("frontmatter"):
        return tuple(name.strip() for name in profile["frontmatter"].split(",") if name.strip())
    return DEFAULT_FIELDS


def specs_dir(root, profile):
    if profile and profile.get("specs"):
        return Path(root) / profile["specs"].rstrip("/")
    return Path(root) / DEFAULT_SPECS_DIR
