import json
import socket
import unittest

from admin.posthog import REMEMBER_SECONDS, SCOPE, PostHog, PostHogError
from tests.fake_posthog import FakePostHog

KEY = "phx_secret_test_key"
SITE = "gridcommanders.com"


class FakeCase(unittest.TestCase):
    def setUp(self):
        self.fake = FakePostHog()
        self.addCleanup(self.fake.close)
        self.posthog = PostHog(self.fake.url, "318370", KEY, SITE)


class RowsTests(FakeCase):
    def test_the_answer_is_the_result_rows(self):
        self.fake.answers["q"] = [[1, 2], [3, 4]]
        self.assertEqual(
            self.posthog.rows("q", "SELECT 1", "2026-10-26"), [[1, 2], [3, 4]]
        )

    def test_the_request_is_the_documented_one(self):
        self.posthog.rows("q", "SELECT 1", "2026-10-26")
        sent = self.fake.requests[0]
        self.assertEqual(sent.path, "/api/projects/318370/query/")
        self.assertEqual(sent.authorization, f"Bearer {KEY}")
        self.assertEqual(sent.name, "q")
        self.assertEqual(sent.query["kind"], "HogQLQuery")
        self.assertEqual(sent.query["query"], "SELECT 1")

    def test_a_query_is_held_to_this_site_and_this_range(self):
        # Local builds post to the same project; these rows are not the site's.
        self.posthog.rows("q", f"SELECT 1 FROM events WHERE {SCOPE}", "2026-10-26")
        sql = self.fake.sql("q")
        self.assertIn("properties.$host IN", sql)
        self.assertIn(f"'{SITE}', 'www.{SITE}'", sql)
        self.assertIn("timestamp >= toDateTime('2026-10-26 00:00:00')", sql)
        self.assertNotIn(SCOPE, sql)

    def test_the_project_filter_for_internal_users_is_applied(self):
        # PostHog applies it only where the placeholder is written, and silently
        # ignores the flag without one, so the pair is what the test pins.
        self.posthog.rows("q", f"SELECT 1 FROM events WHERE {SCOPE}", "2026-10-26")
        self.assertIn("{filters}", self.fake.sql("q"))
        self.assertEqual(
            self.fake.requests[0].query["filters"],
            {"filterTestAccounts": True, "dateRange": {"date_from": "2026-10-26"}},
        )

    def test_a_site_host_cannot_break_out_of_its_quotes(self):
        posthog = PostHog(self.fake.url, "318370", KEY, "a'b\\c")
        posthog.rows("q", f"WHERE {SCOPE}", "2026-10-26")
        self.assertIn("'a\\'b\\\\c'", self.fake.sql("q"))


class FailureTests(FakeCase):
    def refusal(self):
        with self.assertRaises(PostHogError) as caught:
            self.posthog.rows("admin_q", "SELECT 1", "2026-10-26")
        return str(caught.exception)

    def test_a_refused_key_says_so_and_never_repeats_the_key(self):
        for status in (401, 403):
            with self.subTest(status=status):
                self.fake.status = status
                message = self.refusal()
                self.assertIn("refused the key", message)
                self.assertNotIn(KEY, message)

    def test_a_refused_query_carries_posthogs_reason_and_its_name(self):
        self.fake.status = 400
        self.fake.raw = json.dumps({"detail": "unknown function"}).encode()
        message = self.refusal()
        self.assertIn("admin_q", message)
        self.assertIn("400", message)
        self.assertIn("unknown function", message)

    def test_a_refusal_with_no_readable_reason_still_names_the_status(self):
        self.fake.status = 500
        self.fake.raw = b"<html>nope</html>"
        self.assertIn("answered 500", self.refusal())

    def test_a_used_up_rate_limit_says_so(self):
        self.fake.status = 429
        self.assertIn("rate limit", self.refusal())

    def test_an_answer_that_is_not_json_is_refused(self):
        self.fake.raw = b"not json"
        self.assertIn("cannot read", self.refusal())

    def test_an_answer_without_a_list_of_rows_is_refused(self):
        for raw in (b"{}", b'{"results": "many"}', b"[1]"):
            with self.subTest(raw=raw):
                self.fake.raw = raw
                self.assertIn("cannot read", self.refusal())

    def test_nothing_listening_is_no_answer(self):
        with socket.socket() as probe:
            probe.bind(("127.0.0.1", 0))
            port = probe.getsockname()[1]
        posthog = PostHog(f"http://127.0.0.1:{port}", "318370", KEY, SITE)
        with self.assertRaises(PostHogError) as caught:
            posthog.rows("q", "SELECT 1", "2026-10-26")
        self.assertIn("did not answer", str(caught.exception))

    def test_an_answer_cut_short_is_no_answer(self):
        self.fake.cut_short = True
        self.assertIn("did not answer", self.refusal())

    def test_a_refusal_cut_short_still_names_the_status(self):
        self.fake.cut_short = True
        self.fake.status = 500
        self.assertIn("answered 500", self.refusal())

    def test_a_redirect_is_not_followed_with_the_key(self):
        elsewhere = FakePostHog()
        self.addCleanup(elsewhere.close)
        self.fake.status = 302
        self.fake.location = f"{elsewhere.url}/stolen"
        self.assertIn("answered 302", self.refusal())
        self.assertEqual(elsewhere.requests, [])


class ConfiguredTests(unittest.TestCase):
    def test_a_blank_key_is_not_configured(self):
        self.assertFalse(PostHog("http://x", "1", "", SITE).configured)

    def test_a_key_is_configured(self):
        self.assertTrue(PostHog("http://x", "1", KEY, SITE).configured)


class RememberedTests(unittest.TestCase):
    def setUp(self):
        self.now = 1000.0
        self.posthog = PostHog("http://x", "1", KEY, SITE, clock=lambda: self.now)
        self.builds = 0

    def build(self):
        self.builds += 1
        return {"build": self.builds}

    def fail(self):
        raise PostHogError("PostHog did not answer.")

    def test_a_second_ask_inside_the_window_does_not_build(self):
        self.assertEqual(self.posthog.remembered("7d", self.build), {"build": 1})
        self.now += REMEMBER_SECONDS - 1
        self.assertEqual(self.posthog.remembered("7d", self.build), {"build": 1})
        self.assertEqual(self.builds, 1)

    def test_an_ask_after_the_window_builds_again(self):
        self.posthog.remembered("7d", self.build)
        self.now += REMEMBER_SECONDS
        self.assertEqual(self.posthog.remembered("7d", self.build), {"build": 2})

    def test_each_key_is_remembered_on_its_own(self):
        self.posthog.remembered("7d", self.build)
        self.assertEqual(self.posthog.remembered("30d", self.build), {"build": 2})

    def test_a_failure_with_nothing_held_is_raised(self):
        with self.assertRaises(PostHogError):
            self.posthog.remembered("7d", self.fail)

    def test_a_failed_refresh_hands_back_the_last_answer_marked_stale(self):
        self.posthog.remembered("7d", self.build)
        self.now += REMEMBER_SECONDS
        answer = self.posthog.remembered("7d", self.fail)
        self.assertEqual(answer["build"], 1)
        self.assertEqual(answer["stale"], "PostHog did not answer.")

    def test_a_good_refresh_after_a_failure_is_no_longer_stale(self):
        self.posthog.remembered("7d", self.build)
        self.now += REMEMBER_SECONDS
        self.posthog.remembered("7d", self.fail)
        self.assertEqual(self.posthog.remembered("7d", self.build), {"build": 2})


if __name__ == "__main__":
    unittest.main()
