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
_HEARTBEATS_ON = "kind = 'heartbeat' AND substr(ts, 1, 10) = ?"

# A visitor's duration is the number of distinct slots they beat in, times the
# slot. The client beats once per slot while its page is visible, so the two
# numbers are one contract: change this and the interval in the landing page's
# inline script and in the Web preset's head include change with it.
BUCKET_SECONDS = 30

# The six lengths the panel sorts sessions into, in the order it shows them,
# and the upper bound of each but the last. The first stays empty while the
# slot is 30 s — a session is at least one slot — and is kept so the reader
# sees the scale starts at zero rather than wondering where the bounces went.
SESSION_BUCKETS: tuple[str, ...] = (
    "under 30 s",
    "30 s to 2 min",
    "2 to 5 min",
    "5 to 15 min",
    "15 to 60 min",
    "over 1 h",
)
_SESSION_BOUNDS: tuple[int, ...] = (30, 120, 300, 900, 3600)

# The two bounded dimensions duration is broken down by. Their keys are the
# bucket names above and the known page paths, so neither can grow with what a
# stranger types.
DURATION_DIMENSIONS: tuple[str, ...] = ("session_length", "time_on_path")

# The two pages the site has, as `hit.PAGE_PATHS` stores them. Their uniques are
# the played share: how many of the people who saw the pitch opened the game.
LANDING_PATH = "/"
GAME_PATH = "/play/"

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
	uniques INTEGER NOT NULL,
	engaged_visitors INTEGER NOT NULL DEFAULT 0,
	engaged_seconds INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS daily_dimension (
	day TEXT NOT NULL,
	dimension TEXT NOT NULL,
	key TEXT NOT NULL,
	views INTEGER NOT NULL,
	uniques INTEGER NOT NULL,
	visitors INTEGER NOT NULL DEFAULT 0,
	seconds INTEGER NOT NULL DEFAULT 0,
	PRIMARY KEY (day, dimension, key)
);
"""

# Columns added after the first deploy. Create-if-missing cannot add them to a
# table that already exists, so an open checks for each and adds what is absent
# — the box's collected history is worth more than a clean schema statement.
_ADDED_COLUMNS: tuple[tuple[str, str, str], ...] = (
    ("daily_totals", "engaged_visitors", "INTEGER NOT NULL DEFAULT 0"),
    ("daily_totals", "engaged_seconds", "INTEGER NOT NULL DEFAULT 0"),
    ("daily_dimension", "visitors", "INTEGER NOT NULL DEFAULT 0"),
    ("daily_dimension", "seconds", "INTEGER NOT NULL DEFAULT 0"),
)


def resolve_range(asked: str) -> str:
    """The range a caller asked for, or the default when it named none we serve."""
    return asked if asked in RANGES else DEFAULT_RANGE


def session_bucket(seconds: int) -> str:
    """Which of the six lengths a session of this many seconds belongs to."""
    for name, bound in zip(SESSION_BUCKETS, _SESSION_BOUNDS):
        if seconds < bound:
            return name
    return SESSION_BUCKETS[-1]


def fold_slots(slots: list[tuple[str, str, int]]) -> dict:
    """The day's duration figures from its (visitor, path, slot) rows.

    One function for both readers: the rollup folds a finished day with it and
    the panel folds today with it, so the two can never drift apart.
    """
    per_visitor: dict[str, set[int]] = {}
    per_path: dict[str, tuple[set[str], set[tuple[str, int]]]] = {}
    for visitor, path, slot in slots:
        per_visitor.setdefault(visitor, set()).add(slot)
        seen, beats = per_path.setdefault(path, (set(), set()))
        seen.add(visitor)
        beats.add((visitor, slot))
    lengths = {name: [0, 0] for name in SESSION_BUCKETS}
    for visitor, taken in per_visitor.items():
        seconds = len(taken) * BUCKET_SECONDS
        counts = lengths[session_bucket(seconds)]
        counts[0] += 1
        counts[1] += seconds
    return {
        "engaged_visitors": len(per_visitor),
        "engaged_seconds": sum(len(taken) for taken in per_visitor.values())
        * BUCKET_SECONDS,
        "session_length": lengths,
        "time_on_path": {
            path: [len(seen), len(beats) * BUCKET_SECONDS]
            for path, (seen, beats) in per_path.items()
        },
    }


def _empty_day(day: str) -> dict:
    return {
        "day": day,
        "views": 0,
        "uniques": 0,
        "engaged_visitors": 0,
        "engaged_seconds": 0,
    }


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
            self._add_missing_columns()
            self._db.commit()

    def _add_missing_columns(self) -> None:
        for table, column, declaration in _ADDED_COLUMNS:
            present = {
                row["name"] for row in self._db.execute(f"PRAGMA table_info({table})")
            }
            if column not in present:
                self._db.execute(
                    f"ALTER TABLE {table} ADD COLUMN {column} {declaration}"
                )

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
                    " WHERE substr(ts, 1, 10) < ? ORDER BY day",
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
        duration = fold_slots(self._slots(day))
        self._db.execute("DELETE FROM daily_totals WHERE day = ?", (day,))
        self._db.execute(
            "INSERT INTO daily_totals"
            " (day, views, uniques, engaged_visitors, engaged_seconds)"
            " SELECT ?, COUNT(*), COUNT(DISTINCT visitor), ?, ?"
            f" FROM events WHERE {_PAGEVIEWS_ON}",
            (day, duration["engaged_visitors"], duration["engaged_seconds"], day),
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
        for dimension in DURATION_DIMENSIONS:
            for key, (visitors, seconds) in duration[dimension].items():
                if visitors == 0:
                    continue
                self._db.execute(
                    "INSERT INTO daily_dimension"
                    " (day, dimension, key, views, uniques, visitors, seconds)"
                    " VALUES (?, ?, ?, 0, 0, ?, ?)",
                    (day, dimension, key, visitors, seconds),
                )

    def _slots(self, day: str) -> list[tuple[str, str, int]]:
        """One row per visitor, page and 30-second slot they beat in.

        The `DISTINCT` is the whole dedupe: two tabs, a retry and the parting
        beat all fall in the same slot and are one row. `strftime` reads the
        stored ISO timestamp, which always carries its UTC offset.
        """
        rows = self._db.execute(
            "SELECT DISTINCT visitor, path,"
            " CAST(strftime('%s', ts) AS INTEGER) / ? AS slot"
            f" FROM events WHERE {_HEARTBEATS_ON}",
            (BUCKET_SECONDS, day),
        )
        return [(row["visitor"], row["path"], row["slot"]) for row in rows]

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
            live = fold_slots(self._slots(today))
            daily = self._daily_totals(first, today, live)
            breakdowns = {
                dimension: self._top(dimension, first, today)
                for dimension in DIMENSIONS
            }
            lengths = self._duration_totals("session_length", first, today, live)
            paths = self._duration_totals("time_on_path", first, today, live)
        engaged_visitors = sum(row["engaged_visitors"] for row in daily)
        engaged_seconds = sum(row["engaged_seconds"] for row in daily)
        uniques_by_path = {row["key"]: row["uniques"] for row in breakdowns["path"]}
        return {
            "range": range_key,
            "from": first,
            "to": today,
            "views": sum(row["views"] for row in daily),
            "uniques": sum(row["uniques"] for row in daily),
            "engaged_visitors": engaged_visitors,
            "engaged_seconds": engaged_seconds,
            "avg_seconds": (
                round(engaged_seconds / engaged_visitors) if engaged_visitors else 0
            ),
            "landing_uniques": uniques_by_path.get(LANDING_PATH, 0),
            "played_uniques": uniques_by_path.get(GAME_PATH, 0),
            "daily": daily,
            "breakdowns": breakdowns,
            "session_length": [
                {"key": name, "visitors": lengths[name][0], "seconds": lengths[name][1]}
                for name in SESSION_BUCKETS
            ],
            "time_on_path": [
                {"key": key, "visitors": counts[0], "seconds": counts[1]}
                for key, counts in sorted(
                    paths.items(), key=lambda item: (-item[1][1], item[0])
                )
            ],
        }

    def _duration_totals(
        self, dimension: str, first: str, today: str, live: dict
    ) -> dict[str, list[int]]:
        """A duration dimension over the range: the folded days plus today."""
        totals: dict[str, list[int]] = (
            {name: [0, 0] for name in SESSION_BUCKETS}
            if dimension == "session_length"
            else {}
        )
        history = self._db.execute(
            "SELECT key, visitors, seconds FROM daily_dimension"
            " WHERE dimension = ? AND day >= ? AND day < ?",
            (dimension, first, today),
        )
        counted = [(row["key"], row["visitors"], row["seconds"]) for row in history]
        counted += [
            (key, visitors, seconds)
            for key, (visitors, seconds) in live[dimension].items()
        ]
        for key, visitors, seconds in counted:
            bucket = totals.setdefault(key, [0, 0])
            bucket[0] += visitors
            bucket[1] += seconds
        return totals

    def _daily_totals(self, first: str, today: str, live: dict) -> list[dict]:
        counted: dict[str, dict] = {}
        for row in self._db.execute(
            "SELECT day, views, uniques, engaged_visitors, engaged_seconds"
            " FROM daily_totals WHERE day >= ? AND day < ?",
            (first, today),
        ):
            counted[row["day"]] = dict(row)
        views = self._db.execute(
            "SELECT COUNT(*) AS views, COUNT(DISTINCT visitor) AS uniques"
            f" FROM events WHERE {_PAGEVIEWS_ON}",
            (today,),
        ).fetchone()
        counted[today] = {
            "day": today,
            "views": views["views"],
            "uniques": views["uniques"],
            "engaged_visitors": live["engaged_visitors"],
            "engaged_seconds": live["engaged_seconds"],
        }
        step = date.fromisoformat(first)
        end = date.fromisoformat(today)
        days: list[dict] = []
        while step <= end:
            key = step.isoformat()
            days.append(counted.get(key, _empty_day(key)))
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
