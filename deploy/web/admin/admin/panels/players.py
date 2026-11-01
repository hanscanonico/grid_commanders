"""The Players panel: who really came and what they played, from PostHog.

PostHog only hears from a browser that ran the page's script, so a scanner that
fetches a page and sends a browser's user agent never reaches it, and the game
tells it about matches. A visit is a PostHog session: nobody is counted as a
person, because someone who has not accepted the banner keeps nothing on their
device and gets a new id on every page they load.
"""

from __future__ import annotations

from datetime import date, datetime, timedelta

from ..posthog import SCOPE, PostHog, PostHogError
from ..sources import Sources
from ..store import GAME_PATH, range_span, resolve_range

name = "Players"
slug = "players"

TOP_N = 12
# A range is at most 365 days, and PostHog stops at 100 rows without a LIMIT.
_DAILY_LIMIT = 400

_SESSION = "properties.$session_id"
_VISIT = "event = '$pageview'"
_GAME_OPEN = f"{_VISIT} AND properties.$pathname = '{GAME_PATH}'"
# A table of computers reports itself as `spectate`: nobody played that match.
_PLAYED_MATCH = "properties.mode != 'spectate'"
_STARTED = f"event = 'match_started' AND {_PLAYED_MATCH}"
_ENDED = f"event = 'match_ended' AND {_PLAYED_MATCH}"

_TOTALS = f"""
SELECT uniqIf({_SESSION}, {_VISIT}) AS visits,
       uniqIf({_SESSION}, {_GAME_OPEN}) AS game,
       uniqIf({_SESSION}, {_STARTED}) AS played,
       uniqIf({_SESSION}, {_ENDED}) AS finished
FROM events
WHERE {SCOPE}"""

_DAILY = f"""
SELECT toDate(timestamp) AS day,
       uniqIf({_SESSION}, {_VISIT}) AS visits,
       uniqIf({_SESSION}, {_GAME_OPEN}) AS game,
       uniqIf({_SESSION}, {_STARTED}) AS played
FROM events
WHERE {SCOPE}
GROUP BY day
ORDER BY day
LIMIT {_DAILY_LIMIT}"""

# A session's first event to its last, on the game page. One that sent nothing
# after its page view has no length to measure, rather than a length of zero.
_TIME_IN_GAME = f"""
SELECT count() AS measured, median(secs) AS typical
FROM (
    SELECT {_SESSION} AS sid,
           dateDiff('second', min(timestamp), max(timestamp)) AS secs
    FROM events
    WHERE properties.$pathname = '{GAME_PATH}' AND {SCOPE}
    GROUP BY sid
)
WHERE secs > 0"""

_MISSIONS = f"""
SELECT properties.mission AS bucket,
       countIf(event = 'campaign_mission_started') AS started,
       countIf(event = 'campaign_mission_cleared') AS cleared
FROM events
WHERE event IN ('campaign_mission_started', 'campaign_mission_cleared') AND {SCOPE}
GROUP BY bucket
ORDER BY started DESC, bucket ASC
LIMIT {TOP_N}"""


def _visits_by(prop: str) -> str:
    return f"""
SELECT {prop} AS bucket,
       uniqIf({_SESSION}, {_VISIT}) AS visits,
       uniqIf({_SESSION}, {_STARTED}) AS played
FROM events
WHERE {SCOPE}
GROUP BY bucket
ORDER BY visits DESC, bucket ASC
LIMIT {TOP_N}"""


def _matches_by(prop: str) -> str:
    return f"""
SELECT {prop} AS bucket,
       countIf({_STARTED}) AS started,
       countIf({_ENDED}) AS finished
FROM events
WHERE event IN ('match_started', 'match_ended') AND {_PLAYED_MATCH} AND {SCOPE}
GROUP BY bucket
ORDER BY started DESC, bucket ASC
LIMIT {TOP_N}"""


def query(sources: Sources, asked: str, now: datetime) -> dict:
    posthog = sources.posthog
    range_key = resolve_range(asked)
    if not posthog.configured:
        return {"configured": False, "range": range_key}
    try:
        return posthog.remembered(range_key, lambda: _read(posthog, range_key, now))
    except PostHogError as error:
        return {"configured": True, "range": range_key, "error": str(error)}


def _read(posthog: PostHog, range_key: str, now: datetime) -> dict:
    """A fresh answer. Rows of a shape this panel did not ask for are PostHog's
    failure like any other, not a dropped connection the page cannot explain."""
    try:
        return _fresh(posthog, range_key, now)
    except (TypeError, ValueError) as error:
        raise PostHogError(f"PostHog sent rows this panel cannot read: {error}")


def _fresh(posthog: PostHog, range_key: str, now: datetime) -> dict:
    first, today = range_span(range_key, now)

    def rows(query_name: str, sql: str) -> list[list]:
        return posthog.rows(f"admin_{query_name}", sql, first)

    visits, game_opens, played, finished = _one_row(rows("totals", _TOTALS), 4)
    measured, typical = _one_row(rows("time", _TIME_IN_GAME), 2)
    return {
        "configured": True,
        "range": range_key,
        "from": first,
        "to": today,
        "fetched_at": now.strftime("%H:%M UTC"),
        "visits": _count(visits),
        "game_opens": _count(game_opens),
        "played": _count(played),
        "finished": _count(finished),
        "measured_sessions": _count(measured),
        "median_seconds": _count(typical),
        "daily": _days(first, today, rows("daily", _DAILY)),
        "pages": _table(rows("page", _visits_by("properties.$pathname")), _VISIT_COLS),
        "countries": _table(
            rows("country", _visits_by("properties.$geoip_country_code")), _VISIT_COLS
        ),
        "referrers": _table(
            rows("referrer", _visits_by("properties.$referring_domain")), _VISIT_COLS
        ),
        "devices": _table(
            rows("device", _visits_by("properties.$device_type")), _VISIT_COLS
        ),
        "modes": _table(rows("mode", _matches_by("properties.mode")), _MATCH_COLS),
        "maps": _table(rows("map", _matches_by("properties.map")), _MATCH_COLS),
        "missions": _table(rows("mission", _MISSIONS), _MISSION_COLS),
    }


_VISIT_COLS = ("visits", "played")
_MATCH_COLS = ("started", "finished")
_MISSION_COLS = ("started", "cleared")
# What PostHog calls a visit with no referrer.
_DIRECT = "$direct"


def _one_row(rows: list[list], width: int) -> list:
    return rows[0] if rows else [0] * width


def _count(value) -> int:
    """A count or a median as a whole number; an empty median is null or NaN."""
    if value is None or value != value:
        return 0
    return round(value)


def _label(value) -> str:
    if value == _DIRECT:
        return "(direct)"
    return "" if value is None else str(value)


def _table(rows: list[list], columns: tuple[str, ...]) -> list[dict]:
    """`[bucket, n, m]` rows as the page's `{key, column: n, ...}`.

    A session can land in a bucket with no event a column counts, a page leave
    being the usual one, and a row of noughts says nothing.
    """
    table = []
    for row in rows:
        counts = {column: _count(value) for column, value in zip(columns, row[1:])}
        if any(counts.values()):
            table.append({"key": _label(row[0]), **counts})
    return table


def _days(first: str, last: str, rows: list[list]) -> list[dict]:
    """One entry per day of the range, a day nobody came included."""
    counted = {str(row[0])[:10]: row for row in rows}
    days = []
    day = date.fromisoformat(first)
    while day <= date.fromisoformat(last):
        key = day.isoformat()
        _, visits, game_opens, played = counted.get(key, (key, 0, 0, 0))
        days.append(
            {
                "day": key,
                "visits": _count(visits),
                "game_opens": _count(game_opens),
                "played": _count(played),
            }
        )
        day += timedelta(days=1)
    return days
