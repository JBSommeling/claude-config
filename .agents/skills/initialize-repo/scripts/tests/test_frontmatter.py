import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import frontmatter  # noqa: E402


class ParseFrontmatterTest(unittest.TestCase):
    def test_no_frontmatter_returns_none(self):
        self.assertIsNone(frontmatter.parse_frontmatter("# Title\nbody\n"))

    def test_scalars_quotes_and_empty_value(self):
        text = "---\ntitle: Hello World\nsummary: 'single'\nstatus: \"double\"\nempty:\n---\nbody\n"
        self.assertEqual(
            frontmatter.parse_frontmatter(text),
            {"title": "Hello World", "summary": "single", "status": "double", "empty": ""},
        )

    def test_comments_and_blank_lines_ignored(self):
        text = "---\n# note\n\ntitle: A\n---\n"
        self.assertEqual(frontmatter.parse_frontmatter(text), {"title": "A"})

    def test_flow_lists(self):
        text = '---\ncovers: [a, b, "c d"]\nnone: []\nread-when: [ \'x y\' ]\n---\n'
        self.assertEqual(
            frontmatter.parse_frontmatter(text),
            {"covers": ["a", "b", "c d"], "none": [], "read-when": ["x y"]},
        )

    def test_unsupported_syntax_raises_with_line_number(self):
        text = "---\ntitle: A\n- block item\n---\n"
        with self.assertRaises(frontmatter.FrontmatterError) as context:
            frontmatter.parse_frontmatter(text)
        self.assertIn("3", str(context.exception))

    def test_nested_map_raises(self):
        text = "---\nparent:\n  child: 1\n---\n"
        with self.assertRaises(frontmatter.FrontmatterError) as context:
            frontmatter.parse_frontmatter(text)
        self.assertIn("3", str(context.exception))

    def test_unterminated_block_raises(self):
        with self.assertRaises(frontmatter.FrontmatterError):
            frontmatter.parse_frontmatter("---\ntitle: A\nbody\n")

    def test_error_is_value_error(self):
        self.assertTrue(issubclass(frontmatter.FrontmatterError, ValueError))


class SplitFrontmatterTest(unittest.TestCase):
    def test_returns_body(self):
        parsed, body = frontmatter.split_frontmatter("---\ntitle: A\n---\nline one\nline two\n")
        self.assertEqual(parsed, {"title": "A"})
        self.assertEqual(body, "line one\nline two\n")

    def test_no_frontmatter_returns_whole_text(self):
        parsed, body = frontmatter.split_frontmatter("plain\n")
        self.assertIsNone(parsed)
        self.assertEqual(body, "plain\n")


class ProfileTest(unittest.TestCase):
    def write_agents(self, content):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        path = Path(directory.name) / "AGENTS.md"
        path.write_text(content)
        return path

    def test_profile_parsed(self):
        path = self.write_agents(
            "# Agents\n\n## repo PROFILE\n\n- Type: library  # kind\n- Specs: docs/specs/\n"
            "- Frontmatter: title, summary\n\n## Other\n- Type: ignored\n"
        )
        self.assertEqual(
            frontmatter.read_profile(path),
            {"type": "library", "specs": "docs/specs/", "frontmatter": "title, summary"},
        )

    def test_profile_absent_returns_none(self):
        path = self.write_agents("# Agents\n\n## Other\n- Type: x\n")
        self.assertIsNone(frontmatter.read_profile(path))

    def test_missing_file_returns_none(self):
        self.assertIsNone(frontmatter.read_profile(Path("/nonexistent/AGENTS.md")))


class RequiredFieldsTest(unittest.TestCase):
    def test_default(self):
        self.assertEqual(frontmatter.required_fields(None), frontmatter.DEFAULT_FIELDS)
        self.assertEqual(frontmatter.required_fields({"type": "x"}), frontmatter.DEFAULT_FIELDS)

    def test_override(self):
        profile = {"frontmatter": "title, summary ,status"}
        self.assertEqual(frontmatter.required_fields(profile), ("title", "summary", "status"))


class QuotedListAndBomTest(unittest.TestCase):
    def test_comma_inside_quotes_stays_one_item(self):
        self.assertEqual(
            frontmatter.parse_frontmatter('---\nk: [always, "when a, b"]\n---\n'),
            {"k": ["always", "when a, b"]},
        )

    def test_brace_glob_stays_one_item(self):
        self.assertEqual(
            frontmatter.parse_frontmatter('---\ncovers: ["src/{a,b}/**"]\n---\n'),
            {"covers": ["src/{a,b}/**"]},
        )

    def test_leading_bom_is_ignored(self):
        self.assertEqual(
            frontmatter.parse_frontmatter("\ufeff---\ntitle: A\n---\nbody\n"),
            {"title": "A"},
        )


class SpecsDirTest(unittest.TestCase):
    def test_absolute_specs_rejected(self):
        with self.assertRaises(frontmatter.ProfileError):
            frontmatter.specs_dir(Path("/repo"), {"specs": "/etc"})

    def test_escaping_specs_rejected(self):
        with self.assertRaises(frontmatter.ProfileError):
            frontmatter.specs_dir(Path("/repo"), {"specs": "../outside"})

    def test_default(self):
        root = Path("/repo")
        self.assertEqual(frontmatter.specs_dir(root, None), root / "context/specs")

    def test_override(self):
        root = Path("/repo")
        self.assertEqual(frontmatter.specs_dir(root, {"specs": "docs/specs/"}), root / "docs/specs")


if __name__ == "__main__":
    unittest.main()
