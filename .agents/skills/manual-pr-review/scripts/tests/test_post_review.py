import contextlib
import io
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import post_review  # noqa: E402

REVIEW = {
    "reviewId": "r1",
    "pr": {"host": "github", "url": "u", "number": 5, "title": "T", "headSha": "abc123"},
    "warnings": [],
    "issues": [
        {"id": "I1", "path": "a.py", "line": 3, "postable": True, "unpostableReason": None},
        {"id": "I2", "path": "b.py", "line": 9, "postable": True, "unpostableReason": None},
        {"id": "I3", "path": "c.py", "line": 1, "postable": False, "unpostableReason": "file not in diff"},
    ],
}


def make_results(decisions, review_id="r1", status="submitted"):
    return {"reviewId": review_id, "status": status, "savedAt": "now", "decisions": decisions}


class ValidateTests(unittest.TestCase):
    def assert_rejected(self, results, fragment):
        with self.assertRaises(post_review.ValidationError) as context:
            post_review.validate_results(REVIEW, results)
        self.assertIn(fragment, str(context.exception))

    def test_valid_returns_comments_and_drops_skips(self):
        comments = post_review.validate_results(REVIEW, make_results([
            {"id": "I1", "action": "post", "body": "hello"},
            {"id": "I2", "action": "skip", "body": ""},
        ]))
        self.assertEqual(comments, [{"id": "I1", "path": "a.py", "line": 3, "body": "hello"}])

    def test_review_id_mismatch(self):
        self.assert_rejected(make_results([], review_id="x"), "reviewId")

    def test_status_not_submitted(self):
        self.assert_rejected(make_results([], status="in_progress"), "submitted")

    def test_unknown_id(self):
        self.assert_rejected(make_results([{"id": "I9", "action": "skip", "body": ""}]), "unknown")

    def test_duplicate_id(self):
        self.assert_rejected(make_results([
            {"id": "I1", "action": "skip", "body": ""},
            {"id": "I1", "action": "skip", "body": ""},
        ]), "duplicate")

    def test_bad_action(self):
        self.assert_rejected(make_results([{"id": "I1", "action": "delete", "body": "x"}]), "action")

    def test_empty_body(self):
        self.assert_rejected(make_results([{"id": "I1", "action": "post", "body": "   "}]), "body")

    def test_non_string_body(self):
        self.assert_rejected(make_results([{"id": "I1", "action": "post", "body": 5}]), "body")

    def test_too_long_body(self):
        self.assert_rejected(
            make_results([{"id": "I1", "action": "post", "body": "x" * 10001}]), "10000"
        )

    def test_post_on_unpostable(self):
        self.assert_rejected(make_results([{"id": "I3", "action": "post", "body": "x"}]), "unpostable")

    def test_decisions_not_list(self):
        self.assert_rejected({"reviewId": "r1", "status": "submitted", "decisions": "x"}, "decisions")


class PayloadTests(unittest.TestCase):
    def test_github_payload_shape(self):
        payload = post_review.github_payload(
            "abc", [{"id": "I1", "path": "a.py", "line": 3, "body": "hi"}]
        )
        self.assertEqual(payload, {
            "commit_id": "abc",
            "event": "COMMENT",
            "comments": [{"path": "a.py", "line": 3, "side": "RIGHT", "body": "hi"}],
        })
        self.assertNotIn("body", payload)

    def test_azure_thread_shape(self):
        thread = post_review.azure_thread({"id": "I1", "path": "src/a.py", "line": 3, "body": "hi"})
        self.assertEqual(thread, {
            "comments": [{"parentCommentId": 0, "content": "hi", "commentType": 1}],
            "status": 1,
            "threadContext": {
                "filePath": "/src/a.py",
                "rightFileStart": {"line": 3, "offset": 1},
                "rightFileEnd": {"line": 3, "offset": 1},
            },
        })


EMOJI_BODY = "\U0001F44D\U0001F3FD \u2764\uFE0F \U0001F468\u200D\U0001F469\u200D\U0001F467"


class EmojiTests(unittest.TestCase):
    def test_length_limit_counts_characters(self):
        body = "\U0001F44D" * 10000
        self.assertGreater(len(body.encode("utf-8")), 10000)
        comments = post_review.validate_results(
            REVIEW, make_results([{"id": "I1", "action": "post", "body": body}])
        )
        self.assertEqual(comments[0]["body"], body)

    def test_github_payload_file_keeps_emoji(self):
        seen = {}

        def runner(command, **kwargs):
            input_path = Path(command[command.index("--input") + 1])
            seen["raw"] = input_path.read_bytes().decode("utf-8")
            return subprocess.CompletedProcess(command, 0, stdout="", stderr="")

        post_review.post("github", [{"id": "I1", "path": "a.py", "line": 3, "body": EMOJI_BODY}],
                         head_sha="abc", repo="o/r", number=5, runner=runner)
        self.assertTrue(seen["raw"].isascii())
        self.assertEqual(json.loads(seen["raw"])["comments"][0]["body"], EMOJI_BODY)

    def test_azure_payload_file_keeps_emoji(self):
        seen = {}

        def runner(command, **kwargs):
            input_path = Path(command[command.index("--in-file") + 1])
            seen["raw"] = input_path.read_bytes().decode("utf-8")
            return subprocess.CompletedProcess(command, 0, stdout="", stderr="")

        post_review.post("azure", [{"id": "I1", "path": "a.py", "line": 3, "body": EMOJI_BODY}],
                         number=5, org_url="https://dev.azure.com/o", project="P",
                         repository="R", runner=runner)
        self.assertTrue(seen["raw"].isascii())
        self.assertEqual(json.loads(seen["raw"])["comments"][0]["content"], EMOJI_BODY)

    def test_azure_thread_keeps_emoji(self):
        thread = post_review.azure_thread({"id": "I1", "path": "a.py", "line": 1, "body": EMOJI_BODY})
        self.assertEqual(thread["comments"][0]["content"], EMOJI_BODY)

    def test_github_payload_keeps_emoji(self):
        payload = post_review.github_payload("abc", [{"id": "I1", "path": "a.py", "line": 1, "body": EMOJI_BODY}])
        self.assertEqual(payload["comments"][0]["body"], EMOJI_BODY)


class PostTests(unittest.TestCase):
    COMMENTS = [
        {"id": "I1", "path": "a.py", "line": 3, "body": "one"},
        {"id": "I2", "path": "b.py", "line": 9, "body": "two"},
    ]

    def test_dry_run_makes_no_subprocess_call(self):
        runner = mock.Mock()
        report = post_review.post(
            "github", self.COMMENTS, head_sha="abc", repo="o/r", number=5, dry_run=True, runner=runner
        )
        runner.assert_not_called()
        self.assertEqual(report["failed"], 0)

    def test_nothing_to_post_makes_no_call(self):
        runner = mock.Mock()
        report = post_review.post("github", [], head_sha="abc", repo="o/r", number=5, runner=runner)
        runner.assert_not_called()
        self.assertEqual(report["posted"], 0)

    def test_github_command_is_arg_list_and_payload_cleaned_up(self):
        seen = {}

        def runner(command, **kwargs):
            seen["command"] = command
            seen["kwargs"] = kwargs
            input_path = Path(command[command.index("--input") + 1])
            seen["payload"] = json.loads(input_path.read_text())
            seen["path"] = input_path
            return subprocess.CompletedProcess(command, 0, stdout="{}", stderr="")

        report = post_review.post(
            "github", self.COMMENTS, head_sha="abc", repo="o/r", number=5, runner=runner
        )
        self.assertEqual(seen["command"][:3], ["gh", "api", "repos/o/r/pulls/5/reviews"])
        self.assertIn("POST", seen["command"])
        self.assertNotIn("shell", seen["kwargs"])
        self.assertEqual(len(seen["payload"]["comments"]), 2)
        self.assertFalse(seen["path"].exists())
        self.assertEqual(report["posted"], 2)

    def test_azure_partial_failure_reported(self):
        calls = []

        def runner(command, **kwargs):
            calls.append(command)
            code = 1 if len(calls) == 1 else 0
            return subprocess.CompletedProcess(command, code, stdout="", stderr="boom")

        report = post_review.post(
            "azure", self.COMMENTS, number=5, org_url="https://dev.azure.com/o",
            project="P", repository="R", runner=runner,
        )
        self.assertEqual(len(calls), 2)
        self.assertEqual(calls[0][:4], ["az", "devops", "invoke", "--area"])
        self.assertEqual((report["posted"], report["failed"]), (1, 1))
        self.assertEqual(report["failures"][0]["id"], "I1")
        self.assertIn("boom", report["failures"][0]["error"])

    def test_main_exits_nonzero_on_failure_and_writes_report(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "review.json").write_text(json.dumps(REVIEW))
            (root / "results.json").write_text(json.dumps(make_results(
                [{"id": "I1", "action": "post", "body": "x"}]
            )))
            failing = lambda command, **kwargs: subprocess.CompletedProcess(command, 1, "", "err")
            exit_code = post_review.main([
                "--review", str(root / "review.json"), "--results", str(root / "results.json"),
                "--host", "github", "--repo", "o/r", "--number", "5",
            ], runner=failing)
            self.assertNotEqual(exit_code, 0)
            report = json.loads((root / "post-report.json").read_text())
            self.assertEqual(report["failed"], 1)

    def test_main_validation_error_exits_nonzero(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "review.json").write_text(json.dumps(REVIEW))
            (root / "results.json").write_text(json.dumps(make_results([], status="in_progress")))
            exit_code = post_review.main([
                "--review", str(root / "review.json"), "--results", str(root / "results.json"),
                "--host", "github", "--repo", "o/r", "--number", "5",
            ], runner=mock.Mock())
            self.assertNotEqual(exit_code, 0)


class MainHarness(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.root = Path(self.directory.name)
        self.addCleanup(self.directory.cleanup)
        (self.root / "review.json").write_text(json.dumps(REVIEW))

    def write_results(self, decisions):
        (self.root / "results.json").write_text(json.dumps(make_results(decisions)))

    def run_main(self, extra=None, runner=None, host_args=None):
        arguments = ["--review", str(self.root / "review.json"), "--results", str(self.root / "results.json")]
        arguments += host_args or ["--host", "github", "--repo", "o/r"]
        arguments += extra if extra is not None else ["--number", "5"]
        with contextlib.redirect_stdout(io.StringIO()) as out, contextlib.redirect_stderr(io.StringIO()) as err:
            try:
                code = post_review.main(arguments, runner=runner or mock.Mock())
            except SystemExit as exit_signal:
                code = exit_signal.code
        return code, out.getvalue(), err.getvalue()


class MainBehaviorTests(MainHarness):
    POST_BOTH = [{"id": "I1", "action": "post", "body": "a"}, {"id": "I2", "action": "post", "body": "b"}]

    def test_github_nonzero_rc_fails_every_comment(self):
        self.write_results(self.POST_BOTH)
        failing = lambda command, **kwargs: subprocess.CompletedProcess(command, 1, "", "nope")
        code, _, _ = self.run_main(runner=failing)
        self.assertEqual(code, 1)
        report = json.loads((self.root / "post-report.json").read_text())
        self.assertEqual(report["failed"], 2)
        self.assertEqual([failure["id"] for failure in report["failures"]], ["I1", "I2"])

    def test_azure_dry_run_never_calls_runner(self):
        self.write_results(self.POST_BOTH)
        runner = mock.Mock()
        code, out, _ = self.run_main(
            extra=["--number", "5", "--dry-run"], runner=runner,
            host_args=["--host", "azure", "--org-url", "https://dev.azure.com/o",
                       "--project", "P", "--repository", "R"],
        )
        runner.assert_not_called()
        self.assertEqual(code, 0)
        self.assertFalse((self.root / "post-report.json").exists())

    def test_stdout_counts_mixed_post_and_skip(self):
        self.write_results([{"id": "I1", "action": "post", "body": "a"}, {"id": "I2", "action": "skip", "body": ""}])
        ok = lambda command, **kwargs: subprocess.CompletedProcess(command, 0, "", "")
        code, out, _ = self.run_main(runner=ok)
        self.assertEqual(code, 0)
        self.assertIn("posted=1 skipped=1 unpostable=1 failed=0", out)

    def test_payload_file_removed_when_runner_raises(self):
        seen = {}

        def raising(command, **kwargs):
            seen["path"] = Path(command[command.index("--input") + 1])
            raise RuntimeError("gh exploded")

        with self.assertRaises(RuntimeError):
            post_review.post("github", [{"id": "I1", "path": "a.py", "line": 1, "body": "x"}],
                             head_sha="abc", repo="o/r", number=5, runner=raising)
        self.assertTrue(seen["path"].name.startswith("manual-pr-review-"))
        self.assertFalse(seen["path"].exists())


class MainArgumentErrorTests(MainHarness):
    def setUp(self):
        super().setUp()
        self.write_results([{"id": "I1", "action": "post", "body": "a"}])

    def assert_exit_two_without_posting(self, **kwargs):
        runner = mock.Mock()
        code, _, err = self.run_main(runner=runner, **kwargs)
        self.assertEqual(code, 2)
        runner.assert_not_called()
        return err

    def test_missing_repo_for_github(self):
        self.assert_exit_two_without_posting(host_args=["--host", "github"])

    def test_missing_azure_arguments(self):
        self.assert_exit_two_without_posting(host_args=["--host", "azure", "--project", "P"])

    def test_missing_number(self):
        self.assert_exit_two_without_posting(extra=[])

    def test_number_mismatch(self):
        err = self.assert_exit_two_without_posting(extra=["--number", "6"])
        self.assertIn("number", err)

    def test_bad_github_repo_values(self):
        for repo in ("o", "o/r/x", "o/r; rm", "-o/r bad", "o/ r", "/r", "o/"):
            with self.subTest(repo):
                self.assert_exit_two_without_posting(host_args=["--host", "github", "--repo", repo])

    def test_bad_azure_values(self):
        good = {"--org-url": "https://dev.azure.com/o", "--project": "P", "--repository": "R"}
        bad_values = {
            "--org-url": ["http://dev.azure.com/o", "ftp://x", "-https://x", "https://x\n"],
            "--project": ["-P", "P\x07", "P\n"],
            "--repository": ["-R", "R\x00", "R\t"],
        }
        for option, values in bad_values.items():
            for value in values:
                with self.subTest(option=option, value=value):
                    options = dict(good, **{option: value})
                    host_args = ["--host", "azure"] + [part for pair in options.items() for part in pair]
                    self.assert_exit_two_without_posting(host_args=host_args)

    def test_missing_review_file_has_clear_message(self):
        (self.root / "review.json").unlink()
        err = self.assert_exit_two_without_posting()
        self.assertIn("review.json", err)
        self.assertNotIn("Traceback", err)

    def test_invalid_results_json_has_clear_message(self):
        (self.root / "results.json").write_text("{nope")
        err = self.assert_exit_two_without_posting()
        self.assertIn("results.json", err)
        self.assertNotIn("Traceback", err)


if __name__ == "__main__":
    unittest.main()
