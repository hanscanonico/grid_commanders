"""Colors: faction ramps, fixed materials, shading math, deterministic noise.

Faction colors mirror grid_commanders' CommanderVisuals.FactionTheme so the
sprites this tool bakes and the UI chrome the game draws can never disagree
about which color a faction is. Row order mirrors SideIdentity._ROW_FOR_KEY:
0 neutral, 1 meridian(red), 2 aurora(blue), 3 iron, 4 verdant.
"""

from __future__ import annotations

import colorsys
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

# Cyan glass is Aurora's alone (sprite review round 3): an untinted cyan
# canopy on every row was the largest accent on some sprites and competed
# with the faction read — a verdant copter was a green-and-blue unit. Every
# other faction's canopies and bridge glass go warm grey-white.
_CANOPY: RGB = (215, 211, 200)
_CANOPY_DK: RGB = (174, 170, 158)


def resolve(material: str, faction: Faction) -> RGB:
    """A model's material name -> concrete RGB for one faction row.

    Terrain and buildings paint with this directly. Units go through the
    indexed ramps at the bottom of this file, so a unit material resolves
    only when it is a fixed accent whose ramp is derived from its colour.
    """
    if material == "body":
        return faction.body
    if material == "body_dk":
        return faction.body_dk
    if material == "body_lt":
        return faction.body_lt
    if material == "glass":
        return MATERIALS["glass"] if faction.key == "aurora" else _CANOPY
    if material == "glass_dk":
        return MATERIALS["glass_dk"] if faction.key == "aurora" else _CANOPY_DK
    return MATERIALS[material]


def clamp8(v: float) -> int:
    return max(0, min(255, round(v)))


def luminance(c: RGB) -> float:
    return 0.299 * c[0] + 0.587 * c[1] + 0.114 * c[2]


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


# ---------------------------------------------------------------------------
# indexed ramps — the unit palette
# ---------------------------------------------------------------------------
#
# Units are painted out of fixed six-step ramps instead of out of shading
# arithmetic (sprite fix spec round 4, sections 2-3). A slot is a lighting
# BAND, not a brightness: S0 contour, S1 under, S2 shadow, S3 body, S4 top,
# S5 rim. `shade` above computes a colour per pixel and so spends a thousand
# palette entries per atlas row on one physical surface; a slot index spends
# one, which is what makes the tint a swap rather than a blend.
#
# S3 is the design-system token itself, so a faction reads at its brand
# luminance rather than at half of it.

SLOTS = 6
S_CONTOUR, S_UNDER, S_SHADOW, S_BODY, S_TOP, S_RIM = range(SLOTS)

Ramp = tuple[RGB, ...]

# Per-pixel material ids emitted beside the colour. Tinting is a lookup on
# FACTION alone; every other id is faction-independent by construction. The
# spec's fifth id, shadow, has no entry here because a shadow is composed
# under the sprite at cell level and never lands in a sprite's map.
MID_CONTOUR = 0
MID_FACTION = 1
MID_GUNMETAL = 2
MID_ACCENT = 3
MID_EMPTY = 255


def _hex(h: str) -> RGB:
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16))


# --- ramp shaping ----------------------------------------------------------
#
# A ramp is BUILT, not typed out: a value ladder authored per faction, and
# one shared chroma shape applied to every rung of it. A ramp written as six
# literal colours drifts toward a value-only ramp — the same hue at six
# brightnesses — which is the flattest thing a six-colour ramp can be. What
# separates a lit plane from a shadowed one in the reference art is not only
# how bright it is but WHICH LIGHT it is: sun on the top faces, sky in the
# shadows. So each rung gets three treatments beyond its brightness.
#
# 1. Saturation peaks in the middle and collapses at the top. A rim step is
#    the sun itself and reads as near-white; a fully saturated rim looks like
#    paint rather than light. The dark end keeps slightly MORE chroma than
#    the light end, because a shadow is lit by a coloured sky while a
#    highlight is washed out by a white sun.
# 2. The shadow steps are mixed toward AMBIENT, a single cool sky. This is
#    the difference between a shadow and an absence of light: unlit faces
#    tinted toward one shared colour read as one scene, and black shadows
#    read as holes.
# 3. Hue rotates a little across the ramp — toward the sky in the dark steps,
#    toward the sun in the light ones. The magnitude is empirical and small:
#    _HUE_ARC is a ceiling on the rotation, not a per-step rule, and rungs
#    take a fraction of it. Big rotations turn a red faction's shadow purple
#    and stop reading as the same army.

# The sky every shadow on the sheet is lit by. One constant, so the five
# armies and the props share a light rather than each carrying their own.
AMBIENT: RGB = (86, 112, 190)
# Hue of that sky, and of the sun the lit steps drift toward.
_SKY_HUE = 225.0
_SUN_HUE = 45.0
# The widest a rung may rotate off its base hue.
_HUE_ARC = 14.0
# Per slot, S0..S5: how far the rung rotates (negative = toward the sky),
# how its chroma scales, and how much AMBIENT is blended into it. S3 is all
# zeros/ones by construction — it IS the faction token and may not move.
_HUE_PULL = (-1.00, -0.72, -0.34, 0.0, 0.46, 1.00)
_SAT_SCALE = (1.10, 1.22, 1.24, 1.0, 0.82, 0.42)
_AMBIENT_MIX = (0.26, 0.16, 0.07, 0.0, 0.0, 0.0)


def _rgb_to_hsv(c: RGB) -> tuple[float, float, float]:
    return colorsys.rgb_to_hsv(c[0] / 255.0, c[1] / 255.0, c[2] / 255.0)


def _full_chroma(h_deg: float, sat: float) -> RGB:
    r, g, b = colorsys.hsv_to_rgb((h_deg % 360.0) / 360.0, sat, 1.0)
    return (clamp8(r * 255), clamp8(g * 255), clamp8(b * 255))


def _rotate(h_deg: float, pull: float) -> float:
    """Rotate a hue toward the sky (pull<0) or the sun (pull>0), capped."""
    if pull == 0.0:
        return h_deg
    target = _SKY_HUE if pull < 0 else _SUN_HUE
    delta = ((target - h_deg + 180.0) % 360.0) - 180.0
    step = min(abs(delta), abs(pull) * _HUE_ARC)
    return h_deg + (step if delta >= 0 else -step)


def _at_luminance(c: RGB, target: float) -> RGB:
    """Re-key a colour to an exact luminance, keeping chroma as long as it
    can: scale first, and only wash toward white once a channel is pinned."""
    lum = luminance(c)
    if lum <= 0.0:
        return (clamp8(target), clamp8(target), clamp8(target))
    ceiling = lum * 255.0 / max(c)  # the brightest this hue gets by scaling
    if target <= ceiling:
        return (
            clamp8(c[0] * target / lum),
            clamp8(c[1] * target / lum),
            clamp8(c[2] * target / lum),
        )
    pinned = mix((0, 0, 0), c, 255.0 / max(c))
    return mix(pinned, (255, 255, 255), (target - ceiling) / (255.0 - ceiling))


def _shape(base: RGB, slot: int, target: float) -> RGB:
    """One rung: the base colour's hue and chroma, shaped for `slot`, keyed
    to `target` luminance. Pure — the same base always gives the same rung."""
    if _AMBIENT_MIX[slot] == 0.0 and _HUE_PULL[slot] == 0.0 and _SAT_SCALE[slot] == 1.0:
        return _at_luminance(base, target)
    h, s, _ = _rgb_to_hsv(base)
    chroma = _full_chroma(
        _rotate(h * 360.0, _HUE_PULL[slot]), min(1.0, s * _SAT_SCALE[slot])
    )
    if _AMBIENT_MIX[slot] > 0.0:
        chroma = mix(
            chroma, _at_luminance(AMBIENT, luminance(chroma)), _AMBIENT_MIX[slot]
        )
    return _at_luminance(chroma, target)


def build_ramp(base: RGB, ladder: tuple[float, ...]) -> Ramp:
    """The six-slot ramp for one base colour and one authored value ladder."""
    return tuple(_shape(base, i, target) for i, target in enumerate(ladder))


# The authored ramps: an anchor colour and a value ladder (Rec. 601 luminance
# per slot). The chroma comes out of `build_ramp` above, which is why these
# carry no hues but S3's own.
#
# The chromatic three anchor on the game's FactionTheme colour at its own
# luminance, so S3 IS the token, bit for bit.
_MERIDIAN_L = (23.0, 56.0, 86.0, 114.9, 148.0, 208.0)
_AURORA_L = (21.0, 50.0, 74.0, 101.3, 136.0, 205.0)
_VERDANT_L = (25.0, 56.0, 76.0, 98.0, 140.0, 214.0)
# Iron keeps its inverted identity — near-black panels jumping to light
# steel, a value structure no chromatic faction has — but its ceiling is
# pulled in (see IRON_SLOT_CEILING) so it sits with them instead of above.
# Its own token is at the value floor, so it is the shadow plane, and the
# ramp anchors on the light steel its lit planes are made of instead.
# S4 sat at L176 while every chromatic S4 sits at L134-147, and the
# round-5 rim pass then lifted a rimmed shadow plane INTO that slot on
# every model — which is how Iron came back as the brightest row (17.3%
# of its pixels above L160 against 14.0-14.9%, round-6 review). It comes
# down to L151, under the band, and Iron's flash stays the S5 rim.
_IRON_L = (7.0, 31.0, 49.0, 129.0, 151.0, 229.0)
# Warm khaki: neutral separates from Iron's cool steel by hue rather than
# by value, so it stops competing with the exhausted state. The round-5
# verdict measured that hue paid for at the top of the ramp — 27% of
# neutral pixels above L160, 4,280 of them the S4 top plane alone, which
# made the row nobody owns the brightest row on the board. S4 comes down
# to L156 and the hue is carried further into the sand instead, which is
# what keeps the row a wide margin off Iron with less light in it.
_NEUTRAL_L = (20.0, 60.0, 102.0, 137.0, 156.0, 219.0)

RAMPS: dict[str, Ramp] = {
    "meridian": build_ramp(_hex("db4a3b"), _MERIDIAN_L),
    "aurora": build_ramp(_hex("3c64d8"), _AURORA_L),
    "verdant": build_ramp(_hex("2c8636"), _VERDANT_L),
    "iron": build_ramp(_hex("79838d"), _IRON_L),
    "neutral": build_ramp(_hex("a4874f"), _NEUTRAL_L),
}

# Shared by every faction, and shaped by the same rules — a gunmetal that is
# six greys is the flat ramp this file exists to stop being. Its body slot
# sits at L130 so an identifying feature — a barrel, a mount, a rotor mast —
# reads on a dark hull instead of only on Iron's light one.
GUNMETAL_RAMP: Ramp = build_ramp(
    _hex("7a848f"), (22.0, 63.0, 97.0, 130.0, 175.0, 216.0)
)

# Iron's ceiling. Shipped Iron put 27-51% of its pixels above L160 and used
# pure white, so it stopped being dark and started out-reading all three
# chromatic factions. Its top plane therefore stops at the body slot and only
# the rim steps above it: the near-black-to-light-steel jump survives — it is
# what Iron IS — while the bright band above L160 stays the chromatic
# factions' to own.
IRON_SLOT_CEILING = S_BODY


@dataclass(frozen=True)
class MaterialSlot:
    """Where a model's material name sits in the indexed palette."""

    ramp: str  # "faction", "gunmetal", or "" = derived from resolve()
    slot: int
    mid: int


_FACTION_SLOT = "faction"
_GUNMETAL_SLOT = "gunmetal"


def _fac(slot: int) -> MaterialSlot:
    return MaterialSlot(_FACTION_SLOT, slot, MID_FACTION)


def _gun(slot: int) -> MaterialSlot:
    return MaterialSlot(_GUNMETAL_SLOT, slot, MID_GUNMETAL)


def _accent(slot: int) -> MaterialSlot:
    return MaterialSlot("", slot, MID_ACCENT)


# The livery convention, restated as slots: the chassis mass wears the body
# slot, the identity accents the two above it. `hull` is no longer a blend
# toward chassis grey — the ramp already carries the value structure the
# blend was faking, and the blend is what halved the brand luminance.
UNIT_MATERIALS: dict[str, MaterialSlot] = {
    "hull": _fac(S_BODY),
    "hull_dk": _fac(S_SHADOW),
    # One band under the shadow plane: the awash hull of a boat that has to
    # read as the darkest thing afloat (see units.sub). Still a faction slot,
    # so a dark hull is a faction-dark hull.
    "hull_under": _fac(S_UNDER),
    "hull_lt": _fac(S_TOP),
    "body": _fac(S_TOP),
    "body_dk": _fac(S_BODY),
    "body_lt": _fac(S_RIM),
    "gunmetal": _gun(S_BODY),
    "gunmetal_dk": _gun(S_SHADOW),
    "steel": _gun(S_TOP),
    "hub": _gun(S_BODY),
    "deck": _gun(S_BODY),
    "deck_dk": _gun(S_SHADOW),
    "track": _gun(S_UNDER),
    "track_lt": _gun(S_SHADOW),
    "tire": _gun(S_UNDER),
    "rotor": _gun(S_UNDER),
    "bore": _gun(S_CONTOUR),
}


def material_slot(material: str) -> MaterialSlot:
    """Slot for a model's material name; anything unlisted is a fixed accent."""
    return UNIT_MATERIALS.get(material, _accent(S_BODY))


# The value ladder a fixed accent's ramp is built on, as fractions of the
# accent's own luminance and, for the two lit steps, of the room above it.
# S3 is the accent itself; S0 lands at ~18% of it and S5 is a pale rim.
_ACCENT_DARK = (0.18, 0.45, 0.72)
_ACCENT_TOP = 1.22
_ACCENT_RIM = 0.62


def _derived_ramp(base: RGB) -> Ramp:
    """A six-step ramp around a fixed accent colour, shaped by the same rules
    as the authored faction ones — chroma peaking mid-ramp, a sky in the
    shadow steps — over the accent's own value ladder."""
    lum = luminance(base)
    top = mix(tuple(clamp8(v * _ACCENT_TOP) for v in base), (255, 255, 255), 0.10)
    ladder = (
        *(lum * f for f in _ACCENT_DARK),
        lum,
        luminance(top),
        lum + (255.0 - lum) * _ACCENT_RIM,
    )
    return build_ramp(base, ladder)


_DERIVED: dict[RGB, Ramp] = {}


def ramp_for(material: str, faction: Faction) -> Ramp:
    """The ramp a material is painted out of, for one faction row."""
    spec = material_slot(material)
    if spec.ramp == _FACTION_SLOT:
        return RAMPS[faction.key]
    if spec.ramp == _GUNMETAL_SLOT:
        return GUNMETAL_RAMP
    base = resolve(material, faction)
    ramp = _DERIVED.get(base)
    if ramp is None:
        ramp = _derived_ramp(base)
        _DERIVED[base] = ramp
    return ramp
