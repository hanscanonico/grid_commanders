"""What the four ships share: a hull's plan, its waterline and foam, a turret's guns.

Not a model itself: the ships are `battleship`, `cruiser`, `lander` and `sub`.
"""

from __future__ import annotations

import math
from collections.abc import Callable, Sequence
from dataclasses import dataclass, replace

import bmesh

from ..kit import RECOIL, Kit
from ..paint import ROLES as PAINTS
from ..paint import Role

# `SeaModels3D`'s numbers, which the cut-ins and the tests still read.
KEEL = -0.06
GUN_PITCH = math.radians(4.0)
GUN_TRUNNION = (0.03, 0.03)

WAIST = 0.015
LOW_SCALE = (0.93, 0.62)
WAIST_SCALE = (0.985, 0.92)

Outline = list[tuple[float, float]]

# A ship takes no road dust: the finish's dust is brown stipple from the ground up.
ROLES: dict[str, Role] = {
    **{name: replace(PAINTS[name], dust=0.0) for name in ("gunmetal", "rubber", "glass", "brass", "canvas", "wood")},
    "steel": replace(PAINTS["steel"], colour=(0.28, 0.31, 0.35), dust=0.0),
    # Fewer chips than a tank's: a ship's long edges turn them into white noise at board size.
    "team": replace(PAINTS["team"], dust=0.0, chip=0.3, edge=0.75),
    # Lower than a tank's: a long flat top lit from above would cross into the ramp's white.
    "team_light": replace(PAINTS["team_light"], colour=(0.6, 0.6, 0.6), dust=0.0, chip=0.2, edge=0.6),
    "team_dark": replace(PAINTS["team_dark"], dust=0.0, chip=0.15, edge=0.8),
    "foam": Role((0.93, 0.95, 0.92), edge=0.0, wash=0.0, dust=0.0, roughness=0.9),
}


@dataclass(frozen=True)
class Plan:
    """A hull seen from above: a curved bow to a point at +X, a rounded stern at -X."""

    half_len: float
    half_beam: float
    bow: float
    stern: float = 0.07
    fullness: float = 2.0
    transom: float = 0.6
    stern_round: float = 2.6

    def width(self, x: float) -> float:
        """Half the beam at `x`."""
        shoulder = self.half_len - self.bow
        if x > shoulder:
            t = min((x - shoulder) / self.bow, 1.0)
            return self.half_beam * (1.0 - t**self.fullness)
        counter = -self.half_len + self.stern
        if x < counter:
            s = min((counter - x) / self.stern, 1.0)
            return self.half_beam * (1.0 - (1.0 - self.transom) * s**self.stern_round)
        return self.half_beam

    def outline(self, along: float = 1.0, across: float = 1.0, grow: float = 0.0) -> Outline:
        """Closed and counter-clockwise from the bow tip, the same count at any scale."""
        side = []
        shoulder = self.half_len - self.bow
        for t in (0.93, 0.8, 0.62, 0.42, 0.22, 0.0):
            side.append(shoulder + self.bow * t)
        counter = -self.half_len + self.stern
        for s in (0.0, 0.35, 0.7, 1.0):
            side.append(counter - self.stern * s)
        tip = self.half_len * along + grow
        port = [(x * along, self.width(x) * across + grow) for x in side]
        return [(tip, 0.0), *port, (port[-1][0] - grow, 0.0), *((x, -y) for x, y in reversed(port))]


def scaled_at(z: float, deck: float) -> tuple[float, float]:
    """How far the hull's waterline flare has come in at height `z`."""
    if z >= WAIST:
        t = min((z - WAIST) / (deck - WAIST), 1.0)
        return (WAIST_SCALE[0] + (1.0 - WAIST_SCALE[0]) * t, WAIST_SCALE[1] + (1.0 - WAIST_SCALE[1]) * t)
    t = max((z - KEEL) / (WAIST - KEEL), 0.0)
    return (
        LOW_SCALE[0] + (WAIST_SCALE[0] - LOW_SCALE[0]) * t,
        LOW_SCALE[1] + (WAIST_SCALE[1] - LOW_SCALE[1]) * t,
    )


def hull(
    k: Kit,
    plan: Plan,
    deck: float,
    sheer: tuple[float, float] = (0.0, 0.0),
    foam_width: float = 0.04,
    bow_wave: float = 0.02,
    limit: float = 0.42,
) -> None:
    """Keel to deck in the army's colour, a painted waterline, and foam on the water."""
    part = k.loft(
        [
            (KEEL, plan.outline(*LOW_SCALE)),
            (WAIST, plan.outline(*WAIST_SCALE)),
            (deck, plan.outline()),
        ],
        "team",
        0.009,
        label="hull",
    )
    rise_bow(part, plan, deck, sheer)
    if k.hi:
        ring(k, plan, deck, KEEL + 0.012, 0.0, "team_dark")
        ring(k, plan, deck, -0.001, 0.021, "foam")
    wash(k, plan.outline(*scaled_at(0.0, deck)), foam_width, bow_wave, limit)


def deck_plate(
    k: Kit,
    plan: Plan,
    deck: float,
    thick: float,
    role: str,
    sheer: tuple[float, float] = (0.0, 0.0),
    inset: float = 0.012,
) -> None:
    """The planked or plated top, its edge just inside the hull's, rising with it at the bow."""
    inner = replace(plan, half_len=plan.half_len - inset, half_beam=plan.half_beam - inset)
    part = k.loft([(deck - 0.002, inner.outline()), (deck + thick, inner.outline())], role, 0.003, label="deck")
    rise_bow(part, plan, deck - 0.003, sheer)


def rise_bow(part, plan: Plan, deck: float, sheer: tuple[float, float]) -> None:
    """Lifts what stands at deck height toward the bow: the sheer line that says ship, not raft."""
    start, rise = sheer
    if rise <= 0.0:
        return
    for vert in part.data.vertices:
        if vert.co.z >= deck - 0.001 and vert.co.x > start:
            vert.co.z += rise * ((vert.co.x - start) / (plan.half_len - start)) ** 2


def ring(k: Kit, plan: Plan, deck: float, z0: float, z1: float, role: str, proud: float = 0.004) -> None:
    """A stripe round the hull, standing just proud so the bake reads it. Bake only."""
    if not k.hi:
        return
    low = plan.outline(*scaled_at(z0, deck), grow=proud)
    high = plan.outline(*scaled_at(z1, deck), grow=proud)
    k.loft([(z0, low), (z1, high)], role, 0.0, label="stripe")


def wash(k: Kit, outline: Outline, width: float, bow_wave: float, limit: float = 0.42) -> None:
    """Foam laid on the water round `outline`, fattening toward the bow. The hull hides its inner edge."""
    points = _densify(outline, 0.03)
    stern = min(range(len(points)), key=lambda i: (points[i][0], abs(points[i][1])))
    front = max(p[0] for p in points)
    back = min(p[0] for p in points)
    outer = []
    for i, (x, y) in enumerate(points):
        ax, ay = points[i - 1]
        bx, by = points[(i + 1) % len(points)]
        nx, ny = by - ay, ax - bx
        length = math.hypot(nx, ny) or 1.0
        nx, ny = nx / length, ny / length
        if nx * x + ny * y < 0.0:
            nx, ny = -nx, -ny
        along = (x - back) / (front - back)
        scallop = 0.88 + 0.08 * math.sin(i * 1.9) + 0.06 * math.sin(i * 4.3)
        reach = (width + bow_wave * along**2) * scallop
        outer.append((max(-limit, min(limit, x + nx * reach)), y + ny * reach))
    inner = [(x * 0.97, y * 0.9) for x, y in points]
    for start, stop in ((0, stern), (stern, len(points))):
        indices = [i % len(points) for i in range(start, stop + 1)]
        strip = [outer[i] for i in indices] + [inner[i] for i in reversed(indices)]
        _clean_foam(k.loft([(0.001, strip), (0.006, strip)], "foam", 0.0, label="foam"), len(strip))


def _clean_foam(part, count: int) -> None:
    """Drops the underside on the water and rungs the long top, whose one concave face streaks a bake."""
    bm = bmesh.new()
    bm.from_mesh(part.data)
    bm.verts.ensure_lookup_table()
    top = [bm.verts[count + i] for i in range(count)]
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.normal.z < -0.7], context="FACES")
    for i in range(1, count // 2 - 1):
        bmesh.ops.connect_verts(bm, verts=[top[i], top[count - 1 - i]])
    bm.to_mesh(part.data)
    bm.free()


def _densify(outline: Outline, spacing: float) -> Outline:
    dense: Outline = []
    for i, a in enumerate(outline):
        b = outline[(i + 1) % len(outline)]
        steps = max(1, int(math.dist(a, b) / spacing))
        dense += [(a[0] + (b[0] - a[0]) * j / steps, a[1] + (b[1] - a[1]) * j / steps) for j in range(steps)]
    return dense


def shell(rx: float, ry: float, nose: float, facing: float = 1.0, sides: int = 18) -> Outline:
    """A rounded oval pushed forward at its nose, as a conning tower is."""
    points = []
    for i in range(sides):
        t = math.tau * i / sides
        cx = math.cos(t)
        points.append((facing * (rx * cx + (nose if cx > 0 else 0.0) * cx * cx), ry * math.sin(t)))
    return points


def house(front: float, back: float, half_y: float, scale: float = 1.0, facing: float = 1.0) -> Outline:
    """A gun house's plan: a flat-faced block, its front a little narrower, corners cut."""
    f, b, y = front * scale, back * scale, half_y * scale
    cut = 0.018 * scale
    points = [
        (f, y * 0.8),
        (f - cut, y),
        (-b + cut, y),
        (-b, y * 0.88),
        (-b, -y * 0.88),
        (-b + cut, -y),
        (f - cut, -y),
        (f, -y * 0.8),
    ]
    return [(facing * x, py) for x, py in points]


def turret(
    k: Kit,
    x: float,
    floor: float,
    guns: Sequence[float],
    length: float,
    radius: float,
    facing: float = 1.0,
    size: tuple[float, float, float, float] = (0.075, 0.062, 0.098, 0.068),
    recoil: bool = True,
) -> tuple[float, float, float]:
    """An army-coloured gun house on a dark ring with its guns; answers its first gun's mouth."""
    front, back, half_y, height = size
    k.cyl(
        (x, 0, floor - 0.004),
        (x, 0, floor + 0.02),
        min(front, back, half_y) * 0.98,
        None,
        "gunmetal",
        12,
        0.003,
        "ring",
    )
    k.loft(
        [
            (floor + 0.014, house(front, back, half_y, 0.97, facing)),
            (floor + height * 0.55, house(front, back, half_y, 1.0, facing)),
            (floor + height, house(front, back, half_y, 0.88, facing)),
        ],
        "team",
        0.009,
        (x, 0, 0),
        "turret",
    )
    k.loft(
        [
            (floor + height - 0.002, house(front, back, half_y, 0.74, facing)),
            (floor + height + 0.007, house(front, back, half_y, 0.7, facing)),
        ],
        "team_light",
        0.003,
        (x, 0, 0),
        "roof",
    )
    mouth = (0.0, 0.0, 0.0)
    for y in guns:
        mouth = gun(k, x, floor, y, length, radius, facing, recoil)
    return mouth


def gun(
    k: Kit, x: float, floor: float, y: float, length: float, radius: float, facing: float, recoil: bool
) -> tuple[float, float, float]:
    """A barrel leaving a turret at the old model's trunnion and pitch; answers its mouth."""
    dx, dz = facing * math.cos(GUN_PITCH), math.sin(GUN_PITCH)
    root = (x + facing * GUN_TRUNNION[0], y, floor + GUN_TRUNNION[1])

    def along(t: float) -> tuple[float, float, float]:
        return (root[0] + dx * t, y, root[2] + dz * t)

    move: Callable = (lambda part: k.moves(part, RECOIL)) if recoil else (lambda part: part)
    move(k.cyl(along(0.0), along(length - 0.026), radius, radius * 0.8, "steel", 8, 0.0, "barrel"))
    move(k.cyl(along(length - 0.028), along(length), radius * 0.98, radius * 0.94, "gunmetal", 8, 0.004, "brake"))
    return along(length)


def rail_rivets(k: Kit, plan: Plan, z: float, xs: Sequence[float], deck: float, r: float = 0.008) -> None:
    """A row of rivets down both flanks at height `z`."""
    across = scaled_at(z, deck)[1]
    for side in (-1.0, 1.0):
        k.rivets([(x, side * (plan.width(x) * across + 0.001), z) for x in xs], (0, side, 0), r)


def band(k: Kit, x0: float, x1: float, half_y: float, z: float, height: float = 0.026) -> None:
    """A bridge's window band, wrapped round a block."""
    k.box(((x0 + x1) / 2, 0, z), (x1 - x0, 2 * half_y, height), "glass", 0.002, label="windows")
