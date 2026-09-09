"""The game tree beside this instrument, and the one way a suite reads it.

Several bars here are the game's own values, read back out of its source rather
than restated: the faction themes, `FACE_REGION`, the roster's faction keys, the
gauge colour. All of them start from the same two paths and end in the same
scrape, so both live here instead of once per suite.

Parsing GDScript with a regex is narrow on purpose — each caller's pattern reads
one construct and nothing else — and `scrape` is what makes a rename in the game
fail loudly instead of silently matching nothing.
"""

from __future__ import annotations

import re
from pathlib import Path

# The checkout this instrument sits in: generators/portraits/tests/game.py, so
# three levels up. Derived from this file's own path, so it holds wherever the
# checkout sits and whatever directory a run is started from.
GAME = Path(__file__).resolve().parents[3]
# The one file the commander art's own constants live in.
VISUALS = GAME / "scenes/common/commander_visuals.gd"


def scrape(path: Path, pattern: re.Pattern[str]) -> re.Match[str]:
    """The one match a game file is read for. No match is a failure, not None.

    A caller that got `None` back would compare against nothing and pass, which
    is the whole reason these suites exist, so the miss is raised here.
    """
    found = pattern.search(path.read_text())
    if found is None:
        raise AssertionError(f"{path} has nothing matching {pattern.pattern!r}")
    return found
