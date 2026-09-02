"""The clips and their frames: the `Pose` enum, the clip keys and `MOVES`."""

from __future__ import annotations

from enum import IntEnum


class Pose(IntEnum):
    """One clip's one frame. A/B are the ambient clip, MOVE_A/MOVE_B the move.

    A is the parked/rest key and B the idle beat; MOVE_A and MOVE_B are the
    same machine under way, one stride apart. KO is the casualty clip's one
    frame — a single key, never a pair, because the dead don't loop.
    FIRE_A/FIRE_B are the cut-in's muzzle-lit pose: a pair, like the ambient
    clip, because the two SUSTAINED weapon families (`FIRE_PAIRS`) need a
    second key for the stream to read as a blaze rather than a held aim — a
    single-shot weapon draws the same model into both, which is FIRE's own
    fallback and not the unauthored-unit one (`_FALLBACK` still handles
    that). The values of A and B are frozen at 0 and 1 because the sheets
    and the manifest's frame order are written against them.
    """

    A = 0
    B = 1
    MOVE_A = 2
    MOVE_B = 3
    KO = 4
    FIRE_A = 5
    FIRE_B = 6


# The clips, as frame order. `CLIP_POSES` is keyed by the clip names
# `anim.MANIFEST["clips"]` publishes, so a sheet, a pose and a clip entry
# cannot end up meaning different things.
AMBIENT_POSES: tuple[Pose, ...] = (Pose.A, Pose.B)
MOVE_POSES: tuple[Pose, ...] = (Pose.MOVE_A, Pose.MOVE_B)
KO_POSES: tuple[Pose, ...] = (Pose.KO,)
FIRE_POSES: tuple[Pose, ...] = (Pose.FIRE_A, Pose.FIRE_B)
CLIP_POSES: dict[str, tuple[Pose, ...]] = {
    "ambient": AMBIENT_POSES,
    "move": MOVE_POSES,
    "ko": KO_POSES,
    "fire": FIRE_POSES,
}

# The ambient pose each move or fire pose falls back to when a unit has not
# authored that clip: same frame index, other clip. KO falls back to A — the
# rest key a unit that has not authored a wreck still stands in — which is
# what keeps the KO sheet a valid 18-column grid the day only the foot family
# has a casualty pose. Nothing draws that fallback column: air, the one
# domain that ships no KO art in v1, keeps the ambient clip's own topple
# instead (`CutsceneSide`'s fallback, gated on domain rather than on this
# one). FIRE_A/FIRE_B fall back the same way MOVE_A/MOVE_B do, which is what
# an unarmed unit's fire clip draws — its own idle beat, so a side that never
# fires never needs a runtime "is this unit armed" question of its own. An
# attacker's fire window opens whatever it carries (`CombatBeats.plan` sizes
# a recoil ramp off `aim_seconds` alone); what makes that safe is the columns
# it opens onto being byte-identical to the idle pair, bob included.
_FALLBACK: dict[Pose, Pose] = {
    Pose.MOVE_A: Pose.A,
    Pose.MOVE_B: Pose.B,
    Pose.KO: Pose.A,
    Pose.FIRE_A: Pose.A,
    Pose.FIRE_B: Pose.B,
}


def moving(pose: Pose) -> bool:
    """True for the move clip's frames."""
    return Pose(pose) in MOVE_POSES


def fires(pose: Pose) -> bool:
    """True for the fire clip's frames."""
    return Pose(pose) in FIRE_POSES


def off_beat(pose: Pose) -> bool:
    """True on the second FRAME of whichever clip is playing.

    A COMPOSITION question — the air/sea bob (`atlas.cell_placement`), which
    belongs to every clip alike because the cut-in swaps the fire pair in and
    out mid-window on the same 500 ms clock the idle pair runs on: a fire
    frame placed at its own clip's rest altitude would step the figure
    `BOB_PX` the moment the window opened or closed.

    A BUILDER asks `beat` instead. The two differ on `FIRE_B` alone, and see
    `beat` for why.
    """
    return Pose(pose) in (Pose.B, Pose.MOVE_B, Pose.FIRE_B)


def beat(pose: Pose) -> bool:
    """True on the off-beat KEY a builder authors — B or MOVE_B.

    Anything whose MODEL ticks with the frame rather than with the clip — a
    rotor blade phase, a canopy glint — asks this instead of
    `pose is Pose.B`. `FIRE_B` is deliberately outside it: the fire clip's
    second key is authored by hand for the units in `FIRE_PAIRS` and by
    nobody else, so a unit whose weapon fires one shot draws the SAME model
    into both fire frames (`test_fire_pose.PairVsSingle`) — an ambient tick
    leaking onto `FIRE_B` would quietly make a single-key unit a pair. What
    the fire frames still take from the frame is their PLACEMENT: see
    `off_beat`.
    """
    return Pose(pose) in (Pose.B, Pose.MOVE_B)


# The uids that author the move clip. Each family task adds its units here as
# it hand-places their strides; everything absent still renders its ambient
# counterpart onto the move sheets, so the sheets stay valid while the
# families arrive one at a time.
MOVES: frozenset[str] = frozenset(
    {
        "tank",
        "md_tank",
        "anti_air",
        "artillery",
        "apc",
        "recon",
        "rockets",
        "missiles",
        "fighter",
        "bomber",
        "b_copter",
        "t_copter",
        "infantry",
        "mech",
        "battleship",
        "cruiser",
        "sub",
        "lander",
    }
)

# The uids that author a KO pose — every land and sea unit. Air is absent on
# purpose rather than pending: the plan takes it as v1's fallback (see
# `_FALLBACK` above), and a family task that ships one adds it here the same
# way `MOVES` grows.
KOS: frozenset[str] = frozenset(
    {
        "infantry",
        "mech",
        "recon",
        "tank",
        "md_tank",
        "anti_air",
        "artillery",
        "rockets",
        "apc",
        "missiles",
        "battleship",
        "cruiser",
        "sub",
        "lander",
    }
)

# The uids that author a fire pose — every unit that carries a weapon.
# `apc`, `t_copter` and `lander` are absent on purpose: unarmed, so their
# fire clip is the idle clip under another name (`_FALLBACK`), the same
# contract `KOS` leaves air out under. This is generator-side data, kept here
# rather than read off `data/units/*.tres`, the way `MOVES` and `KOS` already
# are: the art pipeline builds without the game's own data.
FIRES: frozenset[str] = frozenset(
    {
        "infantry",
        "mech",
        "recon",
        "tank",
        "md_tank",
        "anti_air",
        "artillery",
        "rockets",
        "missiles",
        "fighter",
        "bomber",
        "b_copter",
        "battleship",
        "cruiser",
        "sub",
    }
)

# The subset of `FIRES` whose primary weapon is SUSTAINED — small_arms,
# pintle and autocannon, `BattleStyle.sustained` in the game's own data,
# mirrored here for the same reason `FIRES` mirrors `battle_style` at all —
# and so the only units a second fire key is authored for. Everything else in
# `FIRES` draws the same model into FIRE_B that it draws into FIRE_A (a
# single shot has one key, not a cycle); everything outside `FIRES` falls
# back to the idle pair instead.
#
# The mirror is of a unit's PRIMARY style, while the cut-in resolves a style
# per weapon SLOT (`CombatCutscene._pose`, off the slot the rules picked). So
# a tank firing its `small_arms` secondary draws a stream and a strobing
# muzzle over a figure holding its single cannon-recoil key: the sheet is
# authored per unit and cannot answer per shot. That is the pair set's known
# edge, not a drift in it.
FIRE_PAIRS: frozenset[str] = frozenset(
    {
        "infantry",
        "recon",
        "anti_air",
        "fighter",
        "b_copter",
        "cruiser",
    }
)
