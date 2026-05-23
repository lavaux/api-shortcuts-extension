#!/usr/bin/env python3
"""
Mock HTTP server for API Shortcuts extension testing.

Usage: python3 mock-server.py [port]

Handles GET, POST, PUT, PATCH, DELETE requests and responds with JSON:
  {"method": "<METHOD>", "path": "<PATH>", "message": "<METHOD> request received"}

Every request is logged to stderr with a [mock-server] prefix.
The server runs until the process is killed (it is stopped automatically
when the Podman container is torn down at the end of run-test.sh).
"""

import http.server
import json
import sys


PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 18080


class MockHandler(http.server.BaseHTTPRequestHandler):
    """Request handler that accepts all common HTTP methods."""

    def _read_body(self):
        length = int(self.headers.get("Content-Length", 0))
        return self.rfile.read(length).decode("utf-8") if length > 0 else ""

    def _respond(self, method, body=""):
        data = {
            "method": method,
            "path": self.path,
            "message": f"{method} request received",
        }
        if body:
            data["received_body"] = body
        payload = json.dumps(data).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def do_GET(self):
        self._respond("GET")

    def do_POST(self):
        self._respond("POST", self._read_body())

    def do_PUT(self):
        self._respond("PUT", self._read_body())

    def do_PATCH(self):
        self._respond("PATCH", self._read_body())

    def do_DELETE(self):
        self._respond("DELETE")

    def log_message(self, fmt, *args):
        sys.stderr.write(f"[mock-server] {fmt % args}\n")
        sys.stderr.flush()


def main():
    server = http.server.HTTPServer(("127.0.0.1", PORT), MockHandler)
    print(f"[mock-server] Listening on 127.0.0.1:{PORT}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
