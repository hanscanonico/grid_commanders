import http.client
import json
import tempfile
import threading
import unittest
from datetime import datetime, timezone
from pathlib import Path

from admin import access
from admin.server import AdminServer, Config
from admin.store import Store
from tests import keys

CHROME = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36"
)


class ServerCase(unittest.TestCase):
    env: dict[str, str] = {}

    def setUp(self):
        folder = tempfile.TemporaryDirectory()
        self.addCleanup(folder.cleanup)
        env = {"ADMIN_PORT": "0", "ADMIN_HASH_SECRET": "test-secret"}
        env.update(self.env)
        env["ADMIN_DB_PATH"] = str(Path(folder.name) / "admin.sqlite")
        self.store = Store(env["ADMIN_DB_PATH"])
        self.addCleanup(self.store.close)
        self.cache = keys.FakeKeyCache()
        self.server = AdminServer(Config(env), self.store, key_cache=self.cache)
        self.addCleanup(self.server.server_close)
        thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        thread.start()
        self.addCleanup(thread.join)
        self.addCleanup(self.server.shutdown)
        self.port = self.server.server_address[1]

    def request(self, method, path, headers=None):
        connection = http.client.HTTPConnection("127.0.0.1", self.port, timeout=5)
        try:
            connection.request(method, path, headers=headers or {})
            response = connection.getresponse()
            return response.status, response.read().decode("utf-8"), response.headers
        finally:
            connection.close()

    def signed(self):
        return {access.HEADER: keys.token(now=datetime.now(timezone.utc))}


class IngestTests(ServerCase):
    def mirror(self, uri, **over):
        headers = {
            "X-Original-URI": uri,
            "X-Original-Method": "GET",
            "CF-Connecting-IP": "203.0.113.7",
            "CF-IPCountry": "FR",
            "User-Agent": CHROME,
        }
        headers.update(over)
        return self.request("POST", "/ingest", headers)

    def test_a_page_is_recorded(self):
        status, _, _ = self.mirror("/?utm_source=reddit")
        self.assertEqual(status, 204)
        result = self.store.traffic("7d", datetime.now(timezone.utc))
        self.assertEqual(result["views"], 1)
        self.assertEqual(result["breakdowns"]["path"][0]["key"], "/")
        self.assertEqual(result["breakdowns"]["country"][0]["key"], "FR")

    def test_the_game_page_is_recorded_under_its_own_path(self):
        self.mirror("/play/")
        result = self.store.traffic("7d", datetime.now(timezone.utc))
        self.assertEqual(result["breakdowns"]["path"][0]["key"], "/play/")

    def test_assets_and_bots_are_ignored_but_still_answered(self):
        for uri, over in (
            ("/play/index.js", {}),
            ("/play/index.wasm", {}),
            ("/favicon.png", {}),
            ("/", {"User-Agent": "Googlebot/2.1"}),
            ("/", {"X-Original-Method": "POST"}),
        ):
            with self.subTest(uri=uri, over=over):
                status, _, _ = self.mirror(uri, **over)
                self.assertEqual(status, 204)
        self.assertEqual(self.store.raw_event_count(), 0)

    def test_a_body_is_ignored(self):
        connection = http.client.HTTPConnection("127.0.0.1", self.port, timeout=5)
        connection.request(
            "POST",
            "/ingest",
            body=b"noise",
            headers={
                "X-Original-URI": "/",
                "X-Original-Method": "GET",
                "User-Agent": CHROME,
                "Content-Length": "5",
            },
        )
        self.assertEqual(connection.getresponse().status, 204)
        connection.close()
        self.assertEqual(self.store.raw_event_count(), 1)

    def test_healthz(self):
        status, body, _ = self.request("GET", "/healthz")
        self.assertEqual((status, body.strip()), (200, "ok"))

    def test_an_unknown_route_is_a_404(self):
        self.assertEqual(self.request("GET", "/nope")[0], 404)
        self.assertEqual(self.request("POST", "/nope")[0], 404)


class UnconfiguredAccessTests(ServerCase):
    def test_every_admin_route_is_403(self):
        for path in (
            "/admin/",
            "/admin/api/panels",
            "/admin/api/traffic?range=30d",
            "/admin/static/admin.css",
        ):
            with self.subTest(path=path):
                status, body, _ = self.request("GET", path, self.signed())
                self.assertEqual(status, 403)
                self.assertEqual(body.strip(), access.NOT_CONFIGURED)

    def test_the_collector_still_works(self):
        self.assertEqual(self.request("GET", "/healthz")[0], 200)


class ConfiguredAccessTests(ServerCase):
    env = {"ADMIN_ACCESS_TEAM": "gridcommanders", "ADMIN_ACCESS_AUD": "test-aud"}

    def test_the_shell_needs_a_token(self):
        status, body, _ = self.request("GET", "/admin/")
        self.assertEqual(status, 403)
        self.assertEqual(body.strip(), access.DENIED)

    def test_a_bad_token_is_refused(self):
        status, _, _ = self.request("GET", "/admin/", {access.HEADER: "not-a-token"})
        self.assertEqual(status, 403)

    def test_the_shell_is_served_with_a_valid_token(self):
        status, body, headers = self.request("GET", "/admin/", self.signed())
        self.assertEqual(status, 200)
        self.assertIn("<title>Grid Commanders — admin</title>", body)
        self.assertEqual(headers["Cache-Control"], "no-store")
        self.assertIn("noindex", headers["X-Robots-Tag"])

    def test_admin_redirects_to_the_trailing_slash(self):
        status, _, headers = self.request("GET", "/admin", self.signed())
        self.assertEqual(status, 308)
        self.assertEqual(headers["Location"], "/admin/")

    def test_the_panel_listing(self):
        status, body, _ = self.request("GET", "/admin/api/panels", self.signed())
        self.assertEqual(status, 200)
        self.assertEqual(json.loads(body), [{"slug": "traffic", "name": "Traffic"}])

    def test_the_traffic_panel_answers_json(self):
        status, body, _ = self.request(
            "GET", "/admin/api/traffic?range=30d", self.signed()
        )
        self.assertEqual(status, 200)
        payload = json.loads(body)
        self.assertEqual(payload["range"], "30d")
        self.assertEqual(len(payload["daily"]), 30)

    def test_an_unknown_range_falls_back(self):
        _, body, _ = self.request(
            "GET", "/admin/api/traffic?range=all-time", self.signed()
        )
        self.assertEqual(json.loads(body)["range"], "7d")

    def test_an_unknown_panel_is_a_404(self):
        status, _, _ = self.request("GET", "/admin/api/deploys", self.signed())
        self.assertEqual(status, 404)

    def test_the_static_files_are_served(self):
        for path, marker in (
            ("/admin/static/admin.css", "--accent"),
            ("/admin/static/admin.js", "render_traffic"),
        ):
            with self.subTest(path=path):
                status, body, _ = self.request("GET", path, self.signed())
                self.assertEqual(status, 200)
                self.assertIn(marker, body)

    def test_static_serving_does_not_escape_its_folder(self):
        status, _, _ = self.request("GET", "/admin/static/../server.py", self.signed())
        self.assertEqual(status, 404)

    def test_nothing_is_cached_or_indexed(self):
        # The page is private and must not survive in a cache or a crawler's
        # index — including the 403, which is what a stranger actually sees.
        for path, headers in (
            ("/admin/", self.signed()),
            ("/admin/api/traffic", self.signed()),
            ("/admin/static/admin.css", self.signed()),
            ("/admin/", {}),
        ):
            with self.subTest(path=path, signed=bool(headers)):
                _, _, sent = self.request("GET", path, headers)
                self.assertEqual(sent["Cache-Control"], "no-store")
                self.assertEqual(sent["X-Robots-Tag"], "noindex, nofollow")

    def test_a_recorded_page_shows_up_in_the_panel(self):
        self.request(
            "POST",
            "/ingest",
            {
                "X-Original-URI": "/",
                "X-Original-Method": "GET",
                "CF-Connecting-IP": "203.0.113.7",
                "CF-IPCountry": "DE",
                "User-Agent": CHROME,
            },
        )
        _, body, _ = self.request("GET", "/admin/api/traffic", self.signed())
        payload = json.loads(body)
        self.assertEqual(payload["views"], 1)
        self.assertEqual(payload["breakdowns"]["country"][0]["key"], "DE")


if __name__ == "__main__":
    unittest.main()
