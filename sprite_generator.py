#!/usr/bin/env python3
"""Procedural pixel-art sprite generator.

Generates game-ready sprites (creatures, ships, items, robots) as transparent
PNGs using a classic pipeline:

  1. Shape   - random noise on a half-grid, shaped by a per-type density mask,
               mirrored for symmetry, smoothed with cellular-automata steps,
               then reduced to the largest connected blob.
  2. Color   - a harmonious 5-tone ramp built from a base hue (shadows shift
               toward blue, highlights toward yellow), plus an accent ramp
               painted in symmetric blobs.
  3. Light   - directional shading (light from the top), edge darkening and a
               touch of dithering so surfaces read as volume.
  4. Details - per-type touches: eyes for creatures, a cockpit and engine glow
               for ships, gem facets for items, panel lines for robots.
  5. Finish  - 1px outline in a dark tint of the body color, nearest-neighbor
               upscale, optional spritesheet assembly.

Every sprite is reproducible from its seed (printed and embeddable in the
filename), so a sprite you like can always be regenerated at another scale.

Usage examples:
  python sprite_generator.py                          # 32 mixed sprites + sheet
  python sprite_generator.py --kind creature -n 16
  python sprite_generator.py --size 24 --scale 10 --seed 1234
  python sprite_generator.py --kind ship --hue 0.58   # blue-ish ships

  # 64x64 faction-colored unit sprites for ../grid_commanders (one file per
  # faction row of its units atlas, named <unit>_<faction>.png):
  python sprite_generator.py --preset grid-commanders \
      --names hover_tank:robot,gunship:ship --seed 42
"""

from __future__ import annotations

import argparse
import colorsys
import math
import random
from dataclasses import dataclass, field
from pathlib import Path

from PIL import Image

KINDS = ("creature", "ship", "item", "robot")

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


# --------------------------------------------------------------------------- #
# Color: palette ramps
# --------------------------------------------------------------------------- #

def _hsv_to_rgb(h: float, s: float, v: float) -> tuple[int, int, int]:
    r, g, b = colorsys.hsv_to_rgb(h % 1.0, max(0.0, min(1.0, s)), max(0.0, min(1.0, v)))
    return int(r * 255), int(g * 255), int(b * 255)


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
                 sat: float | None = None, val: float | None = None) -> Palette:
    h = rng.random() if hue is None else hue % 1.0
    s = rng.uniform(0.55, 0.85) if sat is None else sat
    v = rng.uniform(0.62, 0.78) if val is None else val
    body = make_ramp(h, s, v)

    # Accent: complementary-ish or analogous, biased bright so it pops.
    shift = rng.choice((0.5, 0.33, -0.33, 0.12, -0.12))
    a_s = rng.uniform(0.6, 0.9)
    a_v = rng.uniform(0.7, 0.85)
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
            else:  # robot (unused: robots are assembled from parts, not noise)
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


_DETAILERS = {
    "creature": _add_creature_eyes,
    "ship": _add_ship_details,
    "item": _add_item_facets,
    "robot": _add_robot_panels,
}


def generate_sprite(seed: int, kind: str, size: int, hue: float | None = None,
                    sat: float | None = None, val: float | None = None,
                    outline: tuple[int, int, int] | None = None) -> Sprite:
    """One sprite. The same seed always yields the same shape and details, so
    faction variants (same seed, different hue/sat/val) differ only in color."""
    rng = random.Random(seed)
    grid = generate_shape(rng, kind, size, size)
    sp = Sprite(kind=kind, seed=seed, grid=grid,
                palette=make_palette(rng, hue, sat, val))
    if outline is not None:
        # Before the detailers: the robot seam paints in the outline color.
        sp.palette.body.outline = outline
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
                    help="sprite grid size in pixels (before scaling)")
    ap.add_argument("-x", "--scale", type=int, default=8,
                    help="nearest-neighbor upscale factor")
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
                         "assets/sprites/units/<name>_<faction>.png")
    ap.add_argument("--no-sheet", action="store_true",
                    help="skip the combined spritesheet")
    ap.add_argument("--no-singles", action="store_true",
                    help="skip individual sprite PNGs")
    args = ap.parse_args()

    if args.preset == "grid-commanders":
        # Fill in only what the user left at its default.
        for opt, value in (("size", 14), ("scale", 4), ("canvas", 64),
                           ("factions", "all"),
                           ("outline", GRID_COMMANDERS_OUTLINE)):
            if getattr(args, opt) == ap.get_default(opt):
                setattr(args, opt, value)

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
                try:
                    factions.append((label, _hex_to_hsv(hx)))
                except ValueError as e:
                    ap.error(str(e))
            else:
                ap.error(f"unknown faction {tok!r} (choose from "
                         f"{', '.join(FACTIONS)}, 'all', or label:RRGGBB)")

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
        for fi, (flabel, fhsv) in enumerate(variants):
            hue, sat, val = fhsv if fhsv else (args.hue, None, None)
            sp = generate_sprite(master + i, kind, args.size,
                                 hue, sat, val, outline)
            img = render(sp, scale=args.scale)
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
