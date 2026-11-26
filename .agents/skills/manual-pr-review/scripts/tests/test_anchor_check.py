import contextlib
import copy
import io
import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import anchor_check  # noqa: E402

DIFF = """diff --git a/a.py b/a.py
--- a/a.py
+++ b/a.py
@@ -1,3 +1,4 @@
 one
+two
 three
 four
"""


def hunk_row(kind, old_line, new_line, text, anchor=False):
    return {"kind": kind, "oldLine": old_line, "newLine": new_line, "text": text, "anchor": anchor}


def make_issue(issue_id, line, anchor_text):
    return {
        "id": issue_id, "path": "a.py", "line": line, "title": f"title {issue_id}",
        "recommendation": f"rec {issue_id}", "postable": True, "unpostableReason": None,
        "hunk": [
            {"kind": "header", "oldLine": None, "newLine": None, "text": "@@ -1,3 +1,4 @@", "anchor": False},
            hunk_row("add", None, line, anchor_text, anchor=True),
        ],
    }


REVIEW = {
    "reviewId": "r1",
    "pr": {"host": "github", "url": "u", "number": 5, "title": "T", "headSha": "abc"},
    "warnings": [],
    "issues": [make_issue("I1", 2, "two"), make_issue("I2", 3, "three")],
}


class AnchorCheckTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.root = Path(self.directory.name)
        self.addCleanup(self.directory.cleanup)
        (self.root / "pr.diff").write_text(DIFF)

    def run_check(self, review, decisions):
        (self.root / "review.json").write_text(json.dumps(review))
        (self.root / "results.json").write_text(json.dumps(
            {"reviewId": "r1", "status": "submitted", "savedAt": "now", "decisions": decisions}
        ))
        arguments = [
            "--review", str(self.root / "review.json"), "--results", str(self.root / "results.json"),
            "--diff", str(self.root / "pr.diff"), "--out", str(self.root / "anchor-check.json"),
        ]
        with contextlib.redirect_stdout(io.StringIO()) as out, contextlib.redirect_stderr(io.StringIO()) as err:
            code = anchor_check.main(arguments)
        output_path = self.root / "anchor-check.json"
        entries = json.loads(output_path.read_text(encoding="utf-8")) if output_path.exists() else None
        return code, entries, out.getvalue() + err.getvalue()

    def test_all_good_exits_zero_with_full_hunk(self):
        code, entries, _ = self.run_check(REVIEW, [
            {"id": "I1", "action": "post", "body": "my words"},
            {"id": "I2", "action": "post", "body": ""},
        ])
        self.assertEqual(code, 0)
        first, second = entries
        self.assertTrue(first["lineValid"] and first["textMatches"])
        self.assertEqual(first["bodySource"], "comment")
        self.assertEqual(first["body"], "my words")
        self.assertEqual(second["bodySource"], "recommendation")
        self.assertEqual(second["body"], "rec I2")
        self.assertEqual(second["title"], "title I2")
        self.assertEqual(second["anchorText"], "three")
        self.assertEqual([row["text"] for row in first["hunk"][1:]], ["one", "two", "three", "four"])
        self.assertEqual([row["anchor"] for row in first["hunk"][1:]], [False, True, False, False])
        self.assertEqual([row["anchor"] for row in second["hunk"][1:]], [False, False, True, False])

    def test_line_not_in_diff(self):
        review = copy.deepcopy(REVIEW)
        review["issues"][0]["line"] = 40
        code, entries, summary = self.run_check(review, [{"id": "I1", "action": "post", "body": "x"}])
        self.assertEqual(code, 3)
        self.assertFalse(entries[0]["lineValid"])
        self.assertFalse(entries[0]["textMatches"])
        self.assertEqual(entries[0]["hunk"], [])
        self.assertIn("I1", summary)

    def test_text_differs(self):
        review = copy.deepcopy(REVIEW)
        review["issues"][0]["hunk"][1]["text"] = "edited"
        code, entries, summary = self.run_check(review, [{"id": "I1", "action": "post", "body": "x"}])
        self.assertEqual(code, 3)
        self.assertTrue(entries[0]["lineValid"])
        self.assertFalse(entries[0]["textMatches"])
        self.assertIn("I1", summary)

    def test_missing_anchor_row_is_mismatch(self):
        review = copy.deepcopy(REVIEW)
        review["issues"][0]["hunk"][1]["anchor"] = False
        code, entries, _ = self.run_check(review, [{"id": "I1", "action": "post", "body": "x"}])
        self.assertEqual(code, 3)
        self.assertFalse(entries[0]["textMatches"])

    def test_skipped_decisions_are_not_checked(self):
        code, entries, _ = self.run_check(REVIEW, [
            {"id": "I1", "action": "skip", "body": ""},
            {"id": "I2", "action": "post", "body": "x"},
        ])
        self.assertEqual(code, 0)
        self.assertEqual([entry["id"] for entry in entries], ["I2"])

    def test_validation_error_exits_two(self):
        code, entries, message = self.run_check(REVIEW, [{"id": "I9", "action": "post", "body": "x"}])
        self.assertEqual(code, 2)
        self.assertIn("unknown issue id", message)


if __name__ == "__main__":
    unittest.main()
