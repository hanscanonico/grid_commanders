"""The busts the measuring suites read, painted once per run.

Four suites measure the same twenty-three rasters — the gauge sweep, the fringe
rule, the contrast floor and the style brief's metrics — and painting one is
what a run of this package costs, so the cache is here rather than four times
over. `bust.paint` is the call `pipeline.py` bakes the committed PNGs with, so a
bar measured off one of these is a bar over the shipped art.

`figure` is the same bust read as a mask, which is the other shape the
measuring suites want and is derived from the cached raster rather than a
second paint.

The image handed back is shared: a caller that has to change one copies it
first.
"""

from __future__ import annotations

from functools import lru_cache

from PIL import Image, ImageChops

from portraitgen import bust, roster


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


@lru_cache(maxsize=None)
def figure(key: str) -> Image.Image:
    """Where the bust differs from its own window: its silhouette.

    The general without the backdrop behind them. The backdrops are flat grey
    fields over slate, so a dark enough hair ramp reads its own shadow band in
    the wall otherwise.
    """
    spec = roster.NEUTRAL if key == roster.NEUTRAL_ID else roster.FACES[key]
    difference = ImageChops.difference(painted(key, cast=False), bust.window(spec))
    return difference.convert("L").point(lambda level: 255 if level else 0)
