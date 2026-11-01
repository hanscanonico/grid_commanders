"""PostHog's query endpoint on a real socket, so the real urllib path runs."""

from __future__ import annotations

import json
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from types import SimpleNamespace


class FakePostHog:
    def __init__(self) -> None:
        self.answers: dict[str, list] = {}
        self.status = 200
        self.raw: bytes | None = None
        self.location: str | None = None
        self.cut_short = False
        self.requests: list[SimpleNamespace] = []
        fake = self

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *args) -> None:
                pass

            def do_POST(self) -> None:
                length = int(self.headers.get("Content-Length") or 0)
                body = json.loads(self.rfile.read(length))
                fake.requests.append(
                    SimpleNamespace(
                        path=self.path,
                        authorization=self.headers.get("Authorization"),
                        user_agent=self.headers.get("User-Agent"),
                        name=body.get("name"),
                        query=body.get("query", {}),
                    )
                )
                self.send_response(fake.status)
                if fake.location:
                    self.send_header("Location", fake.location)
                answer = fake.raw
                if answer is None:
                    rows = fake.answers.get(body.get("name"), [])
                    answer = json.dumps({"results": rows}).encode("utf-8")
                promised = len(answer) + (1 if fake.cut_short else 0)
                self.send_header("Content-Length", str(promised))
                self.end_headers()
                self.wfile.write(answer)

        self._server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        # A short poll: every test closes one of these, and shutdown waits it out.
        self._thread = threading.Thread(
            target=self._server.serve_forever, args=(0.01,), daemon=True
        )
        self._thread.start()

    @property
    def url(self) -> str:
        return f"http://127.0.0.1:{self._server.server_address[1]}"

    def sql(self, name: str) -> str:
        """The SQL of the last query sent under this name."""
        for request in reversed(self.requests):
            if request.name == name:
                return request.query["query"]
        raise AssertionError(f"no query named {name}")

    def close(self) -> None:
        self._server.shutdown()
        self._server.server_close()
        self._thread.join()
