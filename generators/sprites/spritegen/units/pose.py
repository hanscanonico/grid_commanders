"""The clips and their frames: the `Pose` enum, the clip keys and `MOVES`."""

from __future__ import annotations

from enum import IntEnum


class Pose(IntEnum):
    """One clip's one frame. A/B are the ambient clip, MOVE_A/MOVE_B the move.

    A is the parked/rest key and B the idle beat; MOVE_A and MOVE_B are the
    same machine under way, one stride apart. KO is the casualty clip's one
    frame — a single key, never a pair, because the dead don't loop. The
    values of A and B are frozen at 0 and 1 because the sheets and the
    manifest's frame order are written against them.
    """

    A = 0
    B = 1
    MOVE_A = 2
    MOVE_B = 3
    KO = 4


# The clips, as frame order. `CLIP_POSES` is keyed by the clip names
# `anim.MANIFEST["clips"]` publishes, so a sheet, a pose and a clip entry
# cannot end up meaning different things.
AMBIENT_POSES: tuple[Pose, ...] = (Pose.A, Pose.B)
MOVE_POSES: tuple[Pose, ...] = (Pose.MOVE_A, Pose.MOVE_B)
KO_POSES: tuple[Pose, ...] = (Pose.KO,)
CLIP_POSES: dict[str, tuple[Pose, ...]] = {
    "ambient": AMBIENT_POSES,
    "move": MOVE_POSES,
    "ko": KO_POSES,
}

# The ambient pose each move pose falls back to when a unit has not authored
# the move clip: same frame index, other clip. KO falls back to A — the rest
# key a unit that has not authored a wreck still stands in — which is what
# keeps the KO sheet a valid 18-column grid the day only the foot family has
# a casualty pose. Nothing draws that fallback column: air, the one domain
# that ships no KO art in v1, keeps the ambient clip's own topple instead
# (`CutsceneSide`'s fallback, gated on domain rather than on this one).
_FALLBACK: dict[Pose, Pose] = {
    Pose.MOVE_A: Pose.A,
    Pose.MOVE_B: Pose.B,
    Pose.KO: Pose.A,
}


def moving(pose: Pose) -> bool:
    """True for the move clip's frames."""
    return Pose(pose) in MOVE_POSES


def beat(pose: Pose) -> bool:
    """True on the off-beat of whichever clip is playing (B or MOVE_B).

    Anything that ticks with the frame rather than with the clip — a rotor
    blade phase, the air/sea bob — asks this instead of `pose is Pose.B`.
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
