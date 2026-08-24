"""Voxel props for terrain tiles: reef rocks — and the five property
buildings (city, base, hq, airport, port), tinted per faction row.

Buildings carry their own isometric base plate, the convention the game's
compositor has always assumed (the lot IS the plate; no square of pavement
behind a diamond footprint). Each building owns one mass identity the
others don't (design review round 3: five near-identical grey lumps):
city two narrow towers a plaza apart, base a long sawtooth shed, hq a keep
standing a whole board texel over the rest of the sheet, airport a hangar
arch with a control tower, port a crane over a warehouse.
"""

from __future__ import annotations

from .palette import Faction, h01
from .voxel import Model

# The property palette, as ramp slots (`palette.PROPERTY_MATERIALS`).
#
# Rounds 4-7 authored these as five unrelated fixed greys picked by where
# their LIT plane landed, because the shaded renderer computed a lit plane out
# of arithmetic. They are four rungs of one masonry ramp now, so the same
# ladder holds by construction: the mass lit at L116, the trim a rung over it
# at L142, and a wall's shadow steps sitting in the AMBIENT sky the armies
# share. What round 7 found still holds and is what the ladder is authored
# against — a wall under the terrain ceiling is not the same thing as a wall a
# unit separates from, so the mass sits ~40L clear of the band every faction's
# top slot occupies (L135-156), and the rung above it is TRIM, which may only
# ever be drawn as a LINE: a parapet, a coping, a seam. Highlights as trim,
# never as fields, is what keeps the buildings from flattening into dark
# blocks now that their mass is dark.
TRIM = "trim"  # lit top L142 — lines only, never a plane
METAL = "machine"  # lit top L150 — machinery: cranes, masts, chimney caps
WALL = "wall"  # lit top L116 — the mass every wall is built of
WALL_DK = "wall_dk"  # its shaded rung: rear walls, sheds, kerbs
DETAIL = "detail"  # doors, seams, cables and openings — masonry's own S0
# The lot the building stands on is concrete, not stone: the same values in a
# cool SLATE against masonry's warm sandstone, so a plate and the mass on it
# separate by HUE and neither has to spend the value the units are keyed
# against. The gap between the two families is what the unowned row is drawn
# with (`_NEUTRAL_GREYS`), so it is authored wide.
PAD = "pad"  # the slab
PAD_RIM = "pad_rim"  # its kerb
# The two rungs the lot itself has no use for: concrete's own contour step and
# the trim line over its slab. They exist because the unowned row is built out
# of this family end to end (`_NEUTRAL_GREYS`) and needs the same four rungs
# masonry gives an owned one.
PAD_SEAM = "pad_seam"
PAD_TRIM = "pad_trim"
MASONRY = WALL
MASONRY_DK = WALL_DK

# A roof is the same rule in the faction's own ramp: the owner's shadow band
# is the roof plane and the body band — the theme token itself — is the ridge,
# the cap and the banner — and the paint: a fascia under the eaves, a kerb, a
# guide line on an apron, the band round a chimney. A roof deck is four pixels
# at the board's 4:1 rung, so an owner that lives only on roofs does not
# survive the downsample; the paint is how a property carries its owner down
# the front of itself. Both sit two bands under the unit convention, and
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
    """Two clad towers of different heights on a plaza — the tall-narrow
    silhouette of the set.

    The mass is TWO PILLARS, which is a thing the board can see. The 5x5
    towers this used to be, nine voxels tall and five, decimated into one
    slab at the board's 4:1 rung (`PropertySilhouette`, 2026-08-24: city
    against the hq 0.729, against the base 0.671), so both are three and
    four voxels across now, pushed out into opposite corners of the same
    12x12 plaza — a diagonal apart, with daylight between them at rung 1 —
    and each carries its height instead of its width: a pillar four voxels
    across has to be tall or it is a stump.

    The plaza itself does not shrink with them. Its plate is what casts most
    of the cell's shadow, and the phases of the board's 4:1 grid have to draw
    the same share of that shadow (`PropertyOverlays.test_every_rung_draws
    _the_same_share_of_the_shadow`): a smaller lot is a shorter band, and the
    band starts flickering by phase.

    The tall tower is SET BACK for the same reason. A pillar taken straight
    up ends in one unbroken vertical arris, and the shadow of an arris is a
    two-pixel column standing clear of the plate — 52 of the cell's 171
    shadow pixels in two columns of the four, which is the same flicker
    arriving by a different road (deviation 0.47 against a 0.45 bar, 0.18
    with the setback). The step that pays for it is the step a tower this
    narrow wanted anyway.
    """
    m = Model()
    _pad(m, 1, 12, 1, 12)
    # tall tower, right: a stone podium, a shaft set back a voxel on each
    # camera-facing side, and the owner's cladding up both of them. The
    # cladding is what the width paid for: a 3x3 deck is ONE pixel at the
    # board's 4:1 rung, so a tower this narrow cannot say whose it is from
    # its roof, and the owner's band has to be most of the two walls the
    # camera sees or the downsample loses it (`PropertyPalette.test_two
    # _owners_are_tellable_apart_at_the_boards_own_scale`: Iron against
    # verdant, the closest pair on this tile, 17.6 with the two-course fascia
    # the old 5x5 towers wore, 29.2 with the cladding).
    m.box(8, 11, 2, 5, 1, 7, WALL)
    m.box(8, 11, 5, 5, 6, 7, ROOF_TRIM)
    m.box(11, 11, 2, 5, 6, 7, ROOF_TRIM)
    _windows(m, "y", 9, 10, 5, 2, 4, 23)
    _windows(m, "x", 3, 4, 11, 2, 4, 24)
    m.box(8, 10, 2, 4, 8, 15, WALL)
    m.box(8, 10, 4, 4, 8, 15, ROOF_TRIM)
    m.box(10, 10, 2, 4, 8, 15, ROOF_TRIM)
    # a stone belt course halfway up the shaft: eight unbroken courses of
    # paint between the setback and the deck is a silo, and the break is what
    # makes the panels above and below it read as storeys
    m.box(8, 10, 2, 4, 12, 12, WALL)
    m.box(8, 10, 2, 4, 16, 16, ROOF_TRIM)  # the roof deck, in the owner's paint
    m.box(9, 10, 3, 4, 17, 17, PAD)  # the plant room, the tower's lit cap
    # shorter tower, left: the same podium, cladding, belt and deck, with no
    # setback — it is short enough to carry its paint in one panel
    m.box(2, 4, 9, 11, 1, 10, WALL)
    m.box(2, 4, 9, 11, 11, 11, ROOF_TRIM)
    m.chamfer(2, 4, 9, 11, 11, 11)
    m.box(2, 4, 11, 11, 4, 10, ROOF_TRIM)
    m.box(4, 4, 9, 11, 4, 10, ROOF_TRIM)
    m.box(2, 4, 9, 11, 8, 8, WALL)
    _windows(m, "y", 3, 3, 11, 2, 3, 21)
    _windows(m, "x", 9, 10, 4, 2, 3, 22)
    # plaza planter at the front corner
    m.set(11, 11, 1, "leaf")
    m.set(12, 11, 1, "leaf_dk")
    return m


def base() -> Model:
    """A factory: a long stone shed under a faction sawtooth roof, chimney,
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
    m.box(12, 13, 5, 6, 6, 6, ROOF_TRIM)  # the owner's band round the cap
    m.set(12, 5, 7, DETAIL)
    m.set(13, 6, 7, DETAIL)
    # crates on the front apron
    m.box(0, 1, 12, 13, 1, 2, "wood")
    return m


def hq() -> Model:
    """A stone fortress; faction color on the tower caps, keep roof, banner.

    The hq is the tile a match is WON on, so it is the tallest thing on the
    board by a clear step: the keep is a stepped tower — a 6x6 storey, a 4x4
    one on top of it, an oversailing roof, then the banner mast — and its
    top line stands a board texel and a half over the city's and five over
    every other property's (`PropertySilhouette`, which holds the step at one
    texel). What it is not is a taller BOX: the curtain wall
    and its corner towers stay exactly where they were, so the growth reads
    as a keep rising out of a fort rather than as the fort inflating.
    """
    m = Model()
    _pad(m, 0, 13, 0, 13)
    # curtain walls in castle stone
    m.box(1, 12, 1, 12, 1, 4, MASONRY)
    m.clear(3, 10, 3, 10, 1, 4)  # hollow courtyard (hidden anyway)
    # crenellations along all four parapets — the dotted line that keeps the
    # curtain wall from reading as a slab. The two the camera sees are the
    # owner's paint, and they carry it along the widest run of stone on the
    # sheet; the two turned away stay stone, because a merlon the camera only
    # sees the back of is a silhouette pixel and nothing else
    for i in range(1, 13, 2):
        m.set(i, 12, 5, ROOF_TRIM)
        m.set(12, i, 5, ROOF_TRIM)
        m.set(i, 1, 5, TRIM)
        m.set(1, i, 5, TRIM)
    # corner towers, capped in the owner's color at parapet height — they
    # stay LOW on purpose: the whole height budget goes to the central keep,
    # which is what sets the sprite's top line
    for tx, ty in ((1, 1), (1, 11), (11, 1), (11, 11)):
        m.box(tx, tx + 1, ty, ty + 1, 1, 4, MASONRY)
        m.box(tx, tx + 1, ty, ty + 1, 5, 5, ROOF_TRIM)
    # gatehouse: arched gate with a wooden door on the front wall
    m.box(5, 8, 12, 12, 1, 4, MASONRY_DK)
    m.box(6, 7, 12, 12, 1, 3, "wood")
    m.set(6, 12, 4, DETAIL)
    m.set(7, 12, 4, DETAIL)
    # central stone keep under a faction roof, banner mast above. The upper
    # storey is a voxel narrower on every side than the lower one, so the
    # step is what carries the height: a six-wide box taken straight up is a
    # silo, and the rung-1 read of one is a fatter lump, not a taller mass.
    m.box(4, 9, 4, 9, 1, 6, MASONRY)
    m.box(5, 8, 5, 8, 7, 13, MASONRY)
    m.box(4, 9, 4, 9, 14, 14, ROOF)  # the roof oversails the upper storey
    m.box(5, 8, 5, 8, 15, 15, ROOF_TRIM)
    m.chamfer(5, 8, 5, 8, 15, 15)
    _windows(m, "y", 5, 8, 9, 3, 6, 31)
    _windows(m, "y", 6, 7, 8, 8, 10, 32)
    # the keep's own fascia, on the two walls the camera sees, clear of the
    # roof's overhang: the paint has to climb with the stone or the tallest
    # thing on the board is grey
    m.box(5, 8, 8, 8, 11, 12, ROOF_TRIM)
    m.box(8, 8, 5, 8, 11, 12, ROOF_TRIM)
    # the banner: the mast clears the roof's own back corner before the
    # pennant starts, or the flag is drawn inside the roof's silhouette and
    # the hq's top line is a roof like everybody else's
    m.box(6, 6, 6, 6, 16, 19, METAL)
    m.box(7, 9, 6, 6, 17, 19, ROOF_TRIM)
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
    m.box(1, 8, 13, 13, 4, 4, ROOF_TRIM)  # painted lintel over the door
    m.box(2, 7, 13, 13, 1, 3, DETAIL)  # hangar door
    m.box(4, 5, 13, 13, 1, 3, METAL)  # door seam
    m.box(1, 8, 6, 6, 1, 4, WALL_DK)  # rear wall
    # control tower with glass cab and radar
    m.box(10, 12, 4, 6, 1, 4, WALL)
    m.box(9, 13, 3, 7, 5, 5, ROOF)  # balcony ring, in the owner's paint
    m.box(10, 12, 4, 6, 6, 6, "glass_dk")
    m.box(10, 12, 4, 6, 7, 7, ROOF_TRIM)  # cap
    m.set(11, 5, 8, DETAIL)  # radar knob
    # the apron's guide line, dashed in the owner's paint: ground markings
    # are how an airfield says whose it is, and they cost no height at all
    for x in range(0, 14, 2):
        m.set(x, 4, 0, ROOF_TRIM)
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
    for x in range(0, 14, 2):
        m.set(x, 4, 1, ROOF_TRIM)  # quay edge, dashed in the owner's paint
    # warehouse: concrete walls under a shallow faction gabled roof
    m.box(1, 6, 7, 13, 2, 5, WALL)
    m.box(1, 6, 8, 12, 6, 6, ROOF)
    m.box(1, 6, 10, 10, 7, 7, ROOF_TRIM)  # ridge
    m.box(1, 6, 13, 13, 5, 5, ROOF_TRIM)  # fascia along both eaves
    m.box(6, 6, 7, 13, 5, 5, ROOF_TRIM)
    m.box(3, 4, 13, 13, 2, 4, DETAIL)  # cargo door
    # gantry crane over the dockside
    m.box(9, 10, 11, 12, 2, 7, ROOF_TRIM)  # painted crane legs
    m.box(9, 10, 4, 12, 8, 8, METAL)  # jib reaching the water
    m.set(9, 5, 7, DETAIL)  # cable
    m.set(9, 5, 6, DETAIL)
    m.box(9, 10, 11, 12, 8, 9, ROOF_TRIM)  # cab + counterweight, owner-painted
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

# The neutral row is COLD. An unowned property must not read as lit or owned,
# so every hue-carrying material resolves off the faction ramps (design review
# 2026-08-13) — and since round 8 it resolved onto the same warm masonry every
# owned property is built of, which is how the row nobody owns and the Iron
# row ended up 12 RGB apart at the board's 4:1 rung: Iron's own colour is a
# grey, so an Iron property was a neutral property with slightly darker roof
# panels. The unowned row is drawn out of CONCRETE end to end instead — the
# cool slate the lots were already paved in — against the warm sandstone an
# owned one is built of. Nobody's lights are on and nobody's stone is in the
# sun: that is a temperature, not a value, so the row stays under every band
# the owned rows are held to while telling itself apart at a glance.
#
# Every entry is still a RUNG, so an unowned property is keyed exactly like an
# owned one: the roof plane lands a rung above the wall and its ridge on the
# trim step, which is the same three-step read with the owner taken out. Owned
# rows keep their accents untouched, so the lit-window glint is an owned
# property's alone. `bore` stays — the palette has no dark true grey and its
# few pixels read black.
_NEUTRAL_GREYS = {
    "amber": PAD_TRIM,  # lit windows, hazard stripe, windsock, container mark
    "glass_dk": METAL,  # window and cab glazing
    "wood": PAD_RIM,  # doors, crates
    "leaf": METAL,  # plaza planter
    "leaf_dk": PAD,
    ROOF: PAD_RIM,  # roof planes: a dark plane, as an owned roof is
    ROOF_TRIM: PAD,  # and their ridges, caps and banner
    # ...and the masonry itself, rung for rung, into the cool family
    DETAIL: PAD_SEAM,
    WALL_DK: PAD_RIM,
    WALL: PAD,
    TRIM: PAD_TRIM,
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
