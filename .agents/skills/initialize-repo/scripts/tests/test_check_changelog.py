import contextlib
import io
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import check_changelog  # noqa: E402


def run(root, *extra):
    out, err = io.StringIO(), io.StringIO()
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
        code = check_changelog.main(["--root", str(root), *extra])
    return code, out.getvalue() + err.getvalue()


def git(root, *args):
    subprocess.run(
        ["git", "-c", "user.name=t", "-c", "user.email=t@t", *args],
        cwd=root, check=True, capture_output=True,
    )


class CheckChangelogTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.addCleanup(self.temp.cleanup)
        git(self.root, "init")
        (self.root / "CHANGELOG.md").write_text("# Changelog\n", encoding="utf-8")
        (self.root / "code.py").write_text("1\n", encoding="utf-8")
        git(self.root, "add", "-A")
        git(self.root, "commit", "-m", "base")

    def commit_change(self, relative, text):
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
        git(self.root, "add", "-A")
        git(self.root, "commit", "-m", "change")

    def test_changelog_changed_passes(self):
        self.commit_change("CHANGELOG.md", "# Changelog\n- entry\n")
        self.assertEqual(run(self.root, "--base", "HEAD~1")[0], 0)

    def test_fragment_only_passes(self):
        self.commit_change("changes/1.md", "entry\n")
        self.assertEqual(run(self.root, "--base", "HEAD~1")[0], 0)

    def test_neither_fails(self):
        self.commit_change("code.py", "2\n")
        code, output = run(self.root, "--base", "HEAD~1")
        self.assertEqual(code, 1)
        self.assertIn("no-changelog", output)

    def test_skip(self):
        code, output = run(self.root, "--skip")
        self.assertEqual(code, 0)
        self.assertIn("skipped", output)

    def test_bad_ref(self):
        self.assertEqual(run(self.root, "--base", "nope")[0], 2)

    def test_base_required_without_skip(self):
        self.assertEqual(run(self.root)[0], 2)


if __name__ == "__main__":
    unittest.main()
