"""A general as a painted figure: parts in the army's colours on a skeleton.

Every bone stands straight up in the rest pose, so the game's `ActorPose3D` poses
it with the same angles it gives the old figure: +X on a limb swings it forward.
The clips live in the game, as pure functions of its clock. The figure faces +Y
here, which is the game's -Z, and its right hand is on +X.
"""

from __future__ import annotations

import math
from dataclasses import dataclass

import bpy
from mathutils import Vector

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
    hip=0.19, shoulder=0.345, head_z=0.47, head_r=0.128, hip_w=0.082, chest_w=0.09, chest_d=0.062,
    leg_r=0.033, arm_r=0.026, arm_len=0.17, shoulder_x=0.13, leg_x=0.05, foot=0.05, hem=0.115,
)


def linear(r: int, g: int, b: int) -> tuple[float, float, float]:
    def one(c: int) -> float:
        v = c / 255
        return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4

    return (one(r), one(g), one(b))


def looks_roles(skin: tuple[int, int, int], hair: tuple[int, int, int]) -> dict[str, Role]:
    return {
        "skin": Role(linear(*skin), edge=0.0, wash=0.55, dust=0.0),
        "blush": Role(tuple(c * m for c, m in zip(linear(*skin), (1.0, 0.62, 0.58))), edge=0.0, wash=0.2, dust=0.0),
        "hair": Role(linear(*hair), edge=0.0, wash=1.0, dust=0.0),
        "hair_lit": Role(tuple(min(1.0, c * 1.7 + 0.02) for c in linear(*hair)), edge=0.0, wash=0.6, dust=0.0),
        "eye_white": Role((0.86, 0.86, 0.82), edge=0.0, wash=0.25, dust=0.0),
        "iris": Role((0.05, 0.2, 0.34), edge=0.0, wash=0.1, dust=0.0),
        "ink": Role((0.012, 0.01, 0.012), edge=0.0, wash=0.0, dust=0.0),
        "spark": Role((1.0, 1.0, 1.0), edge=0.0, wash=0.0, dust=0.0),
        "lip": Role((0.34, 0.09, 0.08), edge=0.0, wash=0.2, dust=0.0),
        "gold": Role((0.62, 0.43, 0.13), edge=1.4, wash=0.7, dust=0.0),
        "boot": Role((0.045, 0.03, 0.025), edge=1.3, dust=0.12),
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


def build_legs(k: Kit, b: Body) -> None:
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
            "boot",
            0.004,
            label="boot",
        )
        k.bind(boot, rigid(shin))


def build_torso(k: Kit, b: Body) -> None:
    chest = b.shoulder - 0.03
    waist = b.hip + (b.shoulder - b.hip) * 0.28
    coat = k.loft(
        [
            (b.hem, ellipse(b.hip_w * 1.25, b.chest_d * 1.2)),
            (b.hip, ellipse(b.hip_w * 1.03, b.chest_d * 0.98)),
            (waist, ellipse(b.chest_w * 0.82, b.chest_d * 0.82)),
            (chest, ellipse(b.chest_w, b.chest_d)),
            (b.shoulder + 0.006, ellipse(b.chest_w * 0.9, b.chest_d * 0.82)),
            (b.shoulder + 0.022, ellipse(b.chest_w * 0.42, b.chest_d * 0.5)),
        ],
        "team",
        0.006,
        label="coat",
    )
    k.bind(coat, lambda co: {"hips": 1.0} if co.z < b.hip else {"torso": 1.0})
    belt_z = waist - 0.006
    belt = k.loft(
        [
            (belt_z - 0.012, ellipse(b.chest_w * 0.86, b.chest_d * 0.87)),
            (belt_z + 0.012, ellipse(b.chest_w * 0.86, b.chest_d * 0.87)),
        ],
        "boot",
        0.003,
        label="belt",
    )
    k.bind(belt, rigid("torso"))
    buckle = k.box((0, b.chest_d * 0.86, belt_z), (0.03, 0.008, 0.024), "gold", 0.002, label="buckle")
    k.bind(buckle, rigid("torso"))
    collar = k.loft(
        [
            (b.shoulder + 0.01, ellipse(b.chest_w * 0.52, b.chest_d * 0.62)),
            (b.shoulder + 0.038, ellipse(b.chest_w * 0.46, b.chest_d * 0.56)),
        ],
        "team_dark",
        0.004,
        label="collar",
    )
    k.bind(collar, rigid("torso"))
    for side in (-1.0, 1.0):
        epaulette = k.box(
            (side * b.shoulder_x * 0.98, 0, b.shoulder + 0.022), (0.05, 0.05, 0.014), "gold", 0.005, label="epaulette"
        )
        k.bind(epaulette, rigid("torso"))
    # The sash across the chest, the look's own: a band wrapped around the coat.
    sash = k.loft(
        [
            (chest + 0.004 - i * 0.0, ellipse(b.chest_w * (0.99 - 0.0), b.chest_d * 1.02))
            for i in range(0)
        ]
        or [
            (waist + 0.018, ellipse(b.chest_w * 0.88, b.chest_d * 0.9)),
            (waist + 0.036, ellipse(b.chest_w * 0.9, b.chest_d * 0.93)),
        ],
        "gold",
        0.002,
        label="sash",
    )
    k.bind(sash, rigid("torso"))
    for dz in (0.0, 0.03, 0.06):
        k.seam((0, b.chest_d * 0.97, waist + 0.02 + dz), (0.012, 0.004, 0.012), "gold")


def build_arms(k: Kit, b: Body) -> None:
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
        glove = k.ellipsoid((x2, 0.002, hand - 0.012), (b.arm_r * 0.92, b.arm_r, b.arm_r * 1.25), "boot", 6, 8, "glove")
        k.bind(glove, rigid(fore))


def build_sabre(k: Kit, b: Body) -> None:
    x = b.shoulder_x + 0.018
    z = b.shoulder - b.arm_len - 0.012
    length = min(z - 0.025, 0.26)
    grip = k.cyl((x, 0.0, z + 0.02), (x, 0.0, z - 0.03), 0.009, None, "boot", 6, 0.0, "grip")
    guard = k.box((x, 0.0, z - 0.034), (0.012, 0.05, 0.01), "gold", 0.003, label="guard")
    blade = k.box((x, 0.012, z - 0.034 - length / 2), (0.007, 0.024, length), "steel", 0.001, taper=0.7, label="blade")
    for part in (grip, guard, blade):
        k.bind(part, rigid("prop"))


def build_head(k: Kit, b: Body, big_eyes: float) -> None:
    r = b.head_r
    z = b.head_z
    neck = k.cyl((0, 0, b.shoulder), (0, 0, z - r * 0.7), r * 0.32 + 0.012, None, "skin", 8, 0.0, "neck")
    k.bind(neck, rigid("head"))
    rx, ry, rz = r * 0.97, r * 0.93, r * 1.02
    skull = k.ellipsoid((0, 0, z), (rx, ry, rz), "skin", 10, 16, "skull")
    k.bind(skull, rigid("head"))
    k.boost(skull, 1.8)
    for side in (-1.0, 1.0):
        ear = k.ellipsoid((side * rx, -0.004, z - r * 0.08), (r * 0.1, r * 0.13, r * 0.18), "skin", 5, 6, "ear")
        k.bind(ear, rigid("head"))
    nose = k.ellipsoid((0, ry + r * 0.015, z - r * 0.2), (r * 0.095, r * 0.09, r * 0.1), "skin", 5, 6, "nose")
    k.bind(nose, rigid("head"))
    if k.hi:
        _face(k, r, rx, ry, rz, z, big_eyes)
    _hair(k, b, rx, ry, rz)


def _on_face(rx: float, ry: float, rz: float, z0: float, x: float, z: float, lift: float = 0.0) -> Vector:
    q = 1.0 - (x / rx) ** 2 - ((z - z0) / rz) ** 2
    return Vector((x, ry * math.sqrt(max(q, 0.02)) + lift, z))


def _face(k: Kit, r: float, rx: float, ry: float, rz: float, z0: float, big: float) -> None:
    """The face is paint: flat discs laid on the skull that only the bake sees."""
    eye_x = r * 0.4
    eye_z = z0 - r * 0.02
    for side in (-1.0, 1.0):
        x = side * eye_x
        w, h = r * 0.2 * big, r * 0.28 * big
        k.ellipsoid(_on_face(rx, ry, rz, z0, x, eye_z, 0.0005), (w, 0.0035, h), "eye_white", 6, 14, "white")
        k.ellipsoid(_on_face(rx, ry, rz, z0, x + side * -w * 0.1, eye_z - h * 0.05, 0.0024), (w * 0.72, 0.0035, h * 0.8), "iris", 6, 14, "iris")
        k.ellipsoid(_on_face(rx, ry, rz, z0, x + side * -w * 0.1, eye_z - h * 0.03, 0.004), (w * 0.38, 0.0035, h * 0.46), "ink", 6, 12, "pupil")
        k.ellipsoid(_on_face(rx, ry, rz, z0, x + w * 0.28, eye_z + h * 0.36, 0.0055), (w * 0.22, 0.0035, h * 0.2), "spark", 5, 10, "spark")
        for i in range(17):
            t = i / 16
            lash_x = x + w * 1.08 * math.cos(math.pi * t)
            lash_z = eye_z + h * 0.97 * math.sin(math.pi * t) + h * 0.02
            k.ellipsoid(_on_face(rx, ry, rz, z0, lash_x, lash_z, 0.0045), (w * 0.14, 0.0035, r * 0.026), "ink", 4, 8, "lash")
        for i in range(15):
            t = i / 14
            brow_x = x - w * 0.95 + 1.9 * w * t
            brow_z = eye_z + h * 1.32 + r * 0.05 * math.sin(math.pi * t)
            k.ellipsoid(_on_face(rx, ry, rz, z0, brow_x, brow_z, 0.0015), (w * 0.14, 0.0035, r * 0.026), "hair", 4, 8, "brow")
        k.ellipsoid(_on_face(rx, ry, rz, z0, side * r * 0.62, z0 - r * 0.3, 0.0002), (r * 0.15, 0.0025, r * 0.09), "blush", 5, 10, "blush")
    for i in range(6):
        t = i / 5
        mx = -r * 0.14 + t * r * 0.28
        mz = z0 - r * 0.47 - r * 0.035 * math.sin(math.pi * t)
        k.ellipsoid(_on_face(rx, ry, rz, z0, mx, mz, 0.0015), (r * 0.04, 0.0035, r * 0.022), "lip", 4, 8, "mouth")


def _hair(k: Kit, b: Body, rx: float, ry: float, rz: float) -> None:
    """Long auburn hair: a soft crown, a fringe swept aside and a mane down the back."""
    r, z = b.head_r, b.head_z
    crown = k.ellipsoid((0, -r * 0.14, z + r * 0.2), (rx * 1.08, ry * 1.0, rz * 0.94), "hair", 9, 16, "crown")
    k.bind(crown, rigid("head"))
    fringe = k.ellipsoid((r * 0.3, ry * 0.62, z + r * 0.72), (r * 0.66, r * 0.34, r * 0.2), "hair", 6, 10, "fringe")
    k.bind(fringe, rigid("head"))
    fringe2 = k.ellipsoid((-r * 0.44, ry * 0.62, z + r * 0.68), (r * 0.44, r * 0.3, r * 0.2), "hair", 6, 10, "fringe")
    k.bind(fringe2, rigid("head"))
    mane_low = max(b.shoulder - (b.shoulder - b.hip) * 0.55, z - r * 2.2)
    mane = k.tube(
        [
            ((0, -ry * 0.52, z + r * 0.05), rx * 1.0, r * 0.62),
            ((0, -ry * 0.68, z - r * 0.5), rx * 1.08, r * 0.52),
            ((0, -ry * 0.72, b.shoulder + 0.01), rx * 1.0, r * 0.42),
            ((0, -ry * 0.72, mane_low + 0.03), rx * 0.78, r * 0.3),
            ((0, -ry * 0.7, mane_low), rx * 0.34, r * 0.12),
        ],
        "hair",
        12,
        "mane",
    )
    k.bind(mane, rigid("head"))
    for side in (-1.0, 1.0):
        lock = k.tube(
            [
                ((side * rx * 0.94, r * 0.12, z + r * 0.2), r * 0.17, r * 0.24),
                ((side * rx * 1.02, r * 0.08, z - r * 0.35), r * 0.17, r * 0.24),
                ((side * rx * 0.96, r * 0.12, z - r * 0.92), r * 0.13, r * 0.18),
                ((side * rx * 0.88, r * 0.16, z - r * 1.28), r * 0.03, r * 0.05),
            ],
            "hair",
            8,
            "lock",
        )
        k.bind(lock, rigid("head"))


def build_figure(k: Kit, b: Body, big_eyes: float) -> None:
    k.cull = False
    build_legs(k, b)
    build_torso(k, b)
    build_arms(k, b)
    build_sabre(k, b)
    build_head(k, b, big_eyes)


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


def rig_figure(low: bpy.types.Object, b: Body) -> None:
    rig = _armature(low, b)
    low.parent = rig
    modifier = low.modifiers.new("rig", "ARMATURE")
    modifier.object = rig
    for obj in bpy.data.objects:
        obj.select_set(False)
    rig.select_set(True)
    low.select_set(True)
    bpy.context.view_layer.objects.active = rig
