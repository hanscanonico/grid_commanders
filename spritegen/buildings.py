"""Voxel props for terrain tiles: trees, reef rocks — and the five property
buildings (city, base, hq, airport, port), tinted per faction row.

Buildings carry their own isometric base plate, the convention the game's
compositor has always assumed (the lot IS the plate; no square of pavement
behind a diamond footprint).
"""

from __future__ import annotations

from .palette import h01
from .voxel import Model

# ---------------------------------------------------------------------------
# nature props
# ---------------------------------------------------------------------------


def tree(big: bool = True) -> Model:
    """A rounded conifer-ish canopy over a stub trunk."""
    m = Model()
    if big:
        m.box(3, 4, 3, 4, 0, 2, "trunk")
        layers = ((1, 6, 3, 4), (2, 5, 5, 6), (3, 4, 7, 7))
    else:
        m.box(3, 4, 3, 4, 0, 1, "trunk")
        layers = ((2, 5, 2, 3), (3, 4, 4, 5))
    for lo, hi, z0, z1 in layers:
        m.box(lo, hi, lo, hi, z0, z1, "leaf")
        for cx, cy in ((lo, lo), (lo, hi), (hi, lo), (hi, hi)):
            m.unset(cx, cy, z1)
    # shade the skirt, light the crown
    lo, hi, z0, z1 = layers[0]
    for x in range(lo, hi + 1):
        for y in range(lo, hi + 1):
            if (x, y, z0) in m.vox and h01(x, y, 11) < 0.5:
                m.set(x, y, z0, "leaf_dk")
    lo, hi, z0, z1 = layers[-1]
    m.box(lo, hi, lo, hi, z1, z1, "leaf_lt")
    return m


def rock_outcrop(size: int = 2) -> Model:
    """A low shelf of reef rock breaking the surface."""
    m = Model()
    m.box(0, size, 0, size, 0, 0, "rock")
    m.box(0, size - 1, 0, size - 1, 1, 1, "rock")
    m.set(0, 0, 1, "rock_dk")
    m.set(size - 1, size - 1, 1, "rock_dk")
    return m


# ---------------------------------------------------------------------------
# property buildings
# ---------------------------------------------------------------------------


def _pad(m: Model, x0: int, x1: int, y0: int, y1: int, mat: str = "concrete") -> None:
    """The building's own base plate, with a darker rim."""
    m.box(x0, x1, y0, y1, 0, 0, mat)
    for x in range(x0, x1 + 1):
        m.set(x, y0, 0, mat + "_dk")
        m.set(x, y1, 0, mat + "_dk")
    for y in range(y0, y1 + 1):
        m.set(x0, y, 0, mat + "_dk")
        m.set(x1, y, 0, mat + "_dk")


def _windows(m: Model, face: str, along0: int, along1: int, wall: int,
             z0: int, z1: int, salt: int) -> None:
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
    """A block of three grey towers whose roofs carry the owner's color."""
    m = Model()
    _pad(m, 0, 13, 0, 13)
    # main tower, front-left: concrete walls, faction roof
    m.box(1, 6, 6, 11, 1, 8, "concrete")
    m.box(1, 6, 6, 11, 9, 9, "body")        # roof
    m.box(2, 5, 7, 10, 10, 10, "body_dk")   # roof plant
    m.set(3, 8, 11, "gunmetal")             # AC unit
    _windows(m, "y", 2, 5, 11, 2, 8, 21)
    _windows(m, "x", 7, 10, 6, 2, 8, 22)
    # taller slab tower, back-right
    m.box(8, 12, 1, 6, 1, 10, "concrete")
    m.box(8, 12, 1, 6, 11, 11, "body")      # roof
    m.box(9, 11, 2, 5, 12, 12, "body_lt")   # penthouse
    m.chamfer(9, 11, 2, 5, 12, 12)
    _windows(m, "y", 9, 11, 6, 2, 10, 23)
    _windows(m, "x", 2, 5, 12, 2, 10, 24)
    # low storefront, front-right: faction awning over grey walls
    m.box(8, 12, 8, 12, 1, 3, "concrete")
    m.box(8, 12, 8, 12, 4, 4, "body")       # awning roof
    m.chamfer(8, 12, 8, 12, 4, 4)
    m.box(9, 11, 12, 12, 1, 2, "glass_dk")  # shopfront glazing
    # plaza detail
    m.set(2, 3, 1, "leaf")                   # planter
    m.set(3, 3, 1, "leaf_dk")
    return m


def base() -> Model:
    """A factory: grey shed under a faction sawtooth roof, chimney, crates."""
    m = Model()
    _pad(m, 0, 13, 0, 13)
    # main shed in industrial concrete
    m.box(1, 11, 3, 12, 1, 4, "concrete_dk")
    # sawtooth roof: three north-lit ridges in the owner's color
    for k in range(3):
        y0 = 10 - k * 3
        m.box(1, 11, y0 - 1, y0, 5, 5, "body_dk")
        m.box(1, 11, y0, y0, 6, 6, "body_lt")
        m.box(1, 11, y0 - 1, y0 - 1, 6, 6, "glass_dk")  # skylight band
    # big vehicle door on the front face with hazard stripe
    m.box(3, 8, 12, 12, 1, 3, "gunmetal_dk")
    m.box(3, 8, 12, 12, 3, 3, "amber")
    m.box(5, 6, 12, 12, 1, 1, "bore")        # door gap
    # chimney at the rear corner
    m.box(11, 12, 1, 2, 1, 8, "concrete_dk")
    m.box(11, 12, 1, 2, 8, 8, "gunmetal")
    m.set(11, 1, 9, "bore")
    m.set(12, 2, 9, "bore")
    # crates on the apron
    m.box(12, 13, 8, 9, 1, 2, "wood")
    m.box(1, 2, 0, 1, 1, 1, "wood")
    return m


def hq() -> Model:
    """A stone fortress; faction color on the tower caps, keep roof, banner."""
    m = Model()
    _pad(m, 0, 13, 0, 13, "concrete")
    # curtain walls in castle stone
    m.box(1, 12, 1, 12, 1, 5, "stone")
    m.clear(3, 10, 3, 10, 1, 5)              # hollow courtyard (hidden anyway)
    # crenellations along the front and right parapets
    for i in range(1, 13, 2):
        m.set(i, 12, 6, "stone")
        m.set(12, i, 6, "stone")
        m.set(i, 1, 6, "stone")
        m.set(1, i, 6, "stone")
    # corner towers, capped in the owner's color
    for tx, ty in ((1, 1), (1, 11), (11, 1), (11, 11)):
        m.box(tx, tx + 1, ty, ty + 1, 1, 6, "stone")
        m.box(tx, tx + 1, ty, ty + 1, 7, 7, "body_dk")
        m.set(tx, ty, 8, "body")
        m.set(tx + 1, ty + 1, 8, "body")
    # gatehouse: arched gate with a wooden door on the front wall
    m.box(5, 8, 12, 12, 1, 4, "stone_dk")
    m.box(6, 7, 12, 12, 1, 3, "wood")
    m.set(6, 12, 4, "bore")
    m.set(7, 12, 4, "bore")
    # central stone keep under a faction roof, banner mast above
    m.box(4, 9, 4, 9, 1, 7, "stone")
    m.box(4, 9, 4, 9, 8, 8, "body_dk")
    m.box(5, 8, 5, 8, 9, 9, "body")
    m.chamfer(5, 8, 5, 8, 9, 9)
    _windows(m, "y", 5, 8, 9, 3, 7, 31)
    m.box(6, 6, 6, 6, 10, 13, "steel")
    m.box(7, 8, 6, 6, 12, 13, "body")        # banner
    return m


def airport() -> Model:
    """A hangar with an arched roof and a glass-cab control tower."""
    m = Model()
    # apron plate
    _pad(m, 0, 13, 3, 13, "concrete")
    # hangar: concrete walls under a faction barrel roof, doors facing the
    # runway (front)
    m.box(1, 8, 6, 13, 1, 4, "concrete")
    m.box(1, 8, 7, 12, 5, 5, "body")          # arch tier 1
    m.box(2, 7, 8, 11, 6, 6, "body_lt")       # arch crown
    m.chamfer(2, 7, 8, 11, 6, 6)
    m.box(2, 7, 13, 13, 1, 3, "gunmetal_dk")  # hangar door
    m.box(4, 5, 13, 13, 1, 3, "gunmetal")     # door seam
    m.box(1, 8, 6, 6, 1, 4, "concrete_dk")    # rear wall
    # control tower with glass cab and radar
    m.box(10, 12, 4, 6, 1, 6, "concrete")
    m.box(9, 13, 3, 7, 7, 7, "concrete_dk")   # balcony ring
    m.box(10, 12, 4, 6, 8, 8, "glass")
    m.box(10, 12, 4, 6, 9, 9, "body_dk")      # cap
    m.set(11, 5, 10, "steel")                 # radar mast
    m.set(11, 5, 11, "gunmetal_dk")
    # windsock on the apron corner
    m.box(13, 13, 11, 11, 1, 4, "steel")
    m.set(13, 12, 4, "amber")
    return m


def port() -> Model:
    """A quay over the water: warehouse, gantry crane, stacked containers."""
    m = Model()
    # quay deck standing on pilings
    m.box(0, 13, 4, 13, 1, 1, "concrete")
    for x in range(0, 14, 3):
        m.set(x, 4, 0, "concrete_dk")         # pilings at the water edge
    for x in range(14):
        m.set(x, 4, 1, "concrete_dk")         # quay edge trim
    # warehouse: concrete walls under a shallow faction gabled roof
    m.box(1, 6, 7, 13, 2, 5, "concrete")
    m.box(1, 6, 8, 12, 6, 6, "body")
    m.box(1, 6, 10, 10, 7, 7, "body_lt")      # ridge
    m.box(3, 4, 13, 13, 2, 4, "gunmetal_dk")  # cargo door
    # gantry crane over the dockside
    m.box(9, 10, 11, 12, 2, 9, "gunmetal")
    m.box(9, 10, 4, 12, 10, 10, "gunmetal")   # jib reaching the water
    m.set(9, 5, 9, "gunmetal_dk")             # cable
    m.set(9, 5, 8, "gunmetal_dk")
    m.box(9, 10, 11, 12, 10, 11, "gunmetal_dk")  # cab + counterweight
    # container stack on the quay
    m.box(11, 13, 6, 8, 2, 2, "body")
    m.box(11, 13, 6, 7, 3, 3, "amber")
    # bollards
    m.set(1, 5, 2, "gunmetal_dk")
    m.set(6, 5, 2, "gunmetal_dk")
    m.set(12, 5, 2, "gunmetal_dk")
    return m


BUILDINGS = {
    "city": city,
    "base": base,
    "hq": hq,
    "airport": airport,
    "port": port,
}
