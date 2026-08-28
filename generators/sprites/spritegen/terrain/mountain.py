"""The massif: a three-summit voxel mass standing on the grass plate."""

from __future__ import annotations

from PIL import Image

from .. import buildings
from ..palette import FACTIONS, RGB
from ..voxel import SHADOW_OFFSET, place_in_cell, render_indexed
from .plains import _grass_ground
from .properties import SHADOW
from .tones import CELL, GRASS_DARK, _rect, _shade, _tone, luminance

# Phase variants for the mountain — the sea's rule (SEA_PHASES below) applied
# to the board's most silhouette-dominant tile, because a range is a wall of
# identical peaks wherever one is repeated. An entry is (summits, relief seed):
# where the massif's three summits stand in the model's own VOXEL grid, as
# (x, y, height) with the tallest first, and the seed the spurs and gullies of
# the height field are keyed off (`buildings.massif`). A phase is a different
# mountain rather than the same one slid sideways, and nothing else varies —
# the mass stands on one row in every phase, so a range sits on one horizon,
# and the rock and snow are the same two ramps throughout. Phase 0 is the
# atlas column, so a board that has not adopted the sheet is unchanged.
MOUNTAIN_PHASES: tuple[tuple[tuple[tuple[int, int, int], ...], int], ...] = (
    (((6, 7, 15), (11, 4, 11), (2, 10, 10)), 21),
    (((5, 8, 15), (11, 5, 11), (3, 3, 9)), 11),
    (((4, 6, 15), (9, 10, 11), (11, 3, 10)), 17),
)

# Where the massif's front corner stands. Fixed across the phases: a ridge of
# mountains that stood on three different rows would read as peaks at three
# altitudes rather than as a range.
MOUNTAIN_GROUND = 57


# The massif's four rock faces, in the order the old painter used them: two
# sunlit, two shaded. They are one warm grey under two lights — the lit faces
# carry the sun's own warmth (S0.14, where they used to be the S0.07 of cut
# card), the shaded ones are `_shade`s of the lit face and so take the sky
# (see `_SHADE_GREY`). The massif is a voxel mass drawn off `palette.ROCK_RAMP`
# now, and the ramp is authored ON this ladder — its four upper rungs sit at
# these four values — so this is what the tile's rock is still keyed to, and
# `docs/terrain_tones.md` records it.
ROCK: tuple[RGB, RGB, RGB, RGB] = (
    _tone((166, 161, 153), 0.14),
    _tone((148, 144, 137), 0.14),
    _shade(_tone((148, 144, 137), 0.14), luminance((117, 113, 108))),
    _shade(_tone((148, 144, 137), 0.14), luminance((98, 95, 91))),
)


def _contact_shadow(tile: Image.Image, sprite: Image.Image, x0: int, y0: int) -> None:
    """The shadow a prop standing on grass drops: its own silhouette, moved
    down-right by `voxel.SHADOW_OFFSET` — the sheet's one sun — in the sheet's
    one cast-shadow tone, `SHADOW`.

    It used to be stamped in GRASS_DARK, which is the grass's own shaded rim
    and the tone the tufts and the shed boulders are drawn in: the massif was
    then the one raised thing on the board whose darkest pixel was its (30,
    32, 36) outline, standing beside a unit and a city that both drop the
    (16, 18, 24) SHADOW at the same offset. A raised mass reads as raised by
    the hole its shadow puts in the ground, so the massif drops the same one.
    The grass keeps GRASS_DARK for what the grass does — the woods' fringe
    line stays a line of dark grass, because a wood is not one massing.

    Only where the prop is not already standing, and only where the pixel that
    CAST it is inside the cell: a shadow whose caster was clipped off the tile
    is shade with nothing above it (`OneSun`).
    """
    sp = sprite.load()
    px = tile.load()
    dx, dy = SHADOW_OFFSET
    for yy in range(sprite.height):
        for xx in range(sprite.width):
            if sp[xx, yy][3] == 0:
                continue
            sx, sy = x0 + xx, y0 + yy
            tx, ty = sx + dx, sy + dy
            if not (0 <= tx < CELL and 0 <= ty < CELL):
                continue
            if 0 <= tx - x0 < sprite.width and 0 <= ty - y0 < sprite.height:
                if sp[tx - x0, ty - y0][3] != 0:
                    continue  # the prop stands on its own shadow
            px[tx, ty] = (*SHADOW, 255)


def mountain(phase: int = 0) -> Image.Image:
    """A three-summit massif in the sheet's own projection: a voxel height
    field rasterised into top, up-left and down-right planes off one rock
    ramp, snow on the summits, talus at the foot.

    The tile it replaces was a front elevation — a fitted silhouette with a
    flat light/dark split and no top plane on it anywhere. See
    `buildings.massif`.
    """
    peaks, seed = MOUNTAIN_PHASES[phase]
    # The massif stands on the same clumped grass plate plains and woods are
    # drawn on: a flat-green apron around a mountain reads as a lighter cell
    # against the field it borders, which is the seam the woods plate was
    # fixed for.
    t = _grass_ground(4)
    rock = render_indexed(buildings.massif(peaks, seed), FACTIONS[0]).image
    x0 = (CELL - rock.width) // 2
    y0 = MOUNTAIN_GROUND - rock.height
    _contact_shadow(t, rock, x0, y0)
    place_in_cell(t, rock, x0, y0)
    # boulders shed onto the apron, in the field's own dark grass
    for sx, sy in ((5, 50), (56, 52), (12, 60), (44, 61)):
        _rect(t, sx, sy, 3, 2, GRASS_DARK)
    return t
