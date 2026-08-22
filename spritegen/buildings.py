"""Voxel props for terrain tiles: reef rocks — and the five property
buildings (city, base, hq, airport, port), tinted per faction row.

Buildings carry their own isometric base plate, the convention the game's
compositor has always assumed (the lot IS the plate; no square of pavement
behind a diamond footprint). Each building owns one mass identity the
others don't (design review round 3: five near-identical grey lumps):
city two towers, base a long sawtooth shed, hq a wide low fort, airport a
hangar arch with a control tower, port a crane over a warehouse.
"""

from __future__ import annotations

from .palette import Faction, h01
from .voxel import Model

# The property palette, as ramp slots (`palette.PROPERTY_MATERIALS`).
#
# Rounds 4-7 authored these as five unrelated fixed greys picked by where
# their LIT plane landed, because the shaded renderer computed a lit plane out
# of arithmetic. They are four rungs of one masonry ramp now, so the same
# ladder holds by construction: the mass lit at L112, the trim a rung over it
# at L140, and a wall's shadow steps sitting in the AMBIENT sky the armies
# share. What round 7 found still holds and is what the ladder is authored
# against — a wall under the terrain ceiling is not the same thing as a wall a
# unit separates from, so the mass sits ~40L clear of the band every faction's
# top slot occupies (L135-156), and the rung above it is TRIM, which may only
# ever be drawn as a LINE: a parapet, a coping, a seam. Highlights as trim,
# never as fields, is what keeps the buildings from flattening into dark
# blocks now that their mass is dark.
TRIM = "trim"  # lit top L140 — lines only, never a plane
METAL = "machine"  # lit top L150 — machinery: cranes, masts, chimney caps
WALL = "wall"  # lit top L112 — the mass every wall is built of
WALL_DK = "wall_dk"  # its shaded rung: rear walls, sheds, kerbs
DETAIL = "detail"  # doors, seams, cables and openings — masonry's own S0
# The lot the building stands on is concrete, not stone: the same values in a
# cool grey, so a plate and the mass on it separate by HUE and neither has to
# spend the value the units are keyed against.
PAD = "pad"
PAD_RIM = "pad_rim"
MASONRY = WALL
MASONRY_DK = WALL_DK

# A roof is the same rule in the faction's own ramp: the owner's shadow band
# is the roof plane and the body band — the theme token itself — is the ridge,
# the cap and the banner. Both sit two bands under the unit convention, and
# the rim step over them is a unit's alone (`voxel.BUILDING_TOP_SLOT`): a roof
# lit like a chassis is the thing a silhouette has to be read against. On Iron
# that is the row's identity rather than a compromise — near-black panels
# under a light-steel ridge.
ROOF = "roof"
ROOF_TRIM = "roof_trim"

# ---------------------------------------------------------------------------
# nature props
# ---------------------------------------------------------------------------


def rock_outcrop(size: int = 2) -> Model:
    """A low shelf of reef rock breaking the surface."""
    m = Model()
    m.box(0, size, 0, size, 0, 0, "rock_dk")
    m.box(0, size - 1, 0, size - 1, 1, 1, "rock_dk")
    m.set(0, 0, 1, "gunmetal_dk")
    m.set(size - 1, size - 1, 1, "gunmetal_dk")
    return m


# --- the massif -------------------------------------------------------------
#
# The mountain used to be the one object on the sheet drawn in a projection of
# its own: a FRONT ELEVATION, a fitted silhouette painted at slope -1.20/+0.92
# with the light split by an `x <= apex` comparison, no top plane anywhere on
# it and no y axis at all. Everything else — every unit, every building, the
# reef rock beside it — is a voxel mass in the dimetric this engine defines,
# so a range of mountains was a row of cardboard cut-outs standing in a
# three-dimensional board.
#
# It is a height field now, rasterised by `voxel.render_indexed` like anything
# else: three oriented planes off the face normals, one flat ramp slot each,
# lit by the sheet's own sun. What the drawer above it still owns is where the
# summits stand (`terrain.MOUNTAIN_PHASES`) and where the grass stops.
MASSIF_SPAN = 13  # voxels across the footprint, on both ground axes
# Voxels of z per voxel of ground — the flank angle, and the only number that
# decides how a massif reads. The projection turns it into a screen slope of
# SLOPE/sqrt(2) along the summit ridge (the crest is the 45° diagonal in the
# ground plane, so a voxel step along it is sqrt(2) of ground for two pixels
# of screen x), which is what `MountainProjection` measures. Anything under
# ~1.2 leaves a wide low apron the renderer draws as one flat plinth — a
# plateau, not a peak; 1.5 is where the flank stops showing terraces wider
# than the crags on it.
MASSIF_SLOPE = 1.5
# Above this height a column is snow. A cap is the one thing that tells a
# summit from a quarry at the board's 4:1 rung, and it is deliberately small:
# the snow ramp is the brightest material on any tile.
MASSIF_SNOW = 12
# Under this height a column is talus rather than scarp — one ramp band down,
# so the foot the grass apron meets is in the mass's own shadow.
MASSIF_TALUS = 3


def _relief(vx: int, vy: int, seed: int, lattice: int) -> float:
    """A wrapping value field on the voxel grid, in -0.5..0.5.

    The same smooth-hash lattice `terrain._clump_field` puts clumps in a
    field, on the massif's ground plan: it is what gives the cone spurs and
    gullies instead of the concentric contour rings a radial height field
    draws — those rings are the wedding cake the first cut of this model was.
    """
    fx, fy = vx / lattice, vy / lattice
    i, j = int(fx), int(fy)
    tx, ty = fx - i, fy - j
    sx, sy = tx * tx * (3 - 2 * tx), ty * ty * (3 - 2 * ty)
    top = h01(i, j, seed) * (1 - sx) + h01(i + 1, j, seed) * sx
    bot = h01(i, j + 1, seed) * (1 - sx) + h01(i + 1, j + 1, seed) * sx
    return top * (1 - sy) + bot * sy - 0.5


# How far the two relief fields move the surface: the coarse one stretches and
# pinches the plan (a spur reaches out, a gully cuts in), the fine one roughens
# the surface by under a voxel so the flanks break into crags.
_PLAN_RELIEF = 0.55
_CRAG_RELIEF = 2.0


def massif(peaks: tuple[tuple[int, int, int], ...], seed: int) -> Model:
    """The mountain tile's mass: three summits over one height field.

    `peaks` is (voxel x, voxel y, height) per summit, tallest first; `seed`
    keys the relief, so a phase is a different mountain rather than the same
    one slid sideways.
    """
    m = Model()
    for vx in range(MASSIF_SPAN + 1):
        for vy in range(MASSIF_SPAN + 1):
            plan = 1.0 + _PLAN_RELIEF * _relief(vx, vy, seed, 4)
            h, near = 0.0, MASSIF_SPAN * 1.0
            for px, py, pz in peaks:
                d = ((vx - px) ** 2 + (vy - py) ** 2) ** 0.5
                near = min(near, d)
                h = max(h, pz - MASSIF_SLOPE * d * plan)
            # The crags fade out at a summit: a peak roughened as hard as its
            # flanks is a rounded lump, and the summit is the one part of the
            # silhouette the tile is read by.
            h += _CRAG_RELIEF * min(1.0, near / 3.0) * _relief(vx, vy, seed + 31, 2)
            top = int(h)
            if top < 1:
                continue
            snow = MASSIF_SNOW + int(h01(vx, vy, seed + 7) * 3)
            for z in range(top + 1):
                if z >= snow:
                    m.set(vx, vy, z, "snowcap")
                elif top < MASSIF_TALUS:
                    m.set(vx, vy, z, "scree")
                else:
                    m.set(vx, vy, z, "scarp")
    return m


# ---------------------------------------------------------------------------
# property buildings
# ---------------------------------------------------------------------------


def _pad(
    m: Model,
    x0: int,
    x1: int,
    y0: int,
    y1: int,
    mat: str = PAD,
    rim: str = PAD_RIM,
) -> None:
    """The building's own base plate, with a darker rim."""
    m.box(x0, x1, y0, y1, 0, 0, mat)
    for x in range(x0, x1 + 1):
        m.set(x, y0, 0, rim)
        m.set(x, y1, 0, rim)
    for y in range(y0, y1 + 1):
        m.set(x0, y, 0, rim)
        m.set(x1, y, 0, rim)


def _windows(
    m: Model,
    face: str,
    along0: int,
    along1: int,
    wall: int,
    z0: int,
    z1: int,
    salt: int,
) -> None:
    """A window grid on a wall: every other column/row, a few lit amber.

    `along0..along1` runs along the wall and `wall` is the wall's fixed
    coordinate on the other axis — for face 'y' that means x along and y
    fixed, for face 'x' the reverse.
    """
    for along in range(along0, along1 + 1, 2):
        for z in range(z0, z1 + 1, 2):
            mat = "amber" if h01(along, z, salt) < 0.28 else "glass_dk"
            if face == "y":
                m.set(along, wall, z, mat)
            else:
                m.set(wall, along, z, mat)


def city() -> Model:
    """Two grey towers of different heights on a compact plaza — the
    tall-narrow silhouette of the set."""
    m = Model()
    _pad(m, 1, 12, 1, 12)
    # tall slab tower, right: concrete walls, faction roof + penthouse
    m.box(7, 11, 2, 6, 1, 7, WALL)
    m.box(7, 11, 2, 6, 8, 8, ROOF)
    m.box(8, 10, 3, 5, 9, 9, ROOF_TRIM)  # penthouse, the tower's lit cap
    m.chamfer(8, 10, 3, 5, 9, 9)
    _windows(m, "y", 8, 10, 6, 2, 7, 23)
    _windows(m, "x", 3, 5, 11, 2, 7, 24)
    # shorter tower, left: faction roof over grey walls, coped along the front
    m.box(2, 6, 7, 11, 1, 4, WALL)
    m.box(2, 6, 7, 11, 5, 5, ROOF)
    m.box(2, 6, 11, 11, 5, 5, ROOF_TRIM)  # parapet coping
    m.chamfer(2, 6, 7, 11, 5, 5)
    _windows(m, "y", 3, 5, 11, 2, 4, 21)
    _windows(m, "x", 8, 10, 6, 2, 4, 22)
    # plaza planter at the front corner
    m.set(11, 11, 1, "leaf")
    m.set(12, 11, 1, "leaf_dk")
    return m


def base() -> Model:
    """A factory: a long grey shed under a faction sawtooth roof, chimney,
    crates. The lot is a shallow full-width strip, so the silhouette reads
    long and low — never the square diamond the hq owns."""
    m = Model()
    _pad(m, 0, 13, 5, 13)
    # main shed in industrial concrete, running the full width
    m.box(1, 12, 5, 12, 1, 3, WALL_DK)
    # sawtooth roof: three north-lit ridges in the owner's color
    for k in range(3):
        y0 = 12 - k * 3
        m.box(1, 12, y0 - 1, y0, 4, 4, ROOF)
        m.box(1, 12, y0, y0, 5, 5, ROOF_TRIM)  # lit ridge
        m.box(1, 12, y0 - 1, y0 - 1, 5, 5, DETAIL)  # skylight band
    # big vehicle door on the front face with hazard stripe. The stripe is
    # DASHED: amber is the brightest thing a property owns, and a solid band
    # of it across the widest door on the sheet is a field rather than a
    # marker — 2.3% of the base's pixels over the terrain ceiling on its own,
    # where the whole building's budget for glazing is 2%.
    m.box(3, 8, 12, 12, 1, 3, DETAIL)
    for x in range(3, 9, 2):
        m.set(x, 12, 3, "amber")
    m.box(5, 6, 12, 12, 1, 1, DETAIL)  # door gap
    # chimney at the rear corner
    m.box(12, 13, 5, 6, 1, 6, WALL_DK)
    m.box(12, 13, 5, 6, 6, 6, METAL)
    m.set(12, 5, 7, DETAIL)
    m.set(13, 6, 7, DETAIL)
    # crates on the front apron
    m.box(0, 1, 12, 13, 1, 2, "wood")
    return m


def hq() -> Model:
    """A stone fortress; faction color on the tower caps, keep roof, banner."""
    m = Model()
    _pad(m, 0, 13, 0, 13)
    # curtain walls in castle stone
    m.box(1, 12, 1, 12, 1, 4, MASONRY)
    m.clear(3, 10, 3, 10, 1, 4)  # hollow courtyard (hidden anyway)
    # crenellations along the front and right parapets — spaced merlons, the
    # dotted trim line that keeps the curtain wall from reading as a slab
    for i in range(1, 13, 2):
        m.set(i, 12, 5, TRIM)
        m.set(12, i, 5, TRIM)
        m.set(i, 1, 5, TRIM)
        m.set(1, i, 5, TRIM)
    # corner towers, capped in the owner's color at parapet height — the
    # rear corner sets the sprite's top line, so the height budget goes to
    # the central keep instead
    for tx, ty in ((1, 1), (1, 11), (11, 1), (11, 11)):
        m.box(tx, tx + 1, ty, ty + 1, 1, 4, MASONRY)
        m.box(tx, tx + 1, ty, ty + 1, 5, 5, ROOF_TRIM)
    # gatehouse: arched gate with a wooden door on the front wall
    m.box(5, 8, 12, 12, 1, 4, MASONRY_DK)
    m.box(6, 7, 12, 12, 1, 3, "wood")
    m.set(6, 12, 4, DETAIL)
    m.set(7, 12, 4, DETAIL)
    # central stone keep under a faction roof, banner mast above
    m.box(4, 9, 4, 9, 1, 6, MASONRY)
    m.box(4, 9, 4, 9, 7, 7, ROOF)
    m.box(5, 8, 5, 8, 8, 8, ROOF_TRIM)
    m.chamfer(5, 8, 5, 8, 8, 8)
    _windows(m, "y", 5, 8, 9, 3, 6, 31)
    m.box(6, 6, 6, 6, 9, 10, METAL)
    m.box(7, 8, 6, 6, 9, 10, ROOF_TRIM)  # banner
    return m


def airport() -> Model:
    """A hangar with an arched roof and a glass-cab control tower."""
    m = Model()
    # apron plate
    _pad(m, 0, 13, 3, 13)
    # hangar: concrete walls under a faction barrel roof, doors facing the
    # runway (front)
    m.box(1, 8, 6, 13, 1, 4, WALL)
    m.box(1, 8, 7, 12, 5, 5, ROOF)  # arch tier 1
    m.box(2, 7, 8, 11, 6, 6, ROOF)  # arch crown
    m.box(2, 7, 9, 10, 6, 6, ROOF_TRIM)  # lit ridge along the barrel
    m.chamfer(2, 7, 8, 11, 6, 6)
    m.box(2, 7, 13, 13, 1, 3, DETAIL)  # hangar door
    m.box(4, 5, 13, 13, 1, 3, METAL)  # door seam
    m.box(1, 8, 6, 6, 1, 4, WALL_DK)  # rear wall
    # control tower with glass cab and radar
    m.box(10, 12, 4, 6, 1, 4, WALL)
    m.box(9, 13, 3, 7, 5, 5, WALL_DK)  # balcony ring
    m.box(10, 12, 4, 6, 6, 6, "glass_dk")
    m.box(10, 12, 4, 6, 7, 7, ROOF_TRIM)  # cap
    m.set(11, 5, 8, DETAIL)  # radar knob
    # windsock on the apron corner
    m.box(13, 13, 11, 11, 1, 4, METAL)
    m.set(13, 12, 4, "amber")
    return m


def port() -> Model:
    """A quay over the water: warehouse, gantry crane, stacked containers."""
    m = Model()
    # quay deck standing on pilings
    m.box(0, 13, 4, 13, 1, 1, PAD)
    for x in range(0, 14, 3):
        m.set(x, 4, 0, PAD_RIM)  # pilings at the water edge
    for x in range(14):
        m.set(x, 4, 1, PAD_RIM)  # quay edge trim
    # warehouse: concrete walls under a shallow faction gabled roof
    m.box(1, 6, 7, 13, 2, 5, WALL)
    m.box(1, 6, 8, 12, 6, 6, ROOF)
    m.box(1, 6, 10, 10, 7, 7, ROOF_TRIM)  # ridge
    m.box(3, 4, 13, 13, 2, 4, DETAIL)  # cargo door
    # gantry crane over the dockside
    m.box(9, 10, 11, 12, 2, 7, METAL)
    m.box(9, 10, 4, 12, 8, 8, METAL)  # jib reaching the water
    m.set(9, 5, 7, DETAIL)  # cable
    m.set(9, 5, 6, DETAIL)
    m.box(9, 10, 11, 12, 8, 9, DETAIL)  # cab + counterweight
    # container stack on the quay
    m.box(11, 13, 6, 8, 2, 2, ROOF)
    m.box(11, 13, 6, 7, 3, 3, ROOF_TRIM)
    m.set(11, 6, 3, "amber")  # one lit marker, not a lit roof
    # bollards
    m.set(1, 5, 2, DETAIL)
    m.set(6, 5, 2, DETAIL)
    m.set(12, 5, 2, DETAIL)
    return m


BUILDINGS = {
    "city": city,
    "base": base,
    "hq": hq,
    "airport": airport,
    "port": port,
}

# The neutral row strips hue: an unowned property must not read as lit or
# owned, so every hue-carrying material resolves to a grey (design review
# 2026-08-13). The greys are the ladder above rather than the pale
# `rock`/`stone_dk` pair, for the reason the ladder itself moved: `rock` lit a
# top plane at L200 and `stone_dk` at L176, which put the row nobody owns the
# furthest into the units' band. Every entry is a rung, so an unowned property
# is keyed exactly like an owned one — the roof plane lands a rung above the
# wall and its ridge on TRIM, which is the same three-step read with the hue
# taken out. Owned rows keep their accents untouched, so the lit-window glint
# is an owned property's alone. `bore` stays — the palette has no dark true
# grey and its few pixels read black. The machinery greys need no entry now
# that the ladder itself is built of them.
_NEUTRAL_GREYS = {
    "amber": TRIM,  # lit windows, hazard stripe, windsock, container marker
    "glass_dk": METAL,  # window and cab glazing
    "wood": WALL_DK,  # doors, crates
    "leaf": METAL,  # plaza planter
    "leaf_dk": WALL,
    ROOF: WALL_DK,  # roof planes: a dark plane, as an owned roof is
    ROOF_TRIM: TRIM,  # and their ridges, caps and banner, as a bright line
}


def model_for(bid: str, fac: Faction) -> Model:
    """The property building's model for one faction row."""
    m = BUILDINGS[bid]()
    # Buildings are drawn out of the indexed ramps, one band under the units
    # (`voxel.BUILDING_TOP_SLOT`) — the properties pass, 2026-08-22.
    m.indexed = True
    if fac.key == "neutral":
        for pos, mat in m.vox.items():
            m.vox[pos] = _NEUTRAL_GREYS.get(mat, mat)
    return m
