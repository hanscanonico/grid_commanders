"""The HQ: a walled fortress round a domed keep, the one every player looks for.

Pale walls and stone below; above them a dome, tower caps and banners in the army's
colour, a brass star on the keep's face and the tallest flag on the board. The keep
stands at the back and the walls come forward round a low open forecourt, where a
unit stands to capture it.
"""

from __future__ import annotations

import math

from ..kit import Kit
from ..paint import Role, grey
from .parts import (
    PLINTH,
    battlement,
    dome,
    flag,
    flatten_small_bevels,
    merlon_ring,
    paving,
    star_outline,
    uncap,
    wall_star,
)

CAGE = 0.015
REACH = 0.035
# The keep's and wings' faces look away from the sun and sit in the wash, so the paint
# starts paler to land on the same pale wall every other building wears. The carpet
# stays clean of road dust, which would break its colour up.
ROLES = {
    "wall": Role((0.95, 0.91, 0.79), edge=0.5, dust=0.35, wash=0.55, roughness=0.9),
    "carpet": Role(grey(0.55), team=True, edge=0.3, dust=0.0, wash=0.4, roughness=0.9),
}

KEEP_Y = 0.255
KEEP_SX = 0.36
KEEP_SY = 0.3
KEEP_TOP = 0.48
DRUM_R = 0.128
DRUM_TOP = 0.56
DOME_R = 0.136
DOME_RISE = 0.135
TOWER_R = 0.085
WALL_X = 0.405
WALL_TOP = PLINTH + 0.085


def _slit(k: Kit, x: float, y: float, z: float, w: float = 0.024, h: float = 0.075) -> None:
    """A tall narrow window with a pointed head, on a wall facing -Y."""
    if not k.hi:
        return
    k.box((x, y - 0.002, z), (w + 0.014, 0.004, h + 0.014), "stone", 0.0, label="surround")
    k.box((x, y - 0.004, z), (w, 0.003, h), "glass", 0.0, label="pane")
    k.box((x, y - 0.004, z + h / 2 + 0.006), (w * 0.7, 0.003, 0.012), "glass", 0.0, label="pane_head")


def _side_slit(k: Kit, x: float, y: float, z: float, w: float = 0.024, h: float = 0.075) -> None:
    """The same window on a wall facing +X."""
    if not k.hi:
        return
    k.box((x + 0.002, y, z), (0.004, w + 0.014, h + 0.014), "stone", 0.0, label="surround")
    k.box((x + 0.004, y, z), (0.003, w, h), "glass", 0.0, label="pane")


def _forecourt(k: Kit) -> None:
    k.boost(k.box((0, 0, PLINTH / 2), (0.92, 0.92, PLINTH), "stone", 0.012, label="plinth"), 1.5)
    paving(k, -0.37, 0.37, -0.39, 0.1, PLINTH, 0.082, 1.4, gap=0.006)
    if not k.hi:
        return
    z = PLINTH + 0.0035
    # The army's carpet, from the gate up to the steps. The badge lies on it.
    k.box((0, -0.2, z), (0.1, 0.46, 0.004), "carpet", 0.0, label="carpet")
    for side in (-1.0, 1.0):
        k.box((side * 0.058, -0.2, z), (0.014, 0.46, 0.004), "brass", 0.0, label="carpet_edge")


def _keep(k: Kit) -> None:
    y = KEEP_Y
    z = PLINTH
    front = y - KEEP_SY / 2
    # A battered stone foot, then the pale tower straight up.
    k.box((0, y, z + 0.05), (KEEP_SX + 0.03, KEEP_SY + 0.03, 0.1), "stone", 0.008, taper=0.94, label="keep_foot")
    k.boost(k.box((0, y, (z + KEEP_TOP) / 2), (KEEP_SX, KEEP_SY, KEEP_TOP - z), "wall", 0.008, label="keep"), 1.3)
    # Machicolations: a jutting army-coloured band under the parapet.
    k.box((0, y, KEEP_TOP - 0.014), (KEEP_SX + 0.03, KEEP_SY + 0.03, 0.028), "team_dark", 0.005, label="corbel")
    k.box((0, y, KEEP_TOP + 0.004), (KEEP_SX + 0.03, KEEP_SY + 0.03, 0.012), "bone", 0.003, label="string")
    half = (KEEP_SX + 0.016) / 2
    for dy in (-(KEEP_SY + 0.016) / 2, (KEEP_SY + 0.016) / 2):
        k.boost(
            battlement(k, (0, y + dy), KEEP_SX + 0.03, KEEP_TOP + 0.008, 6, "x", "wall", wall=0.012, tooth=0.034), 0.5
        )
    for dx in (-half, half):
        k.boost(battlement(k, (dx, y), KEEP_SY + 0.03, KEEP_TOP + 0.008, 5, "y", "wall", wall=0.012, tooth=0.034), 0.5)
    k.box((0, y, KEEP_TOP + 0.012), (KEEP_SX, KEEP_SY, 0.012), "stone", 0.0, label="roof")
    # The hi copy's rows of windows and string courses.
    for wy in (0.15, 0.255, 0.355):
        for wz in (0.22, 0.34):
            _side_slit(k, KEEP_SX / 2, wy, wz)
    k.seam((0, front - 0.001, 0.14), (KEEP_SX, 0.003, 0.008), "stone")
    k.seam((KEEP_SX / 2 + 0.001, y, 0.14), (0.003, KEEP_SY, 0.008), "stone")


def _crown(k: Kit) -> None:
    """The drum, the dome and the lantern: the keep's shape against the back of the cell."""
    y = KEEP_Y
    base = KEEP_TOP + 0.018
    uncap(k, k.cyl((0, y, base), (0, y, DRUM_TOP), DRUM_R, DRUM_R * 0.97, "plaster", 12, 0.006, "drum"))
    uncap(
        k,
        k.cyl(
            (0, y, DRUM_TOP - 0.002),
            (0, y, DRUM_TOP + 0.016),
            DOME_R + 0.008,
            DOME_R + 0.004,
            "brass",
            12,
            0.004,
            "dome_ring",
        ),
        bottom=False,
    )
    dome_z = DRUM_TOP + 0.014
    k.boost(dome(k, 0, y, dome_z, DOME_R, DOME_RISE, "team", rings=5, sides=12, power=0.82), 1.4)
    top = dome_z + DOME_RISE
    uncap(k, k.cyl((0, y, top - 0.012), (0, y, top + 0.012), 0.026, 0.02, "brass", 8, 0.003, "lantern"))
    k.ellipsoid((0, y, top + 0.024), (0.016, 0.016, 0.016), "brass", 4, 8, "finial")
    if not k.hi:
        return
    # The dome's ribs, dark lines from its ring to its crown.
    ribs = 12
    for i in range(ribs):
        angle = math.tau * i / ribs
        points = []
        for t in range(7):
            phi = (t / 6) * math.pi / 2 * 0.94
            radius = (DOME_R + 0.003) * math.cos(phi) ** 0.82
            points.append(
                (radius * math.cos(angle), y + radius * math.sin(angle), dome_z + (DOME_RISE + 0.003) * math.sin(phi))
            )
        for p0, p1 in zip(points, points[1:]):
            k.cyl(p0, p1, 0.0045, None, "team_dark", 4, 0.0, "dome_rib")
    # Tall windows round the drum, on the half the lens sees.
    for i in range(12):
        angle = math.tau * (i + 0.5) / 12
        if math.sin(angle) > 0.35:
            continue
        cx, cy = (DRUM_R + 0.001) * math.cos(angle), y + (DRUM_R + 0.001) * math.sin(angle)
        k.cyl((cx, cy, base + 0.014), (cx, cy, DRUM_TOP - 0.012), 0.012, None, "glass", 6, 0.0, "drum_window")


def _pinnacle(k: Kit, x: float, y: float) -> None:
    """A little turret on one of the keep's corners, capped in the army's colour."""
    z = KEEP_TOP - 0.04
    r = 0.04
    uncap(k, k.cyl((x, y, z), (x, y, z + 0.13), r, r, "plaster", 8, 0.004, "turret"))
    k.seam((x, y - r - 0.001, z + 0.06), (0.05, 0.003, 0.01), "stone")
    uncap(k, k.cyl((x, y, z + 0.124), (x, y, z + 0.215), r + 0.013, 0.004, "team", 8, 0.003, "turret_cap"))


def _banner(k: Kit, x: float, y: float, z_top: float, length: float) -> None:
    """A long banner down the keep's face: broad, so the army's colour carries."""
    width = 0.058
    k.box((x, y - 0.006, z_top - length / 2), (width, 0.01, length), "team", 0.002, label="banner")
    k.box((x, y - 0.012, z_top + 0.002), (width + 0.022, 0.012, 0.012), "brass", 0.003, label="banner_rod")
    outline = [
        (x - width / 2, z_top - length),
        (x, z_top - length - 0.03),
        (x + width / 2, z_top - length),
        (x + width / 2, z_top - length + 0.01),
        (x - width / 2, z_top - length + 0.01),
    ]
    k.side_profile(outline, y - 0.011, y - 0.001, "team", 0.0, "banner_tip")
    if not k.hi:
        return
    k.box(
        (x, y - 0.012, z_top - length / 2),
        (width - 0.02, 0.002, length - 0.03),
        "team_light",
        0.0,
        label="banner_stripe",
    )
    wall_star(k, x, y - 0.012, z_top - 0.05, 0.022, "bone", depth=0.002, bevel=0.0)


def _star_plate(k: Kit, x: float, y: float, z: float) -> None:
    """The HQ's mark: a great brass star on a round army-coloured shield, tipped to the lens."""
    lean = 0.42
    normal_y, normal_z = -math.cos(lean), math.sin(lean)
    r = 0.098
    centre = (x, y - 0.02, z)
    back = (centre[0], centre[1] + 0.006, centre[2])
    face = (centre[0], centre[1] + normal_y * 0.018, centre[2] + normal_z * 0.018)
    k.boost(uncap(k, k.cyl(back, face, r, r, "team", 16, 0.004, "shield"), bottom=True, top=False), 1.5)
    if k.hi:
        rim = (face[0], face[1] + normal_y * 0.002, face[2] + normal_z * 0.002)
        k.cyl(face, rim, r, r - 0.002, "team_dark", 16, 0.0, "shield_rim")
        k.cyl(
            (rim[0], rim[1], rim[2]),
            (rim[0], rim[1] + normal_y * 0.002, rim[2] + normal_z * 0.002),
            r - 0.01,
            r - 0.01,
            "team_light",
            16,
            0.0,
            "shield_face",
        )
    k.boost(wall_star(k, face[0], face[1], face[2], r * 0.82, "brass", depth=0.012, lean=lean, bevel=0.003), 1.5)


def _portal(k: Kit) -> None:
    """The grand door, under its pediment, up a flight of steps."""
    front = KEEP_Y - KEEP_SY / 2
    z = PLINTH
    for i, (depth, width) in enumerate(((0.1, 0.27), (0.07, 0.235), (0.04, 0.2))):
        k.box((0, front - depth / 2, z + 0.008 + i * 0.016), (width, depth, 0.016), "stone", 0.003, label="step")
    deck = z + 0.048
    k.box((0, front - 0.008, deck + 0.054), (0.1, 0.016, 0.108), "team_dark", 0.003, label="door")
    k.seam((0, front - 0.018, deck + 0.05), (0.005, 0.003, 0.098), "brass")
    for side in (-1.0, 1.0):
        cx = side * 0.078
        uncap(
            k,
            k.cyl(
                (cx, front - 0.03, deck), (cx, front - 0.03, deck + 0.128), 0.0165, 0.014, "bone", 8, 0.003, "column"
            ),
        )
    top = deck + 0.128
    k.box((0, front - 0.022, top + 0.008), (0.2, 0.05, 0.016), "bone", 0.003, label="entablature")
    pediment = [(-0.108, top + 0.016), (0.108, top + 0.016), (0.0, top + 0.07)]
    k.side_profile(pediment, front - 0.048, front + 0.002, "team", 0.004, "pediment")
    if k.hi:
        k.side_profile(star_outline(0.016), front - 0.051, front - 0.047, "brass", 0.0, "tiny_star").location = (
            0.0,
            0.0,
            top + 0.036,
        )


def _tower(k: Kit, x: float, y: float, r: float, top: float, cap_rise: float, windows: int) -> None:
    """A round wall tower with a stone foot, a merlon ring and a witch's-hat roof."""
    z = PLINTH
    uncap(k, k.cyl((x, y, z), (x, y, z + 0.05), r + 0.014, r, "stone", 12, 0.005, "tower_foot"))
    uncap(k, k.cyl((x, y, z + 0.05), (x, y, top), r, r, "plaster", 12, 0.005, "tower"))
    uncap(
        k,
        k.cyl((x, y, top - 0.006), (x, y, top + 0.012), r + 0.012, r + 0.012, "team_dark", 12, 0.003, "tower_band"),
        top=False,
    )
    merlon_ring(k, x, y, top + 0.012, r + 0.002, 8, "wall", 0.026)
    uncap(
        k, k.cyl((x, y, top + 0.012), (x, y, top + 0.014 + cap_rise), r + 0.002, 0.005, "team", 12, 0.003, "tower_cap")
    )
    if not k.hi:
        return
    for i in range(windows):
        wz = z + 0.1 + i * 0.1
        for angle in (-math.pi / 2, -0.35):
            cx, cy = x + (r + 0.001) * math.cos(angle), y + (r + 0.001) * math.sin(angle)
            k.cyl((cx, cy, wz - 0.03), (cx, cy, wz + 0.03), 0.011, None, "glass", 6, 0.0, "tower_slit")


def _bastion(k: Kit, x: float, y: float) -> None:
    """A low drum tower at a front corner, low enough never to hide the forecourt."""
    r = 0.076
    z = PLINTH
    top = z + 0.13
    uncap(k, k.cyl((x, y, z), (x, y, z + 0.034), r + 0.012, r, "stone", 12, 0.005, "bastion_foot"))
    uncap(k, k.cyl((x, y, z + 0.034), (x, y, top), r, r, "plaster", 12, 0.005, "bastion"))
    uncap(
        k,
        k.cyl((x, y, top - 0.006), (x, y, top + 0.018), r + 0.01, r + 0.01, "team", 12, 0.003, "bastion_band"),
        top=False,
    )
    merlon_ring(k, x, y, top + 0.018, r + 0.004, 8, "wall", 0.026)
    # A brass gun on each, the fort's teeth.
    gun_z = top + 0.046
    k.cyl((x, y + 0.012, gun_z), (x, y - 0.088, gun_z), 0.017, 0.012, "brass", 8, 0.0, "cannon")
    k.box((x, y + 0.012, top + 0.03), (0.056, 0.042, 0.024), "wood", 0.003, label="carriage")


def _curtain_wall(k: Kit) -> None:
    """The walls coming forward either side of the forecourt, and the gate between them."""
    z = PLINTH
    h = 0.075
    thick = 0.05
    back = 0.3
    front = -0.36
    middle = (back + front) / 2
    length = back - front
    for side in (-1.0, 1.0):
        x = side * WALL_X
        k.box((x, middle, z + h / 2), (thick, length, h), "plaster", 0.006, label="curtain")
        k.seam((x, middle, z + 0.012), (thick + 0.008, length, 0.024), "stone")
        k.boost(
            battlement(k, (x, middle), length, z + h - 0.002, 9, "y", "wall", thick=thick, wall=0.002, tooth=0.03), 0.6
        )
    gate_gap = 0.09
    run = WALL_X - 0.076 - gate_gap
    for side in (-1.0, 1.0):
        x = side * (gate_gap + run / 2)
        low = 0.045
        k.box((x, -0.41, z + low / 2), (run, 0.036, low), "plaster", 0.006, label="front_wall")
        k.seam((x, -0.41, z + 0.012), (run, 0.044, 0.024), "stone")
        k.boost(
            battlement(k, (x, -0.41), run, z + low - 0.002, 3, "x", "wall", thick=0.036, wall=0.002, tooth=0.024), 0.6
        )
        # The gate's two piers, each with a brass finial.
        px = side * (gate_gap - 0.012)
        k.box((px, -0.41, z + 0.055), (0.05, 0.05, 0.11), "stone", 0.005, label="gate_pier")
        k.box((px, -0.41, z + 0.113), (0.062, 0.062, 0.012), "bone", 0.003, label="pier_cap")
        uncap(
            k,
            k.cyl((px, -0.41, z + 0.119), (px, -0.41, z + 0.138), 0.016, 0.011, "brass", 6, 0.002, "pier_finial"),
            top=False,
        )


def _wings(k: Kit) -> None:
    """Low buildings between the keep and the back towers, their roofs in the army's colour."""
    z = PLINTH
    h = 0.2
    y = 0.28
    for side in (-1.0, 1.0):
        x = side * 0.275
        k.box((x, y, z + h / 2), (0.14, 0.22, h), "wall", 0.007, label="wing")
        k.seam((x, y - 0.111, z + 0.018), (0.152, 0.004, 0.036), "stone")
        k.box((x, y, z + h + 0.008), (0.16, 0.24, 0.016), "team_dark", 0.004, label="wing_eave")
        roof = [(x - 0.086, z + h + 0.014), (x + 0.086, z + h + 0.014), (x, z + h + 0.085)]
        k.side_profile(roof, y - 0.12, y + 0.12, "team", 0.006, "wing_roof")
        for wx in (x - 0.034, x + 0.034):
            _slit(k, wx, y - 0.11, z + 0.125, 0.018, 0.055)


def build(k: Kit) -> None:
    _forecourt(k)
    _curtain_wall(k)
    _wings(k)
    _keep(k)
    _crown(k)
    half_x, half_y = KEEP_SX / 2, KEEP_SY / 2
    for dx in (-half_x, half_x):
        for dy in (-half_y, half_y):
            _pinnacle(k, dx, KEEP_Y + dy)
    front = KEEP_Y - KEEP_SY / 2
    _star_plate(k, 0.0, front, 0.37)
    for side in (-1.0, 1.0):
        _banner(k, side * 0.137, front, 0.455, 0.17)
    _portal(k)
    _tower(k, -0.36, 0.355, TOWER_R, 0.36, 0.17, 3)
    _tower(k, 0.36, 0.355, TOWER_R, 0.36, 0.17, 3)
    _bastion(k, -0.362, -0.36)
    _bastion(k, 0.362, -0.36)
    flag(
        k,
        0.0,
        KEEP_Y,
        DRUM_TOP + DOME_RISE + 0.03,
        0.85,
        0.25,
        0.115,
        "team_light",
        pole_r=0.0095,
        tail=0.04,
        thick=0.014,
    )
    flatten_small_bevels(k, 0.005)
    k.marker("emblem", (0.0, -0.18, PLINTH))
    k.marker("emblem_edge", (0.12, -0.18, PLINTH))
