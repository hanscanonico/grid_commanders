"""What the property buildings share: the plinth, houses, roofs, parapets, flags, stars.

A property stands on a stone slab with its tall masses at the back (+Y) and the
sides. Walls stay pale for every owner; everything in a `team` role says whose it is.
"""

from __future__ import annotations

import math
from collections.abc import Sequence

import bmesh
import bpy
from mathutils import Matrix

from ..kit import Kit

PLINTH = 0.035


def flatten_small_bevels(k: Kit, below: float = 0.01) -> None:
    """Spares the game's copy the small bevels: the bake paints their highlights anyway."""
    if k.hi:
        return
    for part in k.parts:
        bevel = part.modifiers.get("bevel")
        if bevel is not None and bevel.width < below:
            part.modifiers.remove(bevel)


def uncap(k: Kit, part: bpy.types.Object, top: bool = True, bottom: bool = True) -> bpy.types.Object:
    """Takes a hidden end off a round part on the game's copy: triangles and texture saved."""
    if k.hi:
        return part
    _, axis, _, _ = k.round_parts[part.name]
    bm = bmesh.new()
    bm.from_mesh(part.data)
    bm.normal_update()
    doomed = []
    for face in bm.faces:
        along = face.normal.dot(axis)
        if (top and along > 0.85) or (bottom and along < -0.85):
            doomed.append(face)
    bmesh.ops.delete(bm, geom=doomed, context="FACES_ONLY")
    bm.to_mesh(part.data)
    bm.free()
    return part


def window(k: Kit, x: float, y: float, z: float, facing: str, w: float = 0.05, h: float = 0.066) -> None:
    """A shuttered window only the bake sees, on the +X, -X or -Y wall."""
    if not k.hi:
        return
    depth = 0.006
    if facing == "front":
        k.box((x, y - depth / 2, z), (w + 0.014, depth, h + 0.014), "bone", 0.0, label="frame")
        k.box((x, y - depth, z), (w, depth, h), "glass", 0.0, label="pane")
        k.box((x, y - depth * 1.5, z), (w, 0.003, 0.005), "bone", 0.0, label="bar")
        k.box((x, y - depth * 1.5, z), (0.005, 0.003, h), "bone", 0.0, label="bar")
        for side in (-1.0, 1.0):
            k.box(
                (x + side * (w / 2 + 0.019), y - depth, z), (0.024, depth, h + 0.008), "team_dark", 0.0, label="shutter"
            )
    else:
        sign = 1.0 if facing == "right" else -1.0
        k.box((x + sign * depth / 2, y, z), (depth, w + 0.014, h + 0.014), "bone", 0.0, label="frame")
        k.box((x + sign * depth, y, z), (depth, w, h), "glass", 0.0, label="pane")
        k.box((x + sign * depth * 1.5, y, z), (0.003, w, 0.005), "bone", 0.0, label="bar")
        k.box((x + sign * depth * 1.5, y, z), (0.003, 0.005, h), "bone", 0.0, label="bar")


def gable_roof(
    k: Kit, x: float, y: float, wall_top: float, sx: float, sy: float, rise: float, role: str = "team"
) -> None:
    """A tiled roof with its ridge along Y, overhanging, courses stepped on the bake's copy."""
    half = sx / 2 + 0.024
    y0, y1 = y - sy / 2 - 0.026, y + sy / 2 + 0.026
    base = wall_top - 0.006
    if k.hi:
        courses = 7
        outline = [(x - half, base - 0.006)]
        for side, rng in ((-1.0, range(courses)), (1.0, range(courses, 0, -1))):
            for i in rng:
                t0, t1 = i / courses, (i + (1 if side < 0 else -1)) / courses
                outline.append((x + side * half * (1 - t0), base + rise * t0 + 0.012))
                outline.append((x + side * half * (1 - t1), base + rise * t1))
        outline.append((x + half, base - 0.006))
        k.side_profile(outline, y0, y1, role, 0.0, "tiles")
    else:
        outline = [(x - half, base - 0.006), (x + half, base - 0.006), (x, base + rise + 0.01)]
        k.side_profile(outline, y0, y1, role, 0.006, "roof")
    k.box((x, y, base + rise + 0.012), (0.026, sy + 0.06, 0.022), "team_dark", 0.008, label="ridge")


def house(k: Kit, x: float, y: float, sx: float, sy: float, h: float, floors: int, rise: float) -> None:
    z = PLINTH
    k.box((x, y, z + h / 2), (sx, sy, h), "plaster", 0.008, label="walls")
    k.box((x, y, z + 0.018), (sx + 0.016, sy + 0.016, 0.036), "stone", 0.007, label="footing")
    gable_roof(k, x, y, z + h, sx, sy, rise)
    front = y - sy / 2
    right = x + sx / 2
    for floor in range(floors):
        wz = z + 0.09 + floor * (h - 0.05) / floors
        for dx in (-0.25, 0.25):
            window(k, x + dx * sx, front, wz, "front")
        for dy in (-0.25, 0.25):
            window(k, right, y + dy * sy, wz, "right")
        if floor > 0:
            k.seam((x, front - 0.001, wz - 0.058), (sx, 0.004, 0.007), "wood")


def square(k: Kit) -> None:
    """The city's cobbled slab."""
    k.box((0, 0, PLINTH / 2), (0.92, 0.92, PLINTH), "stone", 0.012, label="plinth")
    if not k.hi:
        return
    # Cobbles for the wash to run between: the lens sees them at every zoom.
    for i in range(16):
        for j in range(16):
            cx = -0.42 + i * 0.056 + (0.028 if j % 2 else 0.0)
            cy = -0.42 + j * 0.056
            if abs(cx) < 0.43:
                k.box((cx, cy, PLINTH + 0.001), (0.05, 0.05, 0.004), "stone", 0.0, label="cobble")


def paving(
    k: Kit,
    x0: float,
    x1: float,
    y0: float,
    y1: float,
    z: float,
    size: float = 0.1,
    long: float = 1.0,
    role: str = "stone",
    gap: float = 0.007,
) -> None:
    """Laid slabs in running bond, on the bake's copy only: wash runs in the joints."""
    if not k.hi:
        return
    rows = max(1, round((y1 - y0) / size))
    depth = (y1 - y0) / rows
    width = size * long
    for j in range(rows):
        cy = y0 + (j + 0.5) * depth
        start = x0 + (width / 2 if j % 2 else 0.0)
        for i in range(math.ceil((x1 - x0) / width) + 1):
            a, b = max(x0, start + (i - 1) * width), min(x1, start + i * width)
            if b - a <= gap:
                continue
            k.box(((a + b) / 2, cy, z + 0.001), (b - a - gap, depth - gap, 0.004), role, 0.0, label="slab")


def slope(
    p0: tuple[float, float], p1: tuple[float, float], courses: int, lap: float = 0.008
) -> list[tuple[float, float]]:
    """A line from `p0` to `p1` stepped into laps, as sheets or tiles overlap down a roof."""
    points = []
    for i in range(courses):
        a, b = i / courses, (i + 1) / courses
        points.append((p0[0] + (p1[0] - p0[0]) * a, p0[1] + (p1[1] - p0[1]) * a + lap))
        points.append((p0[0] + (p1[0] - p0[0]) * b, p0[1] + (p1[1] - p0[1]) * b))
    return points


def _across_x(obj: bpy.types.Object, cx: float, cy: float) -> bpy.types.Object:
    """Turns a part drawn with its Y across the model so it runs along X instead."""
    obj.matrix_world = Matrix.Translation((cx, cy, 0.0)) @ Matrix.Rotation(math.pi / 2, 4, "Z")
    return obj


def long_gable(
    k: Kit,
    cx: float,
    cy: float,
    wall_top: float,
    sx: float,
    sy: float,
    rise: float,
    role: str = "team",
    courses: int = 6,
) -> None:
    """A roof with its ridge along X, so its broad slope faces the lens."""
    half = sy / 2 + 0.024
    base = wall_top - 0.006
    run = sx / 2 + 0.026
    if k.hi:
        outline = [(-half, base - 0.006)]
        outline += slope((-half, base), (0.0, base + rise), courses, lap=0.012)
        outline += slope((0.0, base + rise), (half, base), courses, lap=0.0)
        outline.append((half, base - 0.006))
        _across_x(k.side_profile(outline, -run, run, role, 0.0, "tiles"), cx, cy)
    else:
        outline = [(half, base - 0.006), (0.0, base + rise + 0.01), (-half, base - 0.006)]
        _across_x(k.side_profile(outline, -run, run, role, 0.006, "roof"), cx, cy)
    k.box((cx, cy, base + rise + 0.012), (sx + 0.06, 0.026, 0.022), "team_dark", 0.008, label="ridge")


def battlement(
    k: Kit,
    centre: Sequence[float],
    length: float,
    z: float,
    merlons: int,
    along: str = "x",
    role: str = "plaster",
    thick: float = 0.034,
    wall: float = 0.03,
    tooth: float = 0.036,
) -> bpy.types.Object:
    """A parapet with its teeth, one extruded outline so a long run stays cheap."""
    half = length / 2
    pitch = length / merlons
    outline = [(-half, z), (half, z)]
    for i in range(merlons, 0, -1):
        right = -half + i * pitch
        left = right - pitch * 0.62
        outline += [(right, z + wall + tooth), (left, z + wall + tooth), (left, z + wall), (right - pitch, z + wall)]
    part = k.side_profile(outline, -thick / 2, thick / 2, role, 0.004, "battlement")
    if along == "x":
        part.matrix_world = Matrix.Translation((centre[0], centre[1], 0.0))
    else:
        _across_x(part, centre[0], centre[1])
    return part


def merlon_ring(
    k: Kit, x: float, y: float, z: float, r: float, count: int, role: str = "plaster", h: float = 0.03
) -> None:
    """The teeth round a tower's top, unbevelled on the game's copy to stay cheap."""
    width = math.tau * r / count * 0.58
    for i in range(count):
        angle = math.tau * i / count
        part = k.box((0, 0, 0), (0.026, width, h), role, 0.003 if k.hi else 0.0, label="merlon")
        part.matrix_world = Matrix.Translation(
            (x + r * math.cos(angle), y + r * math.sin(angle), z + h / 2)
        ) @ Matrix.Rotation(angle, 4, "Z")
        k.boost(part, 0.55)


def dome(
    k: Kit,
    x: float,
    y: float,
    z: float,
    rx: float,
    rz: float,
    role: str = "team",
    rings: int = 6,
    sides: int = 12,
    power: float = 1.0,
    label: str = "dome",
) -> bpy.types.Object:
    """A half-egg standing on `z`. A `power` above one draws the crown in to a point."""
    rings = rings * 2 if k.hi else rings
    sides = sides * 2 if k.hi else sides
    sections = []
    for i in range(rings):
        t = i / rings
        phi = t * math.pi / 2
        radius = rx * math.cos(phi) ** power
        sections.append(
            (
                rz * math.sin(phi),
                [
                    (radius * math.cos(math.tau * j / sides), radius * math.sin(math.tau * j / sides))
                    for j in range(sides)
                ],
            )
        )
    tip = rx * 0.05
    sections.append(
        (rz, [(tip * math.cos(math.tau * j / sides), tip * math.sin(math.tau * j / sides)) for j in range(sides)])
    )
    return k.loft(sections, role, 0.0, (x, y, z), label)


def star_outline(r: float, inner: float = 0.42, points: int = 5, turn: float = 0.0) -> list[tuple[float, float]]:
    """A star's XZ outline round the origin, one point up."""
    outline = []
    for i in range(points * 2):
        angle = math.pi / 2 + turn + math.tau * i / (points * 2)
        reach = r if i % 2 == 0 else r * inner
        outline.append((reach * math.cos(angle), reach * math.sin(angle)))
    return outline


def wall_star(
    k: Kit,
    x: float,
    y: float,
    z: float,
    r: float,
    role: str = "brass",
    depth: float = 0.012,
    lean: float = 0.0,
    bevel: float = 0.003,
) -> bpy.types.Object:
    """A star on a wall that faces -Y; `lean` tips its top back toward the lens."""
    part = k.side_profile(star_outline(r), -depth, 0.0, role, bevel, "star")
    part.matrix_world = Matrix.Translation((x, y, z)) @ Matrix.Rotation(-lean, 4, "X")
    return part


def flag(
    k: Kit,
    x: float,
    y: float,
    z0: float,
    z1: float,
    w: float,
    h: float,
    role: str = "team_light",
    pole_r: float = 0.008,
    tail: float = 0.0,
    thick: float = 0.012,
) -> None:
    """A pole and a flag flying to +X, its broad face to the lens; `tail` cuts a swallowtail."""
    k.cyl((x, y, z0), (x, y, z1), pole_r, pole_r * 0.8, "gunmetal", 6, 0.0, "pole")
    top = z1 - 0.004
    bottom = top - h
    mid = (top + bottom) / 2
    wave = h * 0.1
    outline = [
        (x, bottom),
        (x + w * 0.5, bottom - wave),
        (x + w, bottom + wave * 0.6),
        (x + w - tail, mid),
        (x + w, top + wave * 0.6),
        (x + w * 0.5, top - wave),
        (x, top),
    ]
    k.side_profile(outline, y - thick / 2, y + thick / 2, role, 0.002, "flag")
