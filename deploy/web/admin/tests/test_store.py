import sqlite3
import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path

from admin.hit import Hit
from admin.store import DIMENSIONS, RAW_RETENTION_DAYS, Store

NOW = datetime(2026, 9, 14, 12, 0, tzinfo=timezone.utc)


def a_hit(**over) -> Hit:
    base = {
        "path": "/",
        "country": "FR",
        "referrer_host": "reddit.com",
        "device": "desktop",
        "utm_source": "",
        "utm_medium": "",
        "utm_campaign": "",
        "visitor": "v1",
    }
    base.update(over)
    return Hit(**base)


class StoreTests(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.dir.cleanup)
        self.store = Store(str(Path(self.dir.name) / "admin.sqlite"))
        self.addCleanup(self.store.close)

    def test_round_trip_through_the_rollup(self):
        yesterday = NOW - timedelta(days=1)
        self.store.record(a_hit(visitor="v1"), yesterday)
        self.store.record(a_hit(visitor="v1"), yesterday)
        self.store.record(a_hit(visitor="v2"), yesterday)
        self.store.rollup(NOW)

        result = self.store.traffic("7d", NOW)
        self.assertEqual(result["views"], 3)
        self.assertEqual(result["uniques"], 2)
        self.assertEqual(len(result["daily"]), 7)
        self.assertEqual(
            result["daily"][-1], {"day": "2026-09-14", "views": 0, "uniques": 0}
        )
        self.assertEqual(
            result["daily"][-2], {"day": "2026-09-13", "views": 3, "uniques": 2}
        )
        self.assertEqual(
            result["breakdowns"]["country"], [{"key": "FR", "views": 3, "uniques": 2}]
        )

    def test_rollup_is_idempotent(self):
        yesterday = NOW - timedelta(days=1)
        for visitor in ("v1", "v2", "v2"):
            self.store.record(a_hit(visitor=visitor), yesterday)
        self.store.rollup(NOW)
        first = self.store.traffic("7d", NOW)
        self.store.rollup(NOW)
        self.store.rollup(NOW)
        self.assertEqual(self.store.traffic("7d", NOW), first)

    def test_today_is_read_live_without_a_rollup(self):
        self.store.record(a_hit(visitor="v1"), NOW)
        self.store.record(a_hit(visitor="v1"), NOW)
        result = self.store.traffic("7d", NOW)
        self.assertEqual(result["views"], 2)
        self.assertEqual(result["uniques"], 1)
        self.assertEqual(
            result["daily"][-1], {"day": "2026-09-14", "views": 2, "uniques": 1}
        )

    def test_todays_tail_survives_a_rollup(self):
        self.store.record(a_hit(), NOW - timedelta(days=1))
        self.store.record(a_hit(), NOW)
        self.store.rollup(NOW)
        self.assertEqual(self.store.traffic("7d", NOW)["views"], 2)

    def test_raw_events_older_than_the_window_are_deleted(self):
        old = NOW - timedelta(days=RAW_RETENTION_DAYS + 5)
        recent = NOW - timedelta(days=2)
        self.store.record(a_hit(), old)
        self.store.record(a_hit(), recent)
        self.store.rollup(NOW)

        self.assertEqual(self.store.raw_event_count(), 1)
        # The aggregate the deleted event was folded into is still there.
        self.assertEqual(self.store.traffic("365d", NOW)["views"], 2)

    def test_breakdowns_rank_and_merge_history_with_today(self):
        yesterday = NOW - timedelta(days=1)
        self.store.record(a_hit(country="FR", visitor="v1"), yesterday)
        self.store.rollup(NOW)
        self.store.record(a_hit(country="DE", visitor="v2"), NOW)
        self.store.record(a_hit(country="DE", visitor="v3"), NOW)

        countries = self.store.traffic("7d", NOW)["breakdowns"]["country"]
        self.assertEqual(
            countries,
            [
                {"key": "DE", "views": 2, "uniques": 2},
                {"key": "FR", "views": 1, "uniques": 1},
            ],
        )

    def test_every_dimension_is_reported(self):
        self.store.record(a_hit(utm_campaign="launch", device="phone"), NOW)
        breakdowns = self.store.traffic("7d", NOW)["breakdowns"]
        self.assertEqual(set(breakdowns), set(DIMENSIONS))
        self.assertEqual(breakdowns["device"][0]["key"], "phone")
        self.assertEqual(breakdowns["utm_campaign"][0]["key"], "launch")

    def test_one_visitor_on_two_pages_stays_one_unique(self):
        yesterday = NOW - timedelta(days=1)
        self.store.record(a_hit(path="/", visitor="v1"), yesterday)
        self.store.record(a_hit(path="/play/", visitor="v1"), yesterday)
        self.store.rollup(NOW)

        result = self.store.traffic("7d", NOW)
        self.assertEqual((result["views"], result["uniques"]), (2, 1))
        self.assertEqual(
            result["daily"][-2], {"day": "2026-09-13", "views": 2, "uniques": 1}
        )
        self.assertEqual(
            result["breakdowns"]["country"], [{"key": "FR", "views": 2, "uniques": 1}]
        )
        self.assertEqual(
            result["breakdowns"]["path"],
            [
                {"key": "/", "views": 1, "uniques": 1},
                {"key": "/play/", "views": 1, "uniques": 1},
            ],
        )

    def test_the_utm_source_and_medium_survive_the_rollup(self):
        self.store.record(
            a_hit(utm_source="reddit", utm_medium="social"), NOW - timedelta(days=1)
        )
        self.store.rollup(NOW)

        breakdowns = self.store.traffic("7d", NOW)["breakdowns"]
        self.assertEqual(breakdowns["utm_source"][0]["key"], "reddit")
        self.assertEqual(breakdowns["utm_medium"][0]["key"], "social")

    def test_a_range_covers_its_span_and_nothing_older(self):
        self.store.record(a_hit(), NOW - timedelta(days=10))
        self.store.record(a_hit(), NOW - timedelta(days=1))
        self.store.rollup(NOW)
        self.assertEqual(self.store.traffic("7d", NOW)["views"], 1)
        self.assertEqual(self.store.traffic("30d", NOW)["views"], 2)
        self.assertEqual(len(self.store.traffic("30d", NOW)["daily"]), 30)

    def test_an_unknown_range_falls_back_to_a_week(self):
        self.assertEqual(len(self.store.traffic("nonsense", NOW)["daily"]), 7)

    def test_an_event_row_has_nowhere_to_put_a_person(self):
        # The privacy promise is the column list: a salted daily digest is the
        # only per-person thing there is room for. A new column here is a
        # deliberate edit, never a drift.
        self.store.record(a_hit(), NOW)
        with sqlite3.connect(self.store.path) as db:
            columns = [row[1] for row in db.execute("PRAGMA table_info(events)")]
        self.assertEqual(columns, ["id", "ts", "kind", *DIMENSIONS, "visitor"])

    def test_an_empty_database_answers_zeroes(self):
        result = self.store.traffic("7d", NOW)
        self.assertEqual((result["views"], result["uniques"]), (0, 0))
        self.assertEqual(result["breakdowns"]["country"], [])


if __name__ == "__main__":
    unittest.main()
