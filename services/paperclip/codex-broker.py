#!/usr/bin/env python3
"""Small internal OpenAI-compatible proxy for one Hermes Codex OAuth owner.

The Hermes image supplies hermes_cli.auth_codex, including its refresh-token
rotation lock and persistent auth-store handling. This process only forwards
Responses API requests; it never logs request bodies or credentials.
"""
from __future__ import annotations

import hmac
import json
import os
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

from hermes_cli.auth_codex import resolve_codex_runtime_credentials

LISTEN = (os.getenv("LISTEN_HOST", "0.0.0.0"), int(os.getenv("LISTEN_PORT", "8645")))
UPSTREAM_TIMEOUT = float(os.getenv("UPSTREAM_TIMEOUT_SECONDS", "300"))
MAX_BODY = int(os.getenv("MAX_BODY_BYTES", str(32 * 1024 * 1024)))
API_KEY = os.environ["BROKER_API_KEY"].encode()
_REFRESH_LOCK = threading.Lock()


def _json(handler: BaseHTTPRequestHandler, status: int, payload: dict) -> None:
    body = json.dumps(payload, separators=(",", ":")).encode()
    handler.send_response(status)
    handler.send_header("Content-Type", "application/json")
    handler.send_header("Content-Length", str(len(body)))
    handler.end_headers()
    handler.wfile.write(body)


def _upstream_path(path: str) -> str:
    # Hermes custom providers use base_url=http://broker:8645/v1. The Codex
    # base URL is .../backend-api/codex, whose Responses endpoint is /responses.
    if path == "/v1" or path == "/v1/":
        return "/"
    if path.startswith("/v1/"):
        return path[3:]
    return path


def _credentials() -> dict:
    # The Hermes resolver performs its own file locking. Keep this outer lock
    # so concurrent broker requests do not all race to refresh the same store.
    with _REFRESH_LOCK:
        return resolve_codex_runtime_credentials()


class Handler(BaseHTTPRequestHandler):
    server_version = "paperclip-codex-broker/1"

    def log_message(self, format: str, *args) -> None:
        # Do not log paths containing query strings or authorization material.
        if self.path.startswith("/healthz") or self.path.startswith("/readyz"):
            super().log_message(format, *args)

    def _authorized(self) -> bool:
        value = self.headers.get("Authorization", "")
        prefix = "Bearer "
        return value.startswith(prefix) and hmac.compare_digest(
            value[len(prefix):].encode(), API_KEY
        )

    def do_GET(self) -> None:
        if self.path == "/healthz":
            _json(self, 200, {"status": "ok"})
            return
        if self.path == "/readyz":
            try:
                with _REFRESH_LOCK:
                    creds = resolve_codex_runtime_credentials(read_only=True)  # type: ignore[call-arg]
                if not (creds.get("access_token") or creds.get("api_key")):
                    raise RuntimeError("no active access token")
                _json(self, 200, {"status": "ready"})
            except Exception:
                _json(self, 503, {"status": "not_ready"})
            return
        _json(self, 404, {"error": "not_found"})

    def do_POST(self) -> None:
        if not self._authorized():
            _json(self, 401, {"error": "unauthorized"})
            return
        if self.path not in ("/v1/responses", "/v1/chat/completions"):
            _json(self, 404, {"error": "unsupported_path"})
            return
        try:
            length = int(self.headers.get("Content-Length", "-1"))
        except ValueError:
            length = -1
        if length < 0 or length > MAX_BODY:
            _json(self, 413, {"error": "invalid_or_oversized_body"})
            return
        body = self.rfile.read(length)
        try:
            creds = _credentials()
            token = creds.get("access_token") or creds.get("api_key")
            base_url = str(creds.get("base_url") or "").rstrip("/")
            if not token or not base_url:
                raise RuntimeError("Codex credentials are unavailable")
            request = Request(
                base_url + _upstream_path(self.path),
                data=body,
                method="POST",
                headers={
                    "Authorization": f"Bearer {token}",
                    "Content-Type": self.headers.get("Content-Type", "application/json"),
                    "Accept": self.headers.get("Accept", "application/json"),
                    "User-Agent": "hermes-codex-broker/1",
                },
            )
            with urlopen(request, timeout=UPSTREAM_TIMEOUT) as response:
                self.send_response(response.status)
                content_type = response.headers.get("Content-Type")
                if not content_type:
                    content_type = "text/event-stream" if b'"stream":true' in body.replace(b" ", b"") else "application/json"
                self.send_header("Content-Type", content_type)
                for key in ("Cache-Control", "Connection"):
                    value = response.headers.get(key)
                    if value:
                        self.send_header(key, value)
                self.send_header("X-Accel-Buffering", "no")
                self.end_headers()
                while True:
                    chunk = response.read(64 * 1024)
                    if not chunk:
                        break
                    self.wfile.write(chunk)
                    self.wfile.flush()
        except HTTPError as exc:
            payload = exc.read(4096)
            self.send_response(exc.code)
            self.send_header("Content-Type", exc.headers.get("Content-Type", "application/json"))
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)
        except (URLError, TimeoutError, OSError, RuntimeError) as exc:
            _json(self, 502, {"error": "upstream_unavailable", "detail": str(exc)[:240]})
        except Exception:
            _json(self, 502, {"error": "broker_error"})


if __name__ == "__main__":
    ThreadingHTTPServer.allow_reuse_address = True
    server = ThreadingHTTPServer(LISTEN, Handler)
    print(f"codex broker listening on {LISTEN[0]}:{LISTEN[1]}", flush=True)
    server.serve_forever()
