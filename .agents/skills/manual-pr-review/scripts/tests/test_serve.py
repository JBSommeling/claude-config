import http.client
import json
import sys
import tempfile
import threading
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import serve  # noqa: E402


class ServeTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.run_dir = Path(self.directory.name)
        (self.run_dir / "review.json").write_text(json.dumps({"reviewId": "r1", "issues": []}))
        form_path = self.run_dir / "form.html"
        form_path.write_text("<p>form</p>")
        self.server = serve.make_server(self.run_dir, 0, form_path=form_path)
        self.port = self.server.server_address[1]
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join()
        self.directory.cleanup()

    def request(self, method, path, body=None, headers=None, host=None):
        connection = http.client.HTTPConnection("127.0.0.1", self.port)
        merged = {"Host": host or f"127.0.0.1:{self.port}"}
        merged.update(headers or {})
        connection.request(method, path, body=body, headers=merged)
        response = connection.getresponse()
        payload = response.read()
        connection.close()
        self.last_headers = dict(response.getheaders())
        return response.status, payload

    def post_results(self, payload, **kwargs):
        headers = {"Content-Type": "application/json"}
        headers.update(kwargs.pop("headers", {}))
        return self.request("POST", "/results.json", json.dumps(payload), headers, **kwargs)

    def test_get_form_and_review(self):
        status, body = self.request("GET", "/")
        self.assertEqual(status, 200)
        self.assertIn(b"<p>form</p>", body)
        status, body = self.request("GET", "/review.json")
        self.assertEqual(json.loads(body)["reviewId"], "r1")

    def test_valid_post_writes_file(self):
        status, _ = self.post_results({"reviewId": "r1", "status": "submitted", "decisions": []})
        self.assertEqual(status, 200)
        saved = json.loads((self.run_dir / "results.json").read_text())
        self.assertEqual(saved["status"], "submitted")
        status, body = self.request("GET", "/results.json")
        self.assertEqual(status, 200)

    def test_emoji_body_round_trips(self):
        body = "\U0001F44D\U0001F3FD \u2764\uFE0F \U0001F468\u200D\U0001F469\u200D\U0001F467 caf\u00e9"
        payload = {"reviewId": "r1", "status": "submitted",
                   "decisions": [{"id": "I1", "action": "post", "body": body}]}
        raw = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        status, _ = self.request("POST", "/results.json", raw, {"Content-Type": "application/json"})
        self.assertEqual(status, 200)
        saved = json.loads((self.run_dir / "results.json").read_bytes().decode("utf-8"))
        self.assertEqual(saved["decisions"][0]["body"], body)

    def test_invalid_utf8_body(self):
        status, _ = self.request(
            "POST", "/results.json", b"\xff\xfe", {"Content-Type": "application/json"}
        )
        self.assertEqual(status, 400)

    def test_wrong_review_id(self):
        status, _ = self.post_results({"reviewId": "other", "status": "submitted"})
        self.assertEqual(status, 400)
        self.assertFalse((self.run_dir / "results.json").exists())

    def test_bad_status(self):
        status, _ = self.post_results({"reviewId": "r1", "status": "done"})
        self.assertEqual(status, 400)

    def test_bad_host(self):
        status, _ = self.post_results({"reviewId": "r1", "status": "submitted"}, host="evil.com")
        self.assertEqual(status, 403)
        status, _ = self.request("GET", "/", host="evil.com")
        self.assertEqual(status, 403)

    def test_bad_origin(self):
        status, _ = self.post_results(
            {"reviewId": "r1", "status": "submitted"}, headers={"Origin": "http://evil.com"}
        )
        self.assertEqual(status, 403)

    def test_non_json_content_type(self):
        status, _ = self.request(
            "POST", "/results.json", "x=1", {"Content-Type": "text/plain"}
        )
        self.assertEqual(status, 415)

    def test_invalid_json_body(self):
        status, _ = self.request(
            "POST", "/results.json", "{nope", {"Content-Type": "application/json"}
        )
        self.assertEqual(status, 400)

    def test_oversize_body(self):
        connection = http.client.HTTPConnection("127.0.0.1", self.port)
        connection.putrequest("POST", "/results.json", skip_host=True)
        connection.putheader("Host", f"127.0.0.1:{self.port}")
        connection.putheader("Content-Type", "application/json")
        connection.putheader("Content-Length", str(serve.MAX_BODY_BYTES + 1))
        connection.endheaders()
        self.assertEqual(connection.getresponse().status, 413)
        connection.close()

    def test_wrong_post_path(self):
        status, _ = self.request(
            "POST", "/other", "{}", {"Content-Type": "application/json"}
        )
        self.assertEqual(status, 404)


    def assert_security_headers(self):
        self.assertEqual(self.last_headers["X-Frame-Options"], "DENY")
        self.assertEqual(self.last_headers["X-Content-Type-Options"], "nosniff")
        self.assertEqual(self.last_headers["Content-Security-Policy"], serve.CONTENT_SECURITY_POLICY)
        self.assertIn("frame-ancestors 'none'", serve.CONTENT_SECURITY_POLICY)

    def test_security_headers_on_get(self):
        self.request("GET", "/")
        self.assert_security_headers()

    def test_security_headers_on_post_and_errors(self):
        self.post_results({"reviewId": "r1", "status": "in_progress"})
        self.assert_security_headers()
        self.request("GET", "/nope")
        self.assert_security_headers()

    def test_non_object_json_body_rejected(self):
        for body in ("[1, 2]", '"text"', "7", "null"):
            with self.subTest(body):
                status, _ = self.request(
                    "POST", "/results.json", body, {"Content-Type": "application/json"}
                )
                self.assertEqual(status, 400)

    def test_handler_socket_timeout(self):
        self.assertEqual(self.server.RequestHandlerClass.timeout, 10)

    def test_temp_write_failure_returns_500_and_leaves_no_temp_file(self):
        with mock.patch.object(serve.json, "dump", side_effect=OSError("disk full")):
            status, _ = self.post_results({"reviewId": "r1", "status": "in_progress"})
        self.assertEqual(status, 500)
        self.assertEqual(list(self.run_dir.glob(".results-*")), [])
        self.assertFalse((self.run_dir / "results.json").exists())


if __name__ == "__main__":
    unittest.main()
