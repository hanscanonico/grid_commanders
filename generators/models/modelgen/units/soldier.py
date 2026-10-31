"""The foot soldiers' one body: a chunky toy trooper with limbs that swing apart.

There is no skeleton. A leg and everything on it moves as one rigid part about the
hip, an arm and whatever it holds about the shoulder, so every limb is its own
closed part. Figures face +X; the camera's side is -Y, which is the soldier's right.
"""

from __future__ import annotations

import math
from dataclasses import dataclass

from mathutils import Vector

from ..kit import ARM_A, ARM_B, LEG_A, LEG_B, Kit
from ..paint import Role, grey

_PLAIN = {"edge": 0.0, "dust": 0.0}
_SKIN = (0.77, 0.43, 0.25)

ROLES = {
    "skin": Role(_SKIN, wash=0.55, **_PLAIN),
    "blush": Role((_SKIN[0], _SKIN[1] * 0.62, _SKIN[2] * 0.58), wash=0.2, **_PLAIN),
    "hair": Role((0.042, 0.02, 0.011), **_PLAIN),
    "eye_white": Role((0.86, 0.86, 0.82), wash=0.25, **_PLAIN),
    "ink": Role((0.012, 0.01, 0.012), wash=0.0, **_PLAIN),
    "spark": Role((1.0, 1.0, 1.0), wash=0.0, **_PLAIN),
    "lip": Role((0.34, 0.09, 0.08), wash=0.2, **_PLAIN),
    # A steel pot is a smooth shape: the board's light tone with no chips to spot its rim.
    "helmet": Role(grey(0.74), team=True, chip=0.0, edge=0.25),
    "armour": Role(grey(0.62), team=True, chip=0.12, edge=0.55),
    # Dust would pile up a figure this low and turn its boots to gravel.
    "army_boot": Role((0.085, 0.056, 0.036), edge=1.2, dust=0.22),
}
LONE_SCALE = 2.0
# Below this a figure is one of a squad and sharing the cell's triangle budget.
FINE_SCALE = 1.5


@dataclass(frozen=True)
class Body:
    """A soldier's proportions at board scale, in cells."""

    hip: float
    leg_y: float
    leg_r: float
    stride: float
    boot: tuple[float, float, float]
    # (z, radius forward, radius across), from the crotch to the collar.
    torso: tuple[tuple[float, float, float], ...]
    belt_z: float
    shoulder_y: float
    shoulder_z: float
    shoulder_r: float
    arm_r: float
    head_z: float
    head_r: float
    helm_z: float
    helm_r: float
    helm_h: float


RIFLEMAN = Body(
    hip=0.1,
    leg_y=0.032,
    leg_r=0.025,
    stride=0.024,
    boot=(0.034, 0.024, 0.042),
    torso=(
        (0.078, 0.036, 0.05),
        (0.098, 0.042, 0.058),
        (0.122, 0.043, 0.057),
        (0.146, 0.048, 0.063),
        (0.166, 0.042, 0.055),
        (0.178, 0.022, 0.028),
    ),
    belt_z=0.104,
    shoulder_y=0.068,
    shoulder_z=0.156,
    shoulder_r=0.025,
    arm_r=0.02,
    head_z=0.204,
    head_r=0.05,
    helm_z=0.218,
    helm_r=0.066,
    helm_h=0.062,
)

TROOPER = Body(
    hip=0.106,
    leg_y=0.05,
    leg_r=0.037,
    stride=0.026,
    boot=(0.05, 0.036, 0.052),
    torso=(
        (0.082, 0.052, 0.078),
        (0.104, 0.064, 0.092),
        (0.13, 0.066, 0.092),
        (0.156, 0.072, 0.1),
        (0.178, 0.06, 0.084),
        (0.19, 0.028, 0.034),
    ),
    belt_z=0.11,
    shoulder_y=0.106,
    shoulder_z=0.166,
    shoulder_r=0.038,
    arm_r=0.027,
    head_z=0.215,
    head_r=0.052,
    helm_z=0.228,
    helm_r=0.08,
    helm_h=0.066,
)


class Man:
    """One soldier standing at (x, y), `s` times board size, on a march phase of 0 or 1."""

    def __init__(self, k: Kit, x: float, y: float, s: float, body: Body, phase: int) -> None:
        self.k = k
        self.x = x
        self.y = y
        self.s = s
        self.b = body
        self.phase = phase
        self.fine = s >= FINE_SCALE

    def around(self, squad: int) -> int:
        """How many sides a round part gets: a lone figure is seen close, at twice the count."""
        return squad * 2 if self.fine else squad

    def p(self, x: float, y: float, z: float) -> tuple[float, float, float]:
        return (self.x + x * self.s, self.y + y * self.s, z * self.s)

    def pivot(self, x: float, z: float) -> tuple[float, float]:
        return (self.x + x * self.s, z * self.s)

    def loft(self, rings: list[tuple[float, float, float, float]], role: str, bevel: float, label: str, y: float = 0.0, sides: int = 10):
        """Stacked ellipses of (z, radius forward, radius across, shift forward)."""
        s = self.s
        sides = self.around(sides) * (2 if self.k.hi else 1)
        sections = []
        for z, rx, ry, cx in rings:
            outline = []
            for i in range(sides):
                t = math.tau * i / sides
                outline.append(((cx + rx * math.cos(t)) * s, (ry * math.sin(t)) * s))
            sections.append((z * s, outline))
        return self.k.loft(sections, role, bevel * s, (self.x, self.y + y * s, 0.0), label)

    def ball(self, at, radii, role: str, rings: int = 4, sides: int = 6, label: str = "ball"):
        rings, sides = self.around(rings), self.around(sides)
        return self.k.ellipsoid(self.p(*at), [r * self.s for r in radii], role, rings, sides, label)

    def box(self, at, size, role: str, bevel: float = 0.006, taper: float = 1.0, tilt: float = 0.0, label: str = "box"):
        s = self.s
        return self.k.box(self.p(*at), [v * s for v in size], role, bevel * s, taper, tilt, label)

    def cyl(self, a, b, r0: float, r1: float | None, role: str, sides: int = 10, bevel: float = 0.003, label: str = "cyl"):
        s = self.s
        r1 = r0 if r1 is None else r1
        return self.k.cyl(self.p(*a), self.p(*b), r0 * s, r1 * s, role, self.around(sides), bevel * s, label)

    def tube(self, path, role: str, sides: int = 6, label: str = "tube"):
        s = self.s
        sides = self.around(sides)
        rings = [(self.p(*at), across * s, forward * s) for at, across, forward in path]
        return self.k.tube(rings, role, sides, label)

    def kinds(self) -> tuple[int, int, int, int]:
        """The near leg's and far leg's motions, then the near arm's and the far arm's."""
        if self.phase == 0:
            return LEG_A, LEG_B, ARM_A, ARM_B
        return LEG_B, LEG_A, ARM_B, ARM_A

    def legs(self) -> None:
        b = self.b
        near, far, _, _ = self.kinds()
        lead = 1.0 if self.phase == 0 else -1.0
        pivot = self.pivot(0.0, b.hip)
        for side, kind, stride in ((-1.0, near, lead), (1.0, far, -lead)):
            y = side * b.leg_y
            foot = stride * b.stride
            ankle = b.boot[2]
            trouser = self.tube(
                [
                    ((0.0, y, b.hip + 0.012), b.leg_r * 1.1, b.leg_r * 1.15),
                    ((foot * 0.42, y, b.hip * 0.72), b.leg_r, b.leg_r * 1.06),
                    ((foot * 0.82, y, ankle + 0.012), b.leg_r * 0.86, b.leg_r * 0.9),
                    ((foot, y, ankle - 0.008), b.leg_r * 0.8, b.leg_r * 0.84),
                ],
                "team_dark",
                label="trouser",
            )
            self.k.moves(trouser, kind, pivot)
            long, wide, high = b.boot
            boot = self.loft(
                [
                    (0.0, long, wide, foot + long * 0.28),
                    (high * 0.68, long * 0.8, wide * 0.94, foot + long * 0.1),
                    (high, long * 0.7, wide * 0.92, foot),
                ],
                "army_boot",
                0.005,
                "boot",
                y,
                8,
            )
            self.k.moves(boot, kind, pivot)

    def torso(self) -> None:
        b = self.b
        self.loft([(z, rx, ry, 0.0) for z, rx, ry in b.torso], "team", 0.006, "tunic")
        if self.k.hi:
            waist = next((rx, ry) for z, rx, ry in b.torso if z >= b.belt_z)
            belt = [
                (b.belt_z - 0.008, waist[0] + 0.002, waist[1] + 0.002, 0.0),
                (b.belt_z + 0.008, waist[0] + 0.002, waist[1] + 0.002, 0.0),
            ]
            self.loft(belt, "leather", 0.0, "belt")
            front = waist[0] + 0.003
            self.box((front, 0.0, b.belt_z), (0.006, 0.02, 0.016), "brass", 0.0, label="buckle")

    def head(self) -> None:
        b = self.b
        r = b.head_r
        rx, ry, rz = r * 0.96, r, r * 0.96
        z = b.head_z
        cx = 0.008
        skull = self.ball((cx, 0.0, z), (rx, ry, rz), "skin", 4, 8, "skull")
        if self.fine:
            self.k.boost(skull, 1.6)
        if self.k.hi:
            self._face(cx, z, rx, ry, rz)
            for side in (-1.0, 1.0):
                y = side * ry * 0.98
                strap = [
                    ((cx + 0.004, y, b.helm_z), 0.004, 0.003),
                    ((cx + 0.012, y * 0.94, z - rz * 0.5), 0.004, 0.003),
                    ((cx + rx * 0.4, y * 0.5, z - rz * 0.92), 0.004, 0.003),
                ]
                self.tube(strap, "leather", 6, "chin_strap")

    def _face(self, cx: float, z0: float, rx: float, ry: float, rz: float) -> None:
        """Paint only: flat dabs laid on the front of the skull that the bake reads."""

        def on_skull(y: float, z: float, lift: float = 0.0) -> tuple[float, float, float]:
            q = 1.0 - (y / ry) ** 2 - ((z - z0) / rz) ** 2
            return (cx + rx * math.sqrt(max(q, 0.02)) + lift, y, z)

        r = self.b.head_r
        eye_z = z0 + r * 0.02
        for side in (-1.0, 1.0):
            y = side * r * 0.4
            w, h = r * 0.15, r * 0.21
            self.ball(on_skull(y, eye_z, 0.0006), (0.002, w, h), "eye_white", 4, 8, "eye_white")
            self.ball(on_skull(y, eye_z - h * 0.05, 0.0014), (0.002, w * 0.66, h * 0.76), "ink", 4, 8, "pupil")
            self.ball(on_skull(y + w * 0.2, eye_z + h * 0.34, 0.0024), (0.002, w * 0.2, h * 0.18), "spark", 3, 6, "spark")
            self.ball(on_skull(y, eye_z + h * 1.3, 0.001), (0.002, w * 1.25, r * 0.05), "hair", 3, 8, "brow")
            self.ball(on_skull(side * r * 0.62, z0 - r * 0.3, 0.0003), (0.0015, r * 0.15, r * 0.09), "blush", 3, 6, "blush")
        self.ball(on_skull(0.0, z0 - r * 0.15, 0.002), (0.004, r * 0.09, r * 0.1), "skin", 3, 6, "nose")
        self.ball(on_skull(0.0, z0 - r * 0.5, 0.001), (0.002, r * 0.17, r * 0.035), "lip", 3, 8, "mouth")

    def helmet(self) -> None:
        b = self.b
        back = -0.004
        rings = []
        for degrees in (0, 24, 48, 68, 84):
            t = math.radians(degrees)
            rings.append((b.helm_z + b.helm_h * math.sin(t), b.helm_r * math.cos(t), b.helm_r * math.cos(t), back))
        self.loft(rings, "helmet", 0.0, "helmet", sides=12)
        lip = b.helm_r + 0.013
        brim = [
            (b.helm_z - 0.007, lip, lip - 0.004, back + 0.005),
            (b.helm_z + 0.004, lip, lip - 0.004, back + 0.005),
            (b.helm_z + 0.012, b.helm_r - 0.001, b.helm_r - 0.001, back),
        ]
        self.loft(brim, "helmet", 0.004, "brim", sides=12)

    def rifle_arms(self) -> Vector:
        """Both hands on the rifle, carried low across the hip; its one motion keeps the grip."""
        b = self.b
        _, _, kind, _ = self.kinds()
        pivot = self.pivot(0.0, b.shoulder_z)
        grip = Vector((0.04, -b.shoulder_y - 0.006, 0.096))
        tilt = math.radians(9)
        along = Vector((math.cos(tilt), 0.0, math.sin(tilt)))

        def on_rifle(a: float, up: float = 0.0) -> tuple[float, float, float]:
            point = grip + along * a + Vector((0, 0, up))
            return (point.x, point.y, point.z)

        muzzle = 0.158
        parts = [
            self.box(on_rifle(-0.082), (0.072, 0.032, 0.044), "wood", 0.007, tilt=tilt, label="stock"),
            self.box(on_rifle(-0.012), (0.072, 0.034, 0.038), "gunmetal", 0.005, tilt=tilt, label="receiver"),
            self.box(on_rifle(0.058), (0.072, 0.03, 0.03), "wood", 0.005, tilt=tilt, label="forestock"),
            self.cyl(on_rifle(0.09), on_rifle(muzzle - 0.012), 0.0155, None, "steel", 8, 0.0, "barrel"),
            self.cyl(on_rifle(muzzle - 0.016), on_rifle(muzzle), 0.019, 0.018, "gunmetal", 8, 0.0, "muzzle"),
        ]
        if self.k.hi:
            parts.append(self.box(on_rifle(-0.012, 0.022), (0.03, 0.01, 0.008), "steel", 0.0, tilt=tilt, label="bolt"))
            parts.append(self.box(on_rifle(muzzle - 0.022, 0.02), (0.008, 0.008, 0.012), "gunmetal", 0.0, tilt=tilt, label="sight"))
        # The near hand has the grip; the far arm reaches across the belly to the forestock.
        wrap_near = (0.0, -0.014, -0.004)
        wrap_far = (0.0, 0.0, 0.017)
        for side, grab, wrap, elbow in (
            (-1.0, on_rifle(-0.002), wrap_near, (-0.012, -b.shoulder_y * 1.08, 0.108)),
            (1.0, on_rifle(0.054), wrap_far, (0.036, b.shoulder_y * 0.72, 0.122)),
        ):
            hand = (grab[0] + wrap[0], grab[1] + wrap[1], grab[2] + wrap[2])
            y = side * b.shoulder_y
            wrist = (hand[0] - 0.014, hand[1] + (0.014 if side > 0 else 0.0), hand[2] + 0.002)
            parts.append(self.ball((0.0, y, b.shoulder_z + 0.004), (b.shoulder_r, b.shoulder_r, b.shoulder_r), "team", label="shoulder"))
            parts.append(
                self.tube(
                    [
                        ((0.0, y, b.shoulder_z), b.arm_r * 0.96, b.arm_r),
                        (elbow, b.arm_r, b.arm_r),
                        (wrist, b.arm_r * 0.9, b.arm_r * 0.9),
                    ],
                    "team",
                    label="sleeve",
                )
            )
            parts.append(self.ball(hand, (0.024, 0.019, 0.02), "skin", label="hand"))
        for part in parts:
            self.k.moves(part, kind, pivot)
        return Vector(self.p(*on_rifle(muzzle)))

    def tube_arms(self) -> Vector:
        """A bazooka on the near shoulder, its fist under the tube; the far arm swings free."""
        b = self.b
        _, _, near, far = self.kinds()
        pivot = self.pivot(0.0, b.shoulder_z)
        y = -b.shoulder_y - 0.012
        tilt = math.radians(8)
        along = Vector((math.cos(tilt), 0.0, math.sin(tilt)))
        rest = Vector((0.0, y, b.shoulder_z + b.shoulder_r + 0.016))

        def on_tube(a: float, up: float = 0.0) -> tuple[float, float, float]:
            point = rest + along * a + Vector((0, 0, up))
            return (point.x, point.y, point.z)

        tube_r = 0.024
        tail, front, tip = -0.11, 0.098, 0.172
        grip_at = on_tube(0.062, -tube_r - 0.012)
        hand = (grip_at[0], y, grip_at[2] - 0.006)
        parts = [
            self.cyl(on_tube(tail + 0.03), on_tube(front), tube_r, None, "team", 10, 0.0, "tube"),
            self.cyl(on_tube(tail), on_tube(tail + 0.034), tube_r + 0.012, tube_r, "gunmetal", 10, 0.004, "flare"),
            self.cyl(on_tube(front - 0.02), on_tube(front - 0.002), tube_r + 0.005, None, "gunmetal", 10, 0.003, "collar"),
            self.cyl(on_tube(front - 0.004), on_tube(front + 0.05), 0.031, 0.027, "bone", 10, 0.004, "warhead"),
            self.cyl(on_tube(front + 0.048), on_tube(tip), 0.018, 0.007, "brass", 10, 0.0, "fuze"),
            self.box(grip_at, (0.024, 0.026, 0.03), "gunmetal", 0.004, tilt=tilt, label="grip"),
            self.ball((0.0, y + 0.006, b.shoulder_z + 0.004), (b.shoulder_r, b.shoulder_r * 0.9, b.shoulder_r * 0.78), "armour", label="pad"),
            self.tube(
                [
                    ((0.0, y + 0.006, b.shoulder_z), b.arm_r * 0.96, b.arm_r),
                    ((-0.024, y - 0.002, 0.11), b.arm_r, b.arm_r),
                    ((hand[0] - 0.004, y, hand[2] - 0.006), b.arm_r * 0.92, b.arm_r * 0.92),
                ],
                "team",
                label="sleeve",
            ),
            self.ball(hand, (0.026, 0.026, 0.026), "team_dark", label="gauntlet"),
        ]
        if self.k.hi:
            parts.append(self.box(on_tube(0.0, tube_r + 0.008), (0.022, 0.008, 0.012), "gunmetal", 0.0, tilt=tilt, label="sight"))
            for a in (-0.05, 0.04):
                parts.append(self.cyl(on_tube(a), on_tube(a + 0.008), tube_r + 0.002, None, "leather", 10, 0.0, "tube_band"))
        for part in parts:
            self.k.moves(part, near, pivot)
        y = b.shoulder_y
        free = [
            self.ball((0.0, y, b.shoulder_z + 0.004), (b.shoulder_r, b.shoulder_r * 0.9, b.shoulder_r * 0.78), "armour", label="pad"),
            self.tube(
                [
                    ((0.0, y, b.shoulder_z), b.arm_r * 0.96, b.arm_r),
                    ((0.004, y * 1.05, 0.118), b.arm_r, b.arm_r),
                    ((0.03, y * 1.02, 0.078), b.arm_r * 0.92, b.arm_r * 0.92),
                ],
                "team",
                label="sleeve",
            ),
            self.ball((0.036, y, 0.066), (0.026, 0.026, 0.026), "team_dark", label="gauntlet"),
        ]
        for part in free:
            self.k.moves(part, far, pivot)
        return Vector(self.p(*on_tube(tip)))

    def _tunic_front(self, y: float, z: float) -> float:
        """How far forward the tunic's surface stands at a height, `y` across it."""
        rings = self.b.torso
        for (z0, rx0, ry0), (z1, rx1, ry1) in zip(rings, rings[1:]):
            if z0 <= z <= z1:
                t = (z - z0) / (z1 - z0)
                rx, ry = rx0 + (rx1 - rx0) * t, ry0 + (ry1 - ry0) * t
                return rx * math.sqrt(max(1.0 - (y / ry) ** 2, 0.0))
        return 0.0

    def small_pack(self) -> None:
        x = -self.b.torso[3][1] - 0.02
        self.box((x, 0.0, 0.132), (0.046, 0.094, 0.076), "team_dark", 0.011, taper=0.92, label="pack")
        self.cyl((x + 0.002, -0.05, 0.178), (x + 0.002, 0.05, 0.178), 0.019, None, "canvas", 8, 0.0, "bedroll")
        if self.k.hi:
            self.box((x - 0.024, 0.0, 0.12), (0.004, 0.06, 0.028), "team", 0.0, label="flap")
            for side in (-1.0, 1.0):
                y = side * 0.034
                straps = [(self._tunic_front(y, z) + 0.001, y, z) for z in (0.166, 0.15, 0.13, 0.112)]
                self.tube([(at, 0.0028, 0.0075) for at in straps], "leather", 6, "webbing")

    def big_pack(self) -> None:
        b = self.b
        x = -b.torso[3][1] - 0.032
        self.box((x, 0.0, 0.138), (0.078, 0.15, 0.118), "team_dark", 0.016, taper=0.94, label="pack")
        self.box((x - 0.022, 0.0, 0.112), (0.05, 0.108, 0.052), "team", 0.01, label="pouch")
        self.cyl((x + 0.004, -0.072, 0.208), (x + 0.004, 0.072, 0.208), 0.027, None, "canvas", 10, 0.0, "bedroll")
        # Armour over the chest, what makes him a heavy at a glance.
        chest = b.torso[3]
        self.box((chest[1] * 0.72, 0.0, chest[0] - 0.008), (0.034, chest[2] * 1.5, 0.066), "armour", 0.012, taper=0.9, label="breastplate")
        if self.k.hi:
            plate_x = chest[1] * 0.72 + 0.017
            self.k.rivets([self.p(plate_x, side * 0.044, chest[0] + 0.012) for side in (-1.0, 1.0)], (1, 0, 0), 0.006 * self.s)
            for dz in (0.145, 0.105):
                self.box((x - 0.037, 0.0, dz), (0.004, 0.11, 0.008), "leather", 0.0, label="pack_strap")

    def stand(self) -> None:
        self.k.cull = False
        self.legs()
        self.torso()
        self.head()
        self.helmet()


def rifleman(k: Kit, x: float, y: float, s: float, phase: int) -> Vector:
    man = Man(k, x, y, s, RIFLEMAN, phase)
    man.stand()
    man.small_pack()
    return man.rifle_arms()


def trooper(k: Kit, x: float, y: float, s: float, phase: int) -> Vector:
    man = Man(k, x, y, s, TROOPER, phase)
    man.stand()
    man.big_pack()
    return man.tube_arms()
