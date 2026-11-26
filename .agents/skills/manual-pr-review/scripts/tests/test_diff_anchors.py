import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import diff_anchors  # noqa: E402

SAMPLE_DIFF = """diff --git a/app.py b/app.py
index 111..222 100644
--- a/app.py
+++ b/app.py
@@ -1,5 +1,6 @@
 line one
-old two
+new two
+new two b
 line three
\\ No newline at end of file
 line four
 line five
@@ -20,3 +21,4 @@
 ctx twenty
 ctx twentyone
+added twentythree
 ctx twentytwo
diff --git a/gone.py b/gone.py
deleted file mode 100644
--- a/gone.py
+++ /dev/null
@@ -1,2 +0,0 @@
-a
-b
diff --git a/old_name.py b/new_name.py
similarity index 90%
rename from old_name.py
rename to new_name.py
--- a/old_name.py
+++ b/new_name.py
@@ -1,2 +1,2 @@
 keep
-before
+after
"""


def make_finding(path, line, severity="Important", title="t"):
    return {
        "severity": severity,
        "reviewers": ["code-reviewer"],
        "path": path,
        "line": line,
        "title": title,
        "recommendation": "fix it",
    }


class ParseDiffTests(unittest.TestCase):
    def setUp(self):
        self.files = diff_anchors.parse_diff(SAMPLE_DIFF)

    def test_valid_new_side_lines(self):
        valid = self.files["app.py"]["valid_lines"]
        self.assertEqual(valid, {1, 2, 3, 4, 5, 6, 21, 22, 23, 24})

    def test_no_newline_marker_does_not_advance_counters(self):
        hunk_lines = self.files["app.py"]["hunks"][0]
        line_four = [entry for entry in hunk_lines if entry["text"] == "line four"][0]
        self.assertEqual(line_four["newLine"], 5)
        self.assertEqual(line_four["oldLine"], 4)

    def test_deleted_line_tracks_old_line_only(self):
        hunk_lines = self.files["app.py"]["hunks"][0]
        deleted = [entry for entry in hunk_lines if entry["kind"] == "del"][0]
        self.assertEqual((deleted["oldLine"], deleted["newLine"]), (2, None))

    def test_deleted_file_has_no_valid_lines(self):
        self.assertEqual(self.files["gone.py"]["valid_lines"], set())

    def test_rename_uses_new_path(self):
        self.assertIn("new_name.py", self.files)
        self.assertNotIn("old_name.py", self.files)
        self.assertEqual(self.files["new_name.py"]["valid_lines"], {1, 2})

    def test_header_kind_is_hunk_line(self):
        first = self.files["app.py"]["hunks"][0][0]
        self.assertEqual(first["kind"], "header")
        self.assertTrue(first["text"].startswith("@@"))


class BuildReviewTests(unittest.TestCase):
    META = {
        "reviewId": "repo-pr-1-20260101-1200",
        "pr": {"host": "github", "url": "u", "number": 1, "title": "T", "headSha": "abc"},
        "warnings": [],
    }

    def build(self, findings, diff=SAMPLE_DIFF, context=3):
        return diff_anchors.build_review(diff, findings, self.META, context)

    def test_valid_line_is_postable(self):
        review = self.build([make_finding("app.py", 3)])
        issue = review["issues"][0]
        self.assertTrue(issue["postable"])
        self.assertIsNone(issue["unpostableReason"])
        self.assertEqual(review["reviewId"], self.META["reviewId"])
        self.assertEqual(review["pr"], self.META["pr"])

    def test_line_outside_diff_is_unpostable(self):
        issue = self.build([make_finding("app.py", 10)])["issues"][0]
        self.assertFalse(issue["postable"])
        self.assertEqual(issue["unpostableReason"], "line not on the new side of the diff")
        self.assertEqual(issue["hunk"], [])

    def test_file_absent(self):
        issue = self.build([make_finding("nope.py", 1)])["issues"][0]
        self.assertFalse(issue["postable"])
        self.assertEqual(issue["unpostableReason"], "file not in diff")

    def test_deleted_file_is_unpostable(self):
        issue = self.build([make_finding("gone.py", 1)])["issues"][0]
        self.assertFalse(issue["postable"])

    def test_excerpt_is_bounded_by_context_and_marks_anchor(self):
        issue = self.build([make_finding("app.py", 22)], context=1)["issues"][0]
        anchors = [entry for entry in issue["hunk"] if entry["anchor"]]
        self.assertEqual(len(anchors), 1)
        self.assertEqual(anchors[0]["newLine"], 22)
        self.assertEqual([entry["text"] for entry in issue["hunk"]],
                         ["@@ -20,3 +21,4 @@", "ctx twenty", "ctx twentyone", "added twentythree"])

    def test_excerpt_stays_within_its_hunk(self):
        issue = self.build([make_finding("app.py", 21)], context=50)["issues"][0]
        texts = [entry["text"] for entry in issue["hunk"]]
        self.assertNotIn("line one", texts)
        self.assertEqual(issue["hunk"][0]["kind"], "header")

    def test_multi_hunk_picks_correct_hunk(self):
        issue = self.build([make_finding("app.py", 23)])["issues"][0]
        texts = [entry["text"] for entry in issue["hunk"]]
        self.assertIn("added twentythree", texts)
        self.assertNotIn("new two", texts)

    def test_sorting_and_ids(self):
        findings = [
            make_finding("app.py", 5, "Nit", "n"),
            make_finding("app.py", 3, "Critical", "c2"),
            make_finding("app.py", 1, "Critical", "c1"),
            make_finding("app.py", 2, "Suggestion", "s"),
        ]
        issues = self.build(findings)["issues"]
        self.assertEqual([issue["id"] for issue in issues], ["I1", "I2", "I3", "I4"])
        self.assertEqual([issue["title"] for issue in issues], ["c1", "c2", "s", "n"])

    def test_large_diff_warning(self):
        body = "".join(f"+row {number}\n" for number in range(1001))
        big_diff = "diff --git a/big.py b/big.py\n--- a/big.py\n+++ b/big.py\n@@ -0,0 +1,1001 @@\n" + body
        review = self.build([], diff=big_diff)
        self.assertTrue(any("1000" in warning for warning in review["warnings"]))

    def test_small_diff_has_no_extra_warning(self):
        self.assertEqual(self.build([])["warnings"], [])


class CliTests(unittest.TestCase):
    def test_main_writes_review_json(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "pr.diff").write_text(SAMPLE_DIFF)
            (root / "findings.json").write_text(json.dumps([make_finding("app.py", 3)]))
            (root / "meta.json").write_text(json.dumps(BuildReviewTests.META))
            diff_anchors.main([
                "--diff", str(root / "pr.diff"), "--findings", str(root / "findings.json"),
                "--meta", str(root / "meta.json"), "--out", str(root / "review.json"),
            ])
            review = json.loads((root / "review.json").read_text())
            self.assertEqual(review["issues"][0]["id"], "I1")


if __name__ == "__main__":
    unittest.main()
