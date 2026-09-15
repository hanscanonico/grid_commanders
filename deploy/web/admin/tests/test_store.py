import sqlite3
import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path

from admin.hit import Hit
from admin.store import (
    BUCKET_SECONDS,
    DIMENSIONS,
    RAW_RETENTION_DAYS,
    SESSION_BUCKETS,
    Store,
    resolve_range,
    session_bucket,
)

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
            result["daily"][-1],
            {
                "day": "2026-09-14",
                "views": 0,
                "uniques": 0,
                "engaged_visitors": 0,
                "engaged_seconds": 0,
            },
        )
        self.assertEqual(
            result["daily"][-2],
            {
                "day": "2026-09-13",
                "views": 3,
                "uniques": 2,
                "engaged_visitors": 0,
                "engaged_seconds": 0,
            },
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
            result["daily"][-1],
            {
                "day": "2026-09-14",
                "views": 2,
                "uniques": 1,
                "engaged_visitors": 0,
                "engaged_seconds": 0,
            },
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
            result["daily"][-2],
            {
                "day": "2026-09-13",
                "views": 2,
                "uniques": 1,
                "engaged_visitors": 0,
                "engaged_seconds": 0,
            },
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
        self.assertEqual(self.store.traffic("nonsense", NOW)["range"], "7d")

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


class DurationTests(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.dir.cleanup)
        self.store = Store(str(Path(self.dir.name) / "admin.sqlite"))
        self.addCleanup(self.store.close)

    def beat(self, moment, visitor="v1", path="/"):
        self.store.record(
            a_hit(path=path, country="", referrer_host="", device="", visitor=visitor),
            moment,
            kind="heartbeat",
        )

    def beats(self, start, count, visitor="v1", path="/"):
        for step in range(count):
            self.beat(start + timedelta(seconds=step * BUCKET_SECONDS), visitor, path)

    def test_two_tabs_in_one_bucket_count_once(self):
        self.beat(NOW, visitor="v1")
        self.beat(NOW + timedelta(seconds=5), visitor="v1")
        result = self.store.traffic("7d", NOW)
        self.assertEqual(result["engaged_visitors"], 1)
        self.assertEqual(result["engaged_seconds"], BUCKET_SECONDS)
        self.assertEqual(result["avg_seconds"], BUCKET_SECONDS)

    def test_five_buckets_are_two_and_a_half_minutes(self):
        self.beats(NOW, 5)
        self.assertEqual(self.store.traffic("7d", NOW)["engaged_seconds"], 150)

    def test_a_visitor_who_never_beat_is_a_unique_but_not_engaged(self):
        self.store.record(a_hit(visitor="reader"), NOW)
        self.beats(NOW, 2, visitor="player")
        self.store.record(a_hit(visitor="player"), NOW)
        result = self.store.traffic("7d", NOW)
        self.assertEqual(result["uniques"], 2)
        self.assertEqual(result["engaged_visitors"], 1)
        self.assertEqual(result["avg_seconds"], 60)

    def test_every_session_length_bucket_has_a_name(self):
        for seconds, expected in (
            (0, SESSION_BUCKETS[0]),
            (29, SESSION_BUCKETS[0]),
            (30, SESSION_BUCKETS[1]),
            (119, SESSION_BUCKETS[1]),
            (120, SESSION_BUCKETS[2]),
            (300, SESSION_BUCKETS[3]),
            (900, SESSION_BUCKETS[4]),
            (3600, SESSION_BUCKETS[5]),
            (99999, SESSION_BUCKETS[5]),
        ):
            with self.subTest(seconds=seconds):
                self.assertEqual(session_bucket(seconds), expected)

    def test_sessions_land_in_their_bucket_in_bucket_order(self):
        self.beats(NOW, 1, visitor="short")
        self.beats(NOW, 6, visitor="middling")
        self.beats(NOW, 30, visitor="long")
        rows = self.store.traffic("7d", NOW)["session_length"]
        self.assertEqual([row["key"] for row in rows], list(SESSION_BUCKETS))
        by_key = {row["key"]: row for row in rows}
        self.assertEqual(
            by_key[SESSION_BUCKETS[1]],
            {"key": SESSION_BUCKETS[1], "visitors": 1, "seconds": 30},
        )
        self.assertEqual(
            by_key[SESSION_BUCKETS[2]],
            {"key": SESSION_BUCKETS[2], "visitors": 1, "seconds": 180},
        )
        self.assertEqual(
            by_key[SESSION_BUCKETS[4]],
            {"key": SESSION_BUCKETS[4], "visitors": 1, "seconds": 900},
        )
        self.assertEqual(by_key[SESSION_BUCKETS[0]]["visitors"], 0)

    def test_time_on_page_splits_the_landing_page_from_the_game(self):
        self.beats(NOW, 2, visitor="v1", path="/")
        self.beats(NOW + timedelta(minutes=5), 4, visitor="v1", path="/play/")
        self.beats(NOW, 1, visitor="v2", path="/play/")
        rows = self.store.traffic("7d", NOW)["time_on_path"]
        self.assertEqual(
            rows,
            [
                {"key": "/play/", "visitors": 2, "seconds": 150},
                {"key": "/", "visitors": 1, "seconds": 60},
            ],
        )

    def test_a_folded_day_and_a_live_day_answer_the_same_numbers(self):
        yesterday = NOW - timedelta(days=1)
        for day in (yesterday, NOW):
            self.beats(day, 3, visitor=f"v{day.day}a", path="/")
            self.beats(day, 12, visitor=f"v{day.day}b", path="/play/")
        self.store.rollup(NOW)
        result = self.store.traffic("7d", NOW)
        folded = result["daily"][-2]
        live = result["daily"][-1]
        self.assertEqual(folded["engaged_visitors"], live["engaged_visitors"])
        self.assertEqual(folded["engaged_seconds"], live["engaged_seconds"])
        self.assertEqual(live["engaged_seconds"], 450)
        self.assertEqual(result["engaged_visitors"], 4)
        self.assertEqual(result["engaged_seconds"], 900)
        self.assertEqual(
            result["time_on_path"],
            [
                {"key": "/play/", "visitors": 2, "seconds": 720},
                {"key": "/", "visitors": 2, "seconds": 180},
            ],
        )

    def test_folding_twice_changes_nothing(self):
        self.beats(NOW - timedelta(days=1), 4)
        self.store.rollup(NOW)
        first = self.store.traffic("7d", NOW)
        self.store.rollup(NOW)
        self.store.rollup(NOW)
        self.assertEqual(self.store.traffic("7d", NOW), first)

    def test_durations_outlive_the_raw_events(self):
        self.beats(NOW - timedelta(days=RAW_RETENTION_DAYS + 5), 4)
        self.store.rollup(NOW)
        self.assertEqual(self.store.raw_event_count(), 0)
        year = self.store.traffic("365d", NOW)
        self.assertEqual(year["engaged_seconds"], 120)
        self.assertEqual(year["engaged_visitors"], 1)

    def test_an_empty_database_answers_zeroes(self):
        result = self.store.traffic("7d", NOW)
        self.assertEqual(result["engaged_visitors"], 0)
        self.assertEqual(result["engaged_seconds"], 0)
        self.assertEqual(result["avg_seconds"], 0)
        self.assertEqual(result["time_on_path"], [])
        self.assertEqual(
            [row["key"] for row in result["session_length"]], list(SESSION_BUCKETS)
        )


class PlayedShareTests(unittest.TestCase):
    """The two unique counts the panel's played share is drawn from."""

    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.dir.cleanup)
        self.store = Store(str(Path(self.dir.name) / "admin.sqlite"))
        self.addCleanup(self.store.close)

    def test_the_two_page_uniques_come_out_of_a_folded_and_a_live_day(self):
        for moment in (NOW - timedelta(days=1), NOW):
            for visitor in ("reader", "player"):
                self.store.record(a_hit(path="/", visitor=visitor), moment)
            self.store.record(a_hit(path="/play/", visitor="player"), moment)
        self.store.rollup(NOW)
        result = self.store.traffic("7d", NOW)
        self.assertEqual(result["landing_uniques"], 4)
        self.assertEqual(result["played_uniques"], 2)

    def test_an_empty_database_answers_zeroes(self):
        result = self.store.traffic("7d", NOW)
        self.assertEqual((result["landing_uniques"], result["played_uniques"]), (0, 0))


class MigrationTests(unittest.TestCase):
    """A database written by the schema before this issue opens and keeps its rows."""

    PREVIOUS_SCHEMA = """
    CREATE TABLE events (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        ts TEXT NOT NULL,
        kind TEXT NOT NULL,
        path TEXT NOT NULL DEFAULT '',
        country TEXT NOT NULL DEFAULT '',
        referrer_host TEXT NOT NULL DEFAULT '',
        device TEXT NOT NULL DEFAULT '',
        utm_source TEXT NOT NULL DEFAULT '',
        utm_medium TEXT NOT NULL DEFAULT '',
        utm_campaign TEXT NOT NULL DEFAULT '',
        visitor TEXT NOT NULL DEFAULT ''
    );
    CREATE TABLE daily_totals (
        day TEXT PRIMARY KEY,
        views INTEGER NOT NULL,
        uniques INTEGER NOT NULL
    );
    CREATE TABLE daily_dimension (
        day TEXT NOT NULL,
        dimension TEXT NOT NULL,
        key TEXT NOT NULL,
        views INTEGER NOT NULL,
        uniques INTEGER NOT NULL,
        PRIMARY KEY (day, dimension, key)
    );
    """

    def test_the_old_database_migrates_with_its_history(self):
        folder = tempfile.TemporaryDirectory()
        self.addCleanup(folder.cleanup)
        path = str(Path(folder.name) / "admin.sqlite")
        with sqlite3.connect(path) as db:
            db.executescript(self.PREVIOUS_SCHEMA)
            db.execute(
                "INSERT INTO daily_totals (day, views, uniques) VALUES (?, ?, ?)",
                ("2026-09-13", 12, 5),
            )
            db.execute(
                "INSERT INTO daily_dimension (day, dimension, key, views, uniques)"
                " VALUES (?, ?, ?, ?, ?)",
                ("2026-09-13", "country", "FR", 12, 5),
            )

        store = Store(path)
        self.addCleanup(store.close)
        result = store.traffic("7d", NOW)
        self.assertEqual(result["views"], 12)
        self.assertEqual(result["breakdowns"]["country"][0]["key"], "FR")
        self.assertEqual(result["daily"][-2]["engaged_visitors"], 0)
        self.assertEqual(result["engaged_seconds"], 0)

        store.record(a_hit(visitor="v1"), NOW, kind="heartbeat")
        self.assertEqual(store.traffic("7d", NOW)["engaged_seconds"], BUCKET_SECONDS)


class ResolveRangeTests(unittest.TestCase):
    def test_a_range_we_serve_is_kept(self):
        for asked in ("7d", "30d", "90d", "365d"):
            with self.subTest(asked=asked):
                self.assertEqual(resolve_range(asked), asked)

    def test_anything_else_is_a_week(self):
        for asked in ("", "all-time", "7", "7D", "-1"):
            with self.subTest(asked=asked):
                self.assertEqual(resolve_range(asked), "7d")


if __name__ == "__main__":
    unittest.main()
