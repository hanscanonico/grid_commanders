import unittest

from admin import hit

CHROME = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36"
)
IPHONE = (
    "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 "
    "(KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1"
)
IPAD = (
    "Mozilla/5.0 (iPad; CPU OS 17_5 like Mac OS X) AppleWebKit/605.1.15 "
    "(KHTML, like Gecko) Version/17.5 Safari/604.1"
)
ANDROID_PHONE = (
    "Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/128.0.0.0 Mobile Safari/537.36"
)
ANDROID_TABLET = (
    "Mozilla/5.0 (Linux; Android 14; SM-X710) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36"
)


class BotTests(unittest.TestCase):
    def test_real_browsers_are_not_bots(self):
        for ua in (CHROME, IPHONE, IPAD, ANDROID_PHONE, ANDROID_TABLET):
            with self.subTest(ua=ua[:32]):
                self.assertFalse(hit.is_bot(ua))

    def test_every_marker_is_caught(self):
        for marker in hit.BOT_MARKERS:
            with self.subTest(marker=marker):
                self.assertTrue(hit.is_bot(f"Some/1.0 {marker.upper()} thing"))

    def test_named_crawlers(self):
        for ua in (
            "Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)",
            "Mozilla/5.0 (compatible; bingbot/2.0)",
            "curl/8.6.0",
            "python-requests/2.32.3",
            "Mozilla/5.0 HeadlessChrome/128.0.0.0",
        ):
            with self.subTest(ua=ua[:24]):
                self.assertTrue(hit.is_bot(ua))

    def test_blank_agent_is_a_bot(self):
        self.assertTrue(hit.is_bot(""))


class DeviceTests(unittest.TestCase):
    def test_classes(self):
        cases = {
            CHROME: "desktop",
            IPHONE: "phone",
            IPAD: "tablet",
            ANDROID_PHONE: "phone",
            ANDROID_TABLET: "tablet",
            "": "desktop",
        }
        for ua, expected in cases.items():
            with self.subTest(ua=ua[:32]):
                self.assertEqual(hit.device_class(ua), expected)


class ReferrerTests(unittest.TestCase):
    def test_host_only_lowercased_and_de_wwwed(self):
        self.assertEqual(
            hit.referrer_host("https://WWW.Reddit.com/r/games/", "gridcommanders.com"),
            "reddit.com",
        )

    def test_own_site_is_dropped(self):
        for referer in (
            "https://gridcommanders.com/",
            "https://www.gridcommanders.com/play/",
        ):
            with self.subTest(referer=referer):
                self.assertEqual(hit.referrer_host(referer, "gridcommanders.com"), "")

    def test_direct_visit(self):
        self.assertEqual(hit.referrer_host("", "gridcommanders.com"), "")

    def test_garbage_is_not_a_host(self):
        self.assertEqual(hit.referrer_host("::::", "gridcommanders.com"), "")

    def test_a_long_host_is_bounded(self):
        host = hit.referrer_host(
            "https://%s.example/" % ("x" * 300), "gridcommanders.com"
        )
        self.assertEqual(len(host), hit.MAX_KEY_CHARS)


class UtmTests(unittest.TestCase):
    def test_all_three(self):
        self.assertEqual(
            hit.utm("utm_source=Reddit&utm_medium=Social&utm_campaign=Launch"),
            ("reddit", "social", "launch"),
        )

    def test_absent_and_partial(self):
        self.assertEqual(hit.utm(""), ("", "", ""))
        self.assertEqual(hit.utm("a=1&utm_source=itch"), ("itch", "", ""))

    def test_long_values_are_bounded(self):
        source, _, _ = hit.utm("utm_source=" + "x" * 200)
        self.assertEqual(len(source), hit.MAX_KEY_CHARS)


class PathTests(unittest.TestCase):
    def test_pages(self):
        cases = {
            "/": "/",
            "/index.html": "/",
            "/?utm_source=x": "/",
            "/play/": "/play/",
            "/play": "/play/",
            "/play/index.html": "/play/",
        }
        for uri, expected in cases.items():
            with self.subTest(uri=uri):
                self.assertEqual(hit.normalise_path(uri), expected)

    def test_assets_and_strangers_are_not_pages(self):
        for uri in (
            "/play/index.js",
            "/play/index.wasm",
            "/og-battle.png",
            "/robots.txt",
            "/admin/",
            "",
            "/nope/",
        ):
            with self.subTest(uri=uri):
                self.assertEqual(hit.normalise_path(uri), "")

    def test_query_is_split_off(self):
        self.assertEqual(hit.query_of("/?utm_source=x&a=1"), "utm_source=x&a=1")
        self.assertEqual(hit.query_of("/"), "")


class VisitorHashTests(unittest.TestCase):
    def test_stable_within_a_day(self):
        first = hit.visitor_hash("s", "2026-09-14", "203.0.113.7", CHROME)
        second = hit.visitor_hash("s", "2026-09-14", "203.0.113.7", CHROME)
        self.assertEqual(first, second)

    def test_rotates_with_the_day(self):
        self.assertNotEqual(
            hit.visitor_hash("s", "2026-09-14", "203.0.113.7", CHROME),
            hit.visitor_hash("s", "2026-09-15", "203.0.113.7", CHROME),
        )

    def test_secret_and_inputs_matter(self):
        base = hit.visitor_hash("s", "2026-09-14", "203.0.113.7", CHROME)
        self.assertNotEqual(
            base, hit.visitor_hash("t", "2026-09-14", "203.0.113.7", CHROME)
        )
        self.assertNotEqual(
            base, hit.visitor_hash("s", "2026-09-14", "203.0.113.8", CHROME)
        )
        self.assertNotEqual(
            base, hit.visitor_hash("s", "2026-09-14", "203.0.113.7", IPHONE)
        )

    def test_the_ip_is_not_recoverable_from_the_digest(self):
        digest = hit.visitor_hash("s", "2026-09-14", "203.0.113.7", CHROME)
        self.assertNotIn("203.0.113.7", digest)
        self.assertEqual(len(digest), 64)


class FromHeadersTests(unittest.TestCase):
    def headers(self, **over):
        base = {
            "X-Original-Method": "GET",
            "X-Original-URI": "/?utm_source=reddit",
            "CF-Connecting-IP": "203.0.113.7",
            "CF-IPCountry": "fr",
            "Referer": "https://www.reddit.com/r/games/",
            "User-Agent": IPHONE,
        }
        base.update(over)
        return base

    def test_a_page_becomes_a_hit(self):
        row = hit.from_headers(self.headers(), "s", "2026-09-14", "gridcommanders.com")
        self.assertIsNotNone(row)
        self.assertEqual(row.path, "/")
        self.assertEqual(row.country, "FR")
        self.assertEqual(row.referrer_host, "reddit.com")
        self.assertEqual(row.device, "phone")
        self.assertEqual(row.utm_source, "reddit")
        self.assertEqual(len(row.visitor), 64)

    def test_assets_bots_and_posts_are_dropped(self):
        for over in (
            {"X-Original-URI": "/play/index.wasm"},
            {"X-Original-Method": "POST"},
            {"User-Agent": "Googlebot/2.1"},
        ):
            with self.subTest(over=over):
                self.assertIsNone(
                    hit.from_headers(
                        self.headers(**over), "s", "2026-09-14", "gridcommanders.com"
                    )
                )

    def test_header_names_are_read_case_insensitively(self):
        shouted = {name.upper(): value for name, value in self.headers().items()}
        row = hit.from_headers(shouted, "s", "2026-09-14", "gridcommanders.com")
        self.assertIsNotNone(row)
        self.assertEqual(row.country, "FR")

    def test_missing_country_is_a_placeholder(self):
        row = hit.from_headers(
            self.headers(**{"CF-IPCountry": ""}),
            "s",
            "2026-09-14",
            "gridcommanders.com",
        )
        self.assertEqual(row.country, "XX")


if __name__ == "__main__":
    unittest.main()
