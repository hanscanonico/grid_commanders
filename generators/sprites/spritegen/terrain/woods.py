"""The wood: crowns drawn back to front over the grass plate."""

from __future__ import annotations

from PIL import Image

from ..palette import RGB, darken, h01
from ..voxel import SHADOW_OFFSET
from .plains import _grass_ground
from .tones import (
    CANOPY,
    CANOPY_DK,
    CANOPY_LT,
    CANOPY_MID,
    CANOPY_TOP,
    CELL,
    E,
    GRASS_DARK,
    N,
    S,
    TRUNK,
    W,
    WOODS_SALT,
    _rect,
)

# The wood, in the projection everything else on the sheet is drawn in.
#
# A crown was an orthographic CIRCLE — a disc of leaf tone with a rim, the one
# shape this dimetric cannot produce. A canopy is a ground-parallel thing seen
# from the sheet's camera, and the camera turns a ground-parallel disc into a
# 2:1 ellipse: twice as wide as it is deep, which is the same 2:1 a voxel's top
# face is drawn at and the same 2:1 the massif's foot lies on. So a crown is
# that ellipse — the canopy's TOP PLANE — with the leaf mass hanging under it,
# and the bands on it are planes rather than a painted gradient: the top plane
# lit, its rim lit or shaded by which way it faces the sun, the mass under it
# rolling off from the shoulder to the shaded side.
#
# The old crown was also the noisiest object on the sheet: a per-pixel hash on
# the body tone and a 14% leaf speckle put 53.7% of the tile on a colour change
# against its right-hand neighbour (the mountain, the tile with the most
# geometry, ran 21%) and spent 77 colours doing it. The hash stays, but only
# where a hash belongs — in the DECISION, ragging the boundary between two
# bands so an arc does not read as a painted stripe. It no longer makes tones.
#
# Banding a crown that way also drew every crown as the same stamp: one shallow
# skirt, laid in six courses on a 12.8px pitch, its lit rim ringing each ellipse
# — and the 2026-08-23 review read the tile as roof shingles, a tray of green
# pills rather than as cover. The plane and its bands are kept; what changed is
# everything a wood is supposed to VARY by.
#
#   size    `_crown_depth` hangs the mass a crown's own width deep and tapers
#           it, so a crown is a ball of leaves at one of five sizes rather
#           than one lid on one skirt.
#   place   the table is scattered (no two crowns share a row) and every
#           centre is moved again by `_crown_jitter`.
#   order   `_crown_order` shuffles the painter's sort, so a crown is not
#           always laid over the one behind it in the same direction.
#   edge    the crown outline is hash-ragged, and the rim is split on the
#           sun's own axis and ragged across it, so it reads as a highlight
#           and not as an outline drawn round every ellipse.
#   surface `_dapple` speckles inside a band, one step along the same ramp.
#   fringe  a pulled crown stops SHORT of its border by a hash (`_crowns_
#           within`), so a wood's outer boundary is bays and points rather
#           than a rectangle, and the trunks belong to crowns rather than to
#           fixed tile coordinates.
#
# Measured on the row profile: the strongest period between 8 and 16px — the
# band a course of crowns lands in — was 12.05L on the shingled tile's worst
# variant and is 6.2L on this one's, 3.3L on the atlas tile, against 0.7L for
# the bare plate underneath (`CanopyGrain`).


def _crown_depth(r: int) -> int:
    """How far a crown's leaf mass hangs under its top plane. It scales with
    the crown, because a canopy of one depth reads as one stamp repeated
    however wide the plane over it is drawn."""
    return r + 1


# (crown x, crown y, radius): the centre of the top plane and its half-WIDTH.
# Twenty-four crowns in five half-widths, scattered rather than coursed —
# twenty-one distinct rows between them and uneven gaps, which is what keeps
# a horizontal row profile from carrying one period. The gaps that survive the
# overlap are the wood's clearings: they are the plains plate `WoodsSeam`
# reads the tile against, and the trunks stand at their heads. Every centre is
# moved again by `_crown_jitter`.
_CROWNS = (
    (36, 0, 9),
    (24, 5, 11),
    (60, 5, 8),
    (41, 7, 10),
    (12, 10, 7),
    (25, 12, 9),
    (51, 13, 11),
    (14, 19, 8),
    (33, 19, 10),
    (42, 25, 9),
    (61, 25, 7),
    (15, 27, 11),
    (56, 32, 9),
    (43, 34, 11),
    (31, 37, 8),
    (13, 39, 10),
    (46, 42, 7),
    (3, 45, 9),
    (31, 48, 11),
    (44, 51, 8),
    (22, 53, 10),
    (62, 55, 9),
    (55, 61, 7),
    (5, 63, 11),
)


def _crown_reach(r: int) -> tuple[int, int]:
    """How far a crown of half-width `r` reaches above and below its centre:
    half the width up (the ellipse) and that plus the mass hanging under it."""
    return r // 2, r // 2 + _crown_depth(r)


def _crown_jitter(cx: int, cy: int) -> tuple[int, int]:
    """Two hash draws that take a crown off the lattice it was authored on.
    The table is hand-placed, so it is regular however carefully it is typed;
    this is the fixed hash spending its one job on a POSITION rather than on
    a tone, and it is what stops the courses from lining up into stripes."""
    return int(h01(cx, cy, 51) * 5) - 2, int(h01(cx, cy, 53) * 7) - 3


def _crowns_within(open_edges: int) -> tuple[tuple[int, int, int, tuple], ...]:
    """Where each crown stands in this variant, as (x, y, r, copies).

    A crown is jittered off the authored table, then PULLED fully inside the
    cell on every edge the wood does not continue across, so it is never
    sliced flat by the tile border. A pulled crown stops a hash-keyed 0-6px
    SHORT of tangent, so the tree line rags instead of laying every crown
    against one straight edge — a wood's outer boundary is the only place the
    block silhouette is visible at all, and tangent crowns drew it as a
    rectangle. The pull is by the crown's REACH, which is not its width: the
    ellipse is half as deep as it is wide and the mass hangs below it.

    `copies` is where the same crown has to be drawn AGAIN, a whole cell
    away, for this tile to butt against the wood beside it: the tile over a
    continued border is drawing this crown a cell along, so the half of it
    that overhangs the seam is this tile's to finish. Clipped instead of
    copied — which is what the first projection pass did — the two halves are
    different crowns and a wood's interior comes out on a visible tile grid.
    A copy takes the neighbour's own coordinate on the axis it crosses, which
    is the UNPULLED one: the neighbour has wood on that side, so it did not
    pull there."""
    placed = []
    for cx, cy, r in _CROWNS:
        jx, jy = _crown_jitter(cx, cy)
        jx, jy = cx + jx, cy + jy
        up, down = _crown_reach(r)
        rag = int(h01(jx, jy, 57) * 7)
        cx, cy = jx, jy
        if open_edges & W:
            cx = max(cx, r + rag)
        if open_edges & E:
            cx = min(cx, CELL - 1 - r - rag)
        if open_edges & N:
            cy = max(cy, up + rag)
        if open_edges & S:
            cy = min(cy, CELL - 1 - down - rag)
        xs = [(cx, cy)]
        if not open_edges & W:
            xs.append((jx - CELL, cy))
        if not open_edges & E:
            xs.append((jx + CELL, cy))
        places = list(xs)
        for x, _ in xs:
            if not open_edges & N:
                places.append((x, jy - CELL))
            if not open_edges & S:
                places.append((x, jy + CELL))
        copies = tuple(
            (x, y)
            for x, y in places[1:]
            if x + r >= 0 and x - r < CELL and y + down >= 0 and y - up < CELL
        )
        placed.append((cx, cy, r, copies))
    return tuple(placed)


def _crown_order(crowns: tuple) -> list:
    """Back to front, hash-shuffled. A strict sort by depth laid every crown
    over the one behind it in the same direction, which is the brick course
    the shingle reading came from; a crown that is sometimes BEHIND its
    neighbour instead makes the overlap irregular."""
    return sorted(crowns, key=lambda c: c[1] + (h01(c[0], c[1], 59) - 0.5) * 13)


def _crown_light(x: int, y: int, dx: float, dy: float, r: int) -> float:
    """How lit a point on a crown's top plane is, on the up-left axis the whole
    sheet is lit from, in -1..1. `dy` is doubled because the plane is a 2:1
    ellipse: a pixel of screen y is two of ground. The hash term breaks the
    band boundary into leaves — a clean arc reads as a painted stripe."""
    return -(dx + dy * 2.0) / (r * 2.0) + (h01(x, y, 35) - 0.5) * 0.22


def _dapple(x: int, y: int, c: RGB) -> RGB:
    """Leaf speckle inside a band: a hash-keyed step to the neighbouring tone
    of the SAME canopy ramp, so the plane keeps its value and its colour count
    and only its surface breaks up. Keyed on a 2x2 cell rather than per pixel
    — a per-pixel speckle is finer than the board's 4:1 downsample, arrives as
    a different random pixel per frame of camera movement, and is what put
    this tile at 53.7% colour change before the projection pass
    (`TileTexture`). Two draws in ten, so the leaves read at 1:1 without the
    tile spending its texture budget on them."""
    if c is CANOPY_TOP and h01(x >> 1, y >> 1, 34) < 0.11:
        return CANOPY_LT
    if c is CANOPY_MID and h01(x >> 1, y >> 1, 36) < 0.08:
        return CANOPY
    return c


def woods(open_edges: int = 0) -> Image.Image:
    """A filled canopy: crowns drawn back to front, each a 2:1 top plane over
    the leaf mass it hangs on, over grass that shows only in the clearings and
    at the fringe. The value drop against plains is the tile's read — cover,
    not decoration — and trunks under the fringe say the cover is trees.

    `open_edges` names the borders the wood ends at (see `_crowns_within`);
    0 — every edge continued — is the atlas tile."""
    t = _grass_ground(WOODS_SALT)
    px = t.load()
    crowns = _crowns_within(open_edges)
    covered = [[False] * CELL for _ in range(CELL)]
    for cx0, cy0, r, copies in _crown_order(crowns):
        up, down = _crown_reach(r)
        depth = down - up
        for cx, cy in ((cx0, cy0), *copies):
            for yy in range(max(0, cy - up), min(CELL, cy + down + 1)):
                for xx in range(max(0, cx - r), min(CELL, cx + r + 1)):
                    dx, dy = xx - cx, yy - cy
                    # The crown's outline is RAGGED: a hash of the pixel,
                    # coarse enough to survive the board's downsample, pushes
                    # the boundary in and out by a pixel or two, so foliage
                    # ends in leaves rather than in a drawn ellipse. It is the
                    # same hash-in-the-decision rule the bands are ragged by.
                    rag = (h01(xx >> 1, yy >> 1, 39) - 0.5) * 1.6
                    rr = r + rag
                    # Half-depth of the top plane here: the 2:1 ellipse.
                    span = 1.0 - (dx / rr) ** 2 if abs(dx) < rr else -1.0
                    if span <= 0.0:
                        continue
                    hh = up * span**0.5
                    if dy < -hh:
                        continue
                    if dy > hh:  # the leaf mass under the plane
                        # It TAPERS: the underside is the bottom half of the
                        # crown, not a cylinder wall, so a tree is a rounded
                        # mass with a lit plane on top of it rather than a
                        # green tin can. Over another crown only its first
                        # rows show, so neighbours merge into one canopy
                        # instead of stacking as separate stamps.
                        if dy > (depth + rag) * span**0.5:
                            continue
                        if covered[yy][xx] and dy > hh + 1:
                            continue
                        # The mass rolls off on the same axis, so a crown is
                        # a ball of leaves and not a lit lid on a dark bucket.
                        # It rolls in the two tones BELOW the plane's — the
                        # plane's three stay the plane's, which is what keeps
                        # `CanopyLight`'s 2:1 reading a reading of the plane.
                        lit = dx / r + (dy - hh) / max(1.0, depth - hh) * 1.3
                        c = CANOPY if lit < 0.55 else CANOPY_DK
                    elif abs(dy) > hh - 1.0 or abs(dx) > r - 1.4:
                        # The plane's rim, split on the sheet's own up-left
                        # axis rather than on the horizon: lit where it faces
                        # the sun, shaded where it turns away, and hash-ragged
                        # at the changeover so it reads as a highlight instead
                        # of as an outline drawn round every crown.
                        rim = dx + dy * 2.0 + (h01(xx >> 1, yy, 37) - 0.5) * r * 0.7
                        c = CANOPY_LT if rim < 0.0 else CANOPY_DK
                    elif _crown_light(xx, yy, dx, dy, r) > 0.04:
                        c = _dapple(xx, yy, CANOPY_TOP)  # the plane itself
                    else:
                        c = _dapple(xx, yy, CANOPY_MID)  # rolling off, shaded
                    px[xx, yy] = (*c, 255)
                    covered[yy][xx] = True
    # Contact shadow: the canopy's own shaded rim dropped by SHADOW_OFFSET, on
    # the one rule every caster on the sheet obeys. It used to be a 1px line
    # straight under the fringe, which put the wood's shade on a different sun
    # from the building beside it and from every unit standing on it. It stays
    # a LINE rather than the building's solid silhouette because the clearings
    # between the crowns are the plains plate the tile is measured on
    # (`WoodsSeam`), and a wood is not one massing casting one shadow.
    sx, sy = SHADOW_OFFSET
    for y in range(CELL):
        for x in range(CELL):
            if not covered[y][x] or (
                covered[min(y + 1, CELL - 1)][x] and covered[y][min(x + 1, CELL - 1)]
            ):
                continue  # only the fringe turned away from the light casts
            tx, ty = x + sx, y + sy
            if 0 <= tx < CELL and 0 <= ty < CELL and not covered[ty][tx]:
                px[tx, ty] = (*GRASS_DARK, 255)
    # A trunk belongs to a CROWN, not to the tile: it stands under the crown
    # it holds up, on the crowns the hash picks, wherever that crown's skirt
    # ends over open ground. So the trunks move when the crowns do — the old
    # pair was two fixed pixels that every one of the sixteen variants
    # repeated at the same offset, which is a tile stamp, not a wood.
    for cx, cy, r, _ in crowns:
        if h01(cx, cy, 41) >= 0.60:
            continue
        tx = cx + int(h01(cx, cy, 43) * 5) - 2
        foot = cy + _crown_reach(r)[1]
        for ty in range(foot, foot + 6):
            if not (0 <= tx and tx + 1 < CELL and 0 <= ty and ty + 2 < CELL):
                continue
            if any(covered[ty + dy][tx + dx] for dy in range(3) for dx in range(2)):
                continue
            _rect(t, tx, ty, 2, 3, TRUNK)
            _rect(t, tx, ty, 1, 3, darken(TRUNK, 0.25))
            break
    return t
