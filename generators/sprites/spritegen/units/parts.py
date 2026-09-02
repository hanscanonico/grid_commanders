"""Chassis parts the unit families share: treads, rotors, tires, shifts."""

from __future__ import annotations

from ..voxel import Model
from .pose import Pose


def _track(
    m: Model, x0: int, x1: int, y0: int, y1: int, z1: int = 1, phase: int = 0
) -> None:
    """One tread block with link texture on its visible faces and road wheels.

    The link stripe has a period of EIGHT voxels along the run — four voxels
    riding the top face, four on the bottom — and `phase` advances it by TWO,
    a quarter of that period and one whole board texel of travel in the
    direction the tread runs (S6, 2026-09-02 — a quarter-step is what lets the
    four-frame move clip carry the stripe all the way round its own period
    once per gait cycle instead of flipping between two halves of it; the
    ambient pair still only ever asks for phase 0 or 2, so its two frames are
    unchanged pixel for pixel). The period-2 checker this replaces was exactly
    Nyquist at the board's 4:1 sample: pose B inverted every link and the
    tread flickered in place with no direction at all. A stripe four voxels
    long survives the sample and a quarter-period step reads as the track
    walking.

    The road wheels no longer take the phase. A hub is bolted to the hull, so
    translating it along the run was the one thing on the model that said the
    chassis had driven off rather than the tread having crept.
    """
    m.box(x0, x1, y0, y1, 0, z1, "track")
    # link texture: a four-on/four-off stripe along the outer (+x) face, and
    # the same stripe wrapping the front (+y) face, mirrored because the run
    # turns the corner there
    for y in range(y0, y1 + 1):
        m.set(x1, y, z1 if (y - y0 + 2 * phase) % 8 < 4 else 0, "track_lt")
    for x in range(x0, x1 + 1):
        m.set(x, y1, z1 if (x1 - x + 2 * phase) % 8 < 4 else 0, "track_lt")
    # road wheel hubs peeking out of the lower run
    for y in range(y0 + 1, y1, 3):
        m.set(x1, y, 0, "hub")


def _tread_phase(pose: Pose) -> int:
    """Which quarter period `_track`'s link stripe stands at, per pose.

    The ambient pair keeps the half-period flip it always had — `A` at 0,
    `B` at 2 (`2 * phase` puts that at the same four-voxel shift `4 * 1`
    always drew, so the shipped ambient sheets are unchanged) — and `MOVE_A`
    and `MOVE_B` keep the exact two quarters they always stood at too (2 and
    0), for the same reason: both were shipped art before S6 touched
    anything, and the legibility ratchet reads every one of their cells.
    Moving either would cost real, already-passing rows for no claim this
    slice makes about them. What is new is `MOVE_C` and `MOVE_D`, which take
    the two quarters `MOVE_A`/`MOVE_B` leave unused (1 and 3) — so the four
    move frames between them VISIT ALL FOUR quarter-positions of the run
    once a cycle rather than flipping between two halves of it.

    Visit, not march: in frame order the quarters read 2, 0, 1, 3, whose
    steps are +2, +1, +2, -1. A monotone lap is not available — the two
    frames the ratchet pins stand at quarters 2 and 0, and both monotone
    4-cycles through all four quarters (2, 1, 0, 3 and 2, 3, 0, 1) put a
    quarter between them, so preserving MOVE_A/MOVE_B byte for byte and
    walking the stripe one way round are mutually exclusive. Of the two
    orders left this is the one whose only unambiguous step points forward:
    a half-period shift of a 4-on/4-off stripe is its own inverse and says
    nothing about direction, which leaves the single +1 to carry it and the
    single -1 to close the loop. A slice free to move all four frames could
    have the lap instead.

    KO and FIRE both stand at pose A's own phase: a wreck does not walk, and
    neither does a hull recoiling from a shot fired at a halt — `artillery`'s
    own docstring says the same of the move clip's gun.
    """
    return {
        Pose.A: 0,
        Pose.B: 2,
        Pose.MOVE_A: 2,
        Pose.MOVE_B: 0,
        Pose.MOVE_C: 1,
        Pose.MOVE_D: 3,
        Pose.KO: 0,
        Pose.FIRE_A: 0,
        Pose.FIRE_B: 0,
    }[Pose(pose)]


# One rotor blade, hub-relative and tip last. The disc is this blade and its
# three quarter turns, so the two poses differ by how far round the SAME four
# blades stand — pose B is each of pose A's five voxels turned 14 degrees
# about the hub and rounded to the grid, which is the smallest turn the grid
# can say: 14 is where the outer three voxels each cross into the next cell
# while the two by the hub, whose lever arm is under a voxel, hold. A larger
# step reads no faster (a four-blade disc repeats every 90 degrees and 45 is
# the ambiguous middle, with no direction in it at all) and costs the read:
#
#   pose B                       blades   IoU with pose A   rung-1 silhouette
#                                        b_copter t_copter   b_copter t_copter
#   45-degree sweep, L1 8 (old)     4/2     0.74     0.74       25       24
#   14-degree tick, thin tips        4      0.88     0.87       28       30
#   this tick, tips 2 across         4      0.89     0.88       31       28
#
# IoU is of the two frames' silhouettes with `atlas.BOB_PX` taken out, so it
# reads the rotor and not the hop; the silhouette counts are
# `tests/measure_motion.py`'s, bob and all. The tick both shares more of the
# frame and moves more of the board's texels than the sweep did.
#
# What went before was a 45-degree sweep drawn as its own blade set — four
# long diagonals on b_copter, two on t_copter — and the tips are why it read
# as a second aircraft rather than a turn. A voxel projects
# to `sx = (x - y) * 2`, `sy = x + y`, so a tip `(a, b)` and its quarter turns
# put the disc's screen extremes at `4(|a| + |b|)` wide by `2(|a| + |b|)`
# tall: the L1 radius alone sets the rendered diameter. Pose A's tips sit at
# L1 5 and draw 20x10; the old diagonals ran out to L1 8 and drew 32x16 — the
# disc grew by half, on the one part of the sprite the eye tracks. This tip is
# at L1 6, one voxel of span per side, and no blade changes length.
#
# The outer two RANKS of every blade are two voxels wide across the blade,
# which is the direction the tip sweeps. A one-voxel tip is 4 atlas px, one
# board texel at rung 1, and the 4:1 sample took it as a lone texel or dropped
# it: the disc arrived as grey speckle with detached texels at the tips
# (b_copter pose B texel (9, 10), t_copter (7, 9) and (4, 11) — none of them
# touching the aircraft under 4-connectivity). Two voxels across the sweep is
# 8 px there, so a tip always shares a texel with the rank behind it and the
# disc samples as an arc. The thickening goes on the RETREATING side, so pose
# B's tip pair is pose A's advanced one voxel round and overlapping it: the
# disc's rendered extent is the same in both poses (L1 6, 24x12 px) and only
# the arc inside it turns.
Blade = tuple[tuple[int, int], ...]

_BLADE_A: Blade = ((1, 0), (2, 0), (3, 0), (4, -1), (4, 0), (5, -1), (5, 0))
_BLADE_B: Blade = ((1, 0), (2, 0), (3, 1), (4, 0), (4, 1), (5, 0), (5, 1))
# Two further ticks, S6 (2026-09-02): the move clip's own four-frame index
# gives the disc somewhere to turn between the ambient pair's two. `_BLADE_C`
# keeps taking the SAME step `_BLADE_B` took from `_BLADE_A` — the two voxels
# nearest the hub hold (their lever arm is under a voxel, same as every
# earlier tick) and the outer five ride the run another `dy +1` each.
# `_BLADE_D` does NOT continue that construction on every point: applied to
# all five it draws a genuine tick — the composed cell reads fine — but
# `_rotor`'s CLIPPED arm (t_copter's tandem, `arm[:-2]`) rotates that same
# delta into a 90-degree turn, and turned, index 2's own `dy +1` opens a
# three-voxel gap along x to the hub-side voxels ahead of it: a stranded
# rung-1 texel on the clipped disc and, on the unclipped one, a sweep wide
# enough to read as `t_copter`'s own rather than `b_copter`'s
# (`tests/test_board_read.py BoardScaleEdge`, `test_clips.py MoveFrames`).
# Holding index 2 at `_BLADE_C`'s own value and advancing only the outer
# four keeps the gap the one `_BLADE_C` already opens (untouched, and
# already shipping clean) rather than widening it.
_BLADE_C: Blade = ((1, 0), (2, 0), (3, 2), (4, 1), (4, 2), (5, 1), (5, 2))
_BLADE_D: Blade = ((1, 0), (2, 0), (3, 2), (4, 2), (4, 3), (5, 2), (5, 3))
# The disc's four ticks, in the frame order `units.beat` returns: ambient
# reads index 0/1 off it (identical to the old `_BLADE_A`/`_BLADE_B` pick),
# the move clip's four frames read all of it.
BLADES: tuple[Blade, Blade, Blade, Blade] = (_BLADE_A, _BLADE_B, _BLADE_C, _BLADE_D)


def _quarters(blade: Blade) -> tuple[Blade, ...]:
    """One blade and its three quarter turns — the whole disc."""
    arms = [blade]
    for _ in range(3):
        arms.append(tuple((-dy, dx) for dx, dy in arms[-1]))
    return tuple(arms)


def _rotor(
    m: Model, cx: int, cy: int, z: int, blade: Blade, clipped: bool = False
) -> None:
    """A four-blade disc at `(cx, cy, z)`, collar last so the livery roots sit
    over the sweep. `clipped` takes the outer RANK — both voxels of it, so
    the shortened blade still ends in a two-wide tip — off the two arms that
    run along y, since the tandem's discs would meet over the hold otherwise;
    it is a property of the AIRCRAFT, so both poses of a disc are clipped
    alike and the tick stays the only difference between them."""
    arms = _quarters(blade)
    if clipped:
        arms = tuple(arm[:-2] if i % 2 else arm for i, arm in enumerate(arms))
    for arm in arms:
        for dx, dy in arm:
            m.set(cx + dx, cy + dy, z, "rotor")
    _rotor_collar(m, cx, cy, z, arms)


def _rotor_collar(m: Model, cx: int, cy: int, z: int, arms: tuple[Blade, ...]) -> None:
    """Paint a rotor's hub cap and its four blade ROOTS in livery.

    A helicopter's disc is the one large mass on the sheet that carries no
    team colour, which is what put b_copter under the 55% faction-share gate
    (53.9%) and t_copter next to it at 60.2%. The roots are where a real
    airframe's paint runs out onto the blade, so the collar buys the share
    back without touching the silhouette or lightening the sweep at the tips.
    Both discs get it, so the two copters answer the gate the same way.
    """
    m.set(cx, cy, z, "hull_lt")
    for arm in arms:
        m.set(cx + arm[0][0], cy + arm[0][1], z, "hull")
        m.set(cx + arm[1][0], cy + arm[1][1], z, "hull_dk")


def _tire(m: Model, x: int, y: int, big: bool = False) -> None:
    """One wheel: dark tire block with a hub dot on the outer face.

    The wheel cannot carry the move clip and no later pass should try. The
    hub dot is a single voxel — 2 screen px, half a board texel at rung 1 —
    and it is the only feature on the tire, so any rotation of it re-tones
    half a texel at best and vanishes at the sample. The tread's link stripe
    works because it is four voxels long and steps a whole texel (see
    `_track`); there is no room on a 2x3 wheel for the same trick. So the
    wheeled family says "moving" with the chassis — `_roll` — and leaves the
    wheels alone.
    """
    m.box(x, x + 1, y, y + 2, 0, 1, "tire")
    if big:
        m.box(x, x + 1, y, y + 2, 2, 2, "tire")
    m.set(x + 1, y + 1, 1, "hub")


def _shift(
    m: Model,
    box: tuple[int, int, int, int, int, int],
    dx: int = 0,
    dy: int = 0,
    dz: int = 0,
) -> None:
    """Move one sub-assembly — the box `(x0, x1, y0, y1, z0, z1)` — bodily.

    Delete then reinsert, so whatever the assembly lands on is overwritten and
    whatever it came off is left open, the same way an authored box paints.

    The size of a delta is not a matter of taste. A voxel is a 4x4px cube
    projected at `sx = (x - y) * 2`, `sy = (x + y) - 2z`, and the board draws
    the 64x96 cell at a quarter of its size, so ONE board texel at zoom rung 1
    is four atlas pixels: a `dz` of two voxels, or a `(dx +1, dy -1)` diagonal
    step. Anything smaller cannot carry a texel a whole texel across — inside
    the silhouette it only re-tones, and at the edge it flips boundary texels
    with the sampling phase. That is what the whole tracked family shipped as
    an idle: a one-voxel settle, worth half a texel, measured at zero changed
    silhouette texels at both rungs the board plays at
    (`tests/measure_motion.py`).

    Which axis moves is still a matter of read: a unit that shifts its weight
    or lays its gun is parked, one that translates its hull has driven off, so
    the callers move a named assembly and leave the chassis alone.
    """
    x0, x1, y0, y1, z0, z1 = box
    moved = {
        (x, y, z): m.vox[(x, y, z)]
        for x in range(x0, x1 + 1)
        for y in range(y0, y1 + 1)
        for z in range(z0, z1 + 1)
        if (x, y, z) in m.vox
    }
    for key in moved:
        del m.vox[key]
    for (x, y, z), mat in moved.items():
        m.vox[(x + dx, y + dy, z + dz)] = mat


def _roll(m: Model, dz: int) -> None:
    """Jolt the WHOLE model `dz` — the chassis riding over ground.

    Two things make this the move clip's bob rather than a slide. It is
    authored in the MODEL, so `atlas.cell_placement` still pins the sprite by
    pose A's crop: origin, `footprint_w` and `ground` are pose-invariant and
    the cast shadow stays nailed to the ground row while the hull lifts off
    it. And it is vertical: the wide land hulls have no horizontal margin left
    in the 64x96 cell — a whole-body `(dx -1, dy +1)` on the tank overflows
    `voxel.place_in_cell` outright — and a hull that translated along its own
    run would say the vehicle had driven off, which is the game's tween's job
    and never the sheet's.

    `dz = 2` is one board texel, the same unit `_shift` moves an assembly by.
    """
    xs = [x for x, _, _ in m.vox]
    ys = [y for _, y, _ in m.vox]
    zs = [z for _, _, z in m.vox]
    _shift(m, (min(xs), max(xs), min(ys), max(ys), min(zs), max(zs)), dz=dz)


def _gear_down(
    m: Model, x0: int, x1: int, y0: int, y1: int, mat: str = "track"
) -> None:
    """Stand the running gear over `(x0..x1, y0..y1)` back on the ground.

    A move frame that raises a chassis — the family's nose pitch, or `_roll`'s
    whole-hull jolt — raises the wheels or the track run under it too, and at
    the board's 4:1 sample that opens ONE TEXEL OF BARE GROUND between the
    hull's lowest row and the cast shadow (rung-1 row 20, the shadow on 21-22):
    the vehicle hovers over its own shadow for the whole clip. Running gear
    does not leave the ground when a hull pitches; the suspension extends. So
    wherever a pose lifts gear, this paints the two voxel courses it came off
    back in — one board texel, `dz = +2`'s own unit — and the machine pitches
    ABOUT its contact patch instead of translating off it.

    The courses go in plain: no link stripe, no hub. They are the lowest texel
    of the sprite and they are identical in every pose, so the contact patch
    carries none of the gait and the clip's measured deltas barely move. z=0
    is the floor and nothing is ever painted under it, so the sprite's ground
    row is pose A's in all four poses.

    How MUCH of a run comes back down is a mass question, not a taste one. A
    pitch grounds the length it lifted, which costs almost nothing because the
    nose boxes are short. `_roll` lifts everything, and a WHOLE run brought
    back down under a rolled hull is a band of new pixels that breaks
    `MoveFrames.MAX_MASS_DRIFT`: measured at 0.100 (md_tank), 0.118
    (anti_air), 0.103 (artillery), 0.118 (apc) and 0.081 (rockets, all eight
    wheels) against the gate's 0.08. So the roll frames ground the LEADING
    four voxels of each run — the end the sprite's lowest texel is drawn from,
    since screen row is `x + y - 2z` and the contact texel is the front-outer
    corner — which is 0.050 to 0.068 and answers the contact rule with the
    same pixels. Lengthening from there is nearly free until it is not:
    md_tank runs 0.050 / 0.060 / 0.068 / 0.076 at four, six, eight and ten
    voxels, and anti_air is already at 0.081 at six.
    """
    m.box(x0, x1, y0, y1, 0, 1, mat)
