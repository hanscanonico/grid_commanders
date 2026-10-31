"""The airport: a runway painted across the cell, a control tower, a round-backed hangar.

The runway runs the whole width at the front, where a unit stands, so its stripes
meet the next airport's; the tower and the hangar keep to the back.
"""

from __future__ import annotations

import math

from ..kit import Kit
from ..paint import Role, grey
from .parts import PLINTH, paving, window

# Paint laid on the runway, kept free of the road dust that would break up its lines.
ROLES = {
    "asphalt": Role((0.085, 0.09, 0.1), edge=0.5, dust=0.0, wash=0.6, roughness=0.95),
    "line": Role((0.72, 0.7, 0.62), edge=0.4, dust=0.0, wash=0.4, roughness=0.8),
    "team_line": Role(grey(0.6), team=True, edge=0.3, dust=0.0, wash=0.4, roughness=0.8),
}

RUNWAY_NEAR = -0.41
RUNWAY_FAR = -0.03
RUNWAY_TOP = PLINTH + 0.007
TERMINAL_HEIGHT = 0.125
TOWER_X = -0.315
TOWER_Y = 0.335
HANGAR_X = 0.2
HANGAR_HALF = 0.25
HANGAR_RISE = 0.27
HANGAR_FRONT = 0.1
HANGAR_BACK = 0.44


def _runway(k: Kit) -> None:
    middle = (RUNWAY_NEAR + RUNWAY_FAR) / 2
    width = RUNWAY_FAR - RUNWAY_NEAR
    k.box((0, middle, PLINTH + 0.0035), (0.92, width, 0.007), "asphalt", 0.0, label="runway")
    if not k.hi:
        return
    z = RUNWAY_TOP + 0.001
    # The centre line in big dashes, off the piano keys at each end.
    for x in (-0.19, 0.0, 0.19):
        k.box((x, middle, z), (0.11, 0.032, 0.004), "line", 0.0, label="dash")
    # Piano keys at both thresholds: the mark that says "runway" at any size.
    keys = 6
    pitch = (width - 0.06) / keys
    for side in (-1.0, 1.0):
        for i in range(keys):
            ky = RUNWAY_NEAR + 0.03 + (i + 0.5) * pitch
            k.box((side * 0.385, ky, z), (0.1, pitch * 0.58, 0.004), "line", 0.0, label="key")
    # The army's colour runs down both edges.
    for ey in (RUNWAY_NEAR + 0.016, RUNWAY_FAR - 0.016):
        k.box((0, ey, z), (0.92, 0.028, 0.004), "team_line", 0.0, label="edge")


def _apron(k: Kit) -> None:
    paving(k, -0.445, 0.445, RUNWAY_FAR + 0.006, 0.445, PLINTH, 0.13, 1.5, gap=0.009)
    if not k.hi:
        return
    z = PLINTH + 0.0035
    # The taxi line, off the runway into the hangar's mouth.
    k.box((HANGAR_X, 0.03, z), (0.02, 0.13, 0.004), "brass", 0.0, label="taxi")
    k.box((HANGAR_X - 0.15, RUNWAY_FAR + 0.018, z), (0.31, 0.02, 0.004), "brass", 0.0, label="taxi")


def _terminal(k: Kit) -> None:
    """The flat-roofed block the tower stands on, its roof wearing the badge."""
    x, y = -0.3, 0.27
    sx, sy = 0.29, 0.31
    z = PLINTH
    k.box((x, y, z + TERMINAL_HEIGHT / 2), (sx, sy, TERMINAL_HEIGHT), "plaster", 0.008, label="walls")
    k.box((x, y, z + 0.018), (sx + 0.016, sy + 0.016, 0.036), "stone", 0.007, label="footing")
    k.box((x, y, z + TERMINAL_HEIGHT + 0.009), (sx + 0.022, sy + 0.022, 0.018), "team", 0.006, label="roof")
    front = y - sy / 2
    for wx in (-0.08, 0.08):
        window(k, x + wx, front, z + 0.082, "front", w=0.045, h=0.058)
    window(k, x + sx / 2, y - 0.06, z + 0.082, "right", w=0.06, h=0.058)
    window(k, x + sx / 2, y + 0.06, z + 0.082, "right", w=0.06, h=0.058)
    k.box((x, front - 0.008, z + 0.05), (0.05, 0.016, 0.1), "team_dark", 0.004, label="door")
    k.box((x, front - 0.03, z + 0.098), (0.11, 0.05, 0.012), "team_light", 0.003, label="canopy")
    k.box((x, front - 0.03, z + 0.008), (0.1, 0.05, 0.016), "stone", 0.004, label="step")


def _tower(k: Kit) -> None:
    z = PLINTH + TERMINAL_HEIGHT + 0.018
    x, y = TOWER_X, TOWER_Y
    neck = 0.46
    k.cyl((x, y, z), (x, y, neck), 0.066, 0.05, "plaster", 8, 0.006, "shaft")
    k.cyl((x, y, 0.3), (x, y, 0.326), 0.066, 0.064, "team_dark", 8, 0.003, "shaft_band")
    # The cab flares out toward the lens: the shape that says tower.
    k.cyl((x, y, neck - 0.008), (x, y, neck + 0.02), 0.052, 0.09, "team_dark", 8, 0.003, "gallery")
    cab = neck + 0.02
    k.cyl((x, y, cab), (x, y, cab + 0.068), 0.082, 0.112, "glass", 8, 0.003, "cab")
    top = cab + 0.068
    k.cyl((x, y, top), (x, y, top + 0.028), 0.09, 0.056, "team", 8, 0.006, "cab_roof")
    k.cyl((x, y, top + 0.028), (x, y, top + 0.052), 0.05, 0.016, "team_light", 8, 0.002, "cap")
    k.cyl((x, y, top + 0.05), (x, y, 0.655), 0.007, 0.005, "gunmetal", 6, 0.0, "mast")
    k.box((x + 0.012, y, top + 0.085), (0.064, 0.016, 0.018), "steel", 0.003, label="radar")
    if not k.hi:
        return
    # Mullions up the cab's eight faces.
    for i in range(8):
        angle = math.tau * (i + 0.5) / 8
        p0 = (x + 0.084 * math.cos(angle), y + 0.084 * math.sin(angle), cab)
        p1 = (x + 0.114 * math.cos(angle), y + 0.114 * math.sin(angle), top)
        k.cyl(p0, p1, 0.0035, None, "bone", 4, 0.0, "mullion")
    for i in range(4):
        wz = z + 0.05 + i * 0.05
        k.box((x, y - 0.062, wz), (0.016, 0.006, 0.024), "glass", 0.0, label="slit")


def _vault(half: float, rise: float, base: float, segments: int) -> list[tuple[float, float]]:
    """A half-ellipse from the left foot over to the right, at the hangar's middle."""
    points = []
    for i in range(segments + 1):
        t = math.pi - math.pi * i / segments
        points.append((HANGAR_X + half * math.cos(t), base + rise * math.sin(t)))
    return points


def _hangar(k: Kit) -> None:
    base = PLINTH
    segments = 10 if not k.hi else 20
    outer = _vault(HANGAR_HALF, HANGAR_RISE, base, segments)
    inner = _vault(HANGAR_HALF - 0.022, HANGAR_RISE - 0.022, base, segments)
    # The shell: a thick arch, so its front edge is a band of army colour round the mouth.
    k.side_profile([*outer, *reversed(inner)], HANGAR_FRONT, HANGAR_BACK, "team", 0.004, "shell")
    k.side_profile(inner, HANGAR_FRONT + 0.016, HANGAR_BACK - 0.004, "plaster", 0.0, "gable")
    # Corrugations over the back: standing ribs the wash can pool between.
    if k.hi:
        rib_outer = _vault(HANGAR_HALF + 0.004, HANGAR_RISE + 0.004, base, segments)
        rib_inner = _vault(HANGAR_HALF - 0.006, HANGAR_RISE - 0.006, base, segments)
        ribs = 9
        for i in range(1, ribs):
            ry = HANGAR_FRONT + (HANGAR_BACK - HANGAR_FRONT) * i / ribs
            k.side_profile([*rib_outer, *reversed(rib_inner)], ry - 0.004, ry + 0.004, "team_dark", 0.0, "rib")
    # The mouth: dark inside, two sliding leaves parted across it.
    mouth_y = HANGAR_FRONT + 0.012
    mouth_half = HANGAR_HALF - 0.05
    k.box((HANGAR_X, mouth_y, base + 0.078), (mouth_half * 2, 0.012, 0.156), "gunmetal", 0.0, label="mouth")
    leaf = mouth_half * 0.46
    for side in (-1.0, 1.0):
        k.box((HANGAR_X + side * (mouth_half - leaf / 2), mouth_y - 0.012, base + 0.08), (leaf, 0.012, 0.16), "team_light", 0.003, label="leaf")
        if k.hi:
            for i in range(1, 4):
                seam_x = HANGAR_X + side * (mouth_half - leaf * i / 4)
                k.box((seam_x, mouth_y - 0.019, base + 0.08), (0.004, 0.003, 0.16), "team", 0.0, label="leaf_seam")
    k.box((HANGAR_X, mouth_y - 0.014, base + 0.172), (mouth_half * 2 + 0.03, 0.018, 0.02), "team_dark", 0.004, label="door_rail")


def _windsock(k: Kit, x: float, y: float) -> None:
    top = PLINTH + 0.25
    k.cyl((x, y, PLINTH), (x, y, top), 0.008, 0.006, "gunmetal", 6, 0.0, "sock_pole")
    k.box((x, y, PLINTH + 0.008), (0.05, 0.05, 0.016), "stone", 0.004, label="sock_foot")
    mouth = (x + 0.006, y, top - 0.006)
    tail = (x + 0.125, y - 0.008, top - 0.038)
    k.cyl(mouth, tail, 0.03, 0.013, "team_light", 8, 0.0, "sock")
    if k.hi:
        for t in (0.34, 0.68):
            cx = mouth[0] + (tail[0] - mouth[0]) * t
            cy = mouth[1] + (tail[1] - mouth[1]) * t
            cz = mouth[2] + (tail[2] - mouth[2]) * t
            r = 0.03 + (0.013 - 0.03) * t + 0.002
            k.cyl((cx - 0.01, cy, cz), (cx + 0.01, cy, cz - 0.003), r, r * 0.92, "bone", 8, 0.0, "sock_band")


def _drums(k: Kit, x: float, y: float) -> None:
    k.cyl((x, y, PLINTH), (x, y, PLINTH + 0.062), 0.027, None, "team_dark", 10, 0.004, "drum")
    k.cyl((x + 0.06, y + 0.012, PLINTH), (x + 0.06, y + 0.012, PLINTH + 0.062), 0.027, None, "steel", 10, 0.004, "drum")
    k.box((x + 0.012, y - 0.052, PLINTH + 0.024), (0.08, 0.05, 0.048), "wood", 0.005, label="crate")


def build(k: Kit) -> None:
    k.box((0, 0, PLINTH / 2), (0.92, 0.92, PLINTH), "stone", 0.012, label="plinth")
    _apron(k)
    _runway(k)
    _terminal(k)
    _tower(k)
    _hangar(k)
    _windsock(k, 0.325, 0.03)
    _drums(k, -0.41, 0.04)
    z = PLINTH + TERMINAL_HEIGHT + 0.018
    k.marker("emblem", (-0.3, 0.18, z))
    k.marker("emblem_edge", (-0.235, 0.18, z))
