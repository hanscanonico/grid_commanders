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
    key: str  # atlas row key (side_identity.gd)
    team: str  # per-unit PNG suffix (paste_unit_sprites.gd TEAM_ROWS)
    body: RGB  # FactionTheme.color
    body_dk: RGB  # FactionTheme.color_dark
    body_lt: RGB  # FactionTheme.color_light


# Atlas row order. Every row is the exact FactionTheme from the game's
# commander_visuals.gd (color / color_dark / color_light, x255), neutral
# included — the sprites and the UI chrome can never disagree about a
# faction's color.
FACTIONS: tuple[Faction, ...] = (
    Faction("neutral", "neutral", (96, 106, 113), (60, 68, 74), (130, 140, 146)),
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
    "stone": (158, 154, 146),
    "stone_dk": (122, 118, 111),
}

# Materials whose big top surfaces get a whisper of per-pixel dither texture.
DITHERED = {
    "body",
    "body_dk",
    "body_lt",
    "hull",
    "hull_dk",
    "hull_lt",
    "deck",
    "leaf",
    "concrete",
    "asphalt",
    "stone",
}
# Materials rendered glossy: hot specular top, brighter left face.
GLOSSY = {"glass", "glass_dk"}

# The hull ramp: faction hue pulled toward a neutral chassis grey, so armour
# reads as military hardware wearing team livery rather than a toy dipped in
# paint. Models keep pure `body` for the identity accents (turret tops, wings,
# cabs, decks) that must still shout the owner at map scale. The pull is 20%:
# at the original 50% a red hull averaged down to brick over terrain and the
# faction read died at board zoom (sprite review, 2026-08-13) — 20% keeps the
# livery-vs-accent split while the hull still carries the flag.
_CHASSIS: RGB = (112, 115, 106)
_CHASSIS_DK: RGB = (80, 83, 76)
_CHASSIS_LT: RGB = (146, 150, 139)
_HULL_PULL = 0.20

# Iron's scheme is inverted: its theme hue sits a step off the chassis grey,
# so a tinted hull makes an iron army indistinguishable from the neutral row
# and from any faction's acted grey-out — three meanings, one appearance.
# Iron therefore fields light-steel hulls and keeps its dark slate on the
# identity accents: the dark-faction read comes from value structure, not hue.
_IRON_HULL: RGB = (178, 184, 192)
_IRON_HULL_DK: RGB = (142, 149, 158)
_IRON_HULL_LT: RGB = (206, 212, 219)


def resolve(material: str, faction: Faction) -> RGB:
    """A model's material name -> concrete RGB for one faction row."""
    if material == "body":
        return faction.body
    if material == "body_dk":
        return faction.body_dk
    if material == "body_lt":
        return faction.body_lt
    if material == "hull":
        return (
            _IRON_HULL
            if faction.key == "iron"
            else mix(faction.body, _CHASSIS, _HULL_PULL)
        )
    if material == "hull_dk":
        return (
            _IRON_HULL_DK
            if faction.key == "iron"
            else mix(faction.body_dk, _CHASSIS_DK, _HULL_PULL)
        )
    if material == "hull_lt":
        return (
            _IRON_HULL_LT
            if faction.key == "iron"
            else mix(faction.body_lt, _CHASSIS_LT, _HULL_PULL)
        )
    return MATERIALS[material]


def clamp8(v: float) -> int:
    return max(0, min(255, round(v)))


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
# the whole sheet leans on for its slightly stylised light. The mix is kept
# mild: at 0.24 it drained the faction hue out of every right face and the
# armies went grey at board zoom (sprite review, 2026-08-13).
_SHADOW_TINT: RGB = (34, 48, 84)
_SHADOW_MIX = 0.16


def shade(c: RGB, face: str, gloss: bool = False) -> RGB:
    """The three dimetric face tones. Light comes from the top-left.

    The left (+y) face is the pure material color, as in the pack art —
    it is the face the player mostly reads, so it must stay vivid. The top
    face is always the lightest plane, and its lift is multiplicative with
    only a whisper of white: a plain white mix drained the saturation out of
    every sunlit face, and flat-decked vehicles are mostly sunlit face, so
    whole armies rendered grey-topped (sprite review, 2026-08-13). Scaling
    brightens while preserving chroma; the white mix is just the sheen.
    """
    if face == "top":
        k, w = (1.45, 0.20) if gloss else (1.30, 0.10)
        return mix(tuple(clamp8(v * k) for v in c), (255, 255, 255), w)
    if face == "left":
        return lighten(c, 0.18) if gloss else c
    # right face: darkest, cold-shifted
    return mix(darken(c, 0.40), _SHADOW_TINT, _SHADOW_MIX)


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
