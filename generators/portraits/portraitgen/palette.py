"""Colours: the board's own ramps, the game's faction themes, and the ink.

The faction themes mirror grid_commanders' `CommanderVisuals.FactionTheme` so the
portraits this tool bakes and the UI chrome that frames them can never disagree
about which colour a faction is; `tests/test_palette_mirror.py` reads the values
back out of the game's own code. Row order mirrors `SideIdentity._ROW_FOR_KEY`:
0 neutral, 1 meridian, 2 aurora, 3 iron, 4 verdant, 5 gold.

Colours are kept as the authored 0-1 floats and converted to bytes in one place
(`rgb8`), which **truncates** — that is what Godot's `Color` to `FORMAT_RGBA8`
conversion does, and the committed emblems carry those exact bytes.

**A bust and the army it commands are lit by one sun**, and how far that goes
is per material rather than sheet-wide:

- the **army's six** rungs are the board's own faction ramp, four of them
  overridden by `BUST_RUNGS` below with the reason named;
- the **gunmetal's two** are the board's `GUNMETAL_RAMP`, rung for rung;
- **skin's four and hair's three** are not off a board ramp at all — the bases
  are the portraits' own (`head.SKIN_BASES`, `hair.HAIR_BASES`) and so is the
  value ladder over them (`light`), because the board has no skin. What is
  shared there is the **shaper**: `build_ramp`, the board's, with its chroma
  curve, its hue rotation and its cool sky;
- the **ink** is off no ladder — it is the design system's outline as bytes.

`tests/test_palette_mirror.py` holds every clause of that: the four overrides
being the only four, every skin and hair rung being the board's shape of its
base, and each slice of the sixteen coming from where this says it does.

What a bust may spend is `PAINTED_TONES`: sixteen, gathered by `bust_palette`
out of the ramps that bust actually wears, and every finished raster is snapped
onto its own sixteen by `quantise`. That is the pixel-art discipline the old
forty-eight-tone bar approximated — a band is a rung of a ramp, and an edge is
one rung meeting another rather than a blend of the two.
"""

from __future__ import annotations

import importlib.util
import sys
from dataclasses import dataclass
from pathlib import Path
from types import ModuleType

from PIL import Image

from .vocab import pick

RGB = tuple[int, int, int]
RGBA = tuple[int, int, int, int]
Float3 = tuple[float, float, float]

# Every border and body glyph in the design system, and the outline weight the
# emblems are drawn with: the retired GDScript bake's OUTLINE, as bytes.
INK: RGB = (19, 23, 27)


def rgb8(colour: Float3) -> RGB:
    """A theme's 0-1 floats as bytes, the way the engine writes them."""
    return tuple(min(255, max(0, int(v * 255.0))) for v in colour)


@dataclass(frozen=True)
class Faction:
    """One `CommanderVisuals.FactionTheme`, colour for colour."""

    key: str
    display: str
    color: Float3
    color_dark: Float3
    color_light: Float3

    @property
    def body(self) -> RGB:
        return rgb8(self.color)

    @property
    def body_dk(self) -> RGB:
        return rgb8(self.color_dark)

    @property
    def body_lt(self) -> RGB:
        return rgb8(self.color_light)


# The six themes, as the game authors them. Not the board's `FACTIONS`, which
# carries the same six from the same source in bytes: the board ROUNDS the
# floats and this module TRUNCATES them, the way Godot writes a `Color` into
# `FORMAT_RGBA8`, so the two disagree by a unit on twenty-three of the
# fifty-four channels. The committed emblems carry the truncated bytes — every
# one of the five moves if this block is swapped for the board's — so the
# difference is pinned by `tests/test_palette_mirror.py` rather than resolved.
FACTIONS: tuple[Faction, ...] = (
    Faction(
        "neutral",
        "No Commander",
        (0.376, 0.416, 0.443),
        (0.235, 0.267, 0.290),
        (0.510, 0.549, 0.573),
    ),
    Faction(
        "meridian",
        "Meridian Coalition",
        (0.859, 0.290, 0.231),
        (0.663, 0.212, 0.192),
        (0.937, 0.447, 0.373),
    ),
    Faction(
        "aurora",
        "Aurora Compact",
        (0.220, 0.396, 0.847),
        (0.169, 0.306, 0.659),
        (0.427, 0.549, 0.910),
    ),
    Faction(
        "iron",
        "Iron Dominion",
        (0.290, 0.322, 0.345),
        (0.184, 0.212, 0.231),
        (0.420, 0.455, 0.482),
    ),
    Faction(
        "verdant",
        "Verdant League",
        (0.173, 0.525, 0.212),
        (0.114, 0.380, 0.153),
        (0.310, 0.659, 0.353),
    ),
    Faction(
        "gold",
        "Gilded Concord",
        (0.914, 0.788, 0.157),
        (0.694, 0.600, 0.118),
        (0.953, 0.863, 0.400),
    ),
)

# The seat nobody holds wears no emblem: assets/portraits/factions holds five
# files, one per army.
EMBLEM_KEYS: tuple[str, ...] = ("aurora", "gold", "iron", "meridian", "verdant")


# Built once off the tuple above, so the lookup below is a table like every
# other vocabulary in this package rather than a scan with its own raise.
_BY_KEY: dict[str, Faction] = {faction.key: faction for faction in FACTIONS}


def faction_by_key(key: str) -> Faction:
    return pick(_BY_KEY, key, "faction")


# --- the board's ramps -------------------------------------------------------
#
# Six lighting bands, not six brightnesses: S0 contour, S1 under, S2 shadow,
# S3 body, S4 top, S5 rim.

# Derived from this file's own path, so it holds wherever the checkout sits and
# whatever directory a run is started from.
BOARD_PALETTE = (
    Path(__file__).resolve().parents[2] / "sprites" / "spritegen" / "palette.py"
)
_BOARD_MODULE = "portraitgen._board_palette"


def _load_board() -> ModuleType:
    """The sprite generator's palette module, executed off its own file.

    `generators/sprites` is a sibling offline instrument rather than an
    installed package, so there is nothing to import it as. It is registered in
    `sys.modules` before it runs because a frozen dataclass inside it looks its
    own module up while its class body is being built.
    """
    if not BOARD_PALETTE.is_file():
        raise ModuleNotFoundError(
            f"the board's palette is not at {BOARD_PALETTE}. A bust is painted "
            "out of generators/sprites' own ramps, so that instrument has to be "
            "checked out beside this one."
        )
    spec = importlib.util.spec_from_file_location(_BOARD_MODULE, BOARD_PALETTE)
    if spec is None or spec.loader is None:
        raise ImportError(f"no importable module at {BOARD_PALETTE}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[_BOARD_MODULE] = module
    spec.loader.exec_module(module)
    return module


BOARD = _load_board()

SLOTS: int = BOARD.SLOTS
S_CONTOUR: int = BOARD.S_CONTOUR
S_UNDER: int = BOARD.S_UNDER
S_SHADOW: int = BOARD.S_SHADOW
S_BODY: int = BOARD.S_BODY
S_TOP: int = BOARD.S_TOP
S_RIM: int = BOARD.S_RIM

Ramp6 = tuple[RGB, ...]

# The sky every shadow on the board is lit by, the shaper that rotates a rung
# toward it, and the authored ramps themselves — the board's, by reference.
AMBIENT: RGB = BOARD.AMBIENT
luminance = BOARD.luminance
build_ramp = BOARD.build_ramp
RAMPS: dict[str, Ramp6] = BOARD.RAMPS
GUNMETAL_RAMP: Ramp6 = BOARD.GUNMETAL_RAMP


def _rung(base: RGB, slot: int, target: float) -> RGB:
    """One rung off the board's shaper, for a bust that authors a single band.

    `build_ramp` is the only way in from outside that module, and a rung
    depends on nothing but its own slot and target, so the ladder around it is
    left at zero.
    """
    ladder = [0.0] * SLOTS
    ladder[slot] = target
    return build_ramp(base, tuple(ladder))[slot]


# --- where a board ramp does not serve a bust --------------------------------
#
# `RAMPS` above is the board's rung for rung and stays that way
# (`tests/test_palette_mirror.py`). Four rungs across two rows are not, because
# a bust asks of them what the board never did: gold's three lit rungs come off
# the funds gold, since the Gilded ramp is authored a band low for a roof and a
# coat painted on it is olive, and Iron's field rung comes up to where every
# other army's sits, since Iron's ramp is the inverted one and a window at L49
# is under every dark cap and every dark skin on the sheet.
#
# Neither base is retyped: the accent IS the funds gold — the Gilded army's own
# `FactionTheme` colour, as the board reads it — and the iron base is the anchor
# the board's own Iron ramp is shaped from, so a rung this module lifts stays
# tied to the row it was lifted off.
ACCENT_BASE: RGB = BOARD.faction_by_key("gold").body
ACCENT_RAMP: Ramp6 = build_ramp(ACCENT_BASE, (20.0, 46.0, 70.0, 150.0, 186.0, 225.0))
IRON_BASE: RGB = BOARD.RAMP_BASES["iron"]
IRON_FIELD: RGB = _rung(IRON_BASE, S_SHADOW, 74.0)

# Which rungs each of the two takes, and from where. Everything not named here
# is the board's own.
BUST_RUNGS: dict[str, dict[int, RGB]] = {
    "gold": {slot: ACCENT_RAMP[slot] for slot in (S_BODY, S_TOP, S_RIM)},
    "iron": {S_SHADOW: IRON_FIELD},
}


def faction_ramp(key: str) -> Ramp6:
    """The six rungs an army is painted on a bust in. An unknown key raises.

    The overrides are spent INSIDE the sixteen rather than added to them:
    `bust_palette` still hands out one ink, six army rungs and nine of the
    three materials', and the membership bar (`ThePaletteIsBounded`) reads its
    allowed set off this same function. The set moved; the cap did not.
    """
    board = pick(RAMPS, key, "ramp")
    taken = BUST_RUNGS.get(key, {})
    return tuple(taken.get(slot, rung) for slot, rung in enumerate(board))


# --- what one bust may spend -------------------------------------------------

# Sixteen tones, and how they are spent: the ink, the army's whole ramp — two
# rungs of it behind the figure, four on its cloth and the rim every material
# on the bust kicks with — four of skin, three of hair, and the two the board's
# gunmetal spends on a blade, a buckle and a pip. A bust that wants a
# seventeenth takes it from one of these instead.
#
# There is no white. The lit rung of a pale skin already reaches 255 and a
# steel top plane is the brightest thing a general in a dark window owns, so a
# white slot would be a tone spent twice.
PAINTED_TONES = 16
# Which rungs each material actually gets, and the one statement of it. The
# light model gives every material four bands, but only skin can afford all
# four here: hair drops its deep and gunmetal keeps its top two, so those two
# quantise onto the rung above. Adding one back means taking a rung off another
# material — `bust_palette` refuses a seventeenth tone.
SKIN_SLOTS = (S_UNDER, S_SHADOW, S_BODY, S_TOP)
HAIR_SLOTS = (S_SHADOW, S_BODY, S_TOP)
METAL_SLOTS = (S_BODY, S_TOP)

# How near two colours are, in whole numbers: red, green and blue weighted the
# way the eye reads them, squared, so `quantise` never divides or takes a root.
_CHANNEL_WEIGHT = (2, 4, 3)


def bust_palette(faction: str, skin: Ramp6, hair: Ramp6) -> tuple[RGB, ...]:
    """The sixteen tones one bust is painted in, in a fixed order.

    Order is the sheet's own hierarchy — ink, army, skin, hair, metal, light —
    so a colour equally far from two entries always takes the earlier one and a
    regenerated bust cannot flip between them.
    """
    army = faction_ramp(faction)
    tones = (
        INK,
        *army,
        *(skin[slot] for slot in SKIN_SLOTS),
        *(hair[slot] for slot in HAIR_SLOTS),
        *(GUNMETAL_RAMP[slot] for slot in METAL_SLOTS),
    )
    if len(tones) != PAINTED_TONES:
        raise ValueError(f"a bust palette is {PAINTED_TONES} tones, not {len(tones)}")
    return tones


def _nearest(colour: RGB, tones: tuple[RGB, ...]) -> RGB:
    return min(
        tones,
        key=lambda tone: sum(
            _CHANNEL_WEIGHT[i] * (colour[i] - tone[i]) ** 2 for i in range(3)
        ),
    )


def quantise(
    image: Image.Image, tones: tuple[RGB, ...], *, shadow: RGBA
) -> Image.Image:
    """Snap every opaque pixel of a finished raster onto `tones`.

    What is not opaque is the hard offset shadow falling past the window, and
    it comes back as `shadow` whatever it composited to: two shadows crossing
    are one shadow, which is the UI's own hard-shadow rule and the reason a
    bust carries exactly one tone that is neither paint nor nothing.
    """
    lookup: dict[RGB, RGB] = {}
    pixels = image.get_flattened_data()
    snapped = []
    for red, green, blue, alpha in pixels:
        if alpha == 0:
            snapped.append((0, 0, 0, 0))
            continue
        if alpha != 255:
            snapped.append(shadow)
            continue
        key = (red, green, blue)
        tone = lookup.get(key)
        if tone is None:
            tone = _nearest(key, tones)
            lookup[key] = tone
        snapped.append((*tone, 255))
    out = Image.new("RGBA", image.size)
    out.putdata(snapped)
    return out
