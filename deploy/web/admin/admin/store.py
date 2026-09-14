"""The SQLite store: raw events, the daily rollup, and the panel queries.

`events` is the tail — everything recorded since the last rollup, plus up to
90 days of history so a rollup can be re-run. The two `daily_` tables are the
history that is kept forever.

The rollup counts each dimension on its own rather than folding all of them
into one row per tuple. A visitor who reads the landing page and then opens
the game appears in two tuples, so a per-tuple table would have counted them
twice in the day's uniques; counted per dimension they are one. It is also far
fewer rows — the dimensions add instead of multiplying.
"""

from __future__ import annotations

import sqlite3
import threading
from datetime import date, datetime, timedelta, timezone

from .hit import Hit

# Raw events older than this are dropped at each rollup; the aggregates they
# were folded into stay forever.
RAW_RETENTION_DAYS = 90
TOP_N = 20

RANGES: dict[str, int] = {"7d": 7, "30d": 30, "90d": 90, "365d": 365}
DEFAULT_RANGE = "7d"

# The one condition every raw-event query shares, so "what counts as a
# pageview on a day" is written once. It binds one parameter: the day.
_PAGEVIEWS_ON = "kind = 'pageview' AND substr(ts, 1, 10) = ?"

DIMENSIONS: tuple[str, ...] = (
    "path",
    "country",
    "referrer_host",
    "device",
    "utm_source",
    "utm_medium",
    "utm_campaign",
)

_SCHEMA = """
CREATE TABLE IF NOT EXISTS events (
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
CREATE INDEX IF NOT EXISTS events_ts ON events (ts);

CREATE TABLE IF NOT EXISTS daily_totals (
	day TEXT PRIMARY KEY,
	views INTEGER NOT NULL,
	uniques INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS daily_dimension (
	day TEXT NOT NULL,
	dimension TEXT NOT NULL,
	key TEXT NOT NULL,
	views INTEGER NOT NULL,
	uniques INTEGER NOT NULL,
	PRIMARY KEY (day, dimension, key)
);
"""


def resolve_range(asked: str) -> str:
    """The range a caller asked for, or the default when it named none we serve."""
    return asked if asked in RANGES else DEFAULT_RANGE


def day_of(moment: datetime) -> str:
    return moment.astimezone(timezone.utc).strftime("%Y-%m-%d")


class Store:
    """Every read and write of the database, behind one lock.

    `check_same_thread=False` plus the lock rather than a connection per
    thread: the writers are one ingest handler and one hourly rollup, and a
    single serialised connection is both simpler and enough at this volume.
    """

    def __init__(self, path: str) -> None:
        self.path = path
        self._lock = threading.Lock()
        self._db = sqlite3.connect(path, check_same_thread=False)
        self._db.row_factory = sqlite3.Row
        with self._lock:
            self._db.execute("PRAGMA journal_mode=WAL")
            self._db.execute("PRAGMA synchronous=NORMAL")
            self._db.executescript(_SCHEMA)
            self._db.commit()

    def close(self) -> None:
        with self._lock:
            self._db.close()

    def record(self, hit: Hit, now: datetime, kind: str = "pageview") -> None:
        with self._lock:
            self._db.execute(
                "INSERT INTO events (ts, kind, path, country, referrer_host, device,"
                " utm_source, utm_medium, utm_campaign, visitor)"
                " VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                (
                    now.astimezone(timezone.utc).isoformat(timespec="seconds"),
                    kind,
                    hit.path,
                    hit.country,
                    hit.referrer_host,
                    hit.device,
                    hit.utm_source,
                    hit.utm_medium,
                    hit.utm_campaign,
                    hit.visitor,
                ),
            )
            self._db.commit()

    def rollup(self, now: datetime) -> int:
        """Fold every complete day in `events` into the daily tables.

        Replace rather than add, so running it twice over the same day leaves
        the same numbers. Today is skipped: it is still being written to, and
        the panel reads it live from `events` instead.
        """
        today = day_of(now)
        cutoff = (
            now.astimezone(timezone.utc) - timedelta(days=RAW_RETENTION_DAYS)
        ).date()
        with self._lock:
            days = [
                row["day"]
                for row in self._db.execute(
                    "SELECT DISTINCT substr(ts, 1, 10) AS day FROM events"
                    " WHERE kind = 'pageview' AND substr(ts, 1, 10) < ?"
                    " ORDER BY day",
                    (today,),
                )
            ]
            for day in days:
                self._fold(day)
            self._db.execute(
                "DELETE FROM events WHERE substr(ts, 1, 10) < ?", (cutoff.isoformat(),)
            )
            self._db.commit()
        return len(days)

    def _fold(self, day: str) -> None:
        self._db.execute("DELETE FROM daily_totals WHERE day = ?", (day,))
        self._db.execute(
            "INSERT INTO daily_totals (day, views, uniques)"
            " SELECT substr(ts, 1, 10), COUNT(*), COUNT(DISTINCT visitor)"
            f" FROM events WHERE {_PAGEVIEWS_ON}",
            (day,),
        )
        self._db.execute("DELETE FROM daily_dimension WHERE day = ?", (day,))
        for dimension in DIMENSIONS:
            self._db.execute(
                "INSERT INTO daily_dimension (day, dimension, key, views, uniques)"
                f" SELECT substr(ts, 1, 10), ?, {dimension},"
                " COUNT(*), COUNT(DISTINCT visitor)"
                f" FROM events WHERE {_PAGEVIEWS_ON} GROUP BY {dimension}",
                (dimension, day),
            )

    def raw_event_count(self) -> int:
        """How many events are still in the tail — the retention readout."""
        with self._lock:
            return self._db.execute("SELECT COUNT(*) FROM events").fetchone()[0]

    def traffic(self, asked: str, now: datetime) -> dict:
        """The Traffic panel's numbers for a range ending today.

        Uniques do not add up across days on purpose: the visitor hash is
        salted with the date, so the same person is a new id every day. A
        range's "uniques" is therefore the sum of daily uniques — visits by
        distinct people per day, not distinct people over the range. The
        panel's footnote says the same thing to the reader.
        """
        range_key = resolve_range(asked)
        span = RANGES[range_key]
        today = day_of(now)
        first = (
            datetime.fromisoformat(today).date() - timedelta(days=span - 1)
        ).isoformat()
        with self._lock:
            daily = self._daily_totals(first, today)
            breakdowns = {
                dimension: self._top(dimension, first, today)
                for dimension in DIMENSIONS
            }
        return {
            "range": range_key,
            "from": first,
            "to": today,
            "views": sum(row["views"] for row in daily),
            "uniques": sum(row["uniques"] for row in daily),
            "daily": daily,
            "breakdowns": breakdowns,
        }

    def _daily_totals(self, first: str, today: str) -> list[dict]:
        counted: dict[str, dict] = {}
        for row in self._db.execute(
            "SELECT day, views, uniques FROM daily_totals WHERE day >= ? AND day < ?",
            (first, today),
        ):
            counted[row["day"]] = dict(row)
        live = self._db.execute(
            "SELECT COUNT(*) AS views, COUNT(DISTINCT visitor) AS uniques"
            f" FROM events WHERE {_PAGEVIEWS_ON}",
            (today,),
        ).fetchone()
        counted[today] = {
            "day": today,
            "views": live["views"],
            "uniques": live["uniques"],
        }
        step = date.fromisoformat(first)
        end = date.fromisoformat(today)
        days: list[dict] = []
        while step <= end:
            key = step.isoformat()
            days.append(counted.get(key, {"day": key, "views": 0, "uniques": 0}))
            step += timedelta(days=1)
        return days

    def _top(self, dimension: str, first: str, today: str) -> list[dict]:
        totals: dict[str, list[int]] = {}
        history = self._db.execute(
            "SELECT key, views, uniques FROM daily_dimension"
            " WHERE dimension = ? AND day >= ? AND day < ?",
            (dimension, first, today),
        )
        live = self._db.execute(
            f"SELECT {dimension} AS key, COUNT(*) AS views,"
            " COUNT(DISTINCT visitor) AS uniques"
            f" FROM events WHERE {_PAGEVIEWS_ON} GROUP BY {dimension}",
            (today,),
        )
        for row in list(history) + list(live):
            bucket = totals.setdefault(row["key"], [0, 0])
            bucket[0] += row["views"]
            bucket[1] += row["uniques"]
        ranked = sorted(totals.items(), key=lambda item: (-item[1][0], item[0]))
        return [
            {"key": key, "views": counts[0], "uniques": counts[1]}
            for key, counts in ranked[:TOP_N]
        ]
