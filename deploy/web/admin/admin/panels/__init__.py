"""The panel registry.

The shell lists whatever is in `PANELS`, opens on the first, and asks the
selected one for its JSON. Adding a panel is appending a module here; the server,
the page and the store need no edit for it.
"""

from __future__ import annotations

from types import ModuleType

from . import players, traffic

PANELS: tuple[ModuleType, ...] = (players, traffic)


def by_slug(wanted: str) -> ModuleType | None:
    for panel in PANELS:
        if panel.slug == wanted:
            return panel
    return None


def listing() -> list[dict[str, str]]:
    return [{"slug": panel.slug, "name": panel.name} for panel in PANELS]
