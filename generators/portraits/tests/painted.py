"""The busts the measuring suites read, painted once per run.

Four suites measure the same twenty-three rasters — the gauge sweep, the fringe
rule, the contrast floor and the style brief's metrics — and painting one is
what a run of this package costs, so the cache is here rather than four times
over. `bust.paint` is the call `pipeline.py` bakes the committed PNGs with, so a
bar measured off one of these is a bar over the shipped art.

The image handed back is shared: a caller that has to change one copies it
first.
"""

from __future__ import annotations

from functools import lru_cache

from PIL import Image

from portraitgen import bust, roster


Spec = roster.Face | roster.EmptySeat


def specs() -> list[tuple[str, Spec]]:
    """The whole sheet in the order the suites walk it — the bake's own order,
    asked of the bake rather than rebuilt here."""
    return bust.sheet_rows()


@lru_cache(maxsize=None)
def painted(key: str, *, cast: bool = True) -> Image.Image:
    """One general's bust, by roster key or `roster.NEUTRAL_ID`.

    `cast=False` is that same bust with the hard offset shadow left off, which
    is how the shadow is measured (`test_metrics.TheShadowIsDrawn`): the
    difference between the two is the shadow and nothing else. It is cached
    beside the shadowed one rather than repainted per assertion.
    """
    spec = roster.NEUTRAL if key == roster.NEUTRAL_ID else roster.FACES[key]
    return bust.paint(spec, cast=cast)
