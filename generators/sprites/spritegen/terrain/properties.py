"""The five property cells: a faction-tinted building and its shadow, on
transparent ground."""

from __future__ import annotations

from PIL import Image

from .. import buildings
from ..palette import AMBIENT, Faction
from ..voxel import SHADOW_OFFSET, place_in_cell, render
from .tones import CELL, _tone

# ---------------------------------------------------------------------------
# property tiles
# ---------------------------------------------------------------------------


# Where each building stands in its cell: (centre x, ground line). One
# statement, read by the atlas tiles and by the iso_buildings cells, so the
# two can never place the same building differently.
#
# One ground line for all five. The line is where the bottom edge of the
# building sprite lands in the cell, not where its base plate happens to end:
# every model is drawn tight, bottom-flush, so pinning the frames to a shared
# `bottom` puts every property's lowest painted row on the same row of the
# board. The airport used to sit at 46 and the port at 52, which floated them
# up to 15px above the row city, base and hq stand on — buildings hovering
# over the same tile grid. Centre x is 32, the cell's own centre, for all of
# them; the airport's old 31 pushed it a pixel off-centre.
PROPERTY_ANCHOR: dict[str, tuple[int, int]] = {
    "city": (32, 61),
    "base": (32, 61),
    "hq": (32, 61),
    "airport": (32, 61),
    "port": (32, 61),
}

# The shadow a building drops on whatever ground it is standing on: the
# building's own silhouette, shifted down-right away from the light every
# model is lit from, in the same tone AND by the same offset the unit cells
# cast (`voxel.SHADOW_OFFSET`, re-exported here — one sun for the sheet).
#
# The tone is the sky, keyed down: a cast shadow is the one surface on the
# sheet lit by AMBIENT and nothing else, so it is stated as AMBIENT's hue at a
# third of its chroma at L18 rather than as a near-black literal — a black
# shadow reads as a hole punched in the board rather than as shade on it, and
# a typed triple gives no way to tell which of the two it is.
#
# It evaluates to (16, 18, 24), the exact literal it replaces: the shadow was
# already the sky at S0.33, which nothing said out loud. So `voxel.SHADOW`,
# the unit cells' copy of the same triple, still agrees with it byte for byte
# — one sun and one sky for the sheet. If this derivation is ever retuned,
# that constant has to move with it.
SHADOW = _tone(AMBIENT, 0.34, 18.0)


def _drop_shadow(cell: Image.Image, sprite: Image.Image, x0: int, y0: int) -> None:
    """Stamp `sprite`'s silhouette into `cell` as a hard SOLID shadow.

    Opaque pixels, never partial alpha: the sheet is read at 16px on the board
    and blown up in the cut-in, and a soft alpha edge is a halo at one end and
    a grey stain at the other.

    It used to be a 1px checkerboard, so that half the pixels missing let the
    ground the board paints underneath read through. That argument only ever
    held at one sampling ratio: the board draws this 64px cell onto a 16px
    grid with nearest filtering at whole zoom rungs 1..5, keeping one source
    pixel in 4/z, and a 1px parity is a different picture at every one of them
    — solid zoomed out, thin at the default rung, and loose dots at rung 4
    where the art is 1:1, which is the stippled fringe a city wore. The units'
    cast shadow went solid for the same measurement (`voxel._shadow_ellipse`);
    this is the same contract, on the drawer that had been left behind.
    """
    px = cell.load()
    sp = sprite.load()
    dx, dy = SHADOW_OFFSET
    for yy in range(sprite.height):
        for xx in range(sprite.width):
            if sp[xx, yy][3] == 0:
                continue
            tx, ty = x0 + xx + dx, y0 + yy + dy
            if not (0 <= tx < CELL and 0 <= ty < CELL):
                continue
            px[tx, ty] = (*SHADOW, 255)


def property_overlay(bid: str, fac: Faction) -> Image.Image:
    """A property cell: the building and its shadow, on transparent ground.

    Design review rounds 4 and 5: baking the plains green into these five
    columns painted a green square around every city standing on road, beach
    or asphalt. The building keeps its own base plate — the plate is part of
    the model, the isometric footprint it stands on — and everything around
    it is left empty, so the board draws the ground and the building reads as
    an object sitting on it rather than as a tile of its own.
    """
    t = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
    prop = render(buildings.model_for(bid, fac), fac)
    cx, bottom = PROPERTY_ANCHOR[bid]
    x0, y0 = cx - prop.width // 2, bottom - prop.height
    _drop_shadow(t, prop, x0, y0)
    place_in_cell(t, prop, x0, y0)
    return t
