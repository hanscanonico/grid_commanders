"""Colors: faction ramps, fixed materials, shading math, deterministic noise.

Faction colors mirror grid_commanders' CommanderVisuals.FactionTheme so the
sprites this tool bakes and the UI chrome the game draws can never disagree
about which color a faction is. Row order mirrors SideIdentity._ROW_FOR_KEY:
0 neutral, 1 meridian(red), 2 aurora(blue), 3 iron, 4 verdant, 5 gold.
"""

from __future__ import annotations

import colorsys
from dataclasses import dataclass

RGB = tuple[int, int, int]


# Which grade of outline a row wears on the two sides the sun is on. The
# selective outline lights those sides instead of darkening them, and that
# trade is only paid for where the lit line reads against the ground: a row
# whose lit planes sit in the ground's own value band, and whose colour the
# ground shares, has nothing left to break with — see GROUND_BAND below and
# docs/outlines.md for the measurement.
#
# LIGHT keeps the lit line wherever it falls: the row's body is a design-system
# token, so a line tying with the grass or the sand in VALUE still breaks with
# it in COLOUR. HEAVY is the answer for the two rows with no colour to spend
# (neutral is the sand's own khaki, Iron is achromatic): the lit line gives way
# to the ground-facing contour where it cannot clear the ground's band. RIM is
# the answer for a row whose colour the ground SHARES — the one case where
# neither half of the argument holds — and it spends the rim rather than the
# contour: a green army on grass has no value left below, and the band above
# the terrain ceiling is the units' by contract (`GROUND_HUES`).
OUTLINE_LIGHT, OUTLINE_HEAVY, OUTLINE_RIM = 0, 1, 2


@dataclass(frozen=True)
class Faction:
    key: str  # atlas row key (side_identity.gd)
    team: str  # per-unit PNG suffix (out/units/<id>_<team>.png)
    body: RGB  # FactionTheme.color
    body_dk: RGB  # FactionTheme.color_dark
    body_lt: RGB  # FactionTheme.color_light
    outline: int = OUTLINE_LIGHT  # OUTLINE_LIGHT / OUTLINE_HEAVY


# Atlas row order. Every row is the exact FactionTheme from the game's
# commander_visuals.gd (color / color_dark / color_light, x255), neutral
# included — the sprites and the UI chrome can never disagree about a
# faction's color.
#
# Meridian wears the light grade: its body is a design-system token no ground
# shares, so a lit line that ties with the grass or the sand in VALUE still
# breaks with it in colour. Neutral is the sand's own khaki and Iron is
# achromatic and capped at S3 — the middle of the ground's band — so those two
# rows have only value to break with, and take the heavy grade. Aurora and
# verdant are the two rows whose own hue is a ground's: blue over the water a
# shoal is half made of, green over the grass, measured at 6.5% and 10.3% of
# their boundary tying in value AND colour. They take the rim grade.
#
# Gold is the fifth row and the third to wear the light grade: its body sits
# at hue 50 degrees, chromatic and outside GROUND_HUES, so it has colour to
# break with the grass and the sand alike. That hue is measured rather than
# chosen: neutral's khaki is hue 39 and the sun the rim turns toward is 45, so
# a warmer gold either collapses into the row nobody owns (`RowSeparation`) or
# leaves its rim nothing to turn to.
FACTIONS: tuple[Faction, ...] = (
    Faction(
        "neutral",
        "neutral",
        (96, 106, 113),
        (60, 68, 74),
        (130, 140, 146),
        OUTLINE_HEAVY,
    ),
    Faction("meridian", "red", (219, 74, 59), (169, 54, 49), (239, 114, 95)),
    Faction(
        "aurora", "blue", (56, 101, 216), (43, 78, 168), (109, 140, 232), OUTLINE_RIM
    ),
    Faction("iron", "iron", (74, 82, 88), (47, 54, 59), (107, 116, 123), OUTLINE_HEAVY),
    Faction(
        "verdant", "verdant", (44, 134, 54), (29, 97, 39), (79, 168, 90), OUTLINE_RIM
    ),
    Faction("gold", "gold", (233, 201, 40), (177, 153, 30), (243, 220, 102)),
)

# The value band the ground a unit stands on occupies, on THIS module's
# Rec. 601 scale (`terrain.py` states its own ceilings on Rec. 709, and the
# two do not agree on green). The two grounds an army spends its game on are
# plains and shoal, and their four authored tones span it: GRASS_DARK L118
# and GRASS L147, SAND_DARK L139 and SAND L165. `terrain.py` cannot be
# imported here — it imports this module — so the band is stated here and
# pinned against the tones themselves by `GroundContrast`.
GROUND_BAND = (118.0, 166.0)
# Under 25L of separation, the 2026-08-21 sheet review read a boundary pixel
# and the tile under it as one surface. A lit line therefore clears the ground
# only below L93 or above L191.
GROUND_BREAK = 25.0


def clears_the_ground(lum: float) -> bool:
    """Does a value read as a break against the ground under it?"""
    lo, hi = GROUND_BAND
    return lum < lo - GROUND_BREAK or lum > hi + GROUND_BREAK


# The two grounds that have a HUE — the grass of the plains and the open water
# a shoal is half made of. Sand is the third and is not listed: it is the
# khaki neutral already answers with the heavy grade, and no chromatic row
# sits inside it (meridian's body is 40 degrees off it). Stated here for the
# same reason GROUND_BAND is, and pinned against the tones by `GroundContrast`.
GROUND_HUES = (106.0, 210.0)
# Inside this arc a colour and a ground are the same colour, so the colour
# half of the light grade's argument — a token hue no ground shares — is not
# available. Verdant's body sits 21 degrees off the grass and aurora's 15 off
# the water; meridian's is 40 off the sand, and stays a light row.
GROUND_HUE_ARC = 30.0
# Under this much saturation a colour has no hue to tie with: gunmetal, steel
# and the greys read as value alone whatever the tile beneath them is.
GROUND_HUE_CHROMA = 0.20


def shares_a_ground_hue(c: RGB) -> bool:
    """Is this colour the same COLOUR as a ground, and not only its value?"""
    h, s, _ = colorsys.rgb_to_hsv(c[0] / 255.0, c[1] / 255.0, c[2] / 255.0)
    if s < GROUND_HUE_CHROMA:
        return False
    deg = h * 360.0
    return any(
        abs(((deg - hue + 180.0) % 360.0) - 180.0) <= GROUND_HUE_ARC
        for hue in GROUND_HUES
    )


# Fixed (faction-independent) materials. Names are what models paint with.
#
# The five greys — rock, stone, concrete and their shades, plus asphalt — are
# the one family here with a TEMPERATURE, added 2026-08-22 with the terrain
# palette pass. They were S0.04-0.10 neutrals, the same hue lit and shaded,
# which is the colour of cut card and not of stone: a lit face takes the warmth
# of the sun (S0.14, hue 34-47) and a shaded one is lit by AMBIENT alone, so it
# takes the sky's own hue at the same chroma (S0.11-0.15, hue 225). Asphalt is
# already a shaded material and goes cool outright. Every value is unchanged to
# a tenth of a luma — these are `terrain._tone`/`terrain._shade` evaluated on
# the tone that was there, tabulated in docs/terrain_tones.md, and typed out
# here because `palette` cannot import `terrain`.
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
    "concrete": (178, 174, 160),
    "concrete_dk": (134, 138, 150),
    "asphalt": (110, 115, 131),
    "leaf": (52, 128, 58),
    "leaf_dk": (33, 96, 42),
    "leaf_lt": (94, 165, 76),
    "trunk": (109, 76, 65),
    "rock": (150, 141, 129),
    "rock_dk": (102, 106, 120),
    "snow": (238, 240, 244),
    "flame": (238, 120, 46),
    "stone": (161, 154, 139),
    "stone_dk": (114, 118, 133),
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

# The sky every shadow on the sheet is lit by. One constant, so the six
# rows and the props share a light rather than each carrying their own.
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
# Gold is the third row authored off-token, and for Iron's reason rather than
# neutral's: its token is a LIT plane. At L190 it keys 75L over the other
# three chromatic bodies, and a row anchored there puts its own S4 over the
# terrain ceiling on every roof it owns. So the ramp carries the token's hue
# on a ladder of the row's own, one step under the other three: the board
# reads gold off the hue and the rim, and the chrome wears the token whole.
_GOLD_L = (20.0, 46.0, 70.0, 104.0, 136.0, 200.0)
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
    "gold": build_ramp(_hex("e9c928"), _GOLD_L),
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


# ---------------------------------------------------------------------------
# the property palette — masonry, concrete, machinery
# ---------------------------------------------------------------------------
#
# Buildings are drawn out of ramps for the same reason units are: the shading
# arithmetic spends a colour per lit pixel, which is how one airport reached
# 74 colours against a unit's 11-16. These three families are built by the
# same `build_ramp` shaper as the faction ramps, so a wall's shadow steps sit
# in the same AMBIENT sky an army's do and the board reads as one scene.
#
# The ladders are authored where the old material greys already put a
# building — the mass lit at L116, the trim a rung above it at L142 — so
# nothing here walks back into the value band `terrain.TERRAIN_VALUE_CEILING`
# reserves for units. What the ramp adds is the STRUCTURE the greys only
# approximated: four rungs of ONE family where there were four unrelated
# materials, and a contour step that belongs to the wall rather than a flat
# 0.55 dip taken off whatever colour happened to be there.
#
# Masonry is warm and concrete is cool at nearly the same values: a lot and
# the building standing on it separate by HUE, so neither has to spend the
# value the units are keyed against. Both dark rungs are rotated into the
# same AMBIENT sky `terrain._shade` puts a ground's shadow in.
#
# The temperature is what the board reads a property by, so it is authored
# far wider than the round-8 pair was (2026-08-23, the faction-read pass).
# Those two were H37/S0.13 and H210/S0.09 — a warm card and a cool card,
# 12 RGB apart at the contour rung — and the row nobody owns is built out of
# concrete end to end while every owned one is built out of masonry, so that
# gap IS the unowned-vs-owned read at the board's 4:1 rung. Sandstone against
# slate holds the same six values 29-66 apart instead, which is what lets
# Iron — the one faction whose own colour is a grey — stand on a warm plate
# and still be told from the neutral row's cool one. The masonry ladder also
# comes up off the near-black its contour rung sat at (24 to 38): a property
# was the darkest, least saturated family on the sheet, and a wall's own
# shadow step is where that was spent.
MASONRY_RAMP: Ramp = build_ramp(_hex("a68d5e"), (38.0, 70.0, 96.0, 116.0, 142.0, 168.0))
CONCRETE_RAMP: Ramp = build_ramp(
    _hex("74889e"), (22.0, 50.0, 78.0, 104.0, 130.0, 156.0)
)
# Machinery — a crane, a mast, a chimney cap, a door seam — sits a full band
# over the masonry: metal catches this light where stone does not, and it is
# the one thing on a building that may.
MACHINE_RAMP: Ramp = build_ramp(_hex("77828f"), (26.0, 60.0, 92.0, 124.0, 150.0, 170.0))

# ---------------------------------------------------------------------------
# the massif's two ramps — rock and snow
# ---------------------------------------------------------------------------
#
# The mountain is a voxel mass now (see `buildings.massif`), so its faces are
# ramp slots like every other mass on the sheet rather than four literals
# picked by hand. The ladder is not new: its four upper rungs are the four
# faces `terrain.ROCK` was authored at (L163/145/118/95 against ROCK's
# 161.5/144.3/113.5/95.3), so a face that used to be painted `rock_lt` is
# still drawn at `rock_lt`'s value — what changes is that the warm/cool split
# those literals carried is now `_shape`'s doing, out of the same AMBIENT sky
# the armies stand in, and the renderer picks the rung off the face normal
# instead of a painter picking it off an x comparison.
#
# The lit rungs are the rock the terrain pass authored (H37/S0.14), the same
# grey masonry's lit rung is: a cliff and a wall are one material under one
# sun. The rim rung is the massif's own sunlit ridge and stops at L163, well
# under `terrain.TERRAIN_VALUE_CEILING` — a mountain may catch the light, it
# may not out-key an army standing in front of it.
#
# The three rungs below the body are built off a SKY-hued base instead, which
# is the one thing `_shape` cannot do for a grey on its own: its ambient mix
# is 7-26% and a stone with this little chroma has no hue to defend, so a
# small rotation lands anywhere. `terrain._shade` settled that for the painted
# tones (`_SHADE_GREY`: under S0.20 a shadow simply IS the sky) and the ramp
# says the same thing — warm stone in the light, cool stone in the shade,
# which is the face a shaded flank of the old massif already wore.
_ROCK_LIT: RGB = _hex("a6a099")
_ROCK_SHADE: RGB = _full_chroma(_SKY_HUE, 0.15)
_ROCK_L = (32.0, 66.0, 95.0, 118.0, 145.0, 163.0)
ROCK_RAMP: Ramp = tuple(
    _shape(_ROCK_LIT if slot >= S_BODY else _ROCK_SHADE, slot, target)
    for slot, target in enumerate(_ROCK_L)
)
# Snow is the one cool material up there, and the only reason the ladder goes
# this high: a cap is what tells a summit from a quarry at the board's 4:1
# rung. It stops at L172, under the ceiling, where the painted caps sat.
SNOW_RAMP: Ramp = build_ramp(_hex("aab2c4"), (44.0, 82.0, 112.0, 140.0, 160.0, 172.0))

_MASONRY_SLOT = "masonry"
_CONCRETE_SLOT = "concrete_ramp"
_MACHINE_SLOT = "machine"
_ROCK_SLOT = "rock_ramp"
_SNOW_SLOT = "snow_ramp"

# Named ramps every row shares. A faction's own is looked up per row instead,
# and anything unlisted derives one from its fixed colour.
_SHARED_RAMPS: dict[str, Ramp] = {
    _GUNMETAL_SLOT: GUNMETAL_RAMP,
    _MASONRY_SLOT: MASONRY_RAMP,
    _CONCRETE_SLOT: CONCRETE_RAMP,
    _MACHINE_SLOT: MACHINE_RAMP,
    _ROCK_SLOT: ROCK_RAMP,
    _SNOW_SLOT: SNOW_RAMP,
}

# The scenery convention: a natural mass carries one material and the renderer
# spends the rungs around it on the three planes — top at S4, the up-left
# flank at S3, the flank turned away at S2. `scree` is the same rock a band
# down, for the talus a massif's foot spills into.
TERRAIN_MATERIALS: dict[str, MaterialSlot] = {
    "scarp": MaterialSlot(_ROCK_SLOT, S_BODY, MID_GUNMETAL),
    "scree": MaterialSlot(_ROCK_SLOT, S_SHADOW, MID_GUNMETAL),
    "snowcap": MaterialSlot(_SNOW_SLOT, S_BODY, MID_GUNMETAL),
}


def _masonry(slot: int) -> MaterialSlot:
    return MaterialSlot(_MASONRY_SLOT, slot, MID_GUNMETAL)


# The building convention, restated as slots. The mass is the shadow band and
# the trim the body band — a highlight on a building is a LINE (a coping, a
# parapet, a ridge), never a field, which is what keeps a property from
# out-keying the army standing on it. `detail` is the contour step of the
# masonry itself, so a door or a seam is the wall's own darkest rung rather
# than a fifth grey.
PROPERTY_MATERIALS: dict[str, MaterialSlot] = {
    "detail": _masonry(S_CONTOUR),
    "wall_dk": _masonry(S_UNDER),
    "wall": _masonry(S_SHADOW),
    "trim": _masonry(S_BODY),
    # Concrete answers the same four rungs, because the row nobody owns is
    # built out of it end to end (`buildings._NEUTRAL_GREYS`): a seam, a kerb,
    # the slab, and the trim line over it.
    "pad_seam": MaterialSlot(_CONCRETE_SLOT, S_CONTOUR, MID_GUNMETAL),
    "pad_rim": MaterialSlot(_CONCRETE_SLOT, S_UNDER, MID_GUNMETAL),
    "pad": MaterialSlot(_CONCRETE_SLOT, S_SHADOW, MID_GUNMETAL),
    "pad_trim": MaterialSlot(_CONCRETE_SLOT, S_BODY, MID_GUNMETAL),
    "machine": MaterialSlot(_MACHINE_SLOT, S_BODY, MID_GUNMETAL),
    # The owner's two rows: the roof plane and the line that caps it. They sit
    # two bands under the unit convention, so a roof plane's LIT face lands
    # where a unit's shadowed one does — a roof lit to the faction token is
    # the mass a silhouette is read against, not a chassis. Iron keeps its
    # inverted identity here more than anywhere: near-black panels under a
    # light-steel ridge.
    "roof": _fac(S_UNDER),
    "roof_trim": _fac(S_SHADOW),
}


def material_slot(material: str) -> MaterialSlot:
    """Slot for a model's material name; anything unlisted is a fixed accent."""
    spec = (
        UNIT_MATERIALS.get(material)
        or PROPERTY_MATERIALS.get(material)
        or TERRAIN_MATERIALS.get(material)
    )
    return spec if spec is not None else _accent(S_BODY)


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
    shared = _SHARED_RAMPS.get(spec.ramp)
    if shared is not None:
        return shared
    base = resolve(material, faction)
    ramp = _DERIVED.get(base)
    if ramp is None:
        ramp = _derived_ramp(base)
        _DERIVED[base] = ramp
    return ramp
