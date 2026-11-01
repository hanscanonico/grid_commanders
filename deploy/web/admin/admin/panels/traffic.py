"""The Server traffic panel: every page request nginx saw, scanners included.

A panel is three names — `name`, `slug`, `query` — and nothing else, so a
second one is a second module and no edit anywhere but the registry.
"""

from __future__ import annotations

from datetime import datetime

from ..sources import Sources

name = "Server traffic"
slug = "traffic"


def query(sources: Sources, asked: str, now: datetime) -> dict:
    return sources.store.traffic(asked, now)
