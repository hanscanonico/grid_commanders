"""The FACES table: one row per general, the columns the painter draws from.

Transcribed column for column off the GDScript face table it replaced — it is a port,
not a re-art — and the vocabularies each column is drawn from are owned by the
module that draws them, never restated here. Rows are in the GDScript table's
own order so the two read side by side.
"""

from __future__ import annotations

from dataclasses import dataclass

from .head import HEAD_DEFAULT, SKIN_BASES, Skull
from .uniform import CHEST_DEFAULT

Pose = tuple[float, float, bool]


@dataclass(frozen=True)
class Face:
    """One general's spec.

    `skin` and `hair` name a ramp, `style` a hair mass, `brow`/`eyes`/`mouth`/
    `nose`/`facial`/`acc` a feature glyph, `collar` a cut, `chest` what is worn
    under it, `bg` a backdrop and `prop` a signature prop; `eye` scales the eyes
    (0.82-1.06), `head` is the skull's four dials and `pose` is
    [tilt degrees, zoom, mirrored].

    `chest` is the one column the GDScript table had no field for: it wore one
    diagonal sash five times over, and the review's own bar is that no chest
    treatment is shared by more than two. It is named per row here for the
    same reason every other column is.
    """

    id: str
    skin: str
    hair: str
    style: str
    brow: str
    eyes: str
    mouth: str
    eye: float
    facial: str
    acc: str
    collar: str
    head: Skull
    nose: str
    pose: Pose
    bg: str
    prop: str
    chest: str = CHEST_DEFAULT
    pip: bool = False
    earring: bool = False
    freckles: bool = False


@dataclass(frozen=True)
class EmptySeat:
    """The empty seat: the shared skull, no features, slate instead of skin.

    Not a `Face`, because it names none of the roster's vocabularies — it has no
    hair, no expression and no prop, and its tone is the UI's slate rather than
    a skin ramp. Keeping it featureless is the point: an empty seat has to read
    as a deliberate choice rather than as a bust that failed to render.
    """

    head: Skull
    pose: Pose
    bg: str


# The skins the head module can paint; named there because it paints them.
SKIN_TONES = frozenset(SKIN_BASES)

NEUTRAL_ID = "none"
NEUTRAL = EmptySeat(head=Skull(*HEAD_DEFAULT), pose=(0.0, 1.18, False), bg="bars")

FACES: dict[str, Face] = {
    face.id: face
    for face in (
        Face(
            id="alina_ward",
            chest="sash",
            skin="light",
            hair="auburn",
            style="long",
            brow="soft",
            eyes="f",
            mouth="smile",
            eye=1.02,
            facial="none",
            acc="none",
            earring=True,
            collar="v",
            head=Skull(0.96, "round", 0.5, 1.0),
            nose="tick",
            pose=(-5.0, 1.2, False),
            bg="rays",
            prop="sabre",
        ),
        Face(
            id="gideon_holt",
            chest="placket",
            skin="tan",
            hair="grey",
            style="short",
            brow="heavy",
            eyes="m",
            mouth="smile",
            eye=0.91,
            facial="beard",
            acc="glasses",
            collar="double",
            head=Skull(1.08, "square", -2.0, 1.0),
            nose="broad",
            pose=(3.0, 1.14, False),
            bg="halftone",
            prop="pipe",
        ),
        Face(
            id="rhea_sol",
            chest="loops",
            skin="tan",
            hair="black",
            style="ponytail",
            brow="angled",
            eyes="narrow",
            mouth="grin",
            eye=0.98,
            facial="none",
            acc="goggles",
            collar="mandarin",
            head=Skull(0.92, "tapered", 0.0, 1.05),
            nose="tick",
            pose=(-8.0, 1.24, True),
            bg="speed",
            prop="wrench",
        ),
        Face(
            id="cass_orlov",
            chest="crossbelt",
            skin="light",
            hair="brown",
            style="buzz",
            brow="cocked",
            eyes="m",
            mouth="smirk",
            eye=0.9,
            facial="stubble",
            acc="scar",
            collar="v",
            head=Skull(1.1, "square", 0.5, 0.96),
            nose="hook",
            pose=(6.0, 1.22, False),
            bg="wedge",
            prop="cigar",
        ),
        Face(
            id="mara_voss",
            chest="bandolier",
            skin="medium",
            hair="black",
            style="bun",
            brow="angled",
            eyes="f",
            mouth="stern",
            eye=0.95,
            facial="none",
            acc="none",
            collar="v",
            head=Skull(0.94, "tapered", 1.0, 1.0),
            nose="hook",
            pose=(0.0, 1.18, False),
            bg="bars",
            prop="baton",
        ),
        Face(
            id="viktor_draeg",
            chest="boards",
            skin="light",
            hair="grey",
            style="bald",
            brow="heavy",
            eyes="wide",
            mouth="open",
            eye=1.06,
            facial="mustache",
            acc="eyepatch",
            collar="v",
            head=Skull(1.12, "square", -1.0, 0.94),
            nose="broad",
            pose=(-3.0, 1.26, False),
            bg="burst",
            prop="medal",
        ),
        Face(
            id="cassian_rook",
            chest="lanyard",
            skin="tan",
            hair="blonde",
            style="sidepart",
            brow="cocked",
            eyes="narrow",
            mouth="wry",
            eye=0.92,
            facial="none",
            acc="none",
            collar="mandarin",
            head=Skull(0.92, "tapered", 1.0, 1.0),
            nose="hook",
            pose=(8.0, 1.18, True),
            bg="halftone",
            prop="card",
        ),
        Face(
            id="lyra_quill",
            chest="placket",
            skin="pale",
            hair="platinum",
            style="bob",
            brow="soft",
            eyes="closed",
            mouth="wry",
            eye=0.86,
            facial="none",
            acc="glasses",
            collar="mandarin",
            head=Skull(0.88, "tapered", 2.0, 0.94),
            nose="hook",
            pose=(-4.0, 1.12, False),
            bg="grid",
            prop="book",
        ),
        Face(
            id="orin_flux",
            chest="lanyard",
            skin="medium",
            hair="black",
            style="spiky",
            brow="angled",
            eyes="wide",
            mouth="laugh",
            eye=1.04,
            facial="none",
            acc="headset",
            collar="mandarin",
            head=Skull(0.9, "round", 1.0, 1.08),
            nose="tick",
            pose=(-9.0, 1.22, False),
            bg="speed",
            prop="drone",
        ),
        Face(
            id="nia_rowan",
            chest="pouch",
            skin="tan",
            hair="brown",
            style="braid",
            brow="soft",
            eyes="f",
            mouth="wry",
            eye=1.0,
            facial="none",
            acc="headband",
            freckles=True,
            collar="v",
            head=Skull(0.92, "round", 0.5, 1.06),
            nose="broad",
            pose=(4.0, 1.16, False),
            bg="rays",
            prop="monocle",
        ),
        Face(
            id="sable_wren",
            chest="scarf",
            skin="pale",
            hair="black",
            style="hood",
            brow="soft",
            eyes="lidded",
            mouth="neutral",
            eye=0.9,
            facial="none",
            acc="hood",
            collar="v",
            head=Skull(0.88, "tapered", 0.5, 0.96),
            nose="tick",
            pose=(0.0, 1.24, False),
            bg="wedge",
            prop="dagger",
        ),
        Face(
            id="tomas_reed",
            chest="pouch",
            skin="dark",
            hair="black",
            style="curly",
            brow="raised",
            eyes="m",
            mouth="grin",
            eye=1.03,
            facial="stubble",
            acc="bandana",
            collar="v",
            head=Skull(1.06, "round", 0.0, 1.0),
            nose="broad",
            pose=(-6.0, 1.2, False),
            bg="burst",
            prop="radio",
        ),
        Face(
            id="ines_calder",
            chest="mapcase",
            skin="dark",
            hair="black",
            style="bun",
            brow="cocked",
            eyes="f",
            mouth="smirk",
            eye=0.93,
            facial="none",
            acc="glasses",
            collar="mandarin",
            head=Skull(0.94, "round", 0.5, 1.02),
            nose="tick",
            pose=(-4.0, 1.18, False),
            bg="grid",
            prop="ledger",
        ),
        Face(
            id="konrad_vale",
            chest="boards",
            skin="pale",
            hair="grey",
            style="sidepart",
            brow="angled",
            eyes="narrow",
            mouth="stern",
            eye=0.87,
            facial="mustache",
            acc="none",
            collar="double",
            head=Skull(1.04, "tapered", -2.0, 0.98),
            nose="hook",
            pose=(5.0, 1.25, False),
            bg="wedge",
            prop="helm",
        ),
        Face(
            id="perrin_ash",
            chest="crossbelt",
            skin="tan",
            hair="auburn",
            style="short",
            brow="raised",
            eyes="m",
            mouth="grin",
            eye=1.01,
            facial="none",
            acc="goggles",
            collar="v",
            head=Skull(0.98, "round", 0.0, 1.06),
            nose="hook",
            pose=(-7.0, 1.2, True),
            bg="speed",
            prop="plane",
        ),
        Face(
            id="halden_marr",
            chest="epaulette",
            skin="tan",
            hair="grey",
            style="curly",
            brow="heavy",
            eyes="m",
            mouth="neutral",
            eye=0.97,
            facial="beard",
            acc="none",
            collar="double",
            head=Skull(1.08, "round", -2.0, 1.0),
            nose="hook",
            pose=(3.0, 1.16, False),
            bg="rays",
            prop="anchor",
        ),
        Face(
            id="dane_ferrow",
            chest="plain",
            skin="dark",
            hair="black",
            style="buzz",
            brow="heavy",
            eyes="narrow",
            mouth="clench",
            eye=0.94,
            facial="stubble",
            acc="cap",
            collar="mandarin",
            head=Skull(1.08, "square", 0.0, 0.96),
            nose="broad",
            pose=(7.0, 1.24, False),
            bg="burst",
            prop="coins",
        ),
        Face(
            id="iris_colt",
            chest="scarf",
            skin="light",
            hair="blonde",
            style="ponytail",
            brow="raised",
            eyes="f",
            mouth="smile",
            eye=1.05,
            facial="none",
            acc="headset",
            collar="v",
            pip=True,
            head=Skull(0.9, "tapered", 0.5, 1.08),
            nose="tick",
            pose=(-6.0, 1.22, False),
            bg="halftone",
            prop="whistle",
        ),
        Face(
            id="sera_lark",
            chest="mapcase",
            skin="dark",
            hair="darkbrown",
            style="ponytail",
            brow="raised",
            eyes="f",
            mouth="laugh",
            eye=0.99,
            facial="none",
            acc="bandana",
            collar="mandarin",
            head=Skull(0.9, "round", 1.0, 1.04),
            nose="tick",
            pose=(5.0, 1.2, True),
            bg="wedge",
            prop="compass",
        ),
        Face(
            id="iona_vance",
            chest="epaulette",
            skin="tan",
            hair="brown",
            style="bob",
            brow="soft",
            eyes="f",
            mouth="stern",
            eye=0.96,
            facial="none",
            acc="cap",
            collar="mandarin",
            pip=True,
            head=Skull(1.0, "square", 0.0, 0.98),
            nose="tick",
            pose=(0.0, 1.16, False),
            bg="grid",
            prop="scales",
        ),
        Face(
            id="ivar_thorne",
            chest="sash",
            skin="light",
            hair="darkbrown",
            style="long",
            brow="angled",
            eyes="narrow",
            mouth="snarl",
            eye=0.85,
            facial="beard",
            acc="scar",
            collar="v",
            pip=True,
            head=Skull(1.1, "square", -0.5, 0.96),
            nose="broad",
            pose=(-5.0, 1.26, True),
            bg="burst",
            prop="axe",
        ),
        Face(
            id="radek_morn",
            chest="bandolier",
            skin="medium",
            hair="darkbrown",
            style="bald",
            brow="heavy",
            eyes="lidded",
            mouth="clench",
            eye=0.88,
            facial="beard",
            acc="none",
            collar="double",
            pip=True,
            head=Skull(1.14, "square", -1.5, 0.94),
            nose="hook",
            pose=(2.0, 1.28, False),
            bg="halftone",
            prop="hammer",
        ),
    )
}
