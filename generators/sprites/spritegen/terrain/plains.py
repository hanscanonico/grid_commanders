"""The grass plate, the field's clumps and decals, and the two grounds drawn
straight onto it: road and plains."""

from __future__ import annotations

from PIL import Image

from ..palette import RGB, h01, mix
from .tones import (
    CELL,
    GRASS,
    GRASS_DARK,
    PLAINS_SALT,
    ROAD,
    ROAD_DARK,
    SAND,
    _grain,
    _ground,
    _lit,
    _rect,
    _tone,
)

# The field's second and third grass tones (design review 2026-08-22). The
# ±3% grain above is a texture no eye reads: 97.9% of a plains tile's pixels
# sat within 8L of its mean (sd 4.5), so a board that is ~78% flat green read
# as one painted rectangle per cell. What breaks that is not more grain — a
# per-pixel wobble averages out under the game's 4:1 nearest downsample — but
# CLUMPS: patches of a darker grass, several blocks across, so the field keeps
# a shape at the board's rung as well as at 1x.
# Both tones are mixes toward GRASS_DARK, which keeps the hue the saturated
# green `GroundContrast`'s COLOUR_BREAK relies on, and neither goes below
# GRASS_DARK, the tuft tone at the floor of `palette.GROUND_BAND` — the band
# the outline grade is chosen out of, so a clump cannot make a silhouette's
# ground-facing contour a decision the renderer did not already account for.
# The field DARKENS only: the median stays GRASS and TERRAIN_MEDIAN_CEILING
# keeps its headroom.
CLUMP = mix(GRASS, GRASS_DARK, 0.5)  # L143, 15L under the field
CLUMP_DK = mix(GRASS, GRASS_DARK, 0.88)  # L132, one step over the tuft tone

_BLOCK = 4  # px — the field's unit, kept at the game's 4:1 downsample step
_BLOCKS = CELL // _BLOCK
# The darkest twelfth and the next fifth of each tile's blocks take the two
# tones (by rank — see `_rank_clumps`), so every phase is the same field in a
# different arrangement, which is what lets the woods plate and the plains
# plate stay tone for tone identical.
_CLUMP_DEEP_SHARE = 0.12
_CLUMP_SHARE = 0.30

# The field's period, and why it is 60 and not 64 (seam pass, 2026-08-23).
#
# The clump field wrapped at the CELL, which makes one phase repeat seamlessly
# — and the game does not repeat one phase. It hashes a phase per cell, so what
# actually butts on a board is phase 3's right edge against phase 1's left, and
# those were two different fields cut off at the border: the mean luma step
# across a 64px boundary on a hashed 8x8 field measured 9.6 against 1.9 inside
# a tile, a five-fold discontinuity that quilts an open field.
#
# Two tiles can only butt without a step if their edges are THE SAME PIXELS, so
# the outermost block ring is drawn from one shared field (`_SEAM_SALT`) that
# every phase carries, and each phase's own field dithers in over `_SEAM_FADE`
# blocks behind it. The shared field has a period of 60px — fifteen blocks —
# so the ring's last block column IS its first: block column 15 starts at x=60
# and reads the same field value as block column 0, so the two 4px blocks that
# meet at a seam carry one tone, whichever phases meet. The period is the
# field's own rather than a duplicated column, which is what keeps the ring
# smooth against the interior it fades into.
_CLUMP_PERIOD = 60
_CLUMP_LATTICE = _CLUMP_PERIOD // 4  # px between field nodes, four to a period
_SEAM_SALT = 5
_SEAM_FADE = 2  # blocks over which a phase's own field takes over from it


def _clump_field(x: int, y: int, salt: int) -> float:
    """A smooth value field on a lattice that wraps every `_CLUMP_PERIOD` px in
    both axes, roughened by the block's own hash so a clump's edge is ragged
    instead of a circle."""
    px_, py = x % _CLUMP_PERIOD, y % _CLUMP_PERIOD
    fx, fy = px_ / _CLUMP_LATTICE, py / _CLUMP_LATTICE
    i, j = int(fx), int(fy)
    tx, ty = fx - i, fy - j
    sx, sy = tx * tx * (3 - 2 * tx), ty * ty * (3 - 2 * ty)

    def node(a: int, b: int) -> float:
        return h01(a % 4, b % 4, salt)

    top = node(i, j) * (1 - sx) + node(i + 1, j) * sx
    bot = node(i, j + 1) * (1 - sx) + node(i + 1, j + 1) * sx
    return top * (1 - sy) + bot * sy + (h01(px_, py, salt + 101) - 0.5) * 0.3


def _seam_key(bxi: int, byi: int) -> tuple[int, int]:
    """A border block's index on the shared ring, folded onto the field's
    period: 15 becomes 0, so a tile's last block column IS its first."""
    return bxi % (_CLUMP_PERIOD // _BLOCK), byi % (_CLUMP_PERIOD // _BLOCK)


def _own_field(bxi: int, byi: int, salt: int) -> float:
    """The field value a block takes behind the shared ring.

    The hand-over is DITHERED, not averaged: a block one step in takes its own
    phase's field or the shared one by its own hash, in the proportion
    `_SEAM_FADE` asks for. Averaging two fields halves their variance, and the
    field is ranked — so a smooth fade put every phase's darkest blocks in the
    middle of its tile and drew a sparse frame around every cell, which is the
    quilt this pass exists to remove. A dither keeps the distribution the rank
    is taken over identical everywhere.
    """
    edge = min(bxi, byi, _BLOCKS - 1 - bxi, _BLOCKS - 1 - byi)
    x, y = bxi * _BLOCK, byi * _BLOCK
    w = min(1.0, edge / _SEAM_FADE)
    keep = h01(bxi, byi, salt + 211) < w
    return _clump_field(x, y, salt if keep else _SEAM_SALT)


def _ring_layout() -> dict[tuple[int, int], RGB]:
    """The border every phase carries, ranked over the shared field alone."""
    field = {
        (bxi, byi): _clump_field(bxi * _BLOCK, byi * _BLOCK, _SEAM_SALT)
        for byi in range(_BLOCKS)
        for bxi in range(_BLOCKS)
    }
    return _rank_clumps(field, round(len(field) * _CLUMP_SHARE))


def _rank_clumps(
    field: dict[tuple[int, int], float], count: int, deep: int | None = None
) -> dict[tuple[int, int], RGB]:
    """The darkest `count` of `field`'s blocks, the darkest `deep` of them in
    the deeper tone. Coverage is fixed by RANK, not by a threshold on the
    field: with four nodes across a tile, an absolute cut gave one phase 4%
    clumps and another 43%."""
    if deep is None:
        deep = round(len(field) * _CLUMP_DEEP_SHARE)
    order = sorted(field, key=lambda b: (field[b], b))[:count]
    return {b: (CLUMP_DK if i < deep else CLUMP) for i, b in enumerate(order)}


def _clump_layout(salt: int) -> dict[tuple[int, int], RGB]:
    """Which of a tile's 4px blocks a phase clumps, and with which tone.

    The border ring is the shared one, read at its folded index; the interior
    is the phase's own field, ranked to whatever the ring left of the tile's
    fixed clump budget. Every phase therefore spends the same number of blocks
    on each tone — the two plates and every phase stay one field in different
    arrangements — while their edges stay identical.
    """
    ring = _ring_layout()
    layout = {}
    for byi in range(_BLOCKS):
        for bxi in range(_BLOCKS):
            if bxi in (0, _BLOCKS - 1) or byi in (0, _BLOCKS - 1):
                tone = ring.get(_seam_key(bxi, byi))
                if tone is not None:
                    layout[(bxi, byi)] = tone
    total, deep = (
        round(_BLOCKS**2 * _CLUMP_SHARE),
        round(_BLOCKS**2 * _CLUMP_DEEP_SHARE),
    )
    inner = {
        (bxi, byi): _own_field(bxi, byi, salt)
        for byi in range(1, _BLOCKS - 1)
        for bxi in range(1, _BLOCKS - 1)
    }
    ring_deep = sum(1 for tone in layout.values() if tone == CLUMP_DK)
    layout.update(_rank_clumps(inner, total - len(layout), max(0, deep - ring_deep)))
    return layout


def _grass_ground(salt: int) -> Image.Image:
    """The grass plate: the three-step grain with the two-tone clump field over
    it, in 4px blocks so a clump survives the game's 4:1 nearest downsample.
    Plains and woods share this plate (see `WoodsSeam`)."""
    img = Image.new("RGBA", (CELL, CELL), (*GRASS, 255))
    px = img.load()
    layout = _clump_layout(salt)
    for byi in range(_BLOCKS):
        for bxi in range(_BLOCKS):
            # The border ring's grain is the shared one too, read at the same
            # folded index the ring's clumps are: a tile's last block column is
            # its first, so any two phases butt with no step at all.
            border = bxi in (0, _BLOCKS - 1) or byi in (0, _BLOCKS - 1)
            kx, ky = _seam_key(bxi, byi) if border else (bxi, byi)
            key_salt = _SEAM_SALT if border else salt
            # A clump is FLAT — the grain the field carries is not repeated
            # inside it. Two reasons: a clump is meant to be a shape at the
            # board's 4:1 rung, which a wobble inside it only blurs, and a
            # grained clump spends a colour per rung on a tile already close
            # to the 80-colour ceiling (woods measured 88). Flat also means
            # both plates and every phase spend exactly these two tones,
            # which is what `WoodsSeam` reads the woods plate against the
            # plains one on.
            tone = layout.get((bxi, byi))
            if tone is None:
                tone = _grain(GRASS, kx * _BLOCK, ky * _BLOCK, key_salt)
            for yy in range(byi * _BLOCK, byi * _BLOCK + _BLOCK):
                for xx in range(bxi * _BLOCK, bxi * _BLOCK + _BLOCK):
                    px[xx, yy] = (*tone, 255)
    return img


# ---------------------------------------------------------------------------
# plain grounds
# ---------------------------------------------------------------------------


def road() -> Image.Image:
    t = _ground(ROAD, 1)
    # tire-wear bands
    _rect(t, 4, 18, 56, 3, mix(ROAD, ROAD_DARK, 0.2))
    _rect(t, 4, 43, 56, 3, mix(ROAD, ROAD_DARK, 0.2))
    # the classic centre dashes, thinned to read as lane markings
    _rect(t, 12, 30, 12, 4, ROAD_DARK)
    _rect(t, 40, 30, 12, 4, ROAD_DARK)
    # a few embedded stones
    for sx, sy in ((22, 12), (50, 50), (8, 54), (34, 8)):
        _rect(t, sx, sy, 3, 2, ROAD_DARK)
        _rect(t, sx, sy, 2, 1, _lit(ROAD, 0.12))
    return t


# Grass tufts: a dark check with a light blade, like the old speckles but drawn
# as 3px clusters.
#
# The pair of wildflowers that used to follow them is gone (2026-08-23). They
# were two pixels of WILDFLOWER (H40 S0.73) and two of SNOW (H214) on a hue-100
# field, at the size the board keeps one source pixel in four of: an off-palette
# fleck reads as a dead pixel, not as a flower. What a stretch of field varies
# by is the clump field; a find is a decal, and every decal is on the field's
# own ramp now.
_TUFTS = (
    (10, 12),
    (34, 8),
    (52, 22),
    (18, 30),
    (42, 38),
    (8, 44),
    (28, 52),
    (54, 48),
    (24, 20),
    (46, 12),
    (14, 56),
    (38, 24),
)


# A clump's leaves, kept off GRASS_DARK so the tufts stay countable per phase.
_LEAF = _tone(GRASS_DARK, 0.44, 105.0)  # L105, S0.44 — a find's chroma bound
_BLADE = _lit(GRASS, 0.18)  # the tuft's lit blade, which a decal reuses

# The decal tones, all of them ON THE FIELD'S RAMP (2026-08-23). A decal used
# to be drawn out of the grounds it depicted — gravel for a stone, sand and
# gravel for a scuff — and at 1-3px on a hue-100 field those are not a stone
# and a scuff, they are three dead pixels: gravel is H41 S0.09, its shadow
# H225, the wildflower H40 S0.73. Nothing that small carries a material; what
# it carries is a hue, so a find is drawn in grass's own hue held under S0.45,
# which is a lichen-grey stone and a patch of dry, bleached grass. The dry tone
# leans 20° toward sand — as far as a find may go — so a patch still reads as
# ground worn thin rather than as more clump.
_STONE = _tone(GRASS, 0.10, 152.0)  # H100 S0.10, L152
_STONE_DK = _tone(GRASS, 0.14, 120.0)
_DRY_BASE = mix(GRASS, SAND, 0.55)
_DRY = _tone(_DRY_BASE, 0.34, 147.0)  # H80 S0.34, L147
_DRY_DK = _tone(_DRY_BASE, 0.38, 127.0)


def _pebble(t: Image.Image, x: int, y: int) -> None:
    _rect(t, x, y + 1, 3, 2, _STONE_DK)
    _rect(t, x + 1, y, 2, 1, _STONE)


def _tussock(t: Image.Image, x: int, y: int) -> None:
    """A knot of taller grass: a leaf base with two blades out of it."""
    _rect(t, x, y + 1, 4, 1, _LEAF)
    _rect(t, x, y, 1, 1, _LEAF)
    _rect(t, x + 2, y, 1, 1, _BLADE)
    _rect(t, x + 3, y + 1, 1, 1, _LEAF)


def _dry_patch(t: Image.Image, x: int, y: int) -> None:
    _rect(t, x, y, 6, 3, _DRY)
    _rect(t, x + 1, y + 1, 4, 1, _DRY_DK)


# A decal is scattered ground detail and nothing more: a stone, a knot of tall
# grass, a patch the summer has dried out — all in the field's own tones and
# all under the terrain value ceiling. Deliberately no signpost, fence or
# marker — a drawn object on open ground reads as a property from across the
# board. A decal is drawn inside the cell (`_rect` clips) so it never overhangs
# into the neighbour, and it stands clear of the tufts, which is what keeps
# every phase carrying the same field.
_DECALS = {"pebble": _pebble, "tussock": _tussock, "dry": _dry_patch}

# Phase offsets for plains — the sea's rule (SEA_PHASES below) applied to the
# ground most of a board is made of. Each entry is (salt, prop dx, dy, decals):
# the salt keys BOTH the grain and the clump field, so a phase is a different
# arrangement of the same field rather than the same picture slid sideways, and
# the props stand somewhere else on top of it. Same tone count and the same
# clump coverage every phase, which is what keeps the field's value read a
# phase apart. Phase 0 is the atlas column, so a board that has not adopted the
# sheet is unchanged and adoption is additive.
# The 2026-08-22 review measured the old table as five translations of one tuft
# grid: tile means within 0.31L of each other, with three of the five carrying
# nothing at all. Rarity is the clump field's job now — it is what a stretch of
# field varies BY — so the decals stop being the only difference between phases
# and all but one carry a find. Phase 0 stays bare because it is the atlas
# column, which is the tile a board falls back to everywhere.
# EIGHT of them since 2026-08-23, not five: the shipped maps are ~56% plains,
# and at the board's 4:1 rung a five-phase field puts the same fleck back at
# the same in-tile position every fifth cell the hash lands on — a lattice at
# a longer pitch is still a lattice. The three added phases are salt variants
# of the same field, drawn by the same painter: only the hash key, the tuft
# offset and where the find lies move, so the coverage, the tone count and the
# value band the field is measured on are the phases the table already had.
# The game's `TerrainAutotiles.PLAINS_PHASES` counts these cells, so it moves
# with this tuple or the board indexes off the end of the sheet.
# The salts are PICKED, not chosen for looks: since the border ring became
# shared it is a fifth of a tile's clumps laid the same way in every phase, a
# floor of ~0.15 under any two phases' layout overlap, so what a salt buys is
# how little its INTERIOR agrees with the others'. The five the table held
# were searched for on 2026-08-23 (0.31 at the worst of ten pairs, against
# 0.47 for the salts it happened to hold); 31, 253 and 316 are the trio that
# joins them at the least worst pair over all 28 — 0.34, which no trio of
# salts under 400 beats.
PLAINS_PHASES: tuple[tuple[int, int, int, tuple[tuple[str, int, int], ...]], ...] = (
    (PLAINS_SALT, 0, 0, ()),
    (8, 27, 19, (("tussock", 52, 22), ("dry", 24, 46))),
    (13, 45, 37, (("pebble", 6, 30), ("dry", 40, 8))),
    (20, 13, 49, (("pebble", 21, 40), ("dry", 43, 14))),
    (49, 55, 7, (("tussock", 12, 22), ("pebble", 45, 50))),
    (31, 33, 29, (("dry", 14, 12), ("tussock", 46, 44))),
    (253, 7, 41, (("pebble", 50, 18), ("tussock", 18, 46))),
    (316, 49, 11, (("dry", 40, 46), ("pebble", 12, 24))),
)

# A tuft is drawn whole, inside the cell. It used to WRAP around the tile,
# which is seamless for one phase repeated and is not what the game does: it
# hashes a phase per cell, so a tuft cut at phase 3's right edge met phase 1's
# uncut left edge and the cut showed. The offset is folded into the cell and
# then held off the border, so every phase still carries all twelve tufts —
# what moves is where they stand, not how many survive.
_TUFT_MARGIN = 1


def _tuft_at(sx: int, sy: int, dx: int, dy: int) -> tuple[int, int]:
    """Where a tuft stands once its phase offset is folded into the cell.

    Both axes are clamped off the outermost pixel ring on both sides — the
    ring is the shared one every phase carries, and a tuft painted into it
    would be the one pixel that is not shared and so the one that seams. The
    low bound on y is one further in because the blade is drawn a row above.
    """
    span = CELL - _TUFT_MARGIN - 3
    x = min(max((sx + dx) % CELL, _TUFT_MARGIN), span)
    y = min(max((sy + dy) % CELL, _TUFT_MARGIN + 1), span)
    return x, y


def plains(phase: int = 0) -> Image.Image:
    salt, dx, dy, decals = PLAINS_PHASES[phase]
    t = _grass_ground(salt)
    for i, (sx, sy) in enumerate(_TUFTS):
        x, y = _tuft_at(sx, sy, dx, dy)
        _rect(t, x, y, 3, 2, GRASS_DARK)
        _rect(t, x + (i % 2), y - 1, 1, 1, _BLADE)
    for kind, x, y in decals:
        _DECALS[kind](t, x, y)
    return t
