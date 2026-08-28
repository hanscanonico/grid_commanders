"""The clips and their frames: the `Pose` enum, the clip keys and `MOVES`."""

from __future__ import annotations

from enum import IntEnum


class Pose(IntEnum):
    """One clip's one frame. A/B are the ambient clip, MOVE_A/MOVE_B the move.

    A is the parked/rest key and B the idle beat; MOVE_A and MOVE_B are the
    same machine under way, one stride apart. The values of A and B are frozen
    at 0 and 1 because the sheets and the manifest's frame order are written
    against them.
    """

    A = 0
    B = 1
    MOVE_A = 2
    MOVE_B = 3


# The clips, as frame order. `CLIP_POSES` is keyed by the clip names
# `anim.MANIFEST["clips"]` publishes, so a sheet, a pose and a clip entry
# cannot end up meaning different things.
AMBIENT_POSES: tuple[Pose, ...] = (Pose.A, Pose.B)
MOVE_POSES: tuple[Pose, ...] = (Pose.MOVE_A, Pose.MOVE_B)
CLIP_POSES: dict[str, tuple[Pose, ...]] = {
    "ambient": AMBIENT_POSES,
    "move": MOVE_POSES,
}

# The ambient pose each move pose falls back to when a unit has not authored
# the move clip: same frame index, other clip.
_FALLBACK: dict[Pose, Pose] = {Pose.MOVE_A: Pose.A, Pose.MOVE_B: Pose.B}


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
