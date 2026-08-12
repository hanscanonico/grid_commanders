#!/usr/bin/env python3
"""Procedural pixel-art sprite generator.

Generates game-ready sprites (creatures, ships, items, robots, tanks) as
transparent PNGs using a classic pipeline:

  1. Shape   - random noise on a half-grid, shaped by a per-type density mask,
               mirrored for symmetry, smoothed with cellular-automata steps,
               then reduced to the largest connected blob.
  2. Color   - a harmonious 5-tone ramp built from a base hue (shadows shift
               toward blue, highlights toward yellow), plus an accent ramp
               painted in symmetric blobs.
  3. Light   - directional shading (light from the top), edge darkening and a
               touch of dithering so surfaces read as volume.
  4. Details - per-type touches: eyes for creatures, a cockpit and engine glow
               for ships, gem facets for items, panel lines for robots. Tanks
               get a full top-down repaint driven by a part map: link-textured
               treads wrapped over sprockets, a lit glacis plate, engine-deck
               vents and exhausts, a round-shaded turret with hatch and
               stowage bustle, a gun with mantlet, bore evacuator and muzzle
               brake, plus drop shadows, camo patches and weathering. Every
               detail scales with resolution, so tanks default to a 160px
               grid (~100x the pixels of the 16px default).
  5. Finish  - 1px outline in a dark tint of the body color, nearest-neighbor
               upscale, optional spritesheet assembly.

Every sprite is reproducible from its seed (printed and embeddable in the
filename), so a sprite you like can always be regenerated at another scale.

Usage examples:
  python sprite_generator.py                          # 32 mixed sprites + sheet
  python sprite_generator.py --kind creature -n 16
  python sprite_generator.py --size 24 --scale 10 --seed 1234
  python sprite_generator.py --kind ship --hue 0.58   # blue-ish ships
  python sprite_generator.py --kind tank -n 8         # 160x160 hi-detail tanks

  # 64x64 faction-colored unit sprites for ../grid_commanders (one file per
  # faction row of its units atlas, named <unit>_<faction>.png; tanks are one
  # curated hi-detail design, facing right like the game's unit art):
  python sprite_generator.py --preset grid-commanders \
      --names hover_tank:tank,gunship:ship --seed 42
"""

from __future__ import annotations

import argparse
import colorsys
import math
import random
from dataclasses import dataclass, field
from pathlib import Path

from PIL import Image

KINDS = ("creature", "ship", "item", "robot", "tank")

# Named faction palettes: the grid_commanders body colors, from that repo's
# tools/generate_unit_placeholders.gd (atlas rows neutral/red/blue/iron/verdant).
FACTIONS: dict[str, str] = {
    "neutral": "8a9099",
    "red": "d84a3c",
    "blue": "3c64d8",
    "iron": "4a5258",
    "verdant": "2c8636",
}
# grid_commanders unit outline color (same source).
GRID_COMMANDERS_OUTLINE = "14171c"
# Tank grid size under the grid-commanders preset: rendered at native scale it
# fills the 64px cell like the game's vendored unit art (which is drawn at the
# cell's own resolution, not chunky-upscaled) and clears the ~40px threshold
# where the tank painter's hatches, vents, headlights and exhausts switch on.
GRID_COMMANDERS_TANK_SIZE = 50
# The preset tank is a curated design, not a seed roll: this seed won a visual
# sweep at the size above (big round turret, stowage bustle, long gun with
# bore evacuator and muzzle brake, and an accent hue that stays inside every
# faction's color family). --seed keeps steering the other kinds.
GRID_COMMANDERS_TANK_SEED = 13


# --------------------------------------------------------------------------- #
# Color: palette ramps
# --------------------------------------------------------------------------- #

def _hsv_to_rgb(h: float, s: float, v: float) -> tuple[int, int, int]:
    r, g, b = colorsys.hsv_to_rgb(h % 1.0, max(0.0, min(1.0, s)), max(0.0, min(1.0, v)))
    return round(r * 255), round(g * 255), round(b * 255)


def _mix(a: tuple[int, int, int], b: tuple[int, int, int], t: float) -> tuple[int, int, int]:
    """Linear blend between two colors; the tank painter derives its fine
    gradients from these blends of ramp tones instead of adding more tones."""
    t = max(0.0, min(1.0, t))
    return (round(a[0] + (b[0] - a[0]) * t),
            round(a[1] + (b[1] - a[1]) * t),
            round(a[2] + (b[2] - a[2]) * t))


@dataclass
class Ramp:
    """A 5-tone shading ramp: outline, shadow, base, light, highlight."""

    outline: tuple[int, int, int]
    shadow: tuple[int, int, int]
    base: tuple[int, int, int]
    light: tuple[int, int, int]
    highlight: tuple[int, int, int]

    def tone(self, i: int) -> tuple[int, int, int]:
        return (self.shadow, self.base, self.light, self.highlight)[max(0, min(3, i))]


def make_ramp(hue: float, sat: float, val: float) -> Ramp:
    """Build a ramp with hue-shifting: shadows drift toward blue/purple,
    highlights toward yellow - the standard pixel-art trick that keeps
    shading lively instead of just darker/lighter."""
    return Ramp(
        outline=_hsv_to_rgb(hue + 0.055, min(1.0, sat * 1.15), val * 0.22),
        shadow=_hsv_to_rgb(hue + 0.045, min(1.0, sat * 1.12), val * 0.55),
        base=_hsv_to_rgb(hue, sat, val),
        light=_hsv_to_rgb(hue - 0.03, sat * 0.82, min(1.0, val * 1.25)),
        highlight=_hsv_to_rgb(hue - 0.055, sat * 0.55, min(1.0, val * 1.45)),
    )


@dataclass
class Palette:
    body: Ramp
    accent: Ramp
    seed_hue: float


def make_palette(rng: random.Random, hue: float | None = None,
                 sat: float | None = None, val: float | None = None,
                 muted: bool = False) -> Palette:
    """muted=True keeps saturation military-low and the accent analogous to
    the body hue - tanks read as machines, not candy."""
    h = rng.random() if hue is None else hue % 1.0
    if muted:
        if hue is None:
            # Bias free hues toward motor-pool paint: olive drab, desert tan,
            # blue-gray, with the odd wildcard so batches stay surprising.
            h = rng.choice((rng.uniform(0.20, 0.30), rng.uniform(0.09, 0.14),
                            rng.uniform(0.53, 0.62), rng.random()))
        s = rng.uniform(0.32, 0.55) if sat is None else sat
        if sat is None and rng.random() < 0.25:
            s = rng.uniform(0.08, 0.18)  # bare-steel gray
        v = rng.uniform(0.52, 0.68) if val is None else val
        shift = rng.choice((0.06, -0.06, 0.1, -0.1, 0.03))
        a_s = rng.uniform(0.35, 0.6)
        a_v = rng.uniform(0.6, 0.75)
    else:
        s = rng.uniform(0.55, 0.85) if sat is None else sat
        v = rng.uniform(0.62, 0.78) if val is None else val
        # Accent: complementary-ish or analogous, biased bright so it pops.
        shift = rng.choice((0.5, 0.33, -0.33, 0.12, -0.12))
        a_s = rng.uniform(0.6, 0.9)
        a_v = rng.uniform(0.7, 0.85)
    body = make_ramp(h, s, v)
    # With a fixed (faction) body color, rein the accent in toward it so a
    # muted gray body doesn't get a neon accent.
    if sat is not None:
        a_s = min(a_s, sat + 0.25)
    if val is not None:
        a_v = min(a_v, val + 0.3)
    accent = make_ramp(h + shift, a_s, a_v)
    return Palette(body=body, accent=accent, seed_hue=h)


# --------------------------------------------------------------------------- #
# Shape: masks, noise, cellular automata
# --------------------------------------------------------------------------- #

def _density_mask(kind: str, w: int, h: int) -> list[list[float]]:
    """Fill-probability multiplier per cell; shapes the silhouette per type."""
    mask = [[0.0] * w for _ in range(h)]
    cx = (w - 1) / 2.0
    cy = (h - 1) / 2.0
    for y in range(h):
        for x in range(w):
            nx = abs(x - cx) / (w / 2.0)   # 0 at center column, 1 at edge
            ny = (y - cy) / (h / 2.0)      # -1 top .. +1 bottom
            if kind == "creature":
                # Round-ish body, slightly bottom-heavy, thins at edges.
                d = math.hypot(nx, abs(ny) * 0.9)
                m = max(0.0, 1.15 - d * 1.05) + max(0.0, ny) * 0.15
            elif kind == "ship":
                # Fuselage along the center column, wings mid-body, tapered nose.
                fuselage = max(0.0, 1.0 - nx * 2.2)
                wings = max(0.0, 1.0 - nx * 1.1) * max(0.0, 1.0 - abs(ny - 0.25) * 2.0)
                nose_taper = 0.35 + 0.65 * min(1.0, (ny + 1.0) * 1.4)
                m = min(1.0, fuselage + wings * 0.9) * nose_taper
            elif kind == "item":
                # Compact and centered - gems, orbs, relics.
                d = math.hypot(nx, abs(ny))
                m = max(0.0, 1.25 - d * 1.35)
            else:  # robot/tank (unused: both are assembled from parts, not noise)
                m = 1.0
            mask[y][x] = max(0.0, min(1.0, m))
    return mask


def _robot_grid(rng: random.Random, w: int, h: int) -> list[list[int]]:
    """Robots are assembled from jittered rectangles (head/torso/arms/legs)
    rather than smoothed noise - noise alone never reads as 'machine'."""
    grid = [[0] * w for _ in range(h)]
    cx = (w - 1) / 2.0

    def stamp(x0: int, y0: int, x1: int, y1: int) -> None:
        for y in range(max(0, y0), min(h, y1 + 1)):
            for x in range(max(0, x0), min(w, x1 + 1)):
                grid[y][x] = 1

    # Torso
    torso_hw = rng.randint(max(2, w // 6), w // 3)          # half-width
    ty0 = rng.randint(int(h * 0.25), int(h * 0.35))
    ty1 = rng.randint(int(h * 0.6), int(h * 0.75))
    stamp(int(cx - torso_hw), ty0, math.ceil(cx + torso_hw), ty1)

    # Head (narrower, sits on the torso; sometimes with an antenna)
    head_hw = max(1, torso_hw - rng.randint(1, 2))
    hy0 = max(1, ty0 - rng.randint(3, max(4, h // 4)))
    stamp(int(cx - head_hw), hy0, math.ceil(cx + head_hw), ty0 - 1)
    if rng.random() < 0.5 and hy0 >= 2:
        ax = int(cx) if rng.random() < 0.5 else int(cx - head_hw)
        stamp(ax, hy0 - min(2, hy0), ax, hy0 - 1)
        stamp(w - 1 - ax, hy0 - min(2, hy0), w - 1 - ax, hy0 - 1)

    # Arms (columns hugging the torso sides, from the shoulders down)
    arm_w = rng.randint(1, 2)
    ay1 = rng.randint(ty0 + 2, ty1 + 1)
    stamp(int(cx - torso_hw) - arm_w, ty0, int(cx - torso_hw) - 1, ay1)
    stamp(math.ceil(cx + torso_hw) + 1, ty0,
          math.ceil(cx + torso_hw) + arm_w, ay1)

    # Legs (two stubby rects reaching the ground line)
    leg_w = rng.randint(1, 2)
    leg_x = int(cx - torso_hw) + rng.randint(0, max(0, torso_hw - leg_w - 1))
    stamp(leg_x, ty1 + 1, leg_x + leg_w - 1, h - 2)
    stamp(w - 1 - (leg_x + leg_w - 1), ty1 + 1, w - 1 - leg_x, h - 2)
    # Feet
    stamp(leg_x - 1, h - 2, leg_x + leg_w - 1, h - 2)
    stamp(w - 1 - (leg_x + leg_w - 1), h - 2, w - leg_x, h - 2)

    # Jitter: notch the torso corners so it isn't a perfect box.
    for _ in range(rng.randint(1, 3)):
        nx0 = rng.choice((int(cx - torso_hw), int(cx - torso_hw) + 1))
        ny0 = rng.choice((ty0, ty1))
        if ny0 == ty1 and ny0 + 1 < h and grid[ny0 + 1][nx0]:
            continue
        grid[ny0][nx0] = 0
        grid[ny0][w - 1 - nx0] = 0

    _mirror_x(grid)
    return _largest_component(grid)


# Part codes for the tank part map: the builder records which component owns
# each pixel so the painter can shade treads, hull, turret and gun separately.
_T_TREAD, _T_HULL, _T_TURRET, _T_BARREL = 1, 2, 3, 4


def _build_tank(rng: random.Random, w: int, h: int) -> tuple[list[list[int]], dict]:
    """Top-down tank assembled from parts onto a part map rather than noise:
    a hull longer front-to-back than wide with a tapered glacis nose, tread
    runs flanking it with their outer corners chamfered around the sprockets,
    a gun stamped first so the turret (round or octagonal, optionally with a
    rear stowage bustle) covers its root, plus mantlet, bore evacuator and
    muzzle brake. All proportions scale with resolution, so the same code
    draws a readable 14px unit and a 160px hero asset. Returns the silhouette
    grid plus a meta dict (part map + geometry) that the painter reads back."""
    S = min(w, h)
    cx = (w - 1) / 2.0
    part = [[0] * w for _ in range(h)]

    def stamp(code: int, x0: int, y0: int, x1: int, y1: int) -> None:
        for y in range(max(0, y0), min(h, y1 + 1)):
            for x in range(max(0, x0), min(w, x1 + 1)):
                part[y][x] = code

    # Hull: the block between the treads, its front rows tapered into a
    # glacis nose. hull_x1 mirrors hull_x0 exactly so even widths stay
    # symmetric without a mirror pass.
    hull_hw = max(2, round(w * 0.205)
                  + rng.randint(-max(1, w // 48), max(1, w // 48)))
    hull_x0 = round(cx - hull_hw)
    hull_x1 = w - 1 - hull_x0
    hull_y0 = round(h * 0.16) + rng.randint(0, max(1, h // 24))
    hull_y1 = h - 2 - rng.randint(0, max(1, h // 32))
    glacis_h = max(2, round(h * 0.10))
    glacis_taper = max(1, round(w * 0.05))
    hull_span: dict[int, tuple[int, int]] = {}
    for y in range(hull_y0, hull_y1 + 1):
        t = max(0.0, (hull_y0 + glacis_h - y) / glacis_h)
        inset = round(glacis_taper * t)
        hull_span[y] = (hull_x0 + inset, hull_x1 - inset)
        stamp(_T_HULL, hull_x0 + inset, y, hull_x1 - inset, y)

    # Treads: runs flanking the hull, overhanging front and rear a touch,
    # outer corners chamfered so they read as wrapped around the sprockets.
    tread_w = max(2, round(w * 0.13) + rng.randint(0, max(1, w // 28)))
    tread_x1 = hull_x0 - 1
    tread_x0 = max(0, tread_x1 - tread_w + 1)
    tread_y0 = max(1, hull_y0 - rng.randint(0, max(1, h // 28)))
    tread_y1 = min(h - 2, hull_y1 + rng.randint(0, max(1, h // 28)))
    stamp(_T_TREAD, tread_x0, tread_y0, tread_x1, tread_y1)
    stamp(_T_TREAD, w - 1 - tread_x1, tread_y0, w - 1 - tread_x0, tread_y1)
    cham = tread_w // 2
    for y in range(tread_y0, tread_y1 + 1):
        d_end = min(y - tread_y0, tread_y1 - y)
        for x in range(tread_x0, tread_x1 + 1):
            if (x - tread_x0) + d_end < cham:
                part[y][x] = 0
                part[y][w - 1 - x] = 0

    # Gun before turret, so the turret stamps over its root and the barrel
    # reads as emerging from under the mantlet. The turret sits near the hull
    # middle, leaving the gun a long reach past the glacis.
    tur_r = min(w * (0.145 + rng.uniform(0.0, 0.03)),
                hull_hw + tread_w * 0.5)
    tur_cy = h * 0.47 + rng.uniform(-0.02 * h, 0.03 * h)
    tur_front = round(tur_cy - tur_r)
    bar_hw = max(1, round(w * 0.022))
    bx0 = int(cx - bar_hw)
    bx1 = w - 1 - bx0
    tip_y = max(1, round(h * 0.02) + rng.randint(0, max(1, h // 40)))
    stamp(_T_BARREL, bx0, tip_y, bx1, round(tur_cy))
    has_muzzle = rng.random() < 0.7
    muzzle_y1 = tip_y + max(1, round(h * 0.045))
    if has_muzzle:
        mw = max(1, round(w * 0.02))
        stamp(_T_BARREL, bx0 - mw, tip_y, bx1 + mw, muzzle_y1)
    has_evac = S >= 24 and rng.random() < 0.55
    evac_y0 = evac_y1 = 0
    if has_evac:
        mid = tip_y + (tur_front - tip_y) * 0.45
        eh = max(1, round(h * 0.03))
        evac_y0, evac_y1 = round(mid - eh), round(mid + eh)
        stamp(_T_BARREL, bx0 - 1, evac_y0, bx1 + 1, evac_y1)
    mant_h = max(1, round(h * 0.03))
    mant_y0 = max(tip_y, tur_front - mant_h)
    mant_w = max(1, round(w * 0.02))
    stamp(_T_BARREL, bx0 - mant_w, mant_y0, bx1 + mant_w, tur_front)

    # Turret: round or octagonal; dx mirrors exactly around the float center
    # so the silhouette stays symmetric.
    shape_round = rng.random() < 0.65
    for y in range(max(0, round(tur_cy - tur_r)),
                   min(h, round(tur_cy + tur_r) + 1)):
        for x in range(max(0, round(cx - tur_r)),
                       min(w, round(cx + tur_r) + 1)):
            dx, dy = x - cx, y - tur_cy
            if shape_round:
                inside = dx * dx + dy * dy <= tur_r * tur_r
            else:
                inside = (max(abs(dx), abs(dy)) <= tur_r * 0.92
                          and abs(dx) + abs(dy) <= tur_r * 1.45)
            if inside:
                part[y][x] = _T_TURRET
    has_bustle = rng.random() < 0.6
    if has_bustle:
        bhw = round(tur_r * 0.7)
        bux0 = int(cx - bhw)
        stamp(_T_TURRET, bux0, round(tur_cy), w - 1 - bux0,
              min(hull_y1 - 1, round(tur_cy + tur_r + h * 0.035)))

    # Engine-deck line: where the mid hull ends and the vented rear begins.
    deck_y = round(h * 0.66) + rng.randint(0, max(1, h // 20))
    deck_y = max(hull_y0 + glacis_h + 1, min(deck_y, hull_y1 - 2))

    grid = [[1 if part[y][x] else 0 for x in range(w)] for y in range(h)]
    meta = dict(part=part, hull_x0=hull_x0, hull_x1=hull_x1, hull_y0=hull_y0,
                hull_y1=hull_y1, hull_hw=hull_hw, hull_span=hull_span,
                glacis_h=glacis_h, deck_y=deck_y,
                tread_x0=tread_x0, tread_x1=tread_x1, tread_y0=tread_y0,
                tread_y1=tread_y1, tread_w=tread_w,
                tur_cy=tur_cy, tur_r=tur_r, tur_front=tur_front,
                shape_round=shape_round, has_bustle=has_bustle,
                bx0=bx0, bx1=bx1, bar_hw=bar_hw, tip_y=tip_y,
                has_muzzle=has_muzzle, muzzle_y1=muzzle_y1,
                has_evac=has_evac, evac_y0=evac_y0, evac_y1=evac_y1,
                mant_y0=mant_y0)
    return grid, meta


def _ca_step(grid: list[list[int]], birth: int, survive: int) -> list[list[int]]:
    h, w = len(grid), len(grid[0])
    out = [[0] * w for _ in range(h)]
    for y in range(h):
        for x in range(w):
            n = 0
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    if dx == 0 and dy == 0:
                        continue
                    yy, xx = y + dy, x + dx
                    if 0 <= yy < h and 0 <= xx < w:
                        n += grid[yy][xx]
            if grid[y][x]:
                out[y][x] = 1 if n >= survive else 0
            else:
                out[y][x] = 1 if n >= birth else 0
    return out


def _largest_component(grid: list[list[int]]) -> list[list[int]]:
    h, w = len(grid), len(grid[0])
    seen = [[False] * w for _ in range(h)]
    best: list[tuple[int, int]] = []
    for y in range(h):
        for x in range(w):
            if grid[y][x] and not seen[y][x]:
                stack, comp = [(y, x)], []
                seen[y][x] = True
                while stack:
                    cy, cx = stack.pop()
                    comp.append((cy, cx))
                    for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                        yy, xx = cy + dy, cx + dx
                        if 0 <= yy < h and 0 <= xx < w and grid[yy][xx] and not seen[yy][xx]:
                            seen[yy][xx] = True
                            stack.append((yy, xx))
                if len(comp) > len(best):
                    best = comp
    out = [[0] * w for _ in range(h)]
    for y, x in best:
        out[y][x] = 1
    return out


def _center_vertically(grid: list[list[int]]) -> None:
    """Shift the blob so its bounding box is vertically centered, in place.
    (Horizontal centering is free: mirror symmetry keeps the blob centered.)"""
    h = len(grid)
    ys = [y for y in range(h) if any(grid[y])]
    if not ys:
        return
    shift = (h - (ys[-1] - ys[0] + 1)) // 2 - ys[0]
    if shift == 0:
        return
    rows = [row[:] for row in grid]
    for y in range(h):
        src = y - shift
        grid[y] = rows[src] if 0 <= src < h else [0] * len(grid[0])


def _mirror_x(grid: list[list[int]]) -> None:
    """Copy the left half onto the right half, in place."""
    h, w = len(grid), len(grid[0])
    for y in range(h):
        for x in range(w // 2):
            grid[y][w - 1 - x] = grid[y][x]


def generate_shape(rng: random.Random, kind: str, w: int, h: int) -> list[list[int]]:
    """Random symmetric silhouette; retries until the blob is a sensible size."""
    if kind == "robot":
        return _robot_grid(rng, w, h)

    mask = _density_mask(kind, w, h)
    target_min = int(w * h * 0.17)

    for attempt in range(60):
        # Ramp density up across retries so sparse masks still converge.
        fill = rng.uniform(0.45, 0.62) + attempt * 0.008
        grid = [[0] * w for _ in range(h)]
        for y in range(h):
            for x in range((w + 1) // 2):
                if rng.random() < fill * mask[y][x]:
                    grid[y][x] = 1
        _mirror_x(grid)

        for _ in range(2 if max(w, h) < 24 else 3):
            grid = _ca_step(grid, birth=5, survive=3)
        grid = _largest_component(grid)
        # The largest component may be a side lobe whose mirror twin was
        # dropped - union with its own mirror to restore exact symmetry.
        for y in range(h):
            for x in range(w // 2):
                grid[y][x] = grid[y][x] | grid[y][w - 1 - x]
        _mirror_x(grid)
        _center_vertically(grid)

        count = sum(map(sum, grid))
        if count >= target_min:
            return grid
    return grid  # give up gracefully; last attempt is still usable


# --------------------------------------------------------------------------- #
# Paint: shading, accents, details
# --------------------------------------------------------------------------- #

def _filled(grid: list[list[int]], x: int, y: int) -> bool:
    return 0 <= y < len(grid) and 0 <= x < len(grid[0]) and bool(grid[y][x])


def _accent_blobs(rng: random.Random, grid: list[list[int]], count: int) -> set[tuple[int, int]]:
    """Small symmetric blobs of accent color grown from random interior seeds."""
    h, w = len(grid), len(grid[0])
    cells = [(x, y) for y in range(h) for x in range(w) if grid[y][x]]
    accents: set[tuple[int, int]] = set()
    if not cells:
        return accents
    for _ in range(count):
        x, y = rng.choice(cells)
        size = rng.randint(2, 5)
        frontier = [(x, y)]
        for _ in range(size):
            if not frontier:
                break
            cx, cy = frontier.pop(rng.randrange(len(frontier)))
            if not grid[cy][cx]:
                continue
            accents.add((cx, cy))
            accents.add((w - 1 - cx, cy))  # keep it symmetric
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                if _filled(grid, cx + dx, cy + dy):
                    frontier.append((cx + dx, cy + dy))
    return accents


@dataclass
class Sprite:
    kind: str
    seed: int
    grid: list[list[int]]
    palette: Palette
    # (x, y) -> RGB overrides painted on top of the shaded body
    detail: dict[tuple[int, int], tuple[int, int, int]] = field(default_factory=dict)
    accents: set[tuple[int, int]] = field(default_factory=set)
    # Extra geometry a builder hands its painter (tanks: part map + layout).
    meta: dict = field(default_factory=dict)


def _add_creature_eyes(rng: random.Random, sp: Sprite) -> None:
    """Two mirrored eyes with at least a 2px gap between them - adjacent
    whites read as a headband, not a face. Each eye is white-over-pupil
    when there is room, or a single dark bead otherwise."""
    grid = sp.grid
    h, w = len(grid), len(grid[0])
    white, pupil = (240, 240, 235), (25, 22, 30)
    es = max(1, round(w / 16))  # eye block size scales with resolution
    # Keep at least a 2px (or eye-width, if larger) gap between the blocks.
    max_x = (w - 2 * es - max(2, es)) // 2
    face_rows = list(range(max(1, int(h * 0.18)), int(h * 0.6)))
    rng.shuffle(face_rows)
    all_rows = list(range(1, h - 1 - es))

    def block_filled(x0: int, y0: int, x1: int, y1: int) -> bool:
        return all(_filled(grid, x, y)
                   for y in range(y0, y1 + 1) for x in range(x0, x1 + 1))

    def embedded(x: int, y: int) -> bool:
        # eye block plus a 1px ring around it (through the pupil row)
        return block_filled(x - 1, y - 1, x + es, y + 2 * es)

    def has_room_below(x: int, y: int) -> bool:
        return block_filled(x, y, x + es - 1, y + 2 * es - 1)

    # Placement priority: interior face cell (tall white+pupil eye), then any
    # face cell with room below, then interior anywhere, then a dark bead.
    attempts = (
        (face_rows, embedded, True),
        (face_rows, has_room_below, True),
        (all_rows, embedded, True),
        (face_rows, lambda x, y: True, False),
        (all_rows, lambda x, y: True, False),
    )
    for band, ok, tall in attempts:
        for y in band:
            xs = [x for x in range(1, max_x + 1) if grid[y][x] and ok(x, y)]
            if not xs:
                continue
            x = rng.choice(xs)
            for ex in (x, w - es - x):  # mirrored block start
                for dy in range(es):
                    for dx in range(es):
                        if tall:
                            sp.detail[(ex + dx, y + dy)] = white
                            sp.detail[(ex + dx, y + es + dy)] = pupil
                        elif _filled(grid, ex + dx, y + dy):
                            sp.detail[(ex + dx, y + dy)] = pupil
                        # Keep accent blobs off the eye so it reads cleanly.
                        sp.accents.discard((ex + dx, y + dy))
                        sp.accents.discard((ex + dx, y + es + dy))
            return


def _add_ship_details(rng: random.Random, sp: Sprite) -> None:
    grid = sp.grid
    h, w = len(grid), len(grid[0])
    cx = w // 2
    # Cockpit: 1-2 glowing cells on the center column, upper third.
    glass = _hsv_to_rgb(rng.uniform(0.5, 0.58), 0.55, 0.95)
    placed = 0
    for y in range(int(h * 0.12), int(h * 0.5)):
        if grid[y][cx]:
            sp.detail[(cx, y)] = glass
            if w % 2 == 0 and _filled(grid, cx - 1, y):
                sp.detail[(cx - 1, y)] = glass
            placed += 1
            if placed >= 2:
                break
    # Engine glow: bottom-most filled cells get a hot accent.
    engine = _hsv_to_rgb(rng.uniform(0.02, 0.12), 0.85, 1.0)
    for x in range(w // 2 + 1):
        for y in range(h - 1, int(h * 0.6), -1):
            if grid[y][x] and not _filled(grid, x, y + 1):
                if rng.random() < 0.45:
                    sp.detail[(x, y)] = engine
                    sp.detail[(w - 1 - x, y)] = engine
                break


def _add_item_facets(rng: random.Random, sp: Sprite) -> None:
    # A bright diagonal glint near the top-left of the shape.
    grid = sp.grid
    h, w = len(grid), len(grid[0])
    glint = (250, 250, 245)
    cells = [
        (x, y)
        for y in range(1, int(h * 0.5))
        for x in range(1, int(w * 0.5))
        if grid[y][x] and not _filled(grid, x - 1, y - 1)
    ]
    if cells:
        x, y = rng.choice(cells)
        sp.detail[(x, y)] = glint
        if _filled(grid, x + 1, y + 1):
            sp.detail[(x + 1, y + 1)] = sp.palette.body.highlight


def _add_robot_panels(rng: random.Random, sp: Sprite) -> None:
    grid = sp.grid
    h, w = len(grid), len(grid[0])
    # A dark horizontal seam across the torso, plus a glowing "eye visor".
    seam_y = rng.randint(int(h * 0.45), int(h * 0.7))
    for x in range(w):
        if grid[seam_y][x] and _filled(grid, x, seam_y - 1) and _filled(grid, x, seam_y + 1):
            sp.detail[(x, seam_y)] = sp.palette.body.outline
    # Glowing eye visor: a horizontal bar across the head, one row below its
    # top. Use the longest contiguous run so antenna tips don't qualify.
    visor = _hsv_to_rgb(rng.choice((0.0, 0.08, 0.33, 0.5)), 0.9, 1.0)
    thickness = max(1, round(h / 16))
    for y in range(1, int(h * 0.45)):
        xs = [x for x in range(1, w - 1) if grid[y][x] and _filled(grid, x, y - 1)]
        run: list[int] = []
        best_run: list[int] = []
        for x in xs:
            run = run + [x] if run and x == run[-1] + 1 else [x]
            if len(run) > len(best_run):
                best_run = run
        if len(best_run) >= 2:
            trim = 1 if len(best_run) > 3 else 0  # inset from the head edges
            for x in best_run[trim:len(best_run) - trim]:
                for dy in range(thickness):
                    if _filled(grid, x, y + dy):
                        sp.detail[(x, y + dy)] = visor
            break


def _paint_tank(rng: random.Random, sp: Sprite) -> None:
    """Repaint every tank pixel from the part map: the generic top-lit shading
    never fights it because detail overrides win in render(). Body ramp paints
    treads and hull, accent ramp paints the turret and gun (so faction bodies
    keep their accent turret), and _mix blends ramp tones into gradients far
    finer than the 5-tone ramp itself. Coarse features (links, glacis light,
    turret dome, mantlet, dark bore) draw at any size; fixtures gate on
    resolution - hatches, vents, headlights, exhausts and camo from ~40px,
    bolts, periscopes, brake slots and weathering from ~96px."""
    m = sp.meta
    part: list[list[int]] = m["part"]
    grid = sp.grid
    h, w = len(grid), len(grid[0])
    S = min(w, h)
    big, fine = S >= 40, S >= 96
    body, acc = sp.palette.body, sp.palette.accent
    cx = (w - 1) / 2.0
    tur_cy, tur_r = m["tur_cy"], m["tur_r"]
    hull_y0, hull_y1 = m["hull_y0"], m["hull_y1"]
    glacis_y = hull_y0 + m["glacis_h"]
    deck_y = m["deck_y"]
    hull_span: dict[int, tuple[int, int]] = m["hull_span"]

    def at(x: int, y: int) -> int:
        return part[y][x] if 0 <= x < w and 0 <= y < h else 0

    def blend(x: int, y: int, color: tuple[int, int, int], t: float) -> None:
        if (x, y) in sp.detail:
            sp.detail[(x, y)] = _mix(sp.detail[(x, y)], color, t)

    # Barrel row extents (muzzle/evacuator/mantlet rows are wider), for
    # cylinder shading across the actual tube width.
    bar_span: dict[int, tuple[int, int]] = {}
    for y in range(h):
        xs = [x for x in range(w) if part[y][x] == _T_BARREL]
        if xs:
            bar_span[y] = (xs[0], xs[-1])

    # Camo: a few soft ellipse patches over the hull, blended in during the
    # base pass so seams and fixtures still draw on top.
    camo: set[tuple[int, int]] = set()
    if big and rng.random() < 0.55:
        for _ in range(rng.randint(3, 6)):
            ex = rng.uniform(m["hull_x0"], m["hull_x1"])
            ey = rng.uniform(hull_y0, hull_y1)
            rx = rng.uniform(0.05, 0.11) * S
            ry = rng.uniform(0.05, 0.11) * S
            for y in range(max(0, round(ey - ry)), min(h, round(ey + ry) + 1)):
                for x in range(max(0, round(ex - rx)), min(w, round(ex + rx) + 1)):
                    if ((x - ex) / rx) ** 2 + ((y - ey) / ry) ** 2 <= 1.0:
                        camo.add((x, y))

    # ---- Base pass: one color per pixel, part by part -------------------- #
    link_step = max(2, round(S * 0.045))
    tread_base = _mix(body.shadow, body.outline, 0.45)
    for y in range(h):
        for x in range(w):
            p = part[y][x]
            if not p:
                continue
            if p == _T_TREAD:
                ox = x if x <= cx else w - 1 - x  # left-tread coordinates
                base = tread_base
                d_end = min(y - m["tread_y0"], m["tread_y1"] - y)
                if d_end <= m["tread_w"]:
                    base = _mix(base, body.base, 0.18)  # wrap over sprockets
                if (y - m["tread_y0"]) % link_step == 0:
                    color = _mix(body.outline, base, 0.15)   # link groove
                elif fine and (y - m["tread_y0"]) % link_step == (link_step + 1) // 2:
                    color = _mix(base, body.base, 0.22)      # link crest
                else:
                    color = base
                if ox == m["tread_x0"]:
                    color = body.outline                     # outer edge
                elif ox == m["tread_x1"]:
                    color = _mix(body.base, body.shadow, 0.45)  # inner fender
            elif p == _T_HULL:
                if y < glacis_y:  # sloped front plate catches the light
                    t = (glacis_y - y) / max(1, m["glacis_h"])
                    color = _mix(body.light, body.highlight, 0.5 * t)
                else:  # long deck gradient, front lit to rear shadowed
                    t = (y - glacis_y) / max(1, hull_y1 - glacis_y)
                    color = (_mix(body.light, body.base, t / 0.45) if t < 0.45
                             else _mix(body.base, body.shadow,
                                       (t - 0.45) / 0.55 * 0.6))
                if (x, y) in camo:
                    color = _mix(color, body.outline, 0.3)
                x0, x1 = hull_span[y]
                d_side = min(x - x0, x1 - x)
                if d_side == 0:
                    color = _mix(color, body.outline, 0.5)
                elif d_side == 1 and big:
                    color = _mix(color, body.shadow, 0.35)
            elif p == _T_TURRET:
                dx, dy = x - cx, y - tur_cy
                nd = math.hypot(dx, dy) / max(1e-6, tur_r)
                if m["shape_round"]:
                    in_top = dx * dx + dy * dy <= tur_r * tur_r
                else:
                    in_top = (max(abs(dx), abs(dy)) <= tur_r * 0.92
                              and abs(dx) + abs(dy) <= tur_r * 1.45)
                if in_top:  # dome: lit toward the muzzle, shaded to the rear
                    lit = -dy / max(1e-6, tur_r)
                    color = (_mix(acc.base, acc.light, min(1.0, lit) * 0.8)
                             if lit > 0 else
                             _mix(acc.base, acc.shadow, min(1.0, -lit) * 0.7))
                    if nd > 0.86:  # rim: bright arc up front, dark behind
                        color = (_mix(color, acc.highlight, 0.55) if lit > 0.35
                                 else _mix(color, acc.outline, 0.45))
                else:  # stowage bustle
                    color = _mix(acc.base, acc.shadow, 0.45)
                    if fine and (x - round(cx)) % max(2, round(S * 0.04)) == 0:
                        color = _mix(color, acc.outline, 0.4)
            else:  # _T_BARREL: cylinder shading across the tube
                x0, x1 = bar_span[y]
                t = (x - x0) / max(1, x1 - x0)
                d = abs(t - 0.5) * 2.0  # 0 at the bore line, 1 at the edges
                color = _mix(acc.light, acc.shadow, d * d)
                if x1 - x0 >= 4 and d < 0.18:
                    color = _mix(color, acc.highlight, 0.6)  # specular stripe
                if y >= m["mant_y0"]:
                    color = _mix(color, acc.shadow, 0.5)     # mantlet collar
                    if y == m["mant_y0"]:
                        color = _mix(color, acc.outline, 0.5)
                if m["has_evac"] and m["evac_y0"] <= y <= m["evac_y1"]:
                    color = _mix(color, acc.light, 0.25)     # evacuator sleeve
                    if y in (m["evac_y0"], m["evac_y1"]):
                        color = _mix(color, acc.outline, 0.5)
                if m["has_muzzle"] and y <= m["muzzle_y1"]:
                    if y == m["muzzle_y1"]:
                        color = _mix(color, acc.outline, 0.6)
                    elif fine and y == m["tip_y"] + (m["muzzle_y1"] - m["tip_y"]) // 2:
                        color = _mix(color, acc.outline, 0.5)  # brake slot
                if y == m["tip_y"] and d < 0.5:
                    color = acc.outline                      # dark bore mouth
            sp.detail[(x, y)] = color

    # ---- Cast shadows: the raised turret and gun sit above the deck ------ #
    off = max(1, round(S / 32))
    for y in range(h):
        for x in range(w):
            if part[y][x] not in (_T_HULL, _T_TREAD):
                continue
            if at(x, y - off) in (_T_TURRET, _T_BARREL):
                blend(x, y, body.outline, 0.45)  # below the turret/bustle
            elif x > cx and at(x - off, y) in (_T_TURRET, _T_BARREL):
                blend(x, y, body.outline, 0.25)  # light from the top-left

    # ---- Hull fixtures ---------------------------------------------------- #
    def seam(y: int, t: float) -> None:
        x0, x1 = hull_span[y]
        for x in range(x0 + 1, x1):
            if part[y][x] == _T_HULL:
                blend(x, y, body.outline, t)

    seam(glacis_y, 0.45)   # glacis weld line
    seam(deck_y, 0.6)      # engine-deck seam
    if big:  # longitudinal panel seams down the deck
        sx = round(m["hull_hw"] * 0.55)
        for y in range(glacis_y + 1, deck_y):
            for x in (round(cx - sx), round(cx + sx)):
                if part[y][x] == _T_HULL:
                    blend(x, y, body.shadow, 0.5)

    # Engine deck: vent slats between the seam and the rear plate, embossed
    # with a light row under each slat at high resolution.
    vent_step = max(2, round(S * 0.035))
    vin = max(2, round(w * 0.05))
    for y in range(deck_y + max(2, S // 40), hull_y1 - max(1, S // 40),
                   vent_step):
        x0, x1 = hull_span[y]
        for x in range(x0 + vin, x1 - vin + 1):
            if part[y][x] == _T_HULL:
                blend(x, y, body.outline, 0.55)
                if fine and at(x, y + 1) == _T_HULL:
                    blend(x, y + 1, body.light, 0.3)

    if big:
        # Headlights: warm blocks on the hull's front corners.
        lx0, _ = hull_span[hull_y0]
        ls = max(1, S // 50)
        for dy in range(ls):
            for dx in range(ls):
                for xx in (lx0 + 1 + dx, w - 1 - (lx0 + 1 + dx)):
                    if at(xx, hull_y0 + 1 + dy) == _T_HULL:
                        sp.detail[(xx, hull_y0 + 1 + dy)] = (250, 243, 205)
        # Driver hatch: a small ringed disc behind the glacis, offset left.
        hr = max(1, round(S * 0.03))
        hxc, hyc = cx - m["hull_hw"] * 0.45, glacis_y + hr + 1
        for y in range(round(hyc - hr), round(hyc + hr) + 1):
            for x in range(round(hxc - hr), round(hxc + hr) + 1):
                dd = math.hypot(x - hxc, y - hyc)
                if dd <= hr and at(x, y) == _T_HULL:
                    sp.detail[(x, y)] = (
                        _mix(body.base, body.outline, 0.6) if dd >= hr - 0.9
                        else _mix(body.base, body.light, 0.4))
        # Exhausts: soot-dark stubs on the rear corners of the deck.
        ex_w = max(1, round(S * 0.04))
        ex_h = max(2, round(S * 0.06))
        for yy in range(hull_y1 - 1 - ex_h, hull_y1):
            x0, x1 = hull_span[yy]
            for dx in range(ex_w):
                for xx in (x0 + 1 + dx, x1 - 1 - dx):
                    if at(xx, yy) == _T_HULL:
                        blend(xx, yy, body.outline, 0.65)
    if fine:  # bolts down the hull side edges
        bolt_step = max(3, round(S * 0.06))
        for y in range(glacis_y + 2, hull_y1 - 2, bolt_step):
            x0, x1 = hull_span[y]
            for x in (x0 + 1, x1 - 1):
                if part[y][x] == _T_HULL:
                    blend(x, y, body.outline, 0.5)

    # ---- Turret fixtures -------------------------------------------------- #
    if tur_r >= 3:
        # Commander's hatch: ringed disc offset to one side, with a hinge
        # glint; two periscope nicks ahead of it at high resolution.
        side = rng.choice((-1, 1))
        hr = max(1, round(tur_r * 0.34))
        hxc = cx + tur_r * 0.28 * side
        hyc = tur_cy + tur_r * 0.15
        for y in range(round(hyc - hr), round(hyc + hr) + 1):
            for x in range(round(hxc - hr), round(hxc + hr) + 1):
                dd = math.hypot(x - hxc, y - hyc)
                if dd <= hr and at(x, y) == _T_TURRET:
                    sp.detail[(x, y)] = (
                        _mix(acc.shadow, acc.outline, 0.6) if dd >= hr - 0.9
                        else _mix(acc.base, acc.shadow, 0.5))
        gx, gy = round(hxc - hr * 0.4), round(hyc - hr * 0.4)
        if at(gx, gy) == _T_TURRET:
            sp.detail[(gx, gy)] = acc.highlight
        if fine:
            for px in (-1, 1):
                x, y = round(hxc + px * hr), round(hyc - hr - 1)
                if at(x, y) == _T_TURRET:
                    blend(x, y, acc.outline, 0.6)
        if big:  # antenna base on the opposite rear quarter
            ax = round(cx - tur_r * 0.6 * side)
            ay = round(tur_cy + tur_r * 0.55)
            if at(ax, ay) == _T_TURRET:
                blend(ax, ay, acc.outline, 0.6)
                if at(ax, ay - 1) == _T_TURRET:
                    sp.detail[(ax, ay - 1)] = acc.highlight

    # ---- Weathering: sparse wear specks over the whole machine ----------- #
    if big:
        for (x, y) in list(sp.detail):
            if part[y][x] not in (_T_HULL, _T_TREAD):
                continue
            r = rng.random()
            if r < 0.03:
                blend(x, y, body.outline, 0.3)
            elif r < 0.05:
                blend(x, y, body.light, 0.25)


_DETAILERS = {
    "creature": _add_creature_eyes,
    "ship": _add_ship_details,
    "item": _add_item_facets,
    "robot": _add_robot_panels,
    "tank": _paint_tank,
}


def generate_sprite(seed: int, kind: str, size: int, hue: float | None = None,
                    sat: float | None = None, val: float | None = None,
                    outline: tuple[int, int, int] | None = None) -> Sprite:
    """One sprite. The same seed always yields the same shape and details, so
    faction variants (same seed, different hue/sat/val) differ only in color."""
    rng = random.Random(seed)
    if kind == "tank":
        grid, meta = _build_tank(rng, size, size)
    else:
        grid, meta = generate_shape(rng, kind, size, size), {}
    sp = Sprite(kind=kind, seed=seed, grid=grid,
                palette=make_palette(rng, hue, sat, val,
                                     muted=kind == "tank"), meta=meta)
    if outline is not None:
        # Before the detailers: the robot seam paints in the outline color.
        sp.palette.body.outline = outline
    if kind != "tank":  # tanks repaint every pixel; random blobs would fight it
        sp.accents = _accent_blobs(rng, grid, count=rng.randint(1, 3))
    _DETAILERS[kind](rng, sp)
    return sp


# --------------------------------------------------------------------------- #
# Render
# --------------------------------------------------------------------------- #

def render(sp: Sprite, scale: int = 1, pad: int = 1) -> Image.Image:
    grid = sp.grid
    h, w = len(grid), len(grid[0])
    W, H = w + pad * 2, h + pad * 2
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    px = img.load()
    pal = sp.palette
    dither = random.Random(sp.seed ^ 0x5EED)

    for y in range(h):
        for x in range(w):
            if not grid[y][x]:
                continue
            ramp = pal.accent if (x, y) in sp.accents else pal.body

            # Directional light from the top: exposed-above cells catch light,
            # exposed-below cells fall into shadow; sprinkle dithering between.
            open_up = not _filled(grid, x, y - 1)
            open_down = not _filled(grid, x, y + 1)
            open_left = not _filled(grid, x - 1, y)
            open_right = not _filled(grid, x + 1, y)

            if open_up:
                tone = 3 if not (open_left and open_right) else 2
            elif open_down:
                tone = 0
            else:
                # Interior: vertical gradient with light dithering.
                depth_t = y / max(1, h - 1)
                tone = 2 if depth_t < 0.35 else 1
                if tone == 1 and depth_t > 0.7 and dither.random() < 0.35:
                    tone = 0
                elif tone == 2 and dither.random() < 0.25:
                    tone = 1
            # Side edges get a slight darkening unless top-lit.
            if (open_left or open_right) and not open_up and tone > 0:
                tone -= 1

            px[x + pad, y + pad] = (*ramp.tone(tone), 255)

    # Detail overrides (eyes, cockpits, glints...) go on top of shading.
    for (x, y), color in sp.detail.items():
        px[x + pad, y + pad] = (*color, 255)

    # Outline: any empty cell touching the body becomes a dark outline pixel.
    oc = (*pal.body.outline, 255)
    for y in range(H):
        for x in range(W):
            if px[x, y][3] != 0 and px[x, y] != oc:
                continue
            gx, gy = x - pad, y - pad
            if px[x, y][3] == 0 and any(
                _filled(grid, gx + dx, gy + dy)
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))
            ):
                px[x, y] = oc

    if scale > 1:
        img = img.resize((W * scale, H * scale), Image.NEAREST)
    return img


def on_canvas(img: Image.Image, size: int) -> Image.Image:
    """Center the rendered sprite on an exact size x size transparent canvas
    (what an atlas pipeline wants: every file the same, known dimensions)."""
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    out.paste(img, ((size - img.width) // 2, (size - img.height) // 2))
    return out


def parse_hex(spec: str) -> tuple[int, int, int]:
    s = spec.lstrip("#")
    if len(s) != 6 or any(c not in "0123456789abcdefABCDEF" for c in s):
        raise ValueError(f"bad color {spec!r} (want RRGGBB)")
    return int(s[0:2], 16), int(s[2:4], 16), int(s[4:6], 16)


def _hex_to_hsv(spec: str) -> tuple[float, float, float]:
    r, g, b = parse_hex(spec)
    return colorsys.rgb_to_hsv(r / 255.0, g / 255.0, b / 255.0)


def make_sheet(images: list[Image.Image], columns: int, spacing: int = 4,
               bg: tuple[int, int, int, int] = (0, 0, 0, 0)) -> Image.Image:
    if not images:
        raise ValueError("no images to assemble")
    cw = max(im.width for im in images)
    ch = max(im.height for im in images)
    rows = math.ceil(len(images) / columns)
    sheet = Image.new("RGBA", (columns * (cw + spacing) + spacing,
                               rows * (ch + spacing) + spacing), bg)
    for i, im in enumerate(images):
        cx = spacing + (i % columns) * (cw + spacing) + (cw - im.width) // 2
        cy = spacing + (i // columns) * (ch + spacing) + (ch - im.height) // 2
        sheet.paste(im, (cx, cy))
    return sheet


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #

def main() -> None:
    ap = argparse.ArgumentParser(
        description="Generate procedural pixel-art sprites with Pillow.",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    ap.add_argument("-n", "--count", type=int, default=32, help="number of sprites")
    ap.add_argument("-k", "--kind", choices=(*KINDS, "mixed"), default="mixed",
                    help="sprite type")
    ap.add_argument("-s", "--size", type=int, default=16,
                    help="sprite grid size in pixels (before scaling); "
                         "--kind tank defaults to 160 for high-detail assets")
    ap.add_argument("-x", "--scale", type=int, default=8,
                    help="nearest-neighbor upscale factor (--kind tank "
                         "defaults to 1)")
    ap.add_argument("--seed", type=int, default=None,
                    help="master seed (default: random); sprite i uses seed+i")
    ap.add_argument("--hue", type=float, default=None,
                    help="base hue 0..1 (default: random per sprite)")
    ap.add_argument("-o", "--out", type=Path, default=Path("out"),
                    help="output directory")
    ap.add_argument("--faction", "--factions", dest="factions", default=None,
                    metavar="LIST",
                    help="render each sprite once per faction palette: comma "
                         f"list of {', '.join(FACTIONS)}, 'all', or custom "
                         "label:RRGGBB; same seed = same shape, only colors "
                         "change. Files get a _<faction> suffix")
    ap.add_argument("--name", "--names", dest="names", default=None,
                    metavar="LIST",
                    help="output name(s) instead of <kind>_<seed>: a comma "
                         "list generates one sprite per name (overrides "
                         "--count); each entry may pin its type as name:kind")
    ap.add_argument("--canvas", type=int, default=None, metavar="N",
                    help="center each sprite on an exact NxN transparent "
                         "canvas (after scaling), for atlas pipelines")
    ap.add_argument("--outline", default=None, metavar="RRGGBB",
                    help="fixed outline color (default: dark tint of the body "
                         "hue)")
    ap.add_argument("--preset", choices=("grid-commanders",), default=None,
                    help="option bundle; grid-commanders = 64x64 unit sprites "
                         "(--size 14 --scale 4 --canvas 64 --factions all "
                         f"--outline {GRID_COMMANDERS_OUTLINE}), matching "
                         "assets/sprites/units/<name>_<faction>.png; tanks "
                         "are one curated hi-detail design at "
                         f"{GRID_COMMANDERS_TANK_SIZE}px native scale, facing "
                         "right like the game's unit art and unaffected by "
                         "--seed")
    ap.add_argument("--no-sheet", action="store_true",
                    help="skip the combined spritesheet")
    ap.add_argument("--no-singles", action="store_true",
                    help="skip individual sprite PNGs")
    args = ap.parse_args()

    # Under the grid-commanders preset, tanks diverge from the other kinds:
    # the game's vendored unit art is drawn at the 64px cell's own resolution
    # facing right, so tanks render at a native-scale hi-detail size (unless
    # the user pinned --size/--scale) and every preset tank is rotated to
    # face right.
    tank_size: int | None = None
    tanks_face_right = False
    if args.preset == "grid-commanders":
        if (args.size == ap.get_default("size")
                and args.scale == ap.get_default("scale")):
            tank_size = GRID_COMMANDERS_TANK_SIZE
        tanks_face_right = True
        # Fill in only what the user left at its default.
        for opt, value in (("size", 14), ("scale", 4), ("canvas", 64),
                           ("factions", "all"),
                           ("outline", GRID_COMMANDERS_OUTLINE)):
            if getattr(args, opt) == ap.get_default(opt):
                setattr(args, opt, value)
    elif args.kind == "tank":
        # Tank assets are high-detail: a 160px grid at native scale carries
        # ~100x the pixels of the old 16px default.
        if args.size == ap.get_default("size"):
            args.size = 160
        if args.scale == ap.get_default("scale"):
            args.scale = 1

    # --names: fixed file names, optional per-name kind, count from the list.
    names: list[tuple[str, str | None]] | None = None
    if args.names:
        names = []
        for tok in args.names.split(","):
            tok = tok.strip()
            name, _, kind = tok.partition(":")
            if kind and kind not in KINDS:
                ap.error(f"unknown kind {kind!r} in --names "
                         f"(choose from {', '.join(KINDS)})")
            if not name:
                ap.error(f"empty name in --names entry {tok!r}")
            names.append((name, kind or None))
        name_list = [n for n, _ in names]
        if len(set(name_list)) != len(name_list):
            dupes = sorted({n for n in name_list if name_list.count(n) > 1})
            ap.error(f"duplicate name(s) in --names: {', '.join(dupes)}")
        if args.count not in (ap.get_default("count"), len(names)):
            ap.error("--count conflicts with the number of --names")
        args.count = len(names)

    # --factions: (label, (h, s, v)) variants; None = one unconstrained pass.
    factions: list[tuple[str, tuple[float, float, float]]] | None = None
    if args.factions:
        if args.hue is not None:
            ap.error("--hue and --faction are mutually exclusive")
        factions = []
        for tok in args.factions.split(","):
            tok = tok.strip()
            if tok == "all":
                factions.extend((n, _hex_to_hsv(hx)) for n, hx in FACTIONS.items())
            elif tok in FACTIONS:
                factions.append((tok, _hex_to_hsv(FACTIONS[tok])))
            elif ":" in tok:
                label, _, hx = tok.partition(":")
                if not label:
                    ap.error(f"empty label in --faction entry {tok!r}")
                try:
                    factions.append((label, _hex_to_hsv(hx)))
                except ValueError as e:
                    ap.error(str(e))
            else:
                ap.error(f"unknown faction {tok!r} (choose from "
                         f"{', '.join(FACTIONS)}, 'all', or label:RRGGBB)")
        labels = [label for label, _ in factions]
        if len(set(labels)) != len(labels):
            dupes = sorted({lb for lb in labels if labels.count(lb) > 1})
            ap.error("duplicate faction label(s): "
                     + ", ".join(lb or "(empty)" for lb in dupes))

    outline: tuple[int, int, int] | None = None
    if args.outline:
        try:
            outline = parse_hex(args.outline)
        except ValueError as e:
            ap.error(str(e))

    if args.count < 1:
        ap.error("--count must be positive")
    if args.size < 8:
        ap.error("--size must be at least 8")
    if args.canvas is not None and (args.size + 2) * args.scale > args.canvas:
        ap.error(f"--canvas {args.canvas} is smaller than the rendered sprite "
                 f"({(args.size + 2) * args.scale}px incl. 1px outline pad); "
                 "lower --size/--scale or raise --canvas")
    master = args.seed if args.seed is not None else random.randrange(1 << 30)
    args.out.mkdir(parents=True, exist_ok=True)

    picker = random.Random(master)
    variants = factions if factions else [(None, None)]
    rows: list[list[Image.Image]] = [[] for _ in variants]
    for i in range(args.count):
        name, name_kind = names[i] if names else (None, None)
        kind = name_kind or (picker.choice(KINDS) if args.kind == "mixed"
                             else args.kind)
        if kind == "tank" and tank_size:
            size, scale, seed = tank_size, 1, GRID_COMMANDERS_TANK_SEED
        else:
            size, scale, seed = args.size, args.scale, master + i
        for fi, (flabel, fhsv) in enumerate(variants):
            hue, sat, val = fhsv if fhsv else (args.hue, None, None)
            sp = generate_sprite(seed, kind, size,
                                 hue, sat, val, outline)
            img = render(sp, scale=scale)
            if kind == "tank" and tanks_face_right:
                # Tanks build facing up; the game's unit art faces right.
                img = img.transpose(Image.Transpose.ROTATE_270)
            if args.canvas is not None:
                img = on_canvas(img, args.canvas)
            rows[fi].append(img)
            if not args.no_singles:
                stem = name if name else f"{kind}_{sp.seed}"
                suffix = f"_{flabel}" if flabel else ""
                img.save(args.out / f"{stem}{suffix}.png")

    if not args.no_sheet:
        # With factions the sheet reads like the game's atlas: one row per
        # faction, one column per sprite.
        cols = args.count if factions else max(1, round(math.sqrt(args.count)))
        sheet = make_sheet([im for row in rows for im in row],
                           columns=cols, spacing=args.scale * 2)
        sheet_path = args.out / f"sheet_{args.kind}_{master}.png"
        sheet.save(sheet_path)
        print(f"spritesheet: {sheet_path}")

    n_files = args.count * len(variants)
    per = f" x {len(variants)} factions" if factions else ""
    print(f"generated {args.count} {args.kind} sprite(s){per} "
          f"({n_files} file(s), {args.size}x{args.size} @ x{args.scale}"
          f"{f', canvas {args.canvas}' if args.canvas else ''}) "
          f"in {args.out}/  [master seed {master}]")


if __name__ == "__main__":
    main()
