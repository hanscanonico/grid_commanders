"""Colors: faction ramps, fixed materials, shading math, deterministic noise.

Faction colors mirror grid_commanders' CommanderVisuals.FactionTheme so the
sprites this tool bakes and the UI chrome the game draws can never disagree
about which color a faction is. Row order mirrors SideIdentity._ROW_FOR_KEY:
0 neutral, 1 meridian(red), 2 aurora(blue), 3 iron, 4 verdant.
"""

from __future__ import annotations

from dataclasses import dataclass

RGB = tuple[int, int, int]


@dataclass(frozen=True)
class Faction:
    key: str          # atlas row key (side_identity.gd)
    team: str         # per-unit PNG suffix (paste_unit_sprites.gd TEAM_ROWS)
    body: RGB         # FactionTheme.color
    body_dk: RGB      # FactionTheme.color_dark
    body_lt: RGB      # FactionTheme.color_light


# Atlas row order. Unit art keeps the pack's convention of a white/grey neutral
# row (a neutral unit must not read as a team), not the UI's neutral slate.
FACTIONS: tuple[Faction, ...] = (
    Faction("neutral", "neutral", (214, 217, 222), (158, 163, 172), (240, 242, 245)),
    Faction("meridian", "red", (219, 74, 59), (169, 54, 49), (239, 114, 95)),
    Faction("aurora", "blue", (56, 101, 216), (43, 78, 168), (109, 140, 232)),
    Faction("iron", "iron", (74, 82, 88), (47, 54, 59), (107, 116, 123)),
    Faction("verdant", "verdant", (44, 134, 54), (29, 97, 39), (79, 168, 90)),
)

# Fixed (faction-independent) materials. Names are what models paint with.
MATERIALS: dict[str, RGB] = {
    "gunmetal": (104, 112, 124),
    "gunmetal_dk": (76, 82, 93),
    "steel": (176, 183, 193),
    "track": (61, 64, 72),
    "track_lt": (92, 96, 106),
    "tire": (50, 52, 60),
    "hub": (120, 124, 132),
    "glass": (110, 205, 228),
    "glass_dk": (58, 148, 186),
    "skin": (226, 178, 134),
    "hair": (92, 68, 50),
    "wood": (128, 92, 66),
    "rotor": (52, 54, 60),
    "bore": (28, 30, 34),
    "amber": (235, 179, 63),
    "white": (240, 242, 245),
    "deck": (139, 145, 155),
    "deck_dk": (112, 118, 128),
    "concrete": (176, 174, 166),
    "concrete_dk": (140, 138, 130),
    "asphalt": (111, 116, 124),
    "leaf": (52, 128, 58),
    "leaf_dk": (33, 96, 42),
    "leaf_lt": (94, 165, 76),
    "trunk": (109, 76, 65),
    "rock": (145, 142, 138),
    "rock_dk": (108, 106, 104),
    "snow": (238, 240, 244),
    "flame": (238, 120, 46),
}

# Materials whose big top surfaces get a whisper of per-pixel dither texture.
DITHERED = {"body", "body_dk", "body_lt", "deck", "leaf", "concrete", "asphalt"}
# Materials rendered glossy: hot specular top, brighter left face.
GLOSSY = {"glass", "glass_dk"}


def resolve(material: str, faction: Faction) -> RGB:
    """A model's material name -> concrete RGB for one faction row."""
    if material == "body":
        return faction.body
    if material == "body_dk":
        return faction.body_dk
    if material == "body_lt":
        return faction.body_lt
    return MATERIALS[material]


def clamp8(v: float) -> int:
    return max(0, min(255, int(round(v))))


def mix(a: RGB, b: RGB, t: float) -> RGB:
    return (
        clamp8(a[0] + (b[0] - a[0]) * t),
        clamp8(a[1] + (b[1] - a[1]) * t),
        clamp8(a[2] + (b[2] - a[2]) * t),
    )


def lighten(c: RGB, t: float) -> RGB:
    return mix(c, (255, 255, 255), t)


def darken(c: RGB, t: float) -> RGB:
    return mix(c, (0, 0, 0), t)


# Shadows drift toward a cold blue rather than plain black — the one hue trick
# the whole sheet leans on for its slightly stylised light.
_SHADOW_TINT: RGB = (34, 48, 84)


def shade(c: RGB, face: str, gloss: bool = False) -> RGB:
    """The three dimetric face tones. Light comes from the top-left.

    The left (+y) face is the pure material color, as in the pack art —
    it is the face the player mostly reads, so it must stay vivid.
    """
    if face == "top":
        return lighten(c, 0.55 if gloss else 0.26)
    if face == "left":
        return lighten(c, 0.18) if gloss else c
    # right face: darkest, cold-shifted
    return mix(darken(c, 0.30), _SHADOW_TINT, 0.20)


def h01(x: int, y: int, salt: int = 0) -> float:
    """Deterministic hash noise in [0,1) — stable across runs and platforms."""
    v = (x * 374761393 + y * 668265263 + salt * 2246822519) & 0xFFFFFFFF
    v = ((v ^ (v >> 13)) * 1274126177) & 0xFFFFFFFF
    return ((v ^ (v >> 16)) & 0xFFFF) / 65536.0


def faction_by_key(key: str) -> Faction:
    for f in FACTIONS:
        if f.key == key or f.team == key:
            return f
    raise KeyError(key)
