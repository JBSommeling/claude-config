import contextlib
import io
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import build_index  # noqa: E402

DOC = "---\ntitle: Auth\nsummary: How login works\nread-when: touching login\nstatus: active\ncovers: []\n---\nbody\n"


def run(root, *extra):
    out, err = io.StringIO(), io.StringIO()
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
        code = build_index.main(["--root", str(root), *extra])
    return code, out.getvalue(), err.getvalue()


def write(root, relative, text):
    path = Path(root) / relative
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")
    return path


class BuildIndexTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.addCleanup(self.temp.cleanup)

    def read_index(self, relative):
        return (self.root / relative).read_text(encoding="utf-8")

    def test_indexes_document_with_frontmatter(self):
        write(self.root, "context/auth.md", DOC)
        self.assertEqual(run(self.root)[0], 0)
        index = self.read_index("context/README.md")
        self.assertTrue(index.startswith(build_index.BANNER))
        self.assertIn("# Context index", index)
        self.assertIn(
            "- [Auth](auth.md) — How login works · read when: touching login · status: active",
            index,
        )

    def test_missing_parts_are_omitted(self):
        write(self.root, "context/a.md", "---\ntitle: A\nstatus: draft\n---\n")
        run(self.root)
        self.assertIn("- [A](a.md) · status: draft\n", self.read_index("context/README.md"))

    def test_unindexed_section_for_missing_or_bad_frontmatter(self):
        write(self.root, "context/plain.md", "# no frontmatter\n")
        write(self.root, "context/bad.md", "---\ntitle: x\n- item\n---\n")
        run(self.root)
        index = self.read_index("context/README.md")
        self.assertIn("## Unindexed", index)
        self.assertIn("- [plain.md](plain.md)", index)
        self.assertIn("- [bad.md](bad.md)", index)

    def test_nested_folder_listed_and_indexed(self):
        write(self.root, "context/adr/0001.md", DOC)
        run(self.root)
        self.assertIn("## Folders", self.read_index("context/README.md"))
        self.assertIn("[adr](adr/README.md)", self.read_index("context/README.md"))
        self.assertIn("# Adr index", self.read_index("context/adr/README.md"))

    def test_readme_not_indexed(self):
        write(self.root, "context/README.md", "# hand written\n")
        write(self.root, "context/a.md", DOC)
        run(self.root)
        self.assertNotIn("(README.md)", self.read_index("context/README.md"))

    def test_does_not_touch_outside_context(self):
        write(self.root, "docs/x.md", DOC)
        write(self.root, "context/a.md", DOC)
        run(self.root)
        self.assertFalse((self.root / "docs" / "README.md").exists())

    def test_check_fresh_and_stale(self):
        write(self.root, "context/a.md", DOC)
        self.assertEqual(run(self.root, "--check")[0], 1)
        self.assertFalse((self.root / "context/README.md").exists())
        run(self.root)
        self.assertEqual(run(self.root, "--check")[0], 0)
        write(self.root, "context/b.md", DOC)
        code, out, err = run(self.root, "--check")
        self.assertEqual(code, 1)
        self.assertIn("README.md", out + err)

    def test_no_context_directory(self):
        code, out, _ = run(self.root)
        self.assertEqual(code, 0)
        self.assertIn("nothing to do", out)


if __name__ == "__main__":
    unittest.main()
