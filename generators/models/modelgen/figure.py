"""A general as a painted figure: parts in the army's colours on a skeleton.

Every bone stands straight up in the rest pose, so the game's `ActorPose3D` poses
it with the same angles it gives the old figure: +X on a limb swings it forward.
The clips live in the game, as pure functions of its clock. The figure faces +Y
here, which is the game's -Z, and its right hand is on +X.

A general's module is one `Look`: the row `CommanderLooks3D` holds for them, plus
the few things that row cannot say and a face needs (who they are, how old, how
they feel). Everything drawn from it is in this file, so the cast stays one family.
"""

from __future__ import annotations

import math
from dataclasses import dataclass, replace

import bmesh
import bpy
from mathutils import Euler, Matrix, Vector

from .kit import Kit
from .paint import Role

BONES = {
    "hips": None,
    "torso": "hips",
    "head": "torso",
    "arm_l": "torso",
    "fore_l": "arm_l",
    "arm_r": "torso",
    "fore_r": "arm_r",
    "prop": "fore_r",
    "leg_l": "hips",
    "shin_l": "leg_l",
    "leg_r": "hips",
    "shin_r": "leg_r",
}


@dataclass(frozen=True)
class Body:
    """A figure's proportions, in cells."""

    hip: float
    shoulder: float
    head_z: float
    head_r: float
    hip_w: float
    chest_w: float
    chest_d: float
    leg_r: float
    arm_r: float
    arm_len: float
    shoulder_x: float
    leg_x: float
    foot: float
    hem: float


# The landmarks are the game's own (`CommanderFigure3D`): hips at 0.19, shoulders
# at 0.345, the head's pivot at 0.37, eyes near 0.475 and the crown at 0.62, so
# every framing and portrait lens written for the figure still holds.
CHIBI = Body(
    hip=0.19,
    shoulder=0.345,
    head_z=0.47,
    head_r=0.128,
    hip_w=0.082,
    chest_w=0.09,
    chest_d=0.062,
    leg_r=0.033,
    arm_r=0.026,
    arm_len=0.17,
    shoulder_x=0.13,
    leg_x=0.05,
    foot=0.05,
    hem=0.115,
)

# `CommanderLooks3D`'s tables: `portraitgen/head.py` SKIN_BASES, `portraitgen/hair.py` HAIR_BASES.
SKIN_BASES = {
    "dark": (138, 90, 60),
    "light": (242, 201, 160),
    "medium": (217, 160, 102),
    "pale": (246, 220, 194),
    "tan": (198, 134, 66),
}
HAIR_BASES = {
    "auburn": (140, 74, 47),
    "black": (38, 38, 38),
    "blonde": (224, 184, 76),
    "brown": (90, 60, 40),
    "darkbrown": (51, 37, 26),
    "grey": (189, 189, 189),
    "platinum": (231, 224, 204),
    "steel": (165, 165, 165),
}
SKIN_CONTRAST = 34.0
HAIR_RUNGS = (1.0, 0.68, 0.40)

IRISES = {
    "blue": (0.05, 0.2, 0.34),
    "ice": (0.2, 0.42, 0.55),
    "green": (0.07, 0.27, 0.13),
    "hazel": (0.24, 0.17, 0.05),
    "brown": (0.13, 0.06, 0.025),
    "dark": (0.035, 0.022, 0.018),
    "grey": (0.2, 0.24, 0.27),
    "amber": (0.42, 0.22, 0.04),
    "cyan": (0.05, 0.36, 0.46),
}


@dataclass(frozen=True)
class Look:
    """The row `CommanderLooks3D` holds, then what only a face can say."""

    skin: str
    hair: str
    style: str
    acc: str
    acc2: str
    facial: str
    collar: str
    chest: str
    prop: str
    woman: bool = False
    age: str = "adult"  # young, adult, old
    mood: str = "calm"  # a key of MOODS
    iris: str = "brown"
    jaw: str = "round"  # a key of JAWS
    build: float = 1.0  # shoulders and limbs; the landmarks do not move
    gloves: bool = False
    boots: str = "boot"
    side: float = 1.0  # which way hair is swept or hung: +1 is the figure's right
    freckles: bool = False
    scar_side: float = 1.0

    def wears(self, *names: str) -> bool:
        return self.acc in names or self.acc2 in names


def look(row: str, **traits) -> Look:
    """A `Look` from its `CommanderLooks3D` row, written as the game writes it."""
    return Look(*row.split(), **traits)


def body_of(lk: Look) -> Body:
    """Width is the only thing a body may vary: every height is a landmark."""
    s = lk.build
    return replace(
        CHIBI,
        hip_w=CHIBI.hip_w * (0.5 + s * 0.5),
        chest_w=CHIBI.chest_w * s,
        chest_d=CHIBI.chest_d * s,
        leg_r=CHIBI.leg_r * (0.5 + s * 0.5),
        arm_r=CHIBI.arm_r * s,
        hem=CHIBI.hem if lk.woman else CHIBI.hem + 0.012,
    )


def linear(r: int, g: int, b: int) -> tuple[float, float, float]:
    def one(c: int) -> float:
        v = c / 255
        return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4

    return (one(r), one(g), one(b))


def _luma(rgb: tuple[float, float, float]) -> float:
    return 0.299 * rgb[0] + 0.587 * rgb[1] + 0.114 * rgb[2]


def stood_off(hair: tuple[int, int, int], skin: tuple[int, int, int]) -> tuple[int, int, int]:
    """`CommanderLooks3D.stood_off`: a hair mass never ties with the cheek it frames."""
    tone = hair
    for rung in HAIR_RUNGS:
        tone = tuple(round(c * rung) for c in hair)
        if abs(_luma(tone) - _luma(skin)) >= SKIN_CONTRAST:
            break
    return tone


def _times(rgb, factors) -> tuple[float, float, float]:
    return tuple(c * m for c, m in zip(rgb, factors))


def _mix(a, b, t: float) -> tuple[float, float, float]:
    return tuple(x + (y - x) * t for x, y in zip(a, b))


def looks_roles(lk: Look) -> dict[str, Role]:
    skin = SKIN_BASES[lk.skin]
    skin_lin = linear(*skin)
    # Hair or a hood closed round the face shades it a good deal: paint against that.
    if lk.style in ("bob", "hood"):
        lift = min(1.3, 1.0 / max(skin_lin))
        skin_lin = tuple(c * lift for c in skin_lin)
    hair_lin = tuple(max(c, 0.024) for c in linear(*stood_off(HAIR_BASES[lk.hair], skin)))
    if lk.hair == "blonde":
        # A rung down, blonde goes olive under the wash: hold on to its warmth.
        hair_lin = _times(hair_lin, (1.2, 1.02, 0.8))
    lit = tuple(min(1.0, c * 1.2 + 0.018) for c in hair_lin)
    mouth = (0.34, 0.09, 0.08) if lk.woman else _times(skin_lin, (0.34, 0.2, 0.18))
    plain = {"edge": 0.0, "dust": 0.0}
    # A mark is a run of overlapping dots: any wash would pool between them and bead it.
    mark = {"edge": 0.0, "dust": 0.0, "wash": 0.0}
    return {
        "skin": Role(skin_lin, wash=0.55, **plain),
        "lid": Role(skin_lin, **mark),
        "crease": Role(_times(skin_lin, (0.62, 0.5, 0.46)), **mark),
        "sheen": Role(tuple(min(1.0, c * 1.2 + 0.03) for c in skin_lin), **mark),
        "blush": Role(_times(skin_lin, (1.0, 0.62, 0.58)), wash=0.2, **plain),
        "hair": Role(hair_lin, wash=1.0, **plain),
        "hair_lit": Role(lit, **mark),
        "brow": Role(_times(hair_lin, (0.62, 0.6, 0.6)), **mark),
        "stubble": Role(_mix(skin_lin, hair_lin, 0.26), **mark),
        "scar": Role(_mix(skin_lin, (0.42, 0.1, 0.09), 0.72), **mark),
        "eye_white": Role((0.86, 0.86, 0.82), wash=0.25, **plain),
        "iris": Role(IRISES[lk.iris], wash=0.1, **plain),
        "ink": Role((0.012, 0.01, 0.012), wash=0.0, **plain),
        "spark": Role((1.0, 1.0, 1.0), wash=0.0, **plain),
        "lip": Role(mouth, **mark),
        "gold": Role((0.62, 0.43, 0.13), edge=1.4, wash=0.7, dust=0.0),
        "gilt": Role((0.72, 0.5, 0.16), **mark),
        "boot": Role((0.045, 0.03, 0.025), edge=1.3, dust=0.12),
        "shirt": Role((0.72, 0.68, 0.58), edge=0.3, wash=0.7, dust=0.0),
        "strap": Role((0.2, 0.105, 0.05), edge=1.2, wash=0.8, dust=0.1),
        "lens": Role((0.34, 0.56, 0.68), edge=0.6, wash=0.2, dust=0.0),
        "shade": Role((0.08, 0.3, 0.17), edge=0.7, wash=0.5, dust=0.0),
        "ember": Role((1.0, 0.36, 0.06), edge=0.0, wash=0.0, dust=0.0),
        "ribbon": Role((0.5, 0.05, 0.05), edge=0.8, wash=0.7, dust=0.0),
        "cover_red": Role((0.28, 0.035, 0.03), edge=1.2, dust=0.0),
        "cover_green": Role((0.04, 0.14, 0.06), edge=1.2, dust=0.0),
        "olive": Role((0.11, 0.14, 0.06), edge=1.2, dust=0.1),
    }


def ellipse(rx: float, ry: float, n: int = 14, cx: float = 0.0, cy: float = 0.0) -> list[tuple[float, float]]:
    return [(cx + rx * math.cos(math.tau * i / n), cy + ry * math.sin(math.tau * i / n)) for i in range(n)]


def rigid(bone: str):
    return lambda _co: {bone: 1.0}


def along(upper: str, lower: str, joint_z: float, blend: float = 0.02):
    """Two bones meeting at a height: a soft elbow or knee."""

    def weigh(co: Vector) -> dict[str, float]:
        t = (joint_z + blend - co.z) / (2 * blend)
        t = max(0.0, min(1.0, t))
        out = {}
        if t < 1.0:
            out[upper] = 1.0 - t
        if t > 0.0:
            out[lower] = t
        return out

    return weigh


def pivots(b: Body) -> dict[str, tuple[float, float, float]]:
    knee = b.hip * 0.48
    elbow = b.shoulder - b.arm_len * 0.5
    hand = b.shoulder - b.arm_len
    return {
        "hips": (0, 0, b.hip),
        "torso": (0, 0, b.hip + 0.035),
        "head": (0, 0, b.hip + 0.18),
        "arm_l": (-b.shoulder_x, 0, b.shoulder),
        "fore_l": (-b.shoulder_x - 0.012, 0, elbow),
        "arm_r": (b.shoulder_x, 0, b.shoulder),
        "fore_r": (b.shoulder_x + 0.012, 0, elbow),
        "prop": (b.shoulder_x + 0.018, 0, hand),
        "leg_l": (-b.leg_x, 0, b.hip),
        "shin_l": (-b.leg_x, 0, knee),
        "leg_r": (b.leg_x, 0, b.hip),
        "shin_r": (b.leg_x, 0, knee),
    }


# ---------------------------------------------------------------------- paint on a surface


class Paint:
    """Marks only the bake sees: little domes laid on a form and turned to its normal.

    They are merged per role into one part, so a face can spend hundreds of them.
    """

    def __init__(self) -> None:
        self.dots: dict[str, list] = {}

    def put(
        self, role: str, at: Vector, normal: Vector, w: float, h: float, roll: float = 0.0, sides: int = 10
    ) -> None:
        self.dots.setdefault(role, []).append((at, normal, w, h, roll, sides))

    def flush(self, k: Kit) -> None:
        for role, dots in self.dots.items():
            bm = bmesh.new()
            for dot in dots:
                _dome(bm, *dot)
            k._finish(bm, role, 0.0, "paint")
        self.dots = {}


def _dome(bm, at: Vector, normal: Vector, w: float, h: float, roll: float, sides: int) -> None:
    up = Vector((0, 0, 1)) if abs(normal.z) < 0.92 else Vector((0, 1, 0))
    v = (up - normal * up.dot(normal)).normalized()
    u = normal.cross(v).normalized()
    across = u * math.cos(roll) + v * math.sin(roll)
    upward = v * math.cos(roll) - u * math.sin(roll)
    rim = [
        bm.verts.new(at + across * (w * math.cos(math.tau * i / sides)) + upward * (h * math.sin(math.tau * i / sides)))
        for i in range(sides)
    ]
    # Shallow, so a line of them shades as one stroke of paint rather than as beads.
    apex = bm.verts.new(at + normal * min(0.0012, min(w, h) * 0.12))
    base = bm.verts.new(at - normal * 0.003)
    for i in range(sides):
        j = (i + 1) % sides
        bm.faces.new((apex, rim[i], rim[j]))
        bm.faces.new((base, rim[j], rim[i]))


# How far a mark stands off the skull, in cells: what covers what. All of it stays
# inside the bake's cage.
UNDER = 0.0003
SKIN_MARK = 0.0008
WHITE = 0.0014
IRIS = 0.0026
PUPIL = 0.0038
SPARK = 0.0048
LID = 0.0058
LASH = 0.0068
BROW = 0.0076
RIM = 0.0084
OVER = 0.0092


JAWS = {
    "round": (2.0, 0.0),
    "heart": (1.72, -0.02),
    "soft": (2.25, 0.03),
    "lean": (1.9, -0.05),
    "square": (2.9, 0.06),
}


@dataclass(frozen=True)
class Skull:
    """The head as one egg, its jaw a superellipse. `u` and `v` are in head radii."""

    z: float
    r: float
    chin: float
    jaw: float
    rx: float = 0.97
    ry: float = 0.93
    rz: float = 1.02

    def spans(self, v: float) -> tuple[float, float]:
        t = min(abs(v) / self.rz, 1.0)
        e = self.chin if v < 0.0 else 2.0
        s = max(1.0 - t**e, 0.0) ** (1.0 / e)
        wide = 1.0 + self.jaw * math.sin(t * math.pi) if v < 0.0 else 1.0
        return self.rx * s * wide, self.ry * s

    def front(self, u: float, v: float) -> float:
        across, deep = self.spans(v)
        if across <= 0.0:
            return 0.0
        return deep * math.sqrt(max(1.0 - (u / across) ** 2, 0.02))

    def at(self, u: float, v: float, lift: float = 0.0) -> Vector:
        return Vector((u * self.r, self.front(u, v) * self.r, self.z + v * self.r)) + self.normal(u, v) * lift

    def normal(self, u: float, v: float) -> Vector:
        d = 0.03
        du = (self.front(u + d, v) - self.front(u - d, v)) / (2 * d)
        dv = (self.front(u, v + d) - self.front(u, v - d)) / (2 * d)
        return Vector((-du, 1.0, -dv)).normalized()

    def rings(self, count: int) -> list[float]:
        return [self.rz * math.sin(-math.radians(84) + math.radians(168) * i / (count - 1)) for i in range(count)]


def skull_of(lk: Look, b: Body) -> Skull:
    chin, jaw = JAWS[lk.jaw]
    return Skull(b.head_z, b.head_r, chin, jaw)


# ---------------------------------------------------------------------- legs, coat, arms


def build_legs(k: Kit, b: Body, lk: Look) -> None:
    knee = b.hip * 0.48
    for side, leg, shin in ((-1.0, "leg_l", "shin_l"), (1.0, "leg_r", "shin_r")):
        x = side * b.leg_x
        trouser = k.tube(
            [
                ((x, 0, b.hip + 0.01), b.leg_r * 1.1, b.leg_r * 1.15),
                ((x, 0, b.hip * 0.72), b.leg_r, b.leg_r * 1.05),
                ((x, 0.002, knee + 0.012), b.leg_r * 0.88, b.leg_r * 0.92),
                ((x, 0.002, knee - 0.012), b.leg_r * 0.86, b.leg_r * 0.92),
                ((x, 0, b.foot + 0.012), b.leg_r * 0.8, b.leg_r * 0.86),
            ],
            "team_dark",
            label="trouser",
        )
        k.bind(trouser, along(leg, shin, knee))
        boot = k.loft(
            [
                (0.0, ellipse(b.leg_r * 0.95, b.leg_r * 1.75, 12, x, 0.014)),
                (0.016, ellipse(b.leg_r * 0.98, b.leg_r * 1.72, 12, x, 0.014)),
                (b.foot * 0.75, ellipse(b.leg_r * 0.92, b.leg_r * 1.16, 12, x, 0.004)),
                (b.foot + 0.03, ellipse(b.leg_r * 0.94, b.leg_r * 1.0, 12, x, 0.0)),
            ],
            lk.boots,
            0.004,
            label="boot",
        )
        k.bind(boot, rigid(shin))


def _coat_rings(b: Body, lk: Look) -> list[tuple[float, float, float]]:
    chest = b.shoulder - 0.03
    waist = b.hip + (b.shoulder - b.hip) * 0.28
    flare = 1.25 if lk.woman else 1.14
    return [
        (b.hem, b.hip_w * flare, b.chest_d * (1.2 if lk.woman else 1.12)),
        (b.hip, b.hip_w * 1.03, b.chest_d * 0.98),
        (waist, b.chest_w * (0.82 if lk.woman else 0.9), b.chest_d * 0.82),
        (chest, b.chest_w, b.chest_d),
        (b.shoulder + 0.006, b.chest_w * 0.9, b.chest_d * 0.82),
        (b.shoulder + 0.022, b.chest_w * 0.42, b.chest_d * 0.5),
    ]


@dataclass
class Torso:
    """Where the coat's surface is, so what is worn on it can lie on it."""

    k: Kit
    b: Body
    lk: Look
    rings: list[tuple[float, float, float]]

    @property
    def waist(self) -> float:
        return self.rings[2][0]

    def span(self, z: float) -> tuple[float, float]:
        for (z0, x0, y0), (z1, x1, y1) in zip(self.rings, self.rings[1:]):
            if z <= z1:
                t = max(0.0, min(1.0, (z - z0) / (z1 - z0)))
                return (x0 + (x1 - x0) * t, y0 + (y1 - y0) * t)
        return self.rings[-1][1:]

    def at(self, x: float, z: float, lift: float = 0.0, back: bool = False) -> Vector:
        rx, ry = self.span(z)
        y = (ry + lift) * math.sqrt(max(1.0 - (x / (rx + lift)) ** 2, 0.04))
        return Vector((x, -y if back else y, z))

    def weigh(self, co: Vector) -> dict[str, float]:
        return {"hips": 1.0} if co.z < self.b.hip else {"torso": 1.0}

    def strap(self, points, width: float, role: str, lift: float = 0.004, back: bool = False, sides: int = 6):
        """A flat band lying on the coat, through (x, z) points."""
        path = [(self.at(x, z, lift, back), width / 2, 0.0045) for x, z in points]
        part = self.k.tube(path, role, sides, "strap")
        return self.k.bind(part, self.weigh)

    def box(self, x: float, z: float, size, role: str, lift: float = 0.004, bevel: float = 0.003, tilt: float = 0.0):
        part = self.k.box(self.at(x, z, lift), size, role, bevel, label="kit")
        if tilt:
            part.matrix_world = part.matrix_world @ Matrix.Rotation(tilt, 4, "Y")
        return self.k.bind(part, self.weigh)

    def stud(self, x: float, z: float, r: float, role: str = "gold", lift: float = 0.005, back: bool = False) -> None:
        """A button only the bake sees."""
        if self.k.hi:
            self.k.ellipsoid(self.at(x, z, lift, back), (r, 0.0045, r), role, 3, 8, "stud")

    def diagonal(self, width: float, role: str, top: float = 0.0) -> None:
        """From the left shoulder to the right hip, front and back."""
        b = self.b
        z0, z1 = b.shoulder + 0.004 + top, b.hip + 0.012
        points = [(-b.chest_w * 0.66 + (b.chest_w * 1.5) * i / 5, z0 + (z1 - z0) * i / 5) for i in range(6)]
        self.strap(points, width, role)
        self.strap(points, width, role, back=True)

    def on_diagonal(self, t: float) -> tuple[float, float]:
        b = self.b
        z0, z1 = b.shoulder + 0.004, b.hip + 0.012
        return (-b.chest_w * 0.66 + b.chest_w * 1.5 * t, z0 + (z1 - z0) * t)


def build_torso(k: Kit, b: Body, lk: Look) -> Torso:
    rings = _coat_rings(b, lk)
    t = Torso(k, b, lk, rings)
    coat = k.loft([(z, ellipse(rx, ry)) for z, rx, ry in rings], "team", 0.006, label="coat")
    k.bind(coat, t.weigh)
    belt_z = t.waist - 0.006
    rx, ry = t.span(belt_z)
    belt = k.loft(
        [(belt_z - 0.012, ellipse(rx * 1.05, ry * 1.06)), (belt_z + 0.012, ellipse(rx * 1.05, ry * 1.06))],
        "boot",
        0.003,
        label="belt",
    )
    k.bind(belt, rigid("torso"))
    buckle = k.box((0, ry * 1.06, belt_z), (0.03, 0.008, 0.024), "gold", 0.002, label="buckle")
    k.bind(buckle, rigid("torso"))
    # What a coat is cut with, so the bake's wash has somewhere to pool.
    if k.hi:
        for side in (-1.0, 1.0):
            k.seam((side * b.chest_w * 0.72, -b.chest_d * 0.5, b.hip + 0.06), (0.004, 0.004, 0.08), "team_dark")
    _collar(t)
    CHESTS[lk.chest](t)
    return t


def _collar(t: Torso) -> None:
    k, b, lk = t.k, t.b, t.lk
    if lk.collar == "mandarin":
        ring = k.loft(
            [
                (b.shoulder + 0.006, ellipse(b.chest_w * 0.6, b.chest_d * 0.74)),
                (b.shoulder + 0.05, ellipse(b.chest_w * 0.5, b.chest_d * 0.62)),
            ],
            "team_dark",
            0.004,
            label="collar",
        )
        k.bind(ring, rigid("torso"))
        t.stud(0, b.shoulder - 0.012, 0.008)
        return
    ring = k.loft(
        [
            (b.shoulder + 0.01, ellipse(b.chest_w * 0.52, b.chest_d * 0.62)),
            (b.shoulder + 0.038, ellipse(b.chest_w * 0.46, b.chest_d * 0.56)),
        ],
        "team_dark",
        0.004,
        label="collar",
    )
    k.bind(ring, rigid("torso"))
    # The open V: a shirt wedge with a lapel down either side of it.
    wide = 0.034 if lk.collar == "v" else 0.044
    top, low = b.shoulder + 0.004, b.shoulder - (0.056 if lk.collar == "v" else 0.05)
    front = t.at(0, top - 0.02).y
    wedge = k.side_profile(
        [(-wide, top), (wide, top), (0.0, low)], front - 0.006, front + 0.0032, "shirt", 0.0, "shirt"
    )
    k.bind(wedge, rigid("torso"))
    lapel = 0.018 if lk.collar == "v" else 0.026
    for side in (-1.0, 1.0):
        t.strap(
            [(side * wide * 1.05, top), (side * wide * 0.56, top - 0.028), (side * 0.004, low - 0.002)],
            lapel,
            "team_dark",
            0.005,
        )
    if lk.collar == "double":
        for row in range(3):
            for side in (-1.0, 1.0):
                t.stud(side * 0.036, t.waist + 0.024 + row * 0.03, 0.0085)
    elif lk.chest != "placket":
        for dz in (0.0, 0.028):
            t.stud(0, t.waist + 0.026 + dz, 0.0075)


def _shoulder_plates(t: Torso, size, role: str, bevel: float) -> list[float]:
    b = t.b
    for side in (-1.0, 1.0):
        plate = t.k.box((side * b.shoulder_x * 0.98, 0, b.shoulder + 0.022), size, role, bevel, label="shoulder")
        t.k.bind(plate, rigid("torso"))
    return [-1.0, 1.0]


def _chest_plain(t: Torso) -> None:
    b = t.b
    # Two flapped pockets, big enough to be the coat's only feature.
    if t.k.hi:
        for side in (-1.0, 1.0):
            at = t.at(side * b.chest_w * 0.46, t.waist + 0.044, 0.002)
            t.k.box(at, (0.05, 0.005, 0.007), "team_dark", 0.0, label="pocket")
            t.k.box(at + Vector((0, 0, -0.03)), (0.05, 0.005, 0.005), "team_dark", 0.0, label="pocket")
            t.stud(side * b.chest_w * 0.46, t.waist + 0.038, 0.006, "gold", 0.004)


def _chest_sash(t: Torso) -> None:
    t.diagonal(0.044, "team_light")
    x, z = t.on_diagonal(0.98)
    knot = t.k.ellipsoid(t.at(x, z, 0.006), (0.026, 0.014, 0.026), "gold", 4, 8, "rosette")
    t.k.bind(knot, t.weigh)
    _shoulder_plates(t, (0.05, 0.05, 0.014), "gold", 0.005)


def _chest_placket(t: Torso) -> None:
    b = t.b
    z0, z1 = b.hip + 0.02, b.shoulder - 0.018
    t.strap([(0, z0), (0, (z0 + z1) / 2), (0, z1)], 0.042, "team_dark", 0.003)
    for i in range(3):
        t.stud(0, t.waist + 0.024 + i * 0.03, 0.011, "gold", 0.008)


def _chest_loops(t: Torso) -> None:
    z = t.waist + 0.05
    rx = t.span(z)[0]
    t.strap([(-rx * 0.92 + 1.84 * rx * i / 6, z) for i in range(7)], 0.03, "strap", 0.003)
    for i in range(5):
        x = -rx * 0.62 + rx * 1.24 * i / 4
        t.box(x, z, (0.015, 0.012, 0.042), "brass", 0.007, 0.002)


def _chest_crossbelt(t: Torso) -> None:
    t.diagonal(0.03, "strap")
    x, z = t.on_diagonal(0.5)
    t.box(x, z, (0.034, 0.012, 0.03), "brass", 0.006, 0.003, -0.6)


def _chest_bandolier(t: Torso) -> None:
    t.diagonal(0.05, "strap")
    for i in range(5):
        x, z = t.on_diagonal(0.22 + i * 0.15)
        t.box(x, z, (0.018, 0.012, 0.036), "brass", 0.008, 0.002, -0.6)


def _chest_boards(t: Torso) -> None:
    for side in _shoulder_plates(t, (0.068, 0.092, 0.016), "team_dark", 0.004):
        stripe = t.k.box(
            (side * t.b.shoulder_x * 0.98, 0, t.b.shoulder + 0.031), (0.07, 0.024, 0.006), "gold", 0.0, label="stripe"
        )
        t.k.bind(stripe, rigid("torso"))
    t.stud(0, t.waist + 0.026, 0.009)
    t.stud(0, t.waist + 0.054, 0.009)


def _chest_epaulette(t: Torso) -> None:
    b = t.b
    for side in _shoulder_plates(t, (0.08, 0.1, 0.02), "gold", 0.007):
        for i in range(4):
            y = -0.036 + 0.024 * i
            fringe = t.k.box(
                (side * (b.shoulder_x + 0.036), y, b.shoulder + 0.0), (0.012, 0.018, 0.04), "gold", 0.0, label="fringe"
            )
            t.k.bind(fringe, rigid("torso"))


def _chest_lanyard(t: Torso) -> None:
    b = t.b
    badge_z = t.waist + 0.036
    for side in (-1.0, 1.0):
        t.strap(
            [(side * 0.04, b.shoulder), (side * 0.022, b.shoulder - 0.03), (0, badge_z + 0.02)],
            0.013,
            "gold",
            0.004,
            sides=4,
        )
    t.box(0, badge_z, (0.046, 0.006, 0.054), "shirt", 0.005, 0.002)
    if t.k.hi:
        at = t.at(0, badge_z + 0.01, 0.009)
        t.k.box(at, (0.022, 0.003, 0.016), "team_dark", 0.0, label="photo")


def _chest_pouch(t: Torso) -> None:
    b = t.b
    z = t.waist + 0.012
    t.box(b.chest_w * 0.52, z - 0.03, (0.064, 0.032, 0.058), "strap", 0.012, 0.006)
    t.box(b.chest_w * 0.52, z - 0.01, (0.07, 0.036, 0.024), "strap", 0.016, 0.005)
    t.stud(b.chest_w * 0.52, z - 0.012, 0.009, "brass", 0.036)
    t.strap([(-b.chest_w * 0.5, b.shoulder), (-b.chest_w * 0.5, t.waist + 0.012)], 0.02, "strap")
    t.stud(0, t.waist + 0.04, 0.008)


def _chest_scarf(t: Torso) -> None:
    k, b = t.k, t.b
    wrap = k.loft(
        [
            (b.shoulder - 0.006, ellipse(b.chest_w * 0.82, b.chest_d * 0.9)),
            (b.shoulder + 0.018, ellipse(b.chest_w * 0.9, b.chest_d * 1.02)),
            (b.shoulder + 0.05, ellipse(b.chest_w * 0.68, b.chest_d * 0.82)),
        ],
        "team_light",
        0.01,
        label="scarf",
    )
    k.bind(wrap, rigid("torso"))
    x = -b.chest_w * 0.44
    t.strap(
        [
            (x, b.shoulder - 0.004),
            (x - 0.004, b.shoulder - 0.05),
            (x + 0.006, t.waist + 0.012),
            (x + 0.012, b.hip - 0.02),
        ],
        0.052,
        "team_light",
        0.006,
        sides=8,
    )
    if k.hi:
        for i in range(3):
            k.box(
                t.at(x + 0.01, b.hip - 0.004 - i * 0.008, 0.012), (0.05, 0.003, 0.003), "team_dark", 0.0, label="fray"
            )


def _chest_harness(t: Torso) -> None:
    b = t.b
    for side in (-1.0, 1.0):
        x = side * b.chest_w * 0.55
        for back in (False, True):
            t.strap(
                [(x, b.shoulder + 0.008), (x, (b.shoulder + b.hip) / 2), (x, b.hip + 0.04)], 0.028, "strap", back=back
            )
    z = t.waist + 0.054
    t.strap([(-b.chest_w * 0.6, z), (0, z), (b.chest_w * 0.6, z)], 0.024, "strap", 0.006)
    t.box(0, z, (0.034, 0.012, 0.034), "brass", 0.008, 0.004)


def _chest_mapcase(t: Torso) -> None:
    b = t.b
    t.diagonal(0.022, "strap")
    k = t.k
    at = Vector((-b.chest_w * 0.72, t.at(-b.chest_w * 0.72, b.hip).y + 0.012, b.hip - 0.012))
    case = k.box(at, (0.086, 0.03, 0.08), "canvas", 0.006, label="case")
    k.bind(case, rigid("torso"))
    flap = k.box(at + Vector((0, 0.003, 0.024)), (0.09, 0.034, 0.036), "canvas", 0.005, label="flap")
    k.bind(flap, rigid("torso"))
    stud = k.box(at + Vector((0, 0.021, 0.012)), (0.014, 0.004, 0.016), "brass", 0.001, label="catch")
    k.bind(stud, rigid("torso"))
    if k.hi:
        k.box(at + Vector((0.0, 0.016, -0.018)), (0.06, 0.003, 0.03), "bone", 0.0, label="map")


CHESTS = {
    "plain": _chest_plain,
    "sash": _chest_sash,
    "placket": _chest_placket,
    "loops": _chest_loops,
    "crossbelt": _chest_crossbelt,
    "bandolier": _chest_bandolier,
    "boards": _chest_boards,
    "epaulette": _chest_epaulette,
    "lanyard": _chest_lanyard,
    "pouch": _chest_pouch,
    "scarf": _chest_scarf,
    "harness": _chest_harness,
    "mapcase": _chest_mapcase,
}


def build_arms(k: Kit, b: Body, lk: Look) -> None:
    elbow = b.shoulder - b.arm_len * 0.5
    hand = b.shoulder - b.arm_len
    for side, arm, fore in ((-1.0, "arm_l", "fore_l"), (1.0, "arm_r", "fore_r")):
        x0 = side * b.shoulder_x
        x1 = side * (b.shoulder_x + 0.012)
        x2 = side * (b.shoulder_x + 0.018)
        sleeve = k.tube(
            [
                ((x0 * 0.92, 0, b.shoulder + 0.02), b.arm_r * 0.5, b.arm_r * 0.6),
                ((x0, 0, b.shoulder + 0.008), b.arm_r * 1.1, b.arm_r * 1.15),
                ((x1, 0, elbow + 0.018), b.arm_r, b.arm_r),
                ((x1, 0, elbow - 0.018), b.arm_r * 0.94, b.arm_r * 0.96),
                ((x2, 0.002, hand + 0.02), b.arm_r * 0.9, b.arm_r * 0.9),
            ],
            "team",
            label="sleeve",
        )
        k.bind(sleeve, along(arm, fore, elbow))
        cuff = k.tube(
            [
                ((x2, 0.002, hand + 0.03), b.arm_r * 1.03, b.arm_r * 1.03),
                ((x2, 0.002, hand + 0.012), b.arm_r * 1.03, b.arm_r * 1.03),
            ],
            "team_dark",
            label="cuff",
        )
        k.bind(cuff, rigid(fore))
        hand_role = "boot" if lk.gloves else "skin"
        glove = k.ellipsoid(
            (x2, 0.002, hand - 0.012), (b.arm_r * 0.92, b.arm_r, b.arm_r * 1.25), hand_role, 6, 8, "glove"
        )
        k.bind(glove, rigid(fore))


# ---------------------------------------------------------------------- what is in the hand


class Held:
    """A prop's frame: the fist at the origin, -Z out of its bottom and tipped forward.

    At this tip the frame's XZ plane faces the board camera square on, so a prop is
    drawn flat in XZ and +Y is toward the lens. That keeps a blade's full length and a
    card's whole face on the board, where a straight-down hang would foreshorten them.
    """

    TIP = 0.8

    def __init__(self, k: Kit, b: Body) -> None:
        self.k = k
        x = b.shoulder_x + 0.018
        z = b.shoulder - b.arm_len - 0.012
        self.frame = Matrix.Translation((x, 0.002, z)) @ Matrix.Rotation(self.TIP, 4, "X")

    def _own(self, part):
        part.matrix_world = self.frame @ part.matrix_world
        return self.k.bind(part, rigid("prop"))

    def box(self, at, size, role, bevel=0.003, taper=1.0):
        return self._own(self.k.box(at, size, role, bevel, taper, label="prop"))

    def egg(self, at, radii, role, rings=5, sides=8):
        return self._own(self.k.ellipsoid(at, radii, role, rings, sides, "prop"))

    def flat(self, outline, role, depth=0.012, bevel=0.003, y=0.0):
        return self._own(self.k.side_profile(outline, y - depth / 2, y + depth / 2, role, bevel, "prop"))

    def cyl(self, p0, p1, r0, r1=None, role="steel", sides=8, bevel=0.0):
        a, c = self.frame @ Vector(p0), self.frame @ Vector(p1)
        return self.k.bind(self.k.cyl(a, c, r0, r1, role, sides, bevel, "prop"), rigid("prop"))

    def disc(self, x, y, z, r, role, depth=0.008, sides=10):
        return self.cyl((x, y - depth / 2, z), (x, y + depth / 2, z), r, None, role, sides, 0.001)

    def mark(self, at, size, role, turn: float = 0.0) -> None:
        """Print on the prop, for the bake alone; `turn` spins it about the prop's face."""
        if self.k.hi:
            part = self.box(at, size, role, 0.0)
            part.matrix_world = part.matrix_world @ Matrix.Rotation(turn, 4, "Y")


def _prop_none(_p: Held) -> None:
    pass


def _prop_sabre(p: Held) -> None:
    p.cyl((0, 0, 0.022), (0, 0, -0.03), 0.01, None, "boot", 6)
    p.box((0, 0, -0.034), (0.056, 0.022, 0.012), "gold", 0.003)
    p.flat(
        [
            (-0.013, -0.04),
            (0.013, -0.04),
            (0.019, -0.11),
            (0.012, -0.18),
            (0.004, -0.205),
            (-0.006, -0.17),
            (-0.011, -0.1),
        ],
        "steel",
        0.009,
        0.0015,
    )


def _prop_dagger(p: Held) -> None:
    p.cyl((0, 0, 0.018), (0, 0, -0.022), 0.01, None, "boot", 6)
    p.box((0, 0, -0.026), (0.044, 0.018, 0.011), "gold", 0.003)
    p.flat([(-0.014, -0.03), (0.014, -0.03), (0.012, -0.08), (0.0, -0.118), (-0.012, -0.08)], "steel", 0.01, 0.0015)


def _prop_baton(p: Held) -> None:
    p.cyl((0, 0, 0.03), (0, 0, -0.13), 0.012, None, "boot", 8)
    for z in (0.03, -0.13):
        p.cyl((0, 0, z + 0.01), (0, 0, z - 0.01), 0.016, None, "gold", 8, 0.002)


def _prop_axe(p: Held) -> None:
    p.cyl((0, 0, 0.03), (0, 0, -0.205), 0.0115, None, "wood", 8)
    head = [
        (-0.012, -0.186),
        (0.03, -0.19),
        (0.074, -0.22),
        (0.09, -0.16),
        (0.074, -0.098),
        (0.03, -0.128),
        (-0.012, -0.134),
    ]
    p.flat(head, "steel", 0.014, 0.002)
    p.flat([(-0.03, -0.17), (-0.012, -0.186), (-0.012, -0.14), (-0.03, -0.155)], "steel", 0.012, 0.002)


def _prop_hammer(p: Held) -> None:
    p.cyl((0, 0, 0.03), (0, 0, -0.17), 0.0115, None, "wood", 8)
    p.box((0, 0, -0.178), (0.104, 0.05, 0.054), "gunmetal", 0.006)
    for side in (-1.0, 1.0):
        p.box((side * 0.057, 0, -0.178), (0.012, 0.056, 0.06), "steel", 0.003)


def _prop_wrench(p: Held) -> None:
    p.box((0, 0, -0.065), (0.024, 0.012, 0.15), "steel", 0.003)
    jaw = [
        (-0.03, -0.128),
        (0.03, -0.128),
        (0.04, -0.158),
        (0.03, -0.19),
        (0.013, -0.19),
        (0.012, -0.156),
        (-0.012, -0.156),
        (-0.013, -0.19),
        (-0.03, -0.19),
        (-0.04, -0.158),
    ]
    p.flat(jaw, "steel", 0.014, 0.003)
    p.egg((0, 0, 0.018), (0.02, 0.009, 0.02), "steel", 4, 8)


def _prop_anchor(p: Held) -> None:
    p.cyl((0, 0, 0.03), (0, 0, -0.17), 0.012, None, "gunmetal", 8)
    p.box((0, 0, -0.03), (0.086, 0.016, 0.016), "gunmetal", 0.004)
    arms = [
        (-0.076, -0.098),
        (-0.07, -0.145),
        (-0.04, -0.178),
        (0.0, -0.19),
        (0.04, -0.178),
        (0.07, -0.145),
        (0.076, -0.098),
        (0.05, -0.135),
        (0.0, -0.158),
        (-0.05, -0.135),
    ]
    p.flat(arms, "gunmetal", 0.018, 0.004)


def _prop_pipe(p: Held) -> None:
    p.cyl((0, 0.01, 0.0), (0, 0.01, -0.058), 0.0085, 0.0095, "boot", 6)
    p.cyl((0, -0.004, -0.076), (0, 0.042, -0.076), 0.024, 0.03, "wood", 10, 0.002)
    p.disc(0, 0.043, -0.076, 0.021, "ink", 0.003)
    p.disc(0, 0.045, -0.076, 0.011, "ember", 0.002)


def _prop_cigar(p: Held) -> None:
    p.cyl((0, 0.01, 0.0), (0, 0.01, -0.09), 0.014, 0.015, "leather", 8)
    p.cyl((0, 0.01, -0.09), (0, 0.01, -0.104), 0.0155, 0.012, "ember", 8)
    p.cyl((0, 0.01, -0.02), (0, 0.01, -0.03), 0.0155, None, "gold", 8)


def _prop_medal(p: Held) -> None:
    p.box((0, 0.012, -0.036), (0.038, 0.006, 0.062), "ribbon", 0.002)
    p.disc(0, 0.016, -0.09, 0.037, "gold", 0.01, 12)
    p.mark((0, 0.024, -0.09), (0.03, 0.002, 0.03), "ribbon")


def _prop_card(p: Held) -> None:
    p.box((0, 0.012, -0.058), (0.066, 0.006, 0.098), "shirt", 0.003)
    p.mark((0, 0.018, -0.058), (0.03, 0.003, 0.03), "team_dark", math.pi / 4)


def _book(p: Held, width: float, height: float, role: str) -> None:
    z = -height / 2 - 0.006
    p.box((0, 0.008, z), (width, 0.006, height), role, 0.002)
    p.box((0, 0.034, z), (width, 0.006, height), role, 0.002)
    p.box((-width / 2 + 0.002, 0.021, z), (0.006, 0.03, height), role, 0.002)
    p.box((0.002, 0.021, z), (width - 0.008, 0.022, height - 0.01), "bone", 0.0)


def _prop_book(p: Held) -> None:
    _book(p, 0.086, 0.104, "cover_red")
    p.mark((0, 0.0375, -0.04), (0.05, 0.002, 0.012), "gold")


def _prop_ledger(p: Held) -> None:
    _book(p, 0.1, 0.122, "cover_green")
    p.box((0, 0.039, -0.066), (0.104, 0.004, 0.018), "gold", 0.001)


def _prop_drone(p: Held) -> None:
    z = -0.054
    for a in (-1.0, 1.0):
        arm = p.k.box((0, 0.02, z), (0.13, 0.008, 0.012), "gunmetal", 0.001, label="prop")
        arm.matrix_world = Matrix.Rotation(a * math.pi / 4, 4, (0, 1, 0)) @ arm.matrix_world
        arm.matrix_world.translation = (0, 0.02, z)
        p._own(arm)
    p.box((0, 0.022, z), (0.05, 0.022, 0.05), "gunmetal", 0.008)
    p.disc(0, 0.036, z, 0.012, "lens", 0.004)
    for sx in (-1.0, 1.0):
        for sz in (-1.0, 1.0):
            p.disc(sx * 0.044, 0.028, z + sz * 0.044, 0.029, "lens", 0.005, 8)


def _prop_radio(p: Held) -> None:
    p.box((0, 0.018, -0.05), (0.06, 0.032, 0.096), "olive", 0.005)
    p.cyl((0.02, 0.018, -0.004), (0.02, 0.018, 0.08), 0.007, 0.004, "gunmetal", 6)
    p.mark((0, 0.036, -0.066), (0.04, 0.002, 0.03), "gunmetal")
    p.mark((-0.014, 0.036, -0.028), (0.016, 0.002, 0.012), "ember")


def _prop_helm(p: Held) -> None:
    p.egg((0, 0.028, -0.06), (0.062, 0.058, 0.05), "gunmetal", 6, 12)
    p.egg((0, 0.018, -0.086), (0.076, 0.07, 0.012), "gunmetal", 4, 12)
    p.mark((0, 0.08, -0.05), (0.03, 0.006, 0.024), "gold")


def _prop_plane(p: Held) -> None:
    p.cyl((0, 0.022, 0.024), (0, 0.022, -0.112), 0.017, 0.015, "steel", 8, 0.002)
    p.cyl((0, 0.022, -0.112), (0, 0.022, -0.132), 0.015, 0.005, "gold", 8)
    wings = [
        (-0.008, -0.1),
        (0.008, -0.1),
        (0.086, -0.038),
        (0.086, -0.018),
        (0.0, -0.044),
        (-0.086, -0.018),
        (-0.086, -0.038),
    ]
    p.flat(wings, "team_light", 0.009, 0.002, 0.022)
    p.flat(
        [(-0.038, 0.022), (0.038, 0.022), (0.03, 0.006), (0.0, -0.002), (-0.03, 0.006)],
        "team_light",
        0.008,
        0.002,
        0.022,
    )
    p.box((0, 0.038, 0.018), (0.008, 0.024, 0.024), "team", 0.002)


def _prop_coins(p: Held) -> None:
    p.egg((0, 0.016, -0.056), (0.05, 0.036, 0.052), "strap", 5, 10)
    p.cyl((0, 0.016, -0.008), (0, 0.016, 0.008), 0.02, 0.014, "gold", 6)
    p.disc(-0.022, 0.054, -0.058, 0.027, "gold", 0.007)
    p.disc(0.024, 0.06, -0.07, 0.027, "gold", 0.007)


def _prop_whistle(p: Held) -> None:
    p.cyl((-0.034, 0.016, -0.03), (0.02, 0.016, -0.03), 0.014, None, "brass", 8, 0.002)
    p.egg((0.022, 0.016, -0.034), (0.024, 0.02, 0.024), "brass", 5, 10)
    p.box((-0.01, 0.016, -0.012), (0.012, 0.012, 0.02), "ribbon", 0.002)


def _prop_compass(p: Held) -> None:
    p.disc(0, 0.016, -0.056, 0.042, "brass", 0.014, 12)
    p.disc(0, 0.026, -0.056, 0.033, "bone", 0.004, 12)
    p.box((0, 0.016, -0.01), (0.012, 0.008, 0.012), "brass", 0.002)
    p.mark((0.004, 0.03, -0.048), (0.008, 0.002, 0.03), "ribbon")
    p.mark((-0.004, 0.03, -0.066), (0.008, 0.002, 0.02), "gunmetal")


def _prop_scales(p: Held) -> None:
    p.cyl((0, 0.016, 0.014), (0, 0.016, -0.046), 0.008, None, "gold", 6)
    p.box((0, 0.016, -0.018), (0.15, 0.012, 0.012), "gold", 0.003)
    for side in (-1.0, 1.0):
        p.box((side * 0.068, 0.016, -0.05), (0.007, 0.007, 0.06), "gold", 0.0)
        p.disc(side * 0.068, 0.016, -0.09, 0.03, "gold", 0.01, 10)


def _prop_monocle(_p: Held) -> None:
    """Worn, not held: `_monocle` draws it on the face."""


PROPS = {
    "none": _prop_none,
    "sabre": _prop_sabre,
    "dagger": _prop_dagger,
    "baton": _prop_baton,
    "axe": _prop_axe,
    "hammer": _prop_hammer,
    "wrench": _prop_wrench,
    "anchor": _prop_anchor,
    "pipe": _prop_pipe,
    "cigar": _prop_cigar,
    "medal": _prop_medal,
    "card": _prop_card,
    "book": _prop_book,
    "ledger": _prop_ledger,
    "drone": _prop_drone,
    "radio": _prop_radio,
    "helm": _prop_helm,
    "plane": _prop_plane,
    "coins": _prop_coins,
    "whistle": _prop_whistle,
    "compass": _prop_compass,
    "scales": _prop_scales,
    "monocle": _prop_monocle,
}


# ---------------------------------------------------------------------- the head


@dataclass(frozen=True)
class Mood:
    brow_in: float
    brow_out: float
    arch: float
    lid: float  # how far the upper lid is down
    slant: float  # the lid's lean: positive is angry, negative is soft
    mouth: str
    width: float
    raise_one: float = 0.0  # one brow up, the other down


MOODS = {
    "smile": Mood(0.0, 0.0, 0.05, 0.0, 0.0, "smile", 0.14),
    "kind": Mood(0.03, -0.07, 0.06, 0.14, -0.14, "smile", 0.13),
    "calm": Mood(0.0, 0.0, 0.02, 0.12, 0.0, "flat", 0.1),
    "stern": Mood(-0.06, 0.04, 0.0, 0.24, 0.14, "flat", 0.13),
    "scowl": Mood(-0.13, 0.08, -0.01, 0.3, 0.3, "frown", 0.14),
    "grin": Mood(-0.07, 0.05, 0.02, 0.1, 0.16, "grin", 0.2),
    "beam": Mood(0.04, 0.0, 0.07, 0.0, 0.0, "beam", 0.22),
    "smirk": Mood(0.0, 0.0, 0.03, 0.18, 0.04, "smirk", 0.14, 0.06),
}


class Head:
    """The head's parts, written in head radii about the head's centre."""

    def __init__(self, k: Kit, b: Body, lk: Look) -> None:
        self.k = k
        self.b = b
        self.lk = lk
        self.r = b.head_r
        self.z = b.head_z
        self.skull = skull_of(lk, b)
        self.paint = Paint()
        self.crown: tuple | None = None

    @property
    def covered(self) -> bool:
        """Headwear sits on the hair, so what would stand out of it is left off."""
        return self.lk.wears("bandana", "fieldcap", "cap")

    def p(self, u: float, w: float, v: float) -> Vector:
        return Vector((u * self.r, w * self.r, self.z + v * self.r))

    def egg(self, at, radii, role="hair", rings=6, sides=10, label="hair", tilt=(0.0, 0.0, 0.0)):
        r = self.r
        part = self.k.ellipsoid((0, 0, 0), (radii[0] * r, radii[1] * r, radii[2] * r), role, rings, sides, label)
        part.matrix_world = Matrix.Translation(self.p(*at)) @ Euler(tilt).to_matrix().to_4x4()
        return self.k.bind(part, rigid("head"))

    def tube(self, path, role="hair", sides=8, label="hair"):
        r = self.r
        return self.k.bind(
            self.k.tube([(self.p(*at), a * r, f * r) for at, a, f in path], role, sides, label), rigid("head")
        )

    def band(self, rings, role, bevel=0.004, fore=0.0, sides=16, label="band"):
        """A ring worn round the head: (v, half width, half depth) from the bottom up."""
        r = self.r
        sections = [(self.z + v * r, ellipse(a * r, f * r, sides, 0.0, fore * r)) for v, a, f in rings]
        return self.k.bind(self.k.loft(sections, role, bevel, label=label), rigid("head"))

    def cone(self, base, tip, r0, r1=0.012, role="hair", sides=4):
        return self.k.bind(
            self.k.cyl(self.p(*base), self.p(*tip), r0 * self.r, r1 * self.r, role, sides, 0.0, "spike"), rigid("head")
        )

    # Marks on the skull, in head radii.
    def dot(self, u, v, w, h, role, lift=SKIN_MARK, roll=0.0, sides=10):
        if self.k.hi:
            s = self.skull
            self.paint.put(role, s.at(u, v, lift), s.normal(u, v), w * self.r, h * self.r, roll, sides)

    def stroke(self, points, width, role, lift=SKIN_MARK, sides=8, taper=False):
        """A brush line through (u, v) points, a run of overlapping dots."""
        if not self.k.hi:
            return
        count = len(points) - 1
        for seg, ((u0, v0), (u1, v1)) in enumerate(zip(points, points[1:])):
            n = max(1, int(math.hypot(u1 - u0, v1 - v0) / (width * 0.5)))
            for i in range(n + 1):
                t = i / n
                pen = width
                if taper:
                    pen = width * (1.0 - 0.75 * ((seg + t) / count))
                self.dot(u0 + (u1 - u0) * t, v0 + (v1 - v0) * t, pen, pen, role, lift, 0.0, sides)

    def on_egg(
        self,
        centre,
        radii,
        lon: float,
        lat: float,
        w: float,
        h: float,
        role: str,
        lift: float = 0.0012,
        roll: float = 0.0,
    ):
        """A mark on one of the hair's eggs, by longitude (+90 is the front) and latitude."""
        if not self.k.hi:
            return
        a, e = math.radians(lon), math.radians(lat)
        d = Vector((math.cos(e) * math.cos(a), math.cos(e) * math.sin(a), math.sin(e)))
        at = self.p(*centre) + Vector((radii[0] * d.x, radii[1] * d.y, radii[2] * d.z)) * self.r
        normal = Vector((d.x / radii[0], d.y / radii[1], d.z / radii[2])).normalized()
        self.paint.put(role, at + normal * lift, normal, w * self.r, h * self.r, roll, 8)

    def combed(self, centre, radii, lons, lat0: float, lat1: float, width: float = 0.03) -> None:
        """Painted strands down a hair egg, for the wash and the eye to catch."""
        if not self.k.hi:
            return
        # Kept off the pole, where every strand would meet in a star.
        lat0, lat1 = min(lat0, 58.0), min(lat1, 58.0)
        for lon in lons:
            n = 16
            for i in range(n + 1):
                t = i / n
                self.on_egg(
                    centre,
                    radii,
                    lon,
                    lat0 + (lat1 - lat0) * t,
                    width * 1.5 * (1.0 - 0.6 * abs(2 * t - 1.0)),
                    width * 1.6,
                    "hair_lit",
                )


def build_head(k: Kit, b: Body, lk: Look) -> None:
    h = Head(k, b, lk)
    s = h.skull
    neck = k.cyl((0, 0, b.shoulder), (0, 0, h.z - h.r * 0.7), h.r * 0.32 + 0.012, None, "skin", 8, 0.0, "neck")
    k.bind(neck, rigid("head"))
    # The bake's copy is far finer: where hair crosses it nearly parallel, a coarse one zig-zags.
    rings = s.rings(40 if k.hi else 10)
    sections = []
    for v in rings:
        across, deep = s.spans(v)
        sections.append((h.z + v * h.r, ellipse(across * h.r, deep * h.r, 64 if k.hi else 16)))
    skull = k.loft(sections, "skin", 0.0, label="skull")
    k.bind(skull, rigid("head"))
    k.boost(skull, 1.8)
    for side in (-1.0, 1.0):
        h.egg((side * s.spans(-0.08)[0], -0.03, -0.08), (0.1, 0.13, 0.18), "skin", 5, 6, "ear")
    rnose = (0.095, 0.09, 0.1)
    if not lk.woman:
        rnose = (0.11, 0.1, 0.13) if lk.age != "old" else (0.125, 0.11, 0.15)
    h.egg((0, s.front(0, -0.2) + 0.03, -0.2), rnose, "skin", 5, 6, "nose")
    _face(h)
    _facial_hair(h)
    _wear_on_face(h)
    if lk.style == "hood" or lk.wears("hood"):
        _hood(h)
    else:
        STYLES[lk.style](h)
    _headgear(h)
    h.paint.flush(k)


# ---------------------------------------------------------------------- the face


def _face(h: Head) -> None:
    lk = h.lk
    m = MOODS[lk.mood]
    big = 1.0 if lk.woman else 0.92
    if lk.age == "old":
        big *= 0.9
    w, tall = 0.2 * big, 0.28 * big * (1.0 if lk.woman else 0.9)
    eye_v = -0.02
    for side in (-1.0, 1.0):
        u = side * 0.4
        if not (side < 0.0 and lk.wears("eyepatch")):
            _eye(h, u, eye_v, w, tall, side, m)
        _brow(h, u, eye_v, w, tall, side, m)
        if lk.woman:
            h.dot(side * 0.62, -0.3, 0.15, 0.09, "blush", UNDER)
    _age_lines(h, eye_v, w, tall)
    if lk.freckles:
        for side in (-1.0, 1.0):
            for du, dv in ((0.0, 0.0), (0.09, 0.045), (0.16, -0.03), (0.07, -0.06)):
                h.dot(side * (0.33 + du), -0.26 + dv, 0.018, 0.018, "crease", SKIN_MARK, 0.0, 6)
    _mouth(h, m)


def _eye(h: Head, u, v, w, tall, side, m: Mood) -> None:
    h.dot(u, v, w, tall, "eye_white", WHITE, 0.0, 14)
    h.dot(u - side * w * 0.1, v - tall * 0.05, w * 0.72, tall * 0.8, "iris", IRIS, 0.0, 14)
    h.dot(u - side * w * 0.1, v - tall * 0.03, w * 0.38, tall * 0.46, "ink", PUPIL, 0.0, 12)
    h.dot(u + w * 0.28, v + tall * 0.36, w * 0.22, tall * 0.2, "spark", SPARK, 0.0, 8)
    pen = 0.028 if h.lk.woman else 0.024
    if m.lid > 0.0:
        # The lid comes down over the eye, leaning with the mood, and carries the lash.
        edge = v + tall - 2 * tall * m.lid
        lean = math.tan(side * m.slant)

        def lid_line(height: float) -> list[tuple[float, float]]:
            spots = (-1.0 + 2.0 * i / 10 for i in range(11))
            return [(u + w * 1.14 * t, height + w * 1.14 * t * lean + 0.03 * (1.0 - t * t)) for t in spots]

        # Painted in rows down to its edge, so it stops at the eye and never reaches the hair.
        top = v + tall * 1.08 + abs(lean) * w * 1.14
        rows = max(2, int((top - edge) / 0.03))
        for i in range(rows + 1):
            h.stroke(lid_line(edge + (top - edge) * i / rows), 0.03, "lid", LID, 6)
        h.stroke(lid_line(edge), pen, "ink", LASH)
    else:
        arc = [
            (u + w * 1.08 * math.cos(math.pi * i / 16), v + tall * 0.97 * math.sin(math.pi * i / 16) + tall * 0.02)
            for i in range(17)
        ]
        if not h.lk.woman:
            arc = arc[2:15]
        h.stroke(arc, pen, "ink", LASH)
    if h.lk.woman:
        h.stroke(
            [(u + side * w * 1.05, v + tall * 0.2), (u + side * w * 1.34, v + tall * 0.38)], 0.024, "ink", LASH, 6, True
        )


def _brow(h: Head, u, v, w, tall, side, m: Mood) -> None:
    lk = h.lk
    pen = 0.026
    if not lk.woman:
        pen = 0.05 if lk.age == "old" else 0.042
    base = v + max(tall * 1.32, 0.3)
    if not lk.woman:
        base -= 0.02
    lift = m.raise_one * side
    inner = u - side * w * 0.95
    outer = u + side * w * 1.05
    points = []
    for i in range(8):
        t = i / 7
        pu = inner + (outer - inner) * t
        pv = base + lift + m.brow_in * (1.0 - t) + m.brow_out * t + m.arch * math.sin(math.pi * t)
        points.append((pu, pv))
    h.stroke(points, pen, "brow", BROW)


def _age_lines(h: Head, v, w, tall) -> None:
    lk = h.lk
    if lk.age == "young":
        return
    if lk.age == "old":
        for dv, half in ((0.56, 0.32), (0.66, 0.26)):
            h.stroke([(-half, dv), (0.0, dv + 0.02), (half, dv)], 0.016, "crease", SKIN_MARK, 6)
        for side in (-1.0, 1.0):
            for dv in (-0.05, 0.05):
                x = side * (0.4 + w * 1.25)
                h.stroke([(x, v + dv), (x + side * 0.12, v + dv * 2)], 0.012, "crease", SKIN_MARK, 6)
            bag = [
                (side * (0.4 - w * 0.8), v - tall * 1.14),
                (side * 0.4, v - tall * 1.3),
                (side * (0.4 + w * 0.8), v - tall * 1.14),
            ]
            h.stroke(bag, 0.014, "crease", SKIN_MARK, 6)
    if not lk.woman or lk.age == "old":
        for side in (-1.0, 1.0):
            h.stroke([(side * 0.2, -0.28), (side * 0.27, -0.42)], 0.014, "crease", SKIN_MARK, 6)


def _mouth(h: Head, m: Mood) -> None:
    w = m.width
    v0 = -0.47
    kind = m.mouth
    pen = 0.024 if h.lk.woman else 0.03
    if kind in ("smile", "frown", "flat", "smirk"):
        bow = {"smile": 0.04, "frown": -0.04, "flat": 0.006, "smirk": 0.02}[kind]
        line = []
        for i in range(9):
            t = i / 8
            u = -w + 2 * w * t
            rise = (u * 0.34 + 0.018) if kind == "smirk" and u > 0.0 else 0.0
            line.append((u, v0 - bow * math.sin(math.pi * t) + rise))
        h.stroke(line, pen, "lip", SKIN_MARK + 0.0006)
        if h.lk.woman and kind != "frown":
            h.dot(0.0, v0 - bow - 0.05, 0.06, 0.018, "crease", SKIN_MARK, 0.0, 6)
        if kind == "frown":
            h.dot(0.0, v0 - 0.1, 0.05, 0.014, "crease", SKIN_MARK, 0.0, 6)
        return
    # An open mouth full of teeth.
    tall = 0.095 if kind == "grin" else 0.115
    h.dot(0.0, v0, w, tall, "ink", WHITE, 0.0, 16)
    h.dot(0.0, v0 + tall * 0.1, w * 0.84, tall * 0.72, "eye_white", IRIS, 0.0, 14)
    if kind == "grin":
        h.stroke([(-w * 0.8, v0 + tall * 0.05), (w * 0.8, v0 + tall * 0.05)], 0.008, "crease", PUPIL, 6)


def _wear_on_face(h: Head) -> None:
    lk = h.lk
    if lk.wears("glasses"):
        _glasses(h)
    if lk.wears("eyepatch"):
        _eyepatch(h)
    if lk.wears("scar"):
        _scar(h)
    if lk.prop == "monocle":
        _monocle(h)


def _glasses(h: Head) -> None:
    round_frames = h.lk.woman
    v = -0.02
    pen = 0.034
    for side in (-1.0, 1.0):
        u = side * 0.41
        if round_frames:
            ring = [(u + 0.31 * math.cos(math.tau * i / 24), v + 0.36 * math.sin(math.tau * i / 24)) for i in range(25)]
        else:
            hw, hh = 0.31, 0.27
            ring = [(u - hw, v + hh), (u + hw, v + hh), (u + hw, v - hh), (u - hw, v - hh), (u - hw, v + hh)]
        h.stroke(ring, pen, "ink", RIM, 6)
        h.stroke([(side * 0.73, v + 0.12), (side * 0.93, v + 0.1)], pen, "ink", RIM, 6)
        h.stroke([(u - side * 0.14, v + 0.2), (u - side * 0.05, v + 0.29)], 0.02, "spark", RIM, 6)
    h.stroke([(-0.1, v + 0.1), (0.1, v + 0.1)], pen, "ink", RIM, 6)


def _eyepatch(h: Head) -> None:
    u, v = -0.4, -0.03
    h.dot(u, v, 0.27, 0.27, "ink", OVER, 0.0, 16)
    h.dot(u + 0.06, v + 0.1, 0.05, 0.04, "hair_lit", OVER + 0.0006, 0.0, 8)
    h.stroke([(u - 0.2, v + 0.06), (-0.93, 0.18)], 0.024, "ink", OVER, 6)
    h.stroke([(u + 0.2, v + 0.12), (0.1, 0.42), (0.55, 0.66), (0.92, 0.42)], 0.024, "ink", OVER, 6)


def _scar(h: Head) -> None:
    side = h.lk.scar_side
    line = [(side * 0.68, 0.38), (side * 0.6, 0.0), (side * 0.47, -0.33)]
    h.stroke(line, 0.038, "scar", UNDER + 0.0003, 6)
    for u, v in line:
        h.stroke([(u - 0.05, v + 0.015), (u + 0.05, v - 0.015)], 0.016, "scar", UNDER + 0.0003, 6)


def _monocle(h: Head) -> None:
    u, v = 0.41, -0.03
    ring = [(u + 0.32 * math.cos(math.tau * i / 26), v + 0.36 * math.sin(math.tau * i / 26)) for i in range(27)]
    h.stroke(ring, 0.05, "gilt", RIM, 8)
    h.stroke([(u + 0.04, v - 0.37), (u + 0.24, -0.74)], 0.026, "gilt", RIM, 6)
    h.tube(
        [
            ((u + 0.22, 0.56, -0.72), 0.03, 0.03),
            ((u + 0.12, 0.74, -1.12), 0.03, 0.03),
            ((u + 0.05, 0.72, -1.5), 0.03, 0.03),
        ],
        "gold",
        4,
        "chain",
    )


def _facial_hair(h: Head) -> None:
    facial = h.lk.facial
    if facial == "beard":
        _beard(h)
    elif facial == "stubble":
        _stubble(h)
    elif facial == "mustache":
        _mustache(h, 1.0 if h.lk.age != "old" else 1.25)


def _mustache(h: Head, size: float) -> None:
    s = h.skull
    for side in (-1.0, 1.0):
        y = s.front(side * 0.16, -0.34)
        h.egg(
            (side * 0.17 * size, y + 0.03, -0.35),
            (0.21 * size, 0.09, 0.08 * size),
            "hair",
            4,
            8,
            "mustache",
            (0.0, side * 0.3, 0.0),
        )


def _beard(h: Head) -> None:
    lk = h.lk
    s = h.skull
    long_beard = lk.age == "old"
    depth = 0.54 if long_beard else 0.46
    wide = s.spans(-0.6)[0]
    chin_v = -0.94 if long_beard else -0.86
    chin = (0.0, 0.24, chin_v)
    radii = (wide * 0.94, 0.8, depth)
    h.egg(chin, radii, "hair", 7, 12, "beard")
    for side in (-1.0, 1.0):
        h.egg((side * (wide * 0.78), 0.22, -0.56), (0.32, 0.52, 0.5), "hair", 5, 8, "beard")
    _mustache(h, 1.1)
    h.combed(chin, radii, (55, 75, 90, 105, 125), -5, -68, 0.028)
    if h.k.hi:
        for side in (-1.0, 1.0):
            for i in range(4):
                h.on_egg(
                    (side * (wide * 0.78), 0.22, -0.56),
                    (0.32, 0.52, 0.5),
                    90 + side * (-30 - i * 16),
                    10 - i * 14,
                    0.026,
                    0.05,
                    "hair_lit",
                )
    # The lip sits on what the beard leaves bare.
    h.dot(0.0, -0.58, 0.1, 0.03, "hair", SKIN_MARK, 0.0, 8)


def _stubble(h: Head) -> None:
    """A shaved shadow over the jaw, painted as one tone, then a little grit on it."""
    if not h.k.hi:
        return
    for iu in range(-14, 15):
        for iv in range(14):
            u = iu * 0.06
            v = -0.3 - iv * 0.052
            if abs(u) > h.skull.spans(v)[0] * 0.9:
                continue
            # The line it stops at climbs the cheek toward the ear and clears the mouth.
            edge = abs(u) / 0.8
            if v > -0.62 + 0.3 * edge * edge:
                continue
            h.dot(u, v, 0.056, 0.056, "stubble", SKIN_MARK - 0.0003, 0.0, 8)
            if (iu * 7 + iv * 13) % 5 == 0:
                h.dot(u + 0.02, v - 0.012, 0.012, 0.012, "brow", SKIN_MARK, 0.0, 5)
    # The mustache's ghost, over the lip.
    h.stroke([(-0.16, -0.38), (0.0, -0.36), (0.16, -0.38)], 0.03, "stubble", SKIN_MARK - 0.0003, 8)


# ---------------------------------------------------------------------- hair


def _crown(h: Head, fore=-0.14, top=0.2, size=(1.05, 0.93, 0.96), rings=9, sides=16):
    at = (0.0, fore, top)
    fine = 2 if h.k.hi else 1
    h.egg(at, size, "hair", rings * fine, sides * fine, "crown")
    h.crown = (at, size)
    return at, size


def _nape(h: Head) -> None:
    """The back of the head under a crown that stops at the ears."""
    h.egg((0.0, -0.38, -0.26), (0.9, 0.56, 0.62), "hair", 5, 8, "nape")


def _ponytail_crown(h: Head):
    at, size = _crown(h, -0.12, 0.24, (1.05, 0.95, 0.92))
    _nape(h)
    if not h.covered:
        for u, r in ((-0.4, 0.5), (0.36, 0.54)):
            h.egg((u, 0.62, 0.7), (r, 0.28, 0.2), "hair", 5, 8, "fringe", (0.0, 0.2 if u < 0 else -0.2, 0.0))
    return at, size


def _style_bald(h: Head) -> None:
    # What is left runs round the back of the head, below the crown.
    h.egg((0.0, -0.42, -0.3), (0.93, 0.56, 0.5), "hair", 6, 12, "fringe")
    for side in (-1.0, 1.0):
        h.egg((side * 0.92, -0.14, 0.08), (0.14, 0.34, 0.26), "hair", 4, 8, "fringe")
    # A bare scalp catches the light.
    if h.k.hi:
        h.dot(0.2, 0.8, 0.3, 0.16, "sheen", SKIN_MARK, 0.3)


def _style_buzz(h: Head) -> None:
    at, size = _crown(h, -0.05, 0.1, (1.0, 0.94, 0.95))
    _nape(h)
    h.combed(at, size, range(30, 151, 24), 34, 72, 0.02)


def _style_short(h: Head) -> None:
    at, size = _crown(h, -0.1, 0.26, (1.05, 0.95, 0.86))
    if h.covered:
        pass
    elif h.lk.age == "old":
        # A receding line: what is left at the temples, and a high bare forehead.
        for side in (-1.0, 1.0):
            h.egg((side * 0.84, 0.2, 0.42), (0.24, 0.42, 0.3), "hair", 5, 8, "fringe", (0.0, side * 0.3, 0.0))
    else:
        for u, w, v, r in ((-0.5, 0.56, 0.66, 0.34), (0.0, 0.66, 0.74, 0.42), (0.5, 0.56, 0.66, 0.34)):
            h.egg((u, w, v), (r, 0.28, 0.2), "hair", 5, 8, "fringe", (0.0, -u * 0.6, 0.0))
    _nape(h)
    h.combed(at, size, (55, 75, 95, 115, 135), 76, 34, 0.026)


def _style_sidepart(h: Head) -> None:
    at, size = _crown(h, -0.1, 0.26, (1.05, 0.95, 0.86))
    _nape(h)
    sweep = -h.lk.side
    # The swoop off the parting, heavier on the side it falls to.
    swoop_v = 0.86 if h.lk.age != "old" else 0.76
    h.egg((sweep * 0.16, 0.3, swoop_v), (0.82, 0.62, 0.3), "hair", 6, 12, "swoop", (0.0, sweep * 0.2, 0.0))
    h.egg((sweep * 0.6, 0.6, 0.62), (0.42, 0.28, 0.2), "hair", 5, 8, "fringe", (0.0, sweep * 0.5, 0.0))
    if h.k.hi:
        for i in range(10):
            t = i / 9
            h.on_egg(at, size, 90 + (-sweep) * 48, 72 - 56 * t * (1 - t) - 20 * t, 0.02, 0.05, "ink", 0.0012)
        swoop = (sweep * 0.16, 0.3, swoop_v)
        h.combed(swoop, (0.82, 0.62, 0.3), (60, 80, 100, 120), 75, 8, 0.028)


def _style_long(h: Head) -> None:
    """Long hair: a soft crown, a fringe swept aside and a mane down the back."""
    b = h.b
    r = h.r
    at, size = _crown(h)
    if h.lk.woman:
        h.egg((0.3, 0.58, 0.72), (0.66, 0.34, 0.2), "hair", 6, 10, "fringe")
        h.egg((-0.44, 0.58, 0.68), (0.44, 0.3, 0.2), "hair", 6, 10, "fringe")
    else:
        for side in (-1.0, 1.0):
            h.egg((side * 0.46, 0.5, 0.72), (0.56, 0.36, 0.24), "hair", 6, 10, "fringe", (0.0, side * 0.42, 0.0))
    shoulder_v = (b.shoulder + 0.01 - h.z) / r
    low = max(b.shoulder - (b.shoulder - b.hip) * 0.55, h.z - r * 2.2)
    low_v = (low - h.z) / r
    h.tube(
        [
            ((0, -0.48, 0.05), 0.97, 0.62),
            ((0, -0.63, -0.5), 1.05, 0.52),
            ((0, -0.67, shoulder_v), 0.97, 0.42),
            ((0, -0.67, low_v + 0.23), 0.76, 0.3),
            ((0, -0.65, low_v), 0.34, 0.12),
        ],
        "hair",
        12,
        "mane",
    )
    for side in (-1.0, 1.0):
        h.tube(
            [
                ((side * 0.91, 0.12, 0.2), 0.17, 0.24),
                ((side * 0.99, 0.08, -0.35), 0.17, 0.24),
                ((side * 0.93, 0.12, -0.92), 0.13, 0.18),
                ((side * 0.85, 0.16, -1.28), 0.03, 0.05),
            ],
            "hair",
            8,
            "lock",
        )
    h.combed(at, size, (20, 40, 60, 120, 140, 160), 70, 14, 0.022)


def _style_ponytail(h: Head) -> None:
    at, size = _ponytail_crown(h)
    side = h.lk.side
    b = h.b
    root = (side * 0.3, -0.72, 0.5)
    h.egg(root, (0.3, 0.26, 0.28), "hair", 5, 8, "tail")
    h.tube(
        [
            (root, 0.2, 0.2),
            ((side * 0.6, -0.84, 0.66), 0.25, 0.24),
            ((side * 0.98, -0.82, 0.36), 0.28, 0.27),
            ((side * 1.16, -0.7, -0.06), 0.28, 0.27),
            ((side * 1.2, -0.58, -0.5), 0.23, 0.23),
            ((side * 1.16, -0.5, -0.86), 0.14, 0.14),
            ((side * 1.1, -0.46, (b.shoulder + 0.015 - h.z) / h.r), 0.03, 0.03),
        ],
        "hair",
        10,
        "tail",
    )
    h.egg((side * 0.5, -0.82, 0.62), (0.12, 0.26, 0.26), "team_dark", 4, 8, "tie")
    h.combed(at, size, (60, 80, 100, 120), 76, 40, 0.024)


def _style_bun(h: Head) -> None:
    at, size = _crown(h, -0.08, 0.2, (1.03, 0.95, 0.92))
    _nape(h)
    for side in (-1.0, 1.0):
        h.egg((side * 0.42, 0.6, 0.72), (0.54, 0.26, 0.18), "hair", 5, 8, "fringe", (0.0, side * 0.42, 0.0))
    knot = (0.0, -0.22, 1.12)
    h.egg(knot, (0.38, 0.38, 0.36), "hair", 6, 12, "bun")
    h.egg((0.0, -0.18, 0.86), (0.28, 0.26, 0.08), "team_dark", 3, 10, "tie")
    h.combed(at, size, (50, 70, 90, 110, 130), 74, 30, 0.022)
    h.combed(knot, (0.38, 0.38, 0.36), (60, 100, 140), 60, -20, 0.03)


def _style_braid(h: Head) -> None:
    at, size = _ponytail_crown(h)
    side = h.lk.side
    links = [(0.84, 0.18, -0.48), (0.8, 0.34, -0.86), (0.72, 0.5, -1.22), (0.64, 0.6, -1.56), (0.58, 0.66, -1.86)]
    h.egg((side * 0.74, 0.0, -0.12), (0.26, 0.26, 0.4), "hair", 5, 8, "braid")
    for i, (u, w, v) in enumerate(links):
        rock = 0.3 if i % 2 else -0.3
        h.egg((side * u, w, v), (0.21, 0.2, 0.25), "hair", 4, 8, "braid", (0.0, rock, 0.0))
    h.egg((side * 0.55, 0.68, -2.1), (0.12, 0.12, 0.09), "team_dark", 3, 8, "tie")
    h.egg((side * 0.54, 0.68, -2.26), (0.13, 0.1, 0.13), "hair", 3, 8, "braid")
    h.combed(at, size, (60, 80, 100, 120), 76, 40, 0.024)


def _style_bob(h: Head) -> None:
    at, size = _crown(h, -0.08, 0.2, (1.12, 1.0, 0.98))
    # A blunt fringe cut straight across, above the brows.
    if not h.covered:
        h.egg((0.0, 0.5, 0.76), (0.92, 0.46, 0.3), "hair", 5, 12, "fringe")
    for side in (-1.0, 1.0):
        h.tube(
            [
                ((side * 0.98, 0.1, 0.34), 0.16, 0.42),
                ((side * 1.0, 0.1, -0.2), 0.17, 0.42),
                ((side * 0.92, 0.14, -0.66), 0.17, 0.36),
                ((side * 0.78, 0.18, -0.84), 0.07, 0.16),
            ],
            "hair",
            8,
            "lock",
        )
    h.tube(
        [
            ((0, -0.42, 0.1), 1.0, 0.56),
            ((0, -0.48, -0.5), 1.0, 0.46),
            ((0, -0.42, -0.86), 0.84, 0.34),
            ((0, -0.32, -0.96), 0.3, 0.12),
        ],
        "hair",
        10,
        "back",
    )
    h.combed(at, size, (40, 65, 90, 115, 140), 62, 24, 0.024)


def _curls(h: Head, lat: float, lon0: float, lon1: float, count: int, size: float) -> None:
    """Curls set into the crown, so only their tops show and the mass stays one shape."""
    at, radii = h.crown
    for i in range(count):
        a = math.radians(lon0 + (lon1 - lon0) * (i + 0.5) / count)
        e = math.radians(lat + 5.0 * math.sin(i * 2.4))
        d = (math.cos(e) * math.cos(a), math.cos(e) * math.sin(a), math.sin(e))
        place = (at[0] + radii[0] * d[0] * 0.92, at[1] + radii[1] * d[1] * 0.92, at[2] + radii[2] * d[2] * 0.92)
        h.egg(place, (size, size, size * 0.92), "hair", 4, 7, "curl")


def _style_curly(h: Head) -> None:
    at, size = _crown(h, -0.1, 0.22, (1.02, 0.94, 0.88), 6, 12)
    _nape(h)
    big = 1.08 if h.lk.age == "old" else 1.0
    if h.covered:
        # Only what the headwear leaves: a roll round the back and over the ears.
        _curls(h, 2, 170, 370, 6, 0.26)
        for side in (-1.0, 1.0):
            h.egg((side * 0.98, 0.04, 0.12), (0.2, 0.24, 0.3), "hair", 4, 8, "curl")
    else:
        _curls(h, 8, 150, 390, 6, 0.29 * big)
        _curls(h, 42, 0, 360, 7, 0.3 * big)
        h.egg((0.0, -0.1, 1.04), (0.3 * big, 0.3 * big, 0.25 * big), "hair", 4, 8, "curl")
    h.combed(at, size, (70, 90, 110), 70, 44, 0.03)


def _style_spiky(h: Head) -> None:
    at, size = _crown(h, -0.08, 0.2, (1.03, 0.94, 0.9))
    _nape(h)
    spikes = (
        (0.0, 0.3, 1.0, 0.0, 0.42, 1.62, 0.32),
        (-0.42, 0.28, 0.92, -0.78, 0.44, 1.46, 0.3),
        (0.42, 0.28, 0.92, 0.78, 0.44, 1.46, 0.3),
        (-0.82, 0.08, 0.62, -1.34, 0.12, 1.02, 0.3),
        (0.82, 0.08, 0.62, 1.34, 0.12, 1.02, 0.3),
        (-0.3, -0.3, 1.0, -0.56, -0.5, 1.54, 0.32),
        (0.3, -0.3, 1.0, 0.56, -0.5, 1.54, 0.32),
        (-0.74, -0.42, 0.56, -1.2, -0.72, 0.92, 0.3),
        (0.74, -0.42, 0.56, 1.2, -0.72, 0.92, 0.3),
        (0.0, -0.76, 0.56, 0.0, -1.3, 0.92, 0.3),
    )
    for u0, w0, v0, u1, w1, v1, r in spikes:
        h.cone((u0, w0, v0), (u1, w1, v1), r)
    # The ragged fringe: short shards that stop above the brows.
    for u, tip_u in ((-0.5, -0.56), (-0.16, -0.2), (0.2, 0.26), (0.52, 0.62)):
        h.cone((u, 0.54, 0.84), (tip_u, 0.86, 0.5), 0.2, 0.02, "hair", 4)
    h.combed(at, size, (20, 160), 60, 20, 0.024)


STYLES = {
    "bald": _style_bald,
    "buzz": _style_buzz,
    "short": _style_short,
    "sidepart": _style_sidepart,
    "long": _style_long,
    "ponytail": _style_ponytail,
    "bun": _style_bun,
    "braid": _style_braid,
    "bob": _style_bob,
    "curly": _style_curly,
    "spiky": _style_spiky,
}


def _hood(h: Head) -> None:
    """A big hood: the skull pokes through the egg, and that is the opening."""
    b = h.b
    at = (0.0, -0.24, 0.1)
    size = (1.22, 1.12, 1.26)
    # What shows of the hair inside it: a parting and a lock down each cheek.
    h.egg((0.0, 0.7, 0.5), (0.5, 0.2, 0.1), "hair", 4, 8, "fringe")
    for side in (-1.0, 1.0):
        h.egg((side * 0.72, 0.5, 0.1), (0.14, 0.2, 0.5), "hair", 4, 8, "lock", (0.0, side * 0.12, 0.0))
    h.egg(at, size, "team", 9, 16, "hood")
    # The rim that frames the face.
    h.egg((0.0, 0.54, 0.9), (0.72, 0.28, 0.13), "team_dark", 4, 10, "hood_rim")
    for side in (-1.0, 1.0):
        h.egg((side * 0.88, 0.34, 0.08), (0.13, 0.24, 0.78), "team_dark", 4, 8, "hood_rim", (0.0, side * 0.1, 0.0))
    # The cowl where it meets the shoulders.
    cowl_v = (b.shoulder + 0.012 - h.z) / h.r
    h.band(
        [
            (cowl_v - 0.1, 0.82, 0.68),
            (cowl_v + 0.04, 0.88, 0.76),
            (cowl_v + 0.3, 0.72, 0.6),
        ],
        "team_dark",
        0.006,
        -0.06,
        14,
        "cowl",
    )
    if h.k.hi:
        for lon in range(210, 340, 26):
            for i in range(14):
                h.on_egg(at, size, lon, 58 - i * 6.0, 0.012, 0.03, "team_dark")


def _strap_round(h: Head, v: float, role: str, half: float = 0.07) -> None:
    """A band drawn tight round whatever the head is wearing at that height."""
    at, size = h.crown or ((0.0, 0.0, 0.0), (h.skull.rx, h.skull.ry, h.skull.rz))
    rings = []
    for height in (v - half, v + half):
        t = min(abs(height - at[2]) / size[2], 0.97)
        s = math.sqrt(1.0 - t * t)
        rings.append((height, size[0] * s + 0.035, size[1] * s + 0.035))
    h.band(rings, role, 0.003, at[1], 18, "headband")


def _headgear(h: Head) -> None:
    lk = h.lk
    for acc in (lk.acc, lk.acc2):
        wear = HEADGEAR.get(acc)
        if wear:
            wear(h)


def _gear_goggles(h: Head) -> None:
    v = 0.66
    _strap_round(h, v - 0.04, "strap", 0.08)
    for side in (-1.0, 1.0):
        u = side * 0.38
        s = h.skull
        y = max(s.front(u, v), 0.62)
        base, face = h.p(u, y - 0.04, v), h.p(u, y + 0.24, v + 0.14)
        h.k.bind(h.k.cyl(base, face, 0.037, 0.039, "gunmetal", 12, 0.0, "goggle"), rigid("head"))
        mid = h.p(u, y + 0.24, v + 0.14)
        lens = h.k.cyl(mid, mid + (face - base).normalized() * 0.004, 0.03, 0.03, "lens", 12, 0.0, "lens")
        h.k.bind(lens, rigid("head"))
        if h.k.hi:
            normal = (face - base).normalized()
            h.paint.put("spark", mid + normal * 0.006 + Vector((-0.012, 0, 0.012)), normal, 0.008, 0.008, 0.0, 8)
    h.band([(v - 0.02, 0.08, 0.05), (v + 0.04, 0.08, 0.05)], "gunmetal", 0.0, 0.92, 6, "goggle")


def _gear_headset(h: Head) -> None:
    arc = []
    for i in range(9):
        a = math.pi * i / 8
        arc.append(((1.16 * math.cos(a), -0.02, 0.05 + 1.16 * math.sin(a)), 0.07, 0.15))
    h.tube(arc, "gunmetal", 6, "headset")
    for side in (-1.0, 1.0):
        h.egg((side * 1.14, -0.02, -0.06), (0.14, 0.3, 0.34), "gunmetal", 5, 10, "headset")
        h.egg((side * 1.27, -0.02, -0.06), (0.03, 0.17, 0.2), "team_light", 3, 8, "headset")
    h.tube(
        [
            ((-1.18, 0.1, -0.2), 0.05, 0.05),
            ((-1.08, 0.58, -0.5), 0.05, 0.05),
            ((-0.56, 1.0, -0.54), 0.05, 0.05),
        ],
        "gunmetal",
        5,
        "boom",
    )
    h.egg((-0.42, 1.0, -0.54), (0.13, 0.11, 0.11), "ink", 4, 8, "mic")


def _gear_headband(h: Head) -> None:
    _strap_round(h, 0.6, "team_light", 0.11)
    h.egg((-0.3, -0.98, 0.6), (0.15, 0.12, 0.13), "team_light", 3, 8, "knot")
    h.tube(
        [((-0.3, -1.02, 0.54), 0.1, 0.03), ((-0.38, -1.12, 0.2), 0.1, 0.03), ((-0.5, -1.08, -0.12), 0.05, 0.02)],
        "team_light",
        5,
        "tail",
    )


def _gear_bandana(h: Head) -> None:
    at = (0.0, -0.1, 0.32)
    size = (1.11, 1.03, 0.9)
    h.egg(at, size, "team", 8, 16, "bandana")
    h.band([(0.44, 1.1, 1.05), (0.62, 1.09, 1.02)], "team_dark", 0.003, -0.08, 18, "bandana_band")
    h.egg((0.12, -1.12, 0.52), (0.19, 0.14, 0.16), "team", 4, 8, "knot")
    for u, end in ((0.24, 0.44), (-0.02, -0.2)):
        h.tube(
            [
                ((0.12, -1.16, 0.5), 0.12, 0.03),
                ((end, -1.28, 0.14), 0.13, 0.03),
                ((end * 1.2, -1.24, -0.18), 0.05, 0.02),
            ],
            "team",
            5,
            "tail",
        )
    if h.k.hi:
        for lon in (20, 60, 90, 120, 160, 230, 290):
            for i in range(8):
                h.on_egg(at, size, lon, 72 - i * 5.0, 0.012, 0.032, "team_dark")


def _badge(h: Head, w: float, v: float, role: str = "brass") -> None:
    h.k.bind(h.k.box(h.p(0, w, v), (0.036, 0.009, 0.036), role, 0.003, label="badge"), rigid("head"))


def _gear_fieldcap(h: Head) -> None:
    h.band(
        [
            (0.56, 1.07, 1.01),
            (0.8, 1.1, 1.05),
            (1.02, 1.1, 1.06),
            (1.14, 0.98, 0.94),
            (1.19, 0.56, 0.54),
        ],
        "team_dark",
        0.006,
        -0.06,
        16,
        "cap",
    )
    h.egg((0.0, 0.8, 0.58), (0.72, 0.3, 0.05), "boot", 3, 12, "peak", (-0.14, 0.0, 0.0))
    _badge(h, 0.96, 0.82)


def _gear_cap(h: Head) -> None:
    h.band([(0.54, 1.07, 1.01), (0.8, 1.07, 1.01)], "team_dark", 0.004, -0.06, 16, "cap")
    h.band(
        [
            (0.78, 1.04, 0.98),
            (0.98, 1.2, 1.14),
            (1.11, 1.22, 1.16),
            (1.18, 0.72, 0.68),
        ],
        "team",
        0.008,
        -0.08,
        16,
        "cap_top",
    )
    h.egg((0.0, 0.82, 0.56), (0.74, 0.34, 0.055), "boot", 3, 12, "peak", (-0.24, 0.0, 0.0))
    _badge(h, 0.98, 0.76, "gold")


def _gear_visor(h: Head) -> None:
    _strap_round(h, 0.62, "gunmetal", 0.1)
    h.egg((0.0, 0.82, 0.56), (0.84, 0.44, 0.05), "shade", 3, 14, "visor", (-0.2, 0.0, 0.0))


HEADGEAR = {
    "goggles": _gear_goggles,
    "headset": _gear_headset,
    "headband": _gear_headband,
    "bandana": _gear_bandana,
    "fieldcap": _gear_fieldcap,
    "cap": _gear_cap,
    "visor": _gear_visor,
}


# ---------------------------------------------------------------------- the whole figure


def build_figure(k: Kit, lk: Look) -> None:
    k.cull = False
    # Round forms are few-sided here; a wider angle keeps them soft and leaves boxes hard.
    k.smooth_angle = 58.0
    b = body_of(lk)
    build_legs(k, b, lk)
    build_torso(k, b, lk)
    build_arms(k, b, lk)
    PROPS[lk.prop](Held(k, b))
    build_head(k, b, lk)


def builder(lk: Look):
    """A general module's `build`."""
    return lambda k: build_figure(k, lk)


def _armature(low: bpy.types.Object, b: Body) -> bpy.types.Object:
    data = bpy.data.armatures.new(f"{low.name}_rig")
    rig = bpy.data.objects.new("rig", data)
    bpy.context.scene.collection.objects.link(rig)
    for obj in bpy.data.objects:
        obj.select_set(False)
    rig.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="EDIT")
    places = pivots(b)
    made = {}
    for name, parent in BONES.items():
        bone = data.edit_bones.new(name)
        head = Vector(places[name])
        bone.head = head
        bone.tail = head + Vector((0, 0, 0.04))
        bone.roll = 0.0
        if parent:
            bone.parent = made[parent]
        made[name] = bone
    bpy.ops.object.mode_set(mode="OBJECT")
    for pose_bone in rig.pose.bones:
        pose_bone.rotation_mode = "XYZ"
    return rig


def rig_figure(low: bpy.types.Object) -> None:
    rig = _armature(low, CHIBI)
    low.parent = rig
    modifier = low.modifiers.new("rig", "ARMATURE")
    modifier.object = rig
    for obj in bpy.data.objects:
        obj.select_set(False)
    rig.select_set(True)
    low.select_set(True)
    bpy.context.view_layer.objects.active = rig
