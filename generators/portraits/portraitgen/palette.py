"""Colours: the game's faction themes, the ink weights' one ink, and 4-band ramps.

The faction themes mirror grid_commanders' `CommanderVisuals.FactionTheme` so the
portraits this tool bakes and the UI chrome that frames them can never disagree
about which colour a faction is; `tests/test_palette_mirror.py` reads the values
back out of the game's own code. Row order mirrors `SideIdentity._ROW_FOR_KEY`:
0 neutral, 1 meridian, 2 aurora, 3 iron, 4 verdant.

Colours are kept as the authored 0-1 floats and converted to bytes in one place
(`rgb8`), which **truncates** — that is what Godot's `Color` to `FORMAT_RGBA8`
conversion does, and the committed emblems carry those exact bytes.
"""

from __future__ import annotations

from dataclasses import dataclass

RGB = tuple[int, int, int]
RGBA = tuple[int, int, int, int]
Float3 = tuple[float, float, float]

# Every border and body glyph in the design system, and the outline weight the
# emblems are drawn with: tools/generate_portraits.gd's OUTLINE, as bytes.
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
)

# The seat nobody holds wears no emblem: assets/portraits/factions holds four
# files, one per army.
EMBLEM_KEYS: tuple[str, ...] = ("aurora", "iron", "meridian", "verdant")


def faction_by_key(key: str) -> Faction:
    for faction in FACTIONS:
        if faction.key == key:
            return faction
    raise KeyError(f"no faction {key!r} (have {[f.key for f in FACTIONS]})")
