#!/usr/bin/env python3
"""Serve a test-plan run directory on localhost so the form can read plan.json and save results.json."""

import argparse
import json
import os
import signal
import sys
import tempfile
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

MAX_BODY_BYTES = 1024 * 1024
ALLOWED_STATUSES = {"in_progress", "submitted"}
PAGE_HEAD = (
    '<!doctype html><html><head><meta charset="utf-8">'
    '<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">'
    "</head><body>"
)
PAGE_TAIL = "</body></html>"


def build_handler(run_dir: Path):
    plan_path = run_dir / "plan.json"
    results_path = run_dir / "results.json"
    form_path = run_dir / "form.html"

    class Handler(BaseHTTPRequestHandler):
        server_version = "TestPlanServer"

        def log_message(self, format, *args):
            pass

        def send_bytes(self, status, body, content_type):
            self.send_response(status)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(body)

        def send_json(self, status, payload):
            self.send_bytes(status, json.dumps(payload).encode("utf-8"), "application/json; charset=utf-8")

        def send_error_json(self, status, message):
            self.send_json(status, {"ok": False, "error": message})

        def allowed_authorities(self):
            port = self.server.server_address[1]
            return {f"127.0.0.1:{port}", f"localhost:{port}"}

        def host_is_allowed(self):
            return self.headers.get("Host", "") in self.allowed_authorities()

        def origin_is_allowed(self):
            origin = self.headers.get("Origin")
            if origin is None:
                return True
            return origin in {f"http://{authority}" for authority in self.allowed_authorities()}

        def serve_file(self, path: Path, content_type, wrap_page=False):
            try:
                body = path.read_bytes()
            except FileNotFoundError:
                self.send_error_json(404, f"{path.name} not found in run directory")
                return
            if wrap_page:
                body = PAGE_HEAD.encode("utf-8") + body + PAGE_TAIL.encode("utf-8")
            self.send_bytes(200, body, content_type)

        def do_GET(self):
            if not self.host_is_allowed():
                self.send_error_json(403, "Host header not allowed")
                return
            route = self.path.split("?", 1)[0]
            if route == "/":
                self.serve_file(form_path, "text/html; charset=utf-8", wrap_page=True)
            elif route == "/plan.json":
                self.serve_file(plan_path, "application/json; charset=utf-8")
            elif route == "/results.json":
                self.serve_file(results_path, "application/json; charset=utf-8")
            else:
                self.send_error_json(404, "Not found")

        def do_POST(self):
            status, message = self.handle_results_post()
            sys.stderr.write(f"POST {self.path} -> {status} {message}\n")
            sys.stderr.flush()

        def handle_results_post(self):
            def fail(status, message):
                self.send_error_json(status, message)
                return status, message

            if not self.host_is_allowed():
                return fail(403, "Host header not allowed")
            if not self.origin_is_allowed():
                return fail(403, "Origin not allowed")
            if self.path.split("?", 1)[0] != "/results.json":
                return fail(404, "Not found")
            content_type = self.headers.get("Content-Type", "").split(";", 1)[0].strip().lower()
            if content_type != "application/json":
                return fail(415, "Content-Type must be application/json")
            try:
                declared_length = int(self.headers.get("Content-Length", ""))
            except ValueError:
                return fail(411, "Content-Length header required")
            if declared_length < 0:
                return fail(400, "Invalid Content-Length")
            if declared_length > MAX_BODY_BYTES:
                return fail(413, f"Body exceeds {MAX_BODY_BYTES} bytes")
            raw_body = self.rfile.read(declared_length)
            try:
                submitted = json.loads(raw_body)
            except (ValueError, UnicodeDecodeError):
                return fail(400, "Body is not valid JSON")
            if not isinstance(submitted, dict):
                return fail(400, "Body must be a JSON object")
            try:
                expected_plan_id = json.loads(plan_path.read_text(encoding="utf-8")).get("planId")
            except (OSError, ValueError, AttributeError):
                return fail(500, "plan.json is missing or unreadable")
            if submitted.get("planId") != expected_plan_id:
                return fail(400, "planId does not match plan.json")
            if submitted.get("status") not in ALLOWED_STATUSES:
                return fail(400, "status must be 'in_progress' or 'submitted'")

            with tempfile.NamedTemporaryFile(
                "w", encoding="utf-8", dir=run_dir, prefix=".results-", suffix=".tmp", delete=False
            ) as temp_file:
                json.dump(submitted, temp_file, indent=2)
                temp_path = temp_file.name
            os.replace(temp_path, results_path)
            self.send_json(200, {"ok": True})
            return 200, f"status={submitted['status']}"

    return Handler


def main():
    parser = argparse.ArgumentParser(description="Serve a test-plan run directory on localhost.")
    parser.add_argument("run_dir", help="directory containing plan.json and form.html")
    parser.add_argument("--port", type=int, default=0, help="port to bind (default: OS-picked)")
    arguments = parser.parse_args()

    run_dir = Path(arguments.run_dir).expanduser().resolve()
    for required_name in ("plan.json", "form.html"):
        if not (run_dir / required_name).is_file():
            parser.error(f"{required_name} not found in {run_dir}")

    server = ThreadingHTTPServer(("127.0.0.1", arguments.port), build_handler(run_dir))

    def shut_down(signal_number, frame):
        raise KeyboardInterrupt

    signal.signal(signal.SIGTERM, shut_down)
    print(f"Test plan form: http://127.0.0.1:{server.server_address[1]}/", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
