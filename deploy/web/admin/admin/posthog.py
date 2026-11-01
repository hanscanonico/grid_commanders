"""PostHog's query API, read from the server.

The personal key stays on this side of /admin: the page only ever sees the
numbers a panel made of an answer. A query writes `SCOPE` in its WHERE and `rows`
fills in what holds it to the site's own traffic.
"""

from __future__ import annotations

import http.client
import json
import logging
import threading
import time
import urllib.error
import urllib.request
from collections.abc import Callable
from typing import NamedTuple

log = logging.getLogger("admin")

TIMEOUT_SECONDS = 20
# A page load runs a handful of queries against a key's hourly budget, and five
# minutes behind is still today's answer.
REMEMBER_SECONDS = 300
# Where a query's SQL says "only the events this site's numbers may count".
SCOPE = "{scope}"


class PostHogError(Exception):
    """A query that got no usable answer, in words safe to show the owner."""


class _RefuseRedirects(urllib.request.HTTPRedirectHandler):
    """urllib would replay the Authorization header wherever a 3xx points."""

    def redirect_request(self, *args, **kwargs):
        return None


_OPENER = urllib.request.build_opener(_RefuseRedirects)


class _Held(NamedTuple):
    at: float
    answer: dict


class PostHog:
    def __init__(
        self,
        url: str,
        project: str,
        key: str,
        site_host: str,
        clock: Callable[[], float] = time.monotonic,
    ) -> None:
        self._endpoint = f"{url.rstrip('/')}/api/projects/{project}/query/"
        self._key = key
        self._hosts = (site_host, f"www.{site_host}")
        self._clock = clock
        self._lock = threading.Lock()
        self._held: dict[str, _Held] = {}

    @property
    def configured(self) -> bool:
        return bool(self._key)

    def rows(self, name: str, sql: str, since: str) -> list[list]:
        """The result rows of `sql`, whose `SCOPE` stands for the site's events.

        `name` labels the query in PostHog's log and in any error it causes.
        Raises `PostHogError` when there is no answer to give.
        """
        body = {
            "query": {
                "kind": "HogQLQuery",
                "query": sql.replace(SCOPE, self._scope(since)),
                "filters": {
                    "filterTestAccounts": True,
                    "dateRange": {"date_from": since},
                },
            },
            "name": name,
        }
        request = urllib.request.Request(
            self._endpoint,
            data=json.dumps(body).encode("utf-8"),
            method="POST",
            headers={
                "Authorization": f"Bearer {self._key}",
                "Content-Type": "application/json",
            },
        )
        try:
            with _OPENER.open(request, timeout=TIMEOUT_SECONDS) as response:
                raw = response.read()
            results = json.loads(raw)["results"]
        except urllib.error.HTTPError as error:
            with error:
                reason = _refusal(error)
            raise self._failed(name, reason) from None
        except (OSError, http.client.HTTPException):
            raise self._failed(name, "PostHog did not answer.") from None
        except (ValueError, KeyError, TypeError):
            raise self._failed(name, _UNREADABLE) from None
        if not isinstance(results, list):
            raise self._failed(name, _UNREADABLE)
        return results

    def remembered(self, key: str, build: Callable[[], dict]) -> dict:
        """`build()`, at most once per `REMEMBER_SECONDS` for each key.

        A refresh that fails hands back the last good answer with `stale` saying
        why. The lock is held across the fetch on purpose: two open tabs share
        one refresh rather than spending the key's budget twice.
        """
        with self._lock:
            held = self._held.get(key)
            if held is not None and self._clock() - held.at < REMEMBER_SECONDS:
                return held.answer
            try:
                answer = build()
            except PostHogError as error:
                if held is None:
                    raise
                return {**held.answer, "stale": str(error)}
            self._held[key] = _Held(self._clock(), answer)
            return answer

    def _scope(self, since: str) -> str:
        """The site's own events from `since` on.

        A local build posts to the same project, hence the hosts. `{filters}` is
        where PostHog applies the project's internal and test user filter, and it
        does so only where the placeholder is written.
        """
        hosts = ", ".join(_quoted(host) for host in self._hosts)
        start = _quoted(f"{since} 00:00:00")
        return (
            f"timestamp >= toDateTime({start})"
            f" AND properties.$host IN ({hosts})"
            " AND {filters}"
        )

    @staticmethod
    def _failed(name: str, reason: str) -> PostHogError:
        log.warning("posthog query %s failed: %s", name, reason)
        return PostHogError(f"{name}: {reason}")


_UNREADABLE = "PostHog sent an answer this page cannot read."


def _quoted(value: str) -> str:
    escaped = value.replace("\\", "\\\\").replace("'", "\\'")
    return f"'{escaped}'"


def _refusal(error: urllib.error.HTTPError) -> str:
    """What a non-2xx means to the owner. Only PostHog's words, never the key."""
    if error.code in (401, 403):
        return (
            f"PostHog refused the key ({error.code}). It needs Query Read access"
            " to this project."
        )
    if error.code == 429:
        return "PostHog's rate limit for this key is used up for now."
    try:
        detail = json.loads(error.read()).get("detail") or ""
    except (ValueError, AttributeError, OSError, http.client.HTTPException):
        detail = ""
    return f"PostHog answered {error.code}. {detail}".strip()
