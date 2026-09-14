"""The Traffic panel: who reached the site, from where, on what.

A panel is three names — `name`, `slug`, `query` — and nothing else, so a
second one is a second module and no edit anywhere but the registry.
"""

from __future__ import annotations

from datetime import datetime

from ..store import Store

name = "Traffic"
slug = "traffic"


def query(store: Store, asked: str, now: datetime) -> dict:
    return store.traffic(asked, now)
