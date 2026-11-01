import json
import tempfile
import unittest
from datetime import datetime, timezone
from pathlib import Path

from admin import panels
from admin.posthog import PostHog
from admin.sources import Sources
from admin.store import Store
from tests.fake_posthog import FakePostHog
from tests.test_store import a_hit

NOW = datetime(2026, 9, 14, 12, 0, tzinfo=timezone.utc)
KEY = "phx_secret_test_key"
SITE = "gridcommanders.com"


def no_posthog() -> PostHog:
    return PostHog("http://unused.invalid", "1", "", SITE)


class RegistryTests(unittest.TestCase):
    def test_the_page_opens_on_players(self):
        self.assertEqual(
            panels.listing(),
            [
                {"slug": "players", "name": "Players"},
                {"slug": "traffic", "name": "Server traffic"},
            ],
        )

    def test_lookup_by_slug(self):
        self.assertIs(panels.by_slug("traffic"), panels.traffic)
        self.assertIs(panels.by_slug("players"), panels.players)
        self.assertIsNone(panels.by_slug("nope"))

    def test_every_panel_has_the_three_names(self):
        for panel in panels.PANELS:
            with self.subTest(panel=panel.__name__):
                self.assertTrue(panel.name)
                self.assertTrue(panel.slug)
                self.assertTrue(callable(panel.query))


class TrafficPanelTests(unittest.TestCase):
    def setUp(self):
        folder = tempfile.TemporaryDirectory()
        self.addCleanup(folder.cleanup)
        self.store = Store(str(Path(folder.name) / "admin.sqlite"))
        self.addCleanup(self.store.close)
        self.sources = Sources(self.store, no_posthog())

    def test_it_answers_the_store(self):
        self.store.record(a_hit(), NOW)
        self.assertEqual(panels.traffic.query(self.sources, "7d", NOW)["views"], 1)

    def test_it_carries_the_duration_keys(self):
        answer = panels.traffic.query(self.sources, "7d", NOW)
        for key in (
            "engaged_visitors",
            "engaged_seconds",
            "avg_seconds",
            "session_length",
            "time_on_path",
            "landing_uniques",
            "played_uniques",
        ):
            self.assertIn(key, answer)
        self.assertIn("engaged_seconds", answer["daily"][-1])


class PlayersPanelCase(unittest.TestCase):
    def setUp(self):
        self.fake = FakePostHog()
        self.addCleanup(self.fake.close)
        self.fake.answers = {
            "admin_totals": [[30, 14, 5, 2]],
            "admin_time": [[9, 431.5]],
            "admin_daily": [["2026-09-10", 4, 2, 1], ["2026-09-14", 6, 3, 2]],
            "admin_page": [["/", 16, 0], ["/play/", 14, 5]],
            "admin_country": [["FR", 20, 4], [None, 3, 0]],
            "admin_referrer": [["$direct", 25, 5], ["itch.io", 5, 0]],
            "admin_device": [["Desktop", 28, 5], ["Mobile", 2, 0], ["Console", 0, 0]],
            "admin_mode": [["campaign", 3, 1], ["skirmish", 2, 1]],
            "admin_map": [["boot_camp", 4, 2]],
            "admin_mission": [["first_light", 3, 1]],
        }
        store = None  # The Players panel never touches the store.
        self.sources = Sources(
            store, PostHog(self.fake.url, "318370", KEY, SITE, clock=lambda: 0.0)
        )

    def answer(self, asked="7d"):
        return panels.players.query(self.sources, asked, NOW)


class PlayersPanelTests(PlayersPanelCase):
    def test_the_headline_numbers(self):
        answer = self.answer()
        self.assertTrue(answer["configured"])
        self.assertEqual(answer["visits"], 30)
        self.assertEqual(answer["game_opens"], 14)
        self.assertEqual(answer["played"], 5)
        self.assertEqual(answer["finished"], 2)
        self.assertEqual(answer["measured_sessions"], 9)
        self.assertEqual(answer["median_seconds"], 432)

    def test_the_range_ends_today(self):
        answer = self.answer("30d")
        self.assertEqual(answer["range"], "30d")
        self.assertEqual(answer["from"], "2026-08-16")
        self.assertEqual(answer["to"], "2026-09-14")
        self.assertEqual(answer["fetched_at"], "2026-09-14 12:00 UTC")

    def test_every_day_of_the_range_is_there_a_quiet_one_included(self):
        daily = self.answer()["daily"]
        self.assertEqual(
            [day["day"] for day in daily],
            [f"2026-09-{day:02d}" for day in range(8, 15)],
        )
        self.assertEqual(
            daily[2],
            {"day": "2026-09-10", "visits": 4, "game_opens": 2, "played": 1},
        )
        self.assertEqual(
            daily[3],
            {"day": "2026-09-11", "visits": 0, "game_opens": 0, "played": 0},
        )

    def test_a_timestamped_day_still_lands_on_its_day(self):
        self.fake.answers["admin_daily"] = [["2026-09-10T00:00:00Z", 4, 2, 1]]
        self.assertEqual(self.answer()["daily"][2]["visits"], 4)

    def test_the_tables(self):
        answer = self.answer()
        self.assertEqual(
            answer["pages"][1], {"key": "/play/", "visits": 14, "played": 5}
        )
        self.assertEqual(
            answer["modes"][0], {"key": "campaign", "started": 3, "finished": 1}
        )
        self.assertEqual(
            answer["maps"][0], {"key": "boot_camp", "started": 4, "finished": 2}
        )
        self.assertEqual(
            answer["missions"][0], {"key": "first_light", "started": 3, "cleared": 1}
        )

    def test_a_visit_with_no_referrer_reads_direct(self):
        self.assertEqual(self.answer()["referrers"][0]["key"], "(direct)")

    def test_a_missing_value_is_an_empty_key_the_page_can_name(self):
        self.assertEqual(self.answer()["countries"][1]["key"], "")

    def test_a_row_of_noughts_is_left_out(self):
        self.assertEqual(
            [row["key"] for row in self.answer()["devices"]], ["Desktop", "Mobile"]
        )

    def test_no_measured_session_is_a_zero_not_a_null(self):
        for empty in (None, float("nan")):
            with self.subTest(empty=empty):
                self.sources = Sources(
                    None, PostHog(self.fake.url, "318370", KEY, SITE, clock=lambda: 0.0)
                )
                self.fake.raw = None
                self.fake.answers["admin_time"] = [[0, empty]]
                answer = self.answer()
                self.assertEqual(answer["median_seconds"], 0)
                json.dumps(answer, allow_nan=False)

    def test_an_empty_answer_is_all_zeros(self):
        self.fake.answers = {}
        answer = self.answer()
        self.assertEqual(answer["visits"], 0)
        self.assertEqual(answer["median_seconds"], 0)
        self.assertEqual(answer["pages"], [])

    def test_the_key_never_reaches_the_answer(self):
        self.assertNotIn(KEY, json.dumps(self.answer()))

    def test_a_second_load_asks_posthog_nothing(self):
        self.answer()
        sent = len(self.fake.requests)
        self.answer()
        self.assertEqual(len(self.fake.requests), sent)

    def test_an_unknown_range_falls_back_and_never_reaches_the_sql(self):
        self.answer("7d' OR 1=1 --")
        for request in self.fake.requests:
            self.assertNotIn("OR 1=1", request.query["query"])
        self.assertEqual(
            self.fake.requests[0].query["filters"]["dateRange"]["date_from"],
            "2026-09-08",
        )


class PlayersQueryTests(PlayersPanelCase):
    def setUp(self):
        super().setUp()
        self.answer()

    def test_every_query_is_held_to_the_site(self):
        for request in self.fake.requests:
            with self.subTest(name=request.name):
                self.assertIn("properties.$host IN", request.query["query"])
                self.assertIn("{filters}", request.query["query"])
                self.assertTrue(request.query["filters"]["filterTestAccounts"])

    def test_a_table_of_computers_is_not_played(self):
        for name in ("admin_totals", "admin_daily", "admin_country", "admin_mode"):
            with self.subTest(name=name):
                self.assertIn("properties.mode != 'spectate'", self.fake.sql(name))

    def test_a_visit_is_a_session_not_an_id(self):
        # An id means nothing before consent: every page load gets a new one.
        sql = self.fake.sql("admin_totals")
        self.assertIn("uniqIf(properties.$session_id", sql)
        self.assertNotIn("distinct_id", sql)

    def test_what_each_headline_number_counts(self):
        sql = self.fake.sql("admin_totals")
        for column in (
            "uniqIf(properties.$session_id, event = '$pageview') AS visits",
            "uniqIf(properties.$session_id, event = '$pageview'"
            " AND properties.$pathname = '/play/') AS game",
            "uniqIf(properties.$session_id, event = 'match_started'"
            " AND properties.mode != 'spectate') AS played",
            "uniqIf(properties.$session_id, event = 'match_ended'"
            " AND properties.mode != 'spectate') AS finished",
        ):
            with self.subTest(column=column):
                self.assertIn(column, sql)

    def test_time_in_game_measures_the_game_page_and_only_a_real_length(self):
        sql = self.fake.sql("admin_time")
        self.assertIn("WHERE properties.$pathname = '/play/' AND", sql)
        self.assertIn("WHERE secs > 0", sql)

    def test_a_mission_counts_its_starts_and_its_clears_apart(self):
        sql = self.fake.sql("admin_mission")
        self.assertIn("countIf(event = 'campaign_mission_started') AS started", sql)
        self.assertIn("countIf(event = 'campaign_mission_cleared') AS cleared", sql)

    def test_a_year_of_days_fits_the_query(self):
        # PostHog stops at 100 rows unless a query names its own limit.
        self.assertIn("LIMIT 400", self.fake.sql("admin_daily"))


class PlayersPanelStateTests(unittest.TestCase):
    def test_without_a_key_it_says_so_and_asks_nothing(self):
        fake = FakePostHog()
        self.addCleanup(fake.close)
        sources = Sources(None, PostHog(fake.url, "318370", "", SITE))
        self.assertEqual(
            panels.players.query(sources, "30d", NOW),
            {"configured": False, "range": "30d"},
        )
        self.assertEqual(fake.requests, [])

    def test_rows_of_another_shape_are_an_answer_too(self):
        fake = FakePostHog()
        self.addCleanup(fake.close)
        fake.answers["admin_totals"] = [[1, 2]]
        sources = Sources(None, PostHog(fake.url, "318370", KEY, SITE))
        answer = panels.players.query(sources, "7d", NOW)
        self.assertIn("cannot read", answer["error"])

    def test_an_empty_row_is_an_answer_too(self):
        fake = FakePostHog()
        self.addCleanup(fake.close)
        fake.answers["admin_daily"] = [[]]
        sources = Sources(None, PostHog(fake.url, "318370", KEY, SITE))
        answer = panels.players.query(sources, "7d", NOW)
        self.assertIn("cannot read", answer["error"])

    def test_a_refusal_is_an_answer_the_page_can_show(self):
        fake = FakePostHog()
        self.addCleanup(fake.close)
        fake.status = 401
        sources = Sources(None, PostHog(fake.url, "318370", KEY, SITE))
        answer = panels.players.query(sources, "7d", NOW)
        self.assertTrue(answer["configured"])
        self.assertIn("refused the key", answer["error"])
        self.assertNotIn(KEY, json.dumps(answer))


if __name__ == "__main__":
    unittest.main()
