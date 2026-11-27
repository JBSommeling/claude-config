import contextlib
import io
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import check_ids  # noqa: E402

TABLE = "| ID | Decision |\n|---|---|\n| DEC-001 | one |\n| DEC-002 | two |\n"


def run(root):
    out, err = io.StringIO(), io.StringIO()
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
        code = check_ids.main(["--root", str(root)])
    return code, out.getvalue() + err.getvalue()


def write(root, relative, text):
    path = Path(root) / relative
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


class CheckIdsTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.addCleanup(self.temp.cleanup)

    def test_clean_pass(self):
        write(self.root, "context/specs/DECISIONS.md", TABLE + "\n## DEC-003\nsee DEC-001\n")
        write(self.root, "context/other.md", "Relies on DEC-002.\n")
        self.assertEqual(run(self.root)[0], 0)

    def test_duplicate_definition(self):
        write(self.root, "context/specs/DECISIONS.md", TABLE + "| DEC-001 | again |\n")
        code, output = run(self.root)
        self.assertEqual(code, 1)
        self.assertIn("DEC-001 is defined more than once: ", output)
        self.assertIn("DECISIONS.md:3", output)
        self.assertIn("DECISIONS.md:5", output)

    def test_specs_outside_root_is_usage_error(self):
        write(self.root, "AGENTS.md", "## Repo profile\n- Specs: ../outside\n")
        code, output = run(self.root)
        self.assertEqual(code, 2)
        self.assertIn("Specs", output)

    def test_non_utf8_file_fails(self):
        write(self.root, "context/specs/DECISIONS.md", TABLE)
        (self.root / "context" / "bad.md").write_bytes(b"\xff\xfe\x00bad")
        code, output = run(self.root)
        self.assertEqual(code, 1)
        self.assertIn("context/bad.md: not valid UTF-8", output)

    def test_symlinked_file_is_skipped(self):
        write(self.root, "context/specs/DECISIONS.md", TABLE)
        outside = self.root / "outside.md"
        outside.write_text("cites DEC-999\n", encoding="utf-8")
        (self.root / "context" / "link.md").symlink_to(outside)
        self.assertEqual(run(self.root)[0], 0)

    def test_dangling_citation(self):
        write(self.root, "context/specs/DECISIONS.md", TABLE)
        write(self.root, "context/other.md", "ok\nsee DEC-012\n")
        code, output = run(self.root)
        self.assertEqual(code, 1)
        self.assertIn("other.md:2: DEC-012 is cited but not defined", output)

    def test_profile_specs_path_used(self):
        write(self.root, "AGENTS.md", "## Repo profile\n- Specs: docs/specs/\n")
        write(self.root, "docs/specs/DECISIONS.md", TABLE)
        write(self.root, "context/a.md", "DEC-002\n")
        self.assertEqual(run(self.root)[0], 0)

    def test_found_elsewhere_under_context(self):
        write(self.root, "context/deep/DECISIONS.md", TABLE)
        self.assertEqual(run(self.root)[0], 0)

    def test_no_decisions_file(self):
        code, output = run(self.root)
        self.assertEqual(code, 0)
        self.assertIn("DECISIONS.md", output)


if __name__ == "__main__":
    unittest.main()
