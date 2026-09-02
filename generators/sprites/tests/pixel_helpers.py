"""Pixel readings the contract suites share.

Colour, hue and coverage measures over a rendered sprite or tile, plus the
cached renderers that keep the suites from re-rendering the same cell.

Run with `.venv/bin/python -m unittest discover tests`.
"""

from __future__ import annotations

import colorsys
from collections import Counter
from functools import lru_cache

from PIL import Image

from spritegen import atlas, terrain
from spritegen.palette import Faction
from spritegen.terrain import CELL, ROAD, ROAD_DARK, WATER, WATER_DARK
from spritegen.units import AMBIENT_POSES, Pose

ROAD_TONES = {ROAD, ROAD_DARK}
WATER_TONES = {WATER, WATER_DARK}
# Edge midpoints, in N, E, S, W order, of a 64px tile.
EDGE_PROBES = (
    (CELL // 2, 0),
    (CELL - 1, CELL // 2),
    (CELL // 2, CELL - 1),
    (0, CELL // 2),
)


def saturation(rgb: tuple[int, int, int]) -> float:
    hi, lo = max(rgb), min(rgb)
    return 0.0 if hi == 0 else (hi - lo) / hi


def hue(rgb: tuple[int, int, int]) -> float:
    """Hue in degrees; 0 for a grey, which has none."""
    return colorsys.rgb_to_hsv(*(v / 255.0 for v in rgb))[0] * 360.0


def hue_gap(rgb: tuple[int, int, int], target: float) -> float:
    """Shortest angle, in degrees, between a colour's hue and `target`."""
    return abs((hue(rgb) - target + 180.0) % 360.0 - 180.0)


def opaque_pixels(img) -> list[tuple[int, int, int]]:
    """Every solid pixel of a sprite or tile, colour only."""
    img = img.convert("RGBA")
    px = img.load()
    return [
        px[x, y][:3]
        for y in range(img.height)
        for x in range(img.width)
        if px[x, y][3] > 200
    ]


def _touches_transparency(px, w: int, h: int, x: int, y: int) -> bool:
    """Is this pixel on the silhouette? Diagonals and the frame edge count."""
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            nx, ny = x + dx, y + dy
            if not (0 <= nx < w and 0 <= ny < h) or px[nx, ny][3] != 255:
                return True
    return False


def share_above(pixels, level: float) -> float:
    """Fraction of `pixels` brighter than `level` — the ramp band measure."""
    return sum(1 for c in pixels if terrain.luminance(c) > level) / len(pixels)


def dominant(pixels) -> tuple[int, int, int]:
    return Counter(pixels).most_common(1)[0][0]


def faction_pixels(sprite_a, sprite_b) -> list[tuple[int, int, int]]:
    """Opaque pixels of `sprite_a` that carry team color — i.e. the ones that
    differ when the same sprite is rendered for another faction."""
    a, b = sprite_a.convert("RGBA"), sprite_b.convert("RGBA")
    pa, pb = a.load(), b.load()
    out = []
    for y in range(a.height):
        for x in range(a.width):
            if pa[x, y][3] > 200 and pa[x, y][:3] != pb[x, y][:3]:
                out.append(pa[x, y][:3])
    return out


# The renders the suites share. Every gate that reads composed art asks for it
# here, so one cell or one sheet is built once for the whole run instead of
# once per question — the suites between them ask the same handful of cells a
# few hundred times, and a cell costs ~35 ms. The images handed back are
# SHARED: read them, crop them, convert them, never paint on them. A gate that
# wants a fresh render — the determinism ones, which compare two builds — calls
# `atlas` directly and says so.


@lru_cache(maxsize=None)
def pose_cell(
    uid: str, fac: Faction, pose: Pose = Pose.A, shadow: bool = True
) -> Image.Image:
    """One composed unit cell."""
    return atlas.unit_cell(uid, fac, pose, shadow)


@lru_cache(maxsize=None)
def units_sheet(pose: Pose = Pose.A, shadow: bool = True) -> Image.Image:
    """One built units atlas — 18 units x 6 factions of `pose_cell`."""
    return atlas.build_units_atlas(pose, shadow)


@lru_cache(maxsize=None)
def terrain_sheet() -> Image.Image:
    """The built terrain atlas."""
    return atlas.build_terrain_atlas()


# Rung 1 of the board's zoom: BattleView scales the 64x96 cell by 0.25 per
# rung with nearest filtering, so the furthest the board zooms out samples the
# cell down to 16x24 texels, and a pose delta under 4 atlas px moves nothing a
# player can see. Both clips are read at this size.
RUNG_1_CELL = (16, 24)


def _rung1_delta(pa, pb, w: int, h: int) -> tuple[int, int]:
    """Rung-1 texels two already-loaded frames disagree on, and how many of
    those disagreements are the silhouette rather than the tone."""
    changed = silhouette = 0
    for y in range(h):
        for x in range(w):
            ca, cb = pa[x, y], pb[x, y]
            if ca != cb:
                changed += 1
                if (ca[3] > 128) != (cb[3] > 128):
                    silhouette += 1
    return changed, silhouette


def rung1_texels(
    uid: str, fac: Faction, poses: tuple[Pose, ...] = AMBIENT_POSES
) -> tuple[int, int]:
    """Rung-1 texels a clip's poses disagree on frame-to-frame, worst adjacent
    step first, and how many of those disagreements are the silhouette rather
    than the tone.

    A two-pose clip (the ambient pair) has one step, read both ways, so this
    is unchanged for every caller that predates the move clip's growth to
    four (S6): the worst of a symmetric pair is itself. A four-pose clip is
    read AROUND the cycle — A-B, B-C, C-D, D-A — and the worst of the four is
    what stands for the clip, since a floor exists to catch the QUIETEST step
    a gait takes, not its busiest.
    """
    w, h = RUNG_1_CELL
    cells = [
        pose_cell(uid, fac, pose).resize(RUNG_1_CELL, Image.NEAREST).load()
        for pose in poses
    ]
    worst_changed, worst_silhouette = None, None
    for i in range(len(cells)):
        changed, silhouette = _rung1_delta(cells[i], cells[(i + 1) % len(cells)], w, h)
        if worst_silhouette is None or silhouette < worst_silhouette:
            worst_changed, worst_silhouette = changed, silhouette
    return worst_changed, worst_silhouette
