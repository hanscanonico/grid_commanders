"""Colours: the board's own ramps, the game's faction themes, and the ink.

The faction themes mirror grid_commanders' `CommanderVisuals.FactionTheme` so the
portraits this tool bakes and the UI chrome that frames them can never disagree
about which colour a faction is; `tests/test_palette_mirror.py` reads the values
back out of the game's own code. Row order mirrors `SideIdentity._ROW_FOR_KEY`:
0 neutral, 1 meridian, 2 aurora, 3 iron, 4 verdant, 5 gold.

Colours are kept as the authored 0-1 floats and converted to bytes in one place
(`rgb8`), which **truncates** — that is what Godot's `Color` to `FORMAT_RGBA8`
conversion does, and the committed emblems carry those exact bytes.

**A bust is painted out of the board's palette, not out of one of its own.** The
six-slot ramps below are `generators/sprites`' — the same anchors, the same
value ladders and the same shaper the unit sheet and the terrain are built from,
so a commander and the army they command are lit by one sun. The mirror test
loads the sprite generator's own module and compares them rung for rung.

What a bust may spend is `PAINTED_TONES` of them: sixteen, chosen by
`bust_palette` out of the ramps that bust actually wears, and every finished
raster is snapped onto its own sixteen by `quantise`. That is the pixel-art
discipline the old forty-eight-tone bar approximated — a band is a rung of a
ramp, and an edge is one rung meeting another rather than a blend of the two.
"""

from __future__ import annotations

import colorsys
from dataclasses import dataclass

from PIL import Image

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


def faction_by_key(key: str) -> Faction:
    for faction in FACTIONS:
        if faction.key == key:
            return faction
    raise KeyError(f"no faction {key!r} (have {[f.key for f in FACTIONS]})")


# --- the board's ramps -------------------------------------------------------
#
# Six lighting bands, not six brightnesses: S0 contour, S1 under, S2 shadow,
# S3 body, S4 top, S5 rim. Mirrored from `spritegen.palette` — the anchors, the
# ladders, the sky and the per-slot chroma shape are that module's, and
# `tests/test_palette_mirror.py` fails if either side moves.

SLOTS = 6
S_CONTOUR, S_UNDER, S_SHADOW, S_BODY, S_TOP, S_RIM = range(SLOTS)

Ramp6 = tuple[RGB, ...]

# The sky every shadow on the board is lit by, and the two hues a rung rotates
# toward.
AMBIENT: RGB = (86, 112, 190)
_SKY_HUE = 225.0
_SUN_HUE = 45.0
_HUE_ARC = 14.0
_HUE_PULL = (-1.00, -0.72, -0.34, 0.0, 0.46, 1.00)
_SAT_SCALE = (1.10, 1.22, 1.24, 1.0, 0.82, 0.42)
_AMBIENT_MIX = (0.26, 0.16, 0.07, 0.0, 0.0, 0.0)


def _hex(value: str) -> RGB:
    return (int(value[0:2], 16), int(value[2:4], 16), int(value[4:6], 16))


def clamp8(value: float) -> int:
    return max(0, min(255, int(round(value))))


def luminance(colour: RGB) -> float:
    """Rec. 601 luma, the scale every ladder here is authored on."""
    return 0.299 * colour[0] + 0.587 * colour[1] + 0.114 * colour[2]


def mix(first: RGB, second: RGB, weight: float) -> RGB:
    return tuple(clamp8(first[i] + (second[i] - first[i]) * weight) for i in range(3))


def _full_chroma(hue: float, saturation: float) -> RGB:
    red, green, blue = colorsys.hsv_to_rgb((hue % 360.0) / 360.0, saturation, 1.0)
    return (clamp8(red * 255), clamp8(green * 255), clamp8(blue * 255))


def _rotate(hue: float, pull: float) -> float:
    if pull == 0.0:
        return hue
    target = _SKY_HUE if pull < 0 else _SUN_HUE
    delta = ((target - hue + 180.0) % 360.0) - 180.0
    step = min(abs(delta), abs(pull) * _HUE_ARC)
    return hue + (step if delta >= 0 else -step)


def _at_luminance(colour: RGB, target: float) -> RGB:
    """Re-key a colour to an exact luma, keeping its chroma as long as it can:
    scale first, and wash toward white only once a channel is pinned."""
    lum = luminance(colour)
    if lum <= 0.0:
        return (clamp8(target), clamp8(target), clamp8(target))
    ceiling = lum * 255.0 / max(colour)
    if target <= ceiling:
        return tuple(clamp8(c * target / lum) for c in colour)
    pinned = mix((0, 0, 0), colour, 255.0 / max(colour))
    return mix(pinned, (255, 255, 255), (target - ceiling) / (255.0 - ceiling))


def _shape(base: RGB, slot: int, target: float) -> RGB:
    """One rung: the base's hue and chroma shaped for `slot`, keyed to `target`
    luma. Pure — one base always gives one rung."""
    if _AMBIENT_MIX[slot] == 0.0 and _HUE_PULL[slot] == 0.0 and _SAT_SCALE[slot] == 1.0:
        return _at_luminance(base, target)
    hue, saturation, _ = colorsys.rgb_to_hsv(*(c / 255.0 for c in base))
    chroma = _full_chroma(
        _rotate(hue * 360.0, _HUE_PULL[slot]), min(1.0, saturation * _SAT_SCALE[slot])
    )
    if _AMBIENT_MIX[slot] > 0.0:
        chroma = mix(
            chroma, _at_luminance(AMBIENT, luminance(chroma)), _AMBIENT_MIX[slot]
        )
    return _at_luminance(chroma, target)


def build_ramp(base: RGB, ladder: tuple[float, ...]) -> Ramp6:
    """The six-slot ramp for one base colour and one authored value ladder."""
    return tuple(_shape(base, slot, target) for slot, target in enumerate(ladder))


# The board's authored ramps, anchor and ladder both.
_MERIDIAN_L = (23.0, 56.0, 86.0, 114.9, 148.0, 208.0)
_AURORA_L = (21.0, 50.0, 74.0, 101.3, 136.0, 205.0)
_VERDANT_L = (25.0, 56.0, 76.0, 98.0, 140.0, 214.0)
_GOLD_L = (20.0, 46.0, 70.0, 104.0, 136.0, 200.0)
_IRON_L = (7.0, 31.0, 49.0, 129.0, 151.0, 229.0)
_NEUTRAL_L = (20.0, 60.0, 102.0, 137.0, 156.0, 219.0)

RAMPS: dict[str, Ramp6] = {
    "meridian": build_ramp(_hex("db4a3b"), _MERIDIAN_L),
    "aurora": build_ramp(_hex("3c64d8"), _AURORA_L),
    "verdant": build_ramp(_hex("2c8636"), _VERDANT_L),
    "gold": build_ramp(_hex("e9c928"), _GOLD_L),
    "iron": build_ramp(_hex("79838d"), _IRON_L),
    "neutral": build_ramp(_hex("a4874f"), _NEUTRAL_L),
}

# The metal every general's prop, buckle and pip is made of — the board's own
# gunmetal, so a sabre on a bust is the steel a tank is plated in.
GUNMETAL_RAMP: Ramp6 = build_ramp(
    _hex("7a848f"), (22.0, 63.0, 97.0, 130.0, 175.0, 216.0)
)


def faction_ramp(key: str) -> Ramp6:
    """The six rungs an army is painted in. An unknown key raises."""
    if key not in RAMPS:
        raise KeyError(f"no ramp for {key!r} (have {sorted(RAMPS)})")
    return RAMPS[key]


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
_SKIN_SLOTS = (S_UNDER, S_SHADOW, S_BODY, S_TOP)
_HAIR_SLOTS = (S_SHADOW, S_BODY, S_TOP)
_METAL_SLOTS = (S_BODY, S_TOP)

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
        *(skin[slot] for slot in _SKIN_SLOTS),
        *(hair[slot] for slot in _HAIR_SLOTS),
        *(GUNMETAL_RAMP[slot] for slot in _METAL_SLOTS),
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
