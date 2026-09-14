"""The collector and the admin shell, in one small stdlib HTTP server.

`/ingest` is reached only through nginx's mirror and always answers 204: a
mirror is fire-and-forget, and a collector that could fail a page request
would be worse than no collector. Everything under `/admin` goes through the
Cloudflare Access check first, and answers 403 when it is not configured.
"""

from __future__ import annotations

import json
import logging
import mimetypes
import os
import secrets
import threading
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

from . import access, hit, panels
from .store import RANGES, Store, day_of

STATIC_DIR = Path(__file__).parent / "static"
ROLLUP_INTERVAL_SECONDS = 3600
DEFAULT_PORT = 8000
DEFAULT_DB_PATH = "/data/admin.sqlite"
DEFAULT_SITE_HOST = "gridcommanders.com"

log = logging.getLogger("admin")


class Config:
    """The environment, read once, with every default in one place."""

    def __init__(self, env: dict[str, str] | None = None) -> None:
        source = os.environ if env is None else env
        self.team = source.get("ADMIN_ACCESS_TEAM", "").strip()
        self.aud = source.get("ADMIN_ACCESS_AUD", "").strip()
        self.db_path = source.get("ADMIN_DB_PATH", "").strip() or DEFAULT_DB_PATH
        self.site_host = source.get("ADMIN_SITE_HOST", "").strip() or DEFAULT_SITE_HOST
        self.port = int(source.get("ADMIN_PORT", "").strip() or DEFAULT_PORT)
        self.hash_secret = source.get("ADMIN_HASH_SECRET", "").strip()
        if not self.hash_secret:
            # A restart with a fresh secret starts today's visitors over. Say
            # so once rather than silently counting the same person twice.
            self.hash_secret = secrets.token_hex(32)
            log.warning(
                "ADMIN_HASH_SECRET is unset: a generated one is in use, so"
                " today's unique counts restart with the process."
            )

    @property
    def access_configured(self) -> bool:
        return bool(self.team and self.aud)


class Handler(BaseHTTPRequestHandler):
    server_version = "grid-commanders-admin"
    protocol_version = "HTTP/1.1"

    @property
    def config(self) -> Config:
        return self.server.config

    @property
    def store(self) -> Store:
        return self.server.store

    def log_message(self, fmt: str, *args) -> None:
        # The stock handler logs the request line, which for /admin carries no
        # token but does carry a query string; nginx already logs the site.
        log.info("%s %s", self.address_string(), fmt % args)

    def do_POST(self) -> None:
        if self.path.split("?")[0] == "/ingest":
            self._ingest()
            return
        self._text(404, "not found")

    def do_GET(self) -> None:
        route = self.path.split("?")[0]
        if route == "/healthz":
            self._text(200, "ok")
        elif route == "/admin":
            self._redirect("/admin/")
        elif route == "/admin/":
            self._guarded(self._page)
        elif route == "/admin/api/panels":
            self._guarded(lambda: self._json(200, panels.listing()))
        elif route.startswith("/admin/api/"):
            self._guarded(lambda: self._panel(route[len("/admin/api/") :]))
        elif route.startswith("/admin/static/"):
            self._guarded(lambda: self._static(route[len("/admin/static/") :]))
        else:
            self._text(404, "not found")

    def _ingest(self) -> None:
        self._drain_body()
        try:
            now = datetime.now(timezone.utc)
            row = hit.from_headers(
                {name: value for name, value in self.headers.items()},
                self.config.hash_secret,
                day_of(now),
                self.config.site_host,
            )
            if row is not None:
                self.store.record(row, now)
        except Exception:
            # The mirror must never become a reason a page is slow or broken,
            # so a bad row is a log line and a 204 like every other.
            log.exception("ingest failed")
        self._empty(204)

    def _guarded(self, render) -> None:
        if not self.config.access_configured:
            self._text(403, access.NOT_CONFIGURED)
            return
        email = access.verify(
            {name: value for name, value in self.headers.items()},
            self.config.team,
            self.config.aud,
            datetime.now(timezone.utc),
            cache=self.server.key_cache,
        )
        if not email:
            self._text(403, access.DENIED)
            return
        render()

    def _panel(self, wanted: str) -> None:
        panel = panels.by_slug(wanted.strip("/"))
        if panel is None:
            self._json(404, {"error": "no such panel"})
            return
        asked = ""
        if "?" in self.path:
            for part in self.path.split("?", 1)[1].split("&"):
                if part.startswith("range="):
                    asked = part[len("range=") :]
        range_key = asked if asked in RANGES else "7d"
        self._json(200, panel.query(self.store, range_key, datetime.now(timezone.utc)))

    def _page(self) -> None:
        self._file(STATIC_DIR / "index.html")

    def _static(self, relative: str) -> None:
        candidate = (STATIC_DIR / relative).resolve()
        if not candidate.is_file() or STATIC_DIR.resolve() not in candidate.parents:
            self._text(404, "not found")
            return
        self._file(candidate)

    def _file(self, path: Path) -> None:
        body = path.read_bytes()
        kind = mimetypes.guess_type(path.name)[0] or "application/octet-stream"
        self._respond(200, body, f"{kind}; charset=utf-8")

    def _json(self, status: int, payload) -> None:
        body = json.dumps(payload).encode("utf-8")
        self._respond(status, body, "application/json; charset=utf-8")

    def _text(self, status: int, message: str) -> None:
        self._respond(status, f"{message}\n".encode(), "text/plain; charset=utf-8")

    def _redirect(self, location: str) -> None:
        self.send_response(308)
        self.send_header("Location", location)
        self.send_header("Content-Length", "0")
        self.end_headers()

    def _empty(self, status: int) -> None:
        self.send_response(status)
        self.send_header("Content-Length", "0")
        self.end_headers()

    def _respond(self, status: int, body: bytes, content_type: str) -> None:
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Robots-Tag", "noindex, nofollow")
        self.end_headers()
        self.wfile.write(body)

    def _drain_body(self) -> None:
        length = int(self.headers.get("Content-Length") or 0)
        if length > 0:
            self.rfile.read(length)


class AdminServer(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True

    def __init__(
        self, config: Config, store: Store, key_cache: access.KeyCache | None = None
    ) -> None:
        super().__init__(("0.0.0.0", config.port), Handler)
        self.config = config
        self.store = store
        self.key_cache = key_cache or access.KeyCache()


def rollup_forever(store: Store, stop: threading.Event) -> None:
    """The hourly fold, plus one at startup so a restart catches up."""
    while True:
        try:
            store.rollup(datetime.now(timezone.utc))
        except Exception:
            log.exception("rollup failed")
        if stop.wait(ROLLUP_INTERVAL_SECONDS):
            return


def main() -> None:
    logging.basicConfig(
        level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s"
    )
    config = Config()
    Path(config.db_path).parent.mkdir(parents=True, exist_ok=True)
    store = Store(config.db_path)
    if not config.access_configured:
        log.warning("ADMIN_ACCESS_TEAM/ADMIN_ACCESS_AUD unset: /admin answers 403.")
    stop = threading.Event()
    threading.Thread(
        target=rollup_forever, args=(store, stop), daemon=True, name="rollup"
    ).start()
    server = AdminServer(config, store)
    log.info("admin listening on :%d, database %s", config.port, config.db_path)
    try:
        server.serve_forever()
    finally:
        stop.set()
        store.close()


if __name__ == "__main__":
    main()
