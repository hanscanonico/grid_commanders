"""The 18 curated unit models, one per atlas column.

Every model is hand-placed voxels — no randomness — so each unit is a single
authored design that renders byte-identically on every run. Units face +y
(screen lower-left), the facing the game's atlas has always used. Column
order and ids mirror data/units/*.tres in grid_commanders.

Weapon silhouettes follow each unit's battle_style family: small_arms carry
rifles or a pintle MG, rocket units carry tubes and pods, cannon units carry a
single big gun, autocannon units carry thin multi-barrels, and the unarmed
transports carry none. An id split off one of those for the cut-in alone —
recon's pintle, mech's bazooka, the APC's convoy — draws its parent's
silhouette.

Every builder takes a `Pose`. A pose is a CLIP and a FRAME: the ambient clip's
two keys are `A`/`B`, the move clip's are `MOVE_A` through `MOVE_D` (S6,
2026-09-02 — grown from a shuffling pair to a walked four). Pose A is the
model as it has always been authored; pose B is one hand-placed idle key pose
of the same machine — a gun laid up, a howitzer recoiled, a rack pitched, a
nose dipped, a tread walked. The poses are keys, not in-betweens: they never
move the silhouette enough to change what the unit is, and pose A is
byte-frozen.

What a key pose moves, it moves a WHOLE BOARD TEXEL (`_shift`). The board
draws the 64x96 cell at a quarter of its size, so a delta under four atlas
pixels — a one-voxel settle, the tread's old period-2 checker — never carries
a texel across: it re-tones the inside of a shape that holds still, and the
sprite boils instead of animating. Measured, that was every land vehicle on
the sheet at zero changed silhouette texels (`tests/measure_motion.py`).

The move clip is the same machine UNDER WAY, and it is a gait and never a
journey: the game tweens the sprite across the board itself, so a move frame
may not translate the hull along its own run — that would double the travel
and slide the unit out of the cell it is standing in. What a move frame owns
is the running gear and the chassis's reaction to it, with the weapons left at
travel-lock — pose A's gun, not pose B's laid-up or recoiled one, because a
vehicle on the move does not lay its gun.

EVERY move frame carries an ATTITUDE, and that is the clip's first rule. A move
frame that reused the parked model would put a rolling column pixel for pixel
alongside a stopped one on half of every beat, which is what the land family
shipped when the clip landed: MOVE_A was byte-identical to pose A. So the land
vehicles stand ONE END of the chassis a whole board texel up on MOVE_A/MOVE_C —
the nose for seven of the eight, the weight gone back over the drivers as the
machine pulls away and the front of the running gear off the ground; the tail
on the rockets truck, whose cast shadow cannot afford the nose (see
`rockets`) — and take the off-beat from the chassis on MOVE_B/MOVE_D too: the
whole hull jolting that texel of ride height clear of the ground (`_roll`), or,
where lifting all of a low hull would raise its silhouette into a neighbour's,
the OTHER end rising instead (the MBT rocks tail-up, see `tank`) or a sprung
sub-assembly riding up over a level chassis (the scout's cabin, see `recon`).
The chassis attitude is the two-frame reading HELD across the four — the
family's own two authored keys, played twice a cycle (`beat(pose) % 2`) — and
what makes the clip a walk rather than a repeat is the tread: `_track`'s link
stripe now steps a QUARTER period on every one of the four frames
(`_tread_phase`), so a full stride crosses the whole 8-voxel run once per
640 ms cycle instead of flipping between two halves of it. The foot family
alone earns a genuinely four-key gait (`infantry`/`mech`, contact-lead /
passing / contact-lead-mirrored / passing), because a figure's stride is the
one motion on the sheet with a real third and fourth thing to say; every other
family's `beat(pose) % 2` interpolates its existing pair across the extra two
frames rather than authoring new attitudes for them.

Only the uids in `MOVES` author the move clip; every other unit falls back to
its ambient counterpart in `build_model`, so the move sheets are valid from
the day the plumbing lands and a family arrives one unit at a time. That
fallback is also why a builder's pose test has to say which question it asks:

* `if pose is Pose.B` is an AMBIENT-only branch — the idle beat, and nothing
  else. A move pose reaching that builder must not fall into it.
* `beat(pose)` answers WHERE in its own clip's cycle a pose sits — 0/1 for the
  ambient pair, 0-3 for the move clip's four — for anything whose MODEL ticks
  with the FRAME rather than with the clip, such as a rotor blade phase or the
  rifleman's stride; `beat(pose) % 2` is the same question asked as the old
  boolean, for a family that plays its two authored keys twice across the
  four move frames rather than authoring new ones. The fire clip is outside
  it on purpose: its second key is hand-authored for `FIRE_PAIRS` and by
  nobody else, so a single-shot weapon draws one model into both fire frames.
  What every clip's second FRAME does share is its PLACEMENT — `off_beat`,
  which `atlas.cell_placement` asks for the air/sea bob and a builder never
  does.

An `else` that quietly means "pose B" is the trap: with six or more poses,
`X if pose is Pose.A else Y` hands every one of them but A the Y branch. Write
the beat side as the condition (`Y if beat(pose) % 2 else X`, or a lookup keyed
on `beat(pose)` for a genuine four-way branch) so an unlisted pose lands on A.
"""

from __future__ import annotations

from ..voxel import Model
from .air import b_copter, bomber, fighter, t_copter
from .foot import infantry, mech
from .land import anti_air, apc, artillery, md_tank, missiles, recon, rockets, tank
from .parts import _BLADE_B as _BLADE_B
from .parts import _rotor as _rotor
from .parts import _shift as _shift
from .parts import _track as _track
from .pose import _FALLBACK, FIRES, KOS, MOVES, Pose, fires, moving
from .pose import AMBIENT_POSES as AMBIENT_POSES
from .pose import CLIP_POSES as CLIP_POSES
from .pose import FIRE_PAIRS as FIRE_PAIRS
from .pose import FIRE_POSES as FIRE_POSES
from .pose import MOVE_POSES as MOVE_POSES
from .pose import beat as beat
from .pose import off_beat as off_beat
from .sea import battleship, cruiser, lander, sub


UNITS: dict[str, tuple] = {
    "infantry": (infantry, "land"),
    "mech": (mech, "land"),
    "recon": (recon, "land"),
    "tank": (tank, "land"),
    "md_tank": (md_tank, "land"),
    "anti_air": (anti_air, "land"),
    "artillery": (artillery, "land"),
    "rockets": (rockets, "land"),
    "apc": (apc, "land"),
    "fighter": (fighter, "air"),
    "bomber": (bomber, "air"),
    "b_copter": (b_copter, "air"),
    "t_copter": (t_copter, "air"),
    "missiles": (missiles, "land"),
    "battleship": (battleship, "sea"),
    "cruiser": (cruiser, "sea"),
    "sub": (sub, "sea"),
    "lander": (lander, "sea"),
}

# Hulls that run awash and so carry a wake (voxel._wake). A ship with
# freeboard reads against open sea on its own; the sub is the one model whose
# deck is at the waterline, which is what left it last in the round-4
# legibility measure.
WAKE: frozenset[str] = frozenset({"sub"})


def resolved_pose(uid: str, pose: Pose) -> Pose:
    """The pose a unit actually answers to a clip's request with: itself, or
    the fallback clip's own key when `uid` has not opted into the clip
    `pose` belongs to.

    The one seam `build_model` reaches a builder through, and also the one
    `atlas.cell_placement` reads before asking `units.off_beat` whether this
    frame bobs — a fallback cell has to bob exactly as its FALLBACK pose
    does (an unarmed air unit's `FIRE_B` cell is pixel-identical to its `B`
    cell, bob included), and `KO`'s fallback is the rest key, which the raw
    pose cannot say.
    """
    pose = Pose(pose)
    if moving(pose) and uid not in MOVES:
        return _FALLBACK[pose]
    if pose is Pose.KO and uid not in KOS:
        return _FALLBACK[pose]
    if fires(pose) and uid not in FIRES:
        return _FALLBACK[pose]
    return pose


def build_model(uid: str, pose: Pose = Pose.A) -> Model:
    """The one seam a pose reaches a builder through.

    Every builder takes the pose, so there is no per-unit list of which
    models animate within a clip: a unit that has nothing to say in pose B
    simply draws the same voxels and lets composition (the air/sea bob) carry
    the beat.

    Across clips there IS such a list. A move pose only reaches the builder
    for a uid in `MOVES`, a KO pose only for a uid in `KOS`, and a fire pose
    only for a uid in `FIRES`; anything else is served its ambient
    counterpart (`resolved_pose`), so every sheet is a valid clip before a
    single stride, a single wreck or a single muzzle is authored and a
    family lands one unit at a time.
    """
    return UNITS[uid][0](resolved_pose(uid, pose))


# atlas_col -> unit id (contiguous 0..17), the order the sheet is assembled in
ATLAS_ORDER: tuple[str, ...] = (
    "infantry",
    "mech",
    "recon",
    "tank",
    "md_tank",
    "anti_air",
    "artillery",
    "rockets",
    "apc",
    "fighter",
    "bomber",
    "b_copter",
    "t_copter",
    "missiles",
    "battleship",
    "cruiser",
    "sub",
    "lander",
)
