from __future__ import annotations

import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from time import time


STARTED_AT = int(time())


class Handler(BaseHTTPRequestHandler):
    server_version = "nginx"
    sys_version = ""

    def _send(self, status: int, body: dict) -> None:
        raw = json.dumps(body, separators=(",", ":"), ensure_ascii=False).encode()
        self.send_response(status)
        self.send_header("content-type", "application/json; charset=utf-8")
        self.send_header("cache-control", "no-store")
        self.send_header("content-length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def do_GET(self) -> None:
        if self.path in {"/healthz", "/api/status"}:
            self._send(200, {"status": "ok", "uptime": int(time()) - STARTED_AT})
            return
        self._send(401, {"error": "authentication_required", "message": "Authentication required"})

    def do_POST(self) -> None:
        self._send(401, {"error": "authentication_required", "message": "Authentication required"})

    def log_message(self, format: str, *args: object) -> None:
        return


if __name__ == "__main__":
    ThreadingHTTPServer(("0.0.0.0", 8080), Handler).serve_forever()

