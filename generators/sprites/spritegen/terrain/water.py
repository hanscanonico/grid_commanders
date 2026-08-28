"""Every tile the water is drawn in: river, sea, shoal, bridge and reef."""

from __future__ import annotations

from PIL import Image

from .. import buildings
from ..palette import FACTIONS, RGB, h01, mix
from ..voxel import render
from .tones import (
    CELL,
    SAND,
    SAND_DARK,
    SNOW,
    TIMBER,
    TIMBER_DARK,
    WATER,
    WATER_DARK,
    WATER_LIGHT,
    _ground,
    _lit,
    _paste_prop,
    _rect,
)


def _water_base(deep: bool, salt: int) -> Image.Image:
    return _ground(WATER_DARK if deep else WATER, salt, grain=0.027)


# The outermost ring a sliding glint may not be pushed into. It is the rule
# the plains tufts are held to (`_tuft_at`, at its own one-px margin) for the
# same reason: the ring is the strip a cell shares with the neighbour it is
# repeated against, so a dash cut at one tile's border meeting the next tile's
# uncut border is a seam. Two px here, one more than the tufts', because a
# glint is two rows and the dash's own edge should not sit on the join either.
_GLINT_RING = 2


def _slide_x(x: int, dx: int) -> int:
    """Where a glint's pixel column lands `dx` px along its own row.

    The dash wraps inside the interior band rather than around the whole cell,
    which is what keeps `_GLINT_RING` clear. No shipped glint reaches the band
    edge, so the wrap is the rule the slide is safe under, not something that
    happens to the art as it stands.
    """
    span = CELL - 2 * _GLINT_RING
    return _GLINT_RING + (x - _GLINT_RING + dx) % span


def _dash(t: Image.Image, sx: int, sy: int, w: int, dx: int, c: RGB) -> None:
    """One glint row, drawn column by column so the wrap can split it."""
    for k in range(w):
        _rect(t, _slide_x(sx + k, dx), sy, 1, 1, c)


def _glints(t: Image.Image, base: RGB, light: RGB, salt: int, slide: int = 0) -> None:
    """Three hash-placed flow glints: short, staggered, low-contrast.

    The old four dashes sat on the same rows in every repeated tile, and a
    stretch of water read as a lattice from across the room (round 3). The
    hash spreads them with no shared row; nothing here aligns to a grid.

    `slide` moves every dash along its own row and nothing else, which is what
    a time frame of this water is (`sea`): the two rows of a glint move
    together, so the stagger between them — the thing that makes a dash read
    as a streak with a direction rather than as a bar — survives the move.
    """
    for i in range(3):
        sx = 3 + int(h01(i, 0, salt) * 42)
        sy = 4 + int(h01(i, 1, salt) * 55)
        w = 7 + int(h01(i, 2, salt) * 7)
        _dash(t, sx, sy, w, slide, mix(base, light, 0.55))
        _dash(t, sx + 2 + i, sy + 1, max(3, w - 4), slide, mix(base, light, 0.3))


def river() -> Image.Image:
    t = _water_base(False, 5)
    _glints(t, WATER, WATER_LIGHT, 78)
    # rounded pebble breaking the current
    _rect(t, 28, 54, 6, 3, mix(WATER, WATER_DARK, 0.7))
    _rect(t, 29, 53, 4, 1, mix(WATER, WATER_LIGHT, 0.55))
    return t


# Phase offsets for the sea (design review rounds 3 and 6). One sea tile
# repeated over a whole frame is visibly row-aligned however the glints are
# spread inside it, because every cell spreads them the same way — the lattice
# is the repeat, not the tile. Each entry is (grain salt, glint salt): a
# variant is the same water with its texture and its flow in a different phase.
# Variant 0 is the atlas column, so it stays exactly what it was and the game
# can adopt the rest one at a time.
SEA_PHASES: tuple[tuple[int, int], ...] = ((6, 73), (14, 91), (23, 108))

# How far a glint travels between the sea's two TIME frames, in atlas px.
# A phase and a frame are different things and the difference is the whole
# trick: a phase re-salts the water base, so playing the phases as frames
# would repaint every pixel of the cell at once — the boil that makes cheap
# animated water look like static. A frame keeps `_water_base` byte-identical
# and moves only the dashes, so what the eye is given is a few streaks
# travelling over water that is standing still.
# Four px is exactly one board texel at the 4:1 rung (`voxel`'s cube is 4 px),
# the same whole-texel rule the unit idles are held to: less than a texel is a
# re-tone the nearest-filtered board can swallow, a texel is a move.
SEA_FRAMES = 2
SEA_GLINT_SLIDE = 4


def sea(phase: int = 0, frame: int = 0) -> Image.Image:
    """One sea cell: spatial variant `phase`, time frame `frame`.

    Frame 0 is the tile as it has always been, so the atlas column and every
    board that has not adopted the clip are unchanged.
    """
    grain, glint = SEA_PHASES[phase]
    t = _water_base(True, grain)
    _glints(t, WATER_DARK, WATER, glint, slide=frame * SEA_GLINT_SLIDE)
    return t


def shoal() -> Image.Image:
    t = _ground(SAND, 7)
    # water across the bottom with a scalloped surf line — irregular foam
    # clusters, not the uniform dashes that read as road markings
    _rect(t, 0, 40, 64, 24, WATER)
    _rect(t, 0, 40, 64, 2, SAND_DARK)  # wet sand lip
    for k, sx in enumerate(range(0, 64, 8)):
        wob = int(h01(sx, 0, 41) * 3)
        _rect(t, sx, 41 + wob, 5 + (k % 2) * 2, 2, SNOW)
        _rect(t, sx + 2, 43 + wob, 3, 1, mix(WATER, SNOW, 0.55))
    _rect(t, 8, 52, 14, 2, WATER_LIGHT)
    _rect(t, 40, 56, 12, 2, WATER_LIGHT)
    # dry-sand speckles and a shell
    for sx, sy in ((12, 12), (36, 20), (24, 32), (48, 8), (54, 30)):
        _rect(t, sx, sy, 3, 2, SAND_DARK)
    _rect(t, 44, 24, 2, 2, SNOW)
    return t


def bridge() -> Image.Image:
    """A timber deck standing over the water. The deck is deliberately not
    the road tile's gravel: the two shared one dominant colour, so a bridge
    read as a road that happened to be wet."""
    t = _water_base(False, 8)
    # support shadows in the water under each pier
    for sx in (8, 28, 48):
        _rect(t, sx, 50, 10, 4, mix(WATER, (10, 30, 60), 0.35))
    _rect(t, 0, 12, 64, 40, TIMBER)
    _rect(t, 0, 12, 64, 2, _lit(TIMBER, 0.25))  # lit rail
    _rect(t, 0, 50, 64, 2, TIMBER_DARK)  # shaded rail
    _rect(t, 0, 14, 64, 1, TIMBER_DARK)
    # railing posts
    for sx in range(2, 64, 8):
        _rect(t, sx, 12, 2, 4, TIMBER_DARK)
        _rect(t, sx, 48, 2, 4, TIMBER_DARK)
    # plank courses across the deck, the structure's own grain
    for sy in range(18, 50, 6):
        _rect(t, 0, sy, 64, 1, mix(TIMBER, TIMBER_DARK, 0.55))
    # deck plank seams
    for sx in (21, 43):
        _rect(t, sx, 16, 1, 32, mix(TIMBER, TIMBER_DARK, 0.5))
    return t


def reef() -> Image.Image:
    t = _water_base(True, 9)
    spots = ((14, 22, 3), (40, 16, 2), (22, 44, 2), (48, 46, 3))
    for sx, sy, size in spots:
        # rock materials are faction-independent; any row renders the same
        rock = render(buildings.rock_outcrop(size), FACTIONS[0])
        # foam ring where the rock breaks the surface
        _rect(
            t,
            sx - rock.width // 2 - 2,
            sy - 2,
            rock.width + 4,
            2,
            mix(WATER_DARK, SNOW, 0.55),
        )
        _paste_prop(t, rock, sx, sy)
    _rect(t, 8, 56, 10, 2, WATER)
    _rect(t, 52, 8, 8, 2, WATER)
    return t
