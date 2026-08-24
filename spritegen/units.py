"""The 18 curated unit models, one per atlas column.

Every model is hand-placed voxels — no randomness — so each unit is a single
authored design that renders byte-identically on every run. Units face +y
(screen lower-left), the facing the game's atlas has always used. Column
order and ids mirror data/units/*.tres in grid_commanders.

Weapon silhouettes follow each unit's battle_style: small_arms carry rifles
or a pintle MG, rocket units carry tubes and pods, cannon units carry a
single big gun, autocannon units carry thin multi-barrels, and the unarmed
transports carry none.

Every builder takes a `Pose`. Pose A is the model as it has always been
authored; pose B is one hand-placed idle key pose of the same machine — a gun
laid up, a howitzer recoiled, a rack pitched, a nose dipped, a tread walked.
The poses are keys, not in-betweens: they never move the silhouette enough to
change what the unit is, and pose A is byte-frozen.

What a key pose moves, it moves a WHOLE BOARD TEXEL (`_shift`). The board
draws the 64x96 cell at a quarter of its size, so a delta under four atlas
pixels — a one-voxel settle, the tread's old period-2 checker — never carries
a texel across: it re-tones the inside of a shape that holds still, and the
sprite boils instead of animating. Measured, that was every land vehicle on
the sheet at zero changed silhouette texels (`tests/measure_motion.py`).
"""

from __future__ import annotations

from enum import IntEnum

from .voxel import Model


class Pose(IntEnum):
    """The two ambient key poses. A is the parked/rest key, B the idle beat."""

    A = 0
    B = 1


# ---------------------------------------------------------------------------
# shared chassis parts
# ---------------------------------------------------------------------------


def _track(
    m: Model, x0: int, x1: int, y0: int, y1: int, z1: int = 1, phase: int = 0
) -> None:
    """One tread block with link texture on its visible faces and road wheels.

    The link stripe has a period of EIGHT voxels along the run — four voxels
    riding the top face, four on the bottom — and `phase` advances it by four,
    which is one whole board texel of travel in the direction the tread runs.
    The period-2 checker this replaces was exactly Nyquist at the board's 4:1
    sample: pose B inverted every link and the tread flickered in place with
    no direction at all. A stripe four voxels long survives the sample and its
    half-period step reads as the track walking.

    The road wheels no longer take the phase. A hub is bolted to the hull, so
    translating it along the run was the one thing on the model that said the
    chassis had driven off rather than the tread having crept.
    """
    m.box(x0, x1, y0, y1, 0, z1, "track")
    # link texture: a four-on/four-off stripe along the outer (+x) face, and
    # the same stripe wrapping the front (+y) face, mirrored because the run
    # turns the corner there
    for y in range(y0, y1 + 1):
        m.set(x1, y, z1 if (y - y0 + 4 * phase) % 8 < 4 else 0, "track_lt")
    for x in range(x0, x1 + 1):
        m.set(x, y1, z1 if (x1 - x + 4 * phase) % 8 < 4 else 0, "track_lt")
    # road wheel hubs peeking out of the lower run
    for y in range(y0 + 1, y1, 3):
        m.set(x1, y, 0, "hub")


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
#   this 14-degree tick, L1 6        4      0.88     0.87       28       30
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
Blade = tuple[tuple[int, int], ...]

_BLADE_A: Blade = ((1, 0), (2, 0), (3, 0), (4, 0), (5, 0))
_BLADE_B: Blade = ((1, 0), (2, 0), (3, 1), (4, 1), (5, 1))


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
    over the sweep. `clipped` takes the tip off the two arms that run along
    y — the tandem's discs would meet over the hold otherwise — and it is a
    property of the AIRCRAFT, so both poses of a disc are clipped alike and
    the tick stays the only difference between them."""
    arms = _quarters(blade)
    if clipped:
        arms = tuple(arm[:-1] if i % 2 else arm for i, arm in enumerate(arms))
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
    """One wheel: dark tire block with a hub dot on the outer face."""
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


# ---------------------------------------------------------------------------
# land
# ---------------------------------------------------------------------------


def infantry(pose: Pose = Pose.A) -> Model:
    """Rifleman: a full stride under a fatigue torso, a lit shoulder line, a
    helmeted head notched well inside that line, and a short dark rifle held
    at low ready across the chest — two hands on it, muzzle breaking the
    silhouette to the right and tipped a voxel down, the opposite corner from
    the mech's tube.

    Everything here is sized for the board, where the 64px cell is sampled
    4:1 and the man is worth some 8x12 logical pixels. The 2026-08-23 reading
    of the model this replaces was the sheet's smallest and dimmest land
    unit — 516 opaque pixels in a 28x29 box, 4.7% of them above L200, twelve
    voxels tall against the mech's seventeen, and a 6x8 smudge once halved
    twice. It is 683 in 30x37 now, at 9.5% above L200, which is 40-46 logical
    pixels on the board against 35-38 before.

    Three of those pixels are what makes it a FIGURE rather than a mass, and
    each is authored against the halving:

    - the boots stand two voxels apart on both axes, so sky survives between
      the legs at all four sampling phases (it survived at three before, and
      the legs fused into a plinth at the fourth);
    - the head is four source pixels inside the shoulder line on the near
      side and six on the far one, with one shadow-slot neck row between the
      two, so the neck reads as a step instead of head and body sharing one
      unbroken field of livery;
    - the face is skin on the camera-facing plane INSIDE the helmet's own
      z-range, three source rows of it and the largest neutral patch on the
      man — 59% of his skin, against the two hands' 41%. The old skin box sat
      below the helmet, on the chest, and read as a sash.

    The shoulders take the top slot on their two camera-facing edges only —
    a lit LINE, not a lit table — and the faction top slot it shares with the
    helmet crest holds 62% of the sprite's mass above L200 against the
    weapon's 34%, so the lit team colour still out-keys the rifle and the
    pure body slot stays an accent on the helmet.

    The rifle runs along the (+x, -y) world diagonal, which this projection
    maps to an exactly HORIZONTAL screen row, so it comes out as a bar rather
    than the 45° stair of mid-greys a z-climbing barrel leaves: three to six
    contiguous gunmetal logical pixels at every phase, against one before the
    2026-08-23 remass. Grip, magazine and handguard hang a voxel under the
    receiver and barrel, which is also what gives the bar a second solid
    screen row — with one row of cubes the board lands on the dotted top face
    at one phase in four. It is kept dark on purpose: an earlier draft ran a
    bright `steel` bar out past the man and became the widest, lightest thing
    on the sprite, out-shouting the faction colour on every row (A/B panel,
    2026-08-15). Only the receiver takes the lighter `gunmetal` step, and
    handguard, under-barrel and muzzle are `bore`, so the weapon darkens
    toward the muzzle and the brightest pixel on the man is his face, not his
    rifle — it was the rifle before this pass.

    How it is HELD is the 2026-08-23 follow-up. The bar used to butt straight
    into the shoulder line at z=11 with two skin voxels tucked under it: no
    arm went anywhere near it, both hands were occluded by the gun cubes
    above them, and the weapon read as a grey bracket bolted to the chest.
    The line is laid one voxel clear of the torso in y now, so it draws IN
    FRONT of the man rather than out of him, and three things hold it:

    - the near arm stops at z=9 and the receiver sits on its wrist, so the
      arm ends ON the weapon instead of running past it down the flank;
    - a shadow-slot cuff over the rear hand at the grip, which is also what
      keeps that hand's lit top plane off the sprite — with it bare, the
      hands outweighed the face and the skin drifted off the head;
    - a livery sleeve along the handguard between the two hands, laid on the
      same screen-horizontal diagonal two pixels under the bar, so a band of
      team colour visibly crosses the gun and the skin lands at each end of
      it where a hand belongs.

    Those three sit BELOW the bar's two solid gunmetal rows on purpose. An
    earlier draft put the sleeve and hands one screen row higher, where they
    ate the bottom of the bar, and the 4:1 sample lost the weapon entirely at
    two phases in sixteen.

    Pose A is byte-frozen; pose B leans the whole upper body one board texel
    over planted boots — 12 changed silhouette texels at rung 1 against the
    2 the old rifle-only settle scored. See the branch below for why the lean
    is diagonal rather than a drop.
    """
    m = Model()
    # Full stride: the boots are two voxels apart on BOTH axes, which opens a
    # wedge of sky wide enough to survive the 4:1 board sample at every phase
    # — at one voxel the legs fused into a plinth on half of them.
    m.box(2, 3, 5, 7, 0, 0, "tire")  # forward boot, planted
    m.box(5, 6, 1, 3, 0, 0, "tire")  # trailing boot
    m.box(2, 3, 5, 6, 1, 5, "hull_dk")  # forward leg
    m.box(5, 6, 2, 3, 1, 5, "hull_dk")  # trailing leg
    # belt line bridging the stride
    m.box(2, 6, 2, 6, 6, 6, "hull_dk")
    # plain fatigue torso — the mech wears the plated chest, not the rifleman
    m.box(2, 6, 2, 6, 7, 11, "hull")
    # backpack riding high on the shoulders
    m.box(3, 5, 2, 2, 7, 11, "body_dk")
    # far arm hanging at the flank; the near arm stops at the elbow, where
    # the rifle's receiver comes to rest on its wrist
    m.box(1, 1, 3, 6, 7, 11, "hull_dk")
    m.box(7, 7, 3, 6, 9, 11, "hull")
    # The lit shoulder LINE, not a lit shoulder table: only the outer edges of
    # the shoulder plane take the top slot. Lighting the whole plane made a
    # bright slab the eye read as a table the head was standing on.
    m.box(1, 7, 6, 6, 11, 11, "hull_lt")
    m.box(7, 7, 3, 6, 11, 11, "hull_lt")
    m.box(1, 1, 3, 6, 11, 11, "hull_lt")
    # Rifle at low ready, laid a voxel clear of the torso in y so it draws in
    # front of the chest: butt over the near shoulder, receiver resting on
    # the near arm's wrist, barrel out past the silhouette and stepping a
    # voxel down at the muzzle. Only the receiver takes the lighter
    # `gunmetal` step; the barrel's underside goes to `bore`.
    m.set(6, 8, 11, "gunmetal_dk")  # butt, over the near shoulder
    m.set(7, 7, 11, "gunmetal_dk")  # receiver, on the near wrist
    m.set(8, 6, 11, "gunmetal")  # the one lit step on the weapon
    m.set(9, 5, 11, "gunmetal_dk")  # barrel
    m.set(10, 4, 11, "gunmetal_dk")  # barrel
    m.set(11, 3, 10, "bore")  # muzzle, tipped a voxel down
    m.set(7, 7, 10, "gunmetal_dk")  # pistol grip
    m.set(8, 6, 10, "gunmetal_dk")  # magazine
    m.set(9, 5, 10, "bore")  # handguard
    m.set(10, 4, 10, "bore")  # under-barrel
    # The hold: a cuff and the rear hand at the grip, then a livery sleeve
    # along the handguard to the forward hand — one screen row clear of the
    # bar's two gunmetal rows, so the sample never loses the weapon.
    m.set(7, 8, 10, "hull_dk")  # cuff over the rear hand
    m.set(7, 8, 9, "skin")  # rear hand on the grip
    m.set(8, 7, 9, "hull")  # forward sleeve crossing the gun
    m.set(9, 6, 9, "hull")  # forward sleeve
    m.set(10, 5, 9, "skin")  # forward hand on the handguard
    # Neck: one shadow-slot row between the shoulder line and the skull, and
    # narrow, so the shoulder plane stays open around it. That dark step is
    # what stops head and body reading as a single field of livery.
    m.box(4, 5, 5, 6, 12, 12, "hull_dk")
    # head, inset from the shoulder line on both sides, with the open face on
    # the camera-facing plane
    m.box(3, 5, 4, 5, 13, 14, "hull_dk")  # skull and cheek guards
    m.box(3, 5, 6, 6, 13, 14, "skin")  # face
    # helmet: one octagonal shell overhanging the skull, still four source
    # pixels inside the shoulder line on the near side and six on the far
    # one, and a pure team crest along its front edge — the accent, not the
    # sprite's brightest plane
    m.box(2, 6, 4, 6, 15, 15, "hull_dk")
    m.chamfer(2, 6, 4, 6, 15, 15)
    m.box(3, 5, 6, 6, 16, 16, "body")  # crest
    if pose is Pose.B:
        # The beat is the man shifting his weight, and it is a WHOLE board
        # texel. Everything from the belt line up — torso, both arms, the
        # shoulder line, backpack, neck, head, helmet, crest, and the whole
        # rifle line with both hands still on it — takes one `(dx +1, dy -1)`
        # diagonal step while the boots and legs stay planted, which carries
        # the weight back over the trailing boot: the figure leans as one
        # body and the weapon travels with the shoulders rather than waggling
        # on its own.
        #
        # The lean is along the diagonal rather than down the z axis on
        # purpose. A `dz = -2` compression of the same assembly is the same
        # one texel, but it costs the man his height and his mass: measured
        # 33 px tall and 619 opaque against pose A's 37 and 683, which is
        # under this sprite's own floor (`tests/test_infantry_read.py`
        # MIN_HEIGHT 34, MIN_PIXELS 640). The diagonal step moves the same
        # texel for free — 689 opaque in the same 37 px box.
        #
        # Rung-1 silhouette texels, pose A against pose B: 2 before (the old
        # rifle-only one-voxel settle, half a texel and inside the shape),
        # 12 now; rung 2 goes 8 -> 45 (`tests/measure_motion.py`).
        _shift(m, (1, 11, 2, 8, 6, 16), dx=1, dy=-1)
    return m


def mech(pose: Pose = Pose.A) -> Model:
    """Rocket trooper: planted wide stance, heavy pauldrons over a bulky
    torso, and a fat launch tube climbing forward over the left shoulder —
    taller, wider and squarer than the rifleman's stride (rocket).

    Pose B leans the loaded tube in a whole board texel: the left pauldron
    and everything it carries ride `dz = -2`, measured at 7 changed
    silhouette texels at rung 1 against the 2 the old one-voxel settle
    scored."""
    m = Model()
    # wide planted stance, two-voxel-thick armoured legs
    for x0 in (1, 6):
        m.box(x0, x0 + 1, 4, 6, 0, 0, "tire")
        m.box(x0, x0 + 1, 4, 6, 1, 2, "hull")
        m.box(x0, x0 + 1, 4, 6, 3, 3, "hull_dk")  # knee plates
    # belt line bridging the stance
    m.box(1, 7, 4, 6, 4, 4, "hull_dk")
    # bulky torso with a light chest plate
    m.box(1, 7, 3, 6, 5, 8, "hull")
    m.box(2, 6, 6, 6, 6, 8, "hull_lt")
    # ammo backpack with two spare-rocket tips
    m.box(2, 6, 2, 2, 5, 8, "hull_dk")
    m.set(3, 2, 9, "steel")
    m.set(5, 2, 9, "steel")
    # pauldrons — the pure team accents
    m.box(0, 0, 3, 6, 7, 9, "body")
    m.box(8, 8, 3, 6, 7, 9, "body")
    # big helmet with a glass visor band across the face
    m.box(3, 5, 4, 6, 9, 9, "skin")
    m.box(3, 5, 6, 6, 10, 10, "glass")
    m.box(3, 5, 3, 5, 10, 10, "hull")
    m.box(2, 6, 3, 6, 11, 12, "hull")
    for cx, cy in ((2, 3), (2, 6), (6, 3), (6, 6)):
        m.unset(cx, cy, 12)  # round the dome
    # fat launch tube seated on the left pauldron, climbing forward past the
    # helmet crown, venturi exhaust hanging off the back
    m.box(0, 1, 2, 2, 9, 10, "bore")  # exhaust
    for i in range(5):
        m.box(0, 1, 3 + i, 3 + i, 10 + i, 11 + i, "gunmetal")
    m.box(0, 1, 8, 8, 15, 16, "gunmetal_dk")  # muzzle ring
    m.set(0, 9, 16, "amber")  # loaded warhead tip
    m.set(1, 9, 16, "amber")
    m.box(1, 1, 5, 5, 9, 11, "hull")  # supporting arm
    if pose is Pose.B:
        # The loaded tube leans in and the left shoulder takes its weight,
        # for a WHOLE board texel: pauldron first, then exhaust, tube, muzzle
        # ring, warhead tips and the supporting arm, all `dz = -2` together —
        # the pauldron leads so the launcher lands back on it rather than
        # through it. The one-voxel settle this replaces was half a texel and
        # stayed inside the shape: 2 changed silhouette texels at rung 1
        # against 7 now, 15 -> 29 at rung 2 (`tests/measure_motion.py`).
        _shift(m, (0, 0, 3, 6, 7, 8), dz=-2)  # left pauldron
        _shift(m, (0, 1, 2, 9, 9, 16), dz=-2)  # launcher, arm, pauldron top
    return m


def recon(pose: Pose = Pose.A) -> Model:
    """Scout car: four wheels, sloped hood, roof MG, whip antenna.

    Pose B traverses the pintle MG and the whip antenna one `(dx +1, dy -1)`
    step each — one whole board texel across the screen, the gunner sweeping
    his arc while the car idles. What it replaces was the whole cabin settling
    one voxel, which is half a texel and measured 3 changed silhouette texels
    at rung 1, all of them boundary flicker. Settling the cabin the two voxels
    a texel actually costs was tried first and is not available: the cabin is
    two voxels tall over a bed two voxels tall, so a texel of settle buries
    the roofline in the hull and the scout reads as a flatbed. The traverse
    measures 4 changed silhouette texels at rung 1, 13 at rung 2.
    """
    m = Model()
    for x in (0, 8):
        _tire(m, x, 2)
        _tire(m, x, 10)
    # hull bed in desaturated armour; a roof stripe carries the team color
    m.box(1, 8, 0, 13, 2, 3, "hull")
    # sloped hood toward the front
    m.box(1, 8, 14, 14, 2, 2, "hull")
    m.box(2, 7, 14, 15, 2, 2, "hull_lt")
    m.box(2, 7, 12, 13, 3, 3, "hull_lt")  # hood top
    # bumper and headlights
    m.box(1, 8, 15, 15, 2, 2, "hull_dk")
    m.set(2, 15, 2, "amber")
    m.set(7, 15, 2, "amber")
    # livery cabin with windshield and side glass, rounded roofline; a pure
    # team stripe survives on the roof front
    m.box(2, 7, 3, 9, 4, 4, "hull")
    m.box(2, 7, 3, 9, 5, 5, "hull")
    m.box(3, 5, 8, 8, 5, 5, "body")
    m.chamfer(2, 7, 3, 9, 5, 5)
    m.box(3, 6, 9, 9, 4, 5, "glass")
    m.box(7, 7, 4, 7, 4, 4, "glass_dk")
    m.box(2, 7, 3, 3, 4, 4, "hull_dk")  # rear cabin plate
    # pintle MG on a rear roof ring mount (small_arms)
    m.box(4, 5, 4, 5, 6, 6, "gunmetal_dk")
    m.box(4, 4, 5, 5, 7, 7, "gunmetal_dk")
    m.box(4, 4, 6, 9, 7, 7, "gunmetal")
    m.set(4, 10, 7, "bore")
    # spare tire on the tail
    m.box(3, 6, 0, 0, 3, 4, "tire")
    m.set(4, 0, 3, "hub")
    # antenna
    m.box(2, 2, 1, 1, 4, 7, "hull")
    if pose is Pose.B:
        # the gunner traverses: pintle mount, barrel and muzzle swing one
        # diagonal step across the cabin roof, and the whip steps with them,
        # both staying inside the hull's own x/y extents
        _shift(m, (4, 5, 4, 10, 6, 7), dx=1, dy=-1)
        _shift(m, (2, 2, 1, 1, 4, 7), dx=1, dy=-1)
    return m


def tank(pose: Pose = Pose.A) -> Model:
    """MBT: deep-chested — tall running gear, a turret raised on a full ring,
    hull-hugging long gun (cannon).

    Pose B lays the gun up: mantlet, barrel, evacuator and muzzle brake all
    take `dz = +4` together, and the mantlet grows down to the deck so the
    gun stays carried. Two board texels, not the one texel the heavy tank's
    gun moves, because this barrel is two voxels wide against the heavy's
    three: a one-texel lay measured 2 changed silhouette texels at rung 1,
    under the 3 an idle needs to be seen at all, and 5 at two: 5 changed
    silhouette texels at rung 1, 26 at rung 2. The tread walks its link
    stripe a half period under it, and the hull's x/y extents are untouched,
    so the footprint and the cast shadow are unchanged.
    """
    m = Model()
    _track(m, 0, 2, 0, 13, 2, phase=pose)
    _track(m, 9, 11, 0, 13, 2, phase=pose)
    # hull in desaturated armour; the turret crown carries the team color
    m.box(0, 11, 1, 12, 3, 5, "hull")
    m.box(1, 10, 13, 13, 3, 5, "hull")
    m.box(2, 9, 14, 14, 3, 4, "hull_lt")  # glacis lip
    m.box(2, 9, 13, 13, 5, 5, "hull_lt")  # glacis top
    # rear deck vents and exhausts
    m.box(2, 9, 1, 1, 5, 5, "hull_dk")
    m.box(2, 9, 3, 3, 5, 5, "hull_dk")
    m.box(0, 1, 0, 0, 3, 5, "hull_dk")
    # turret on a full armour ring under a team crown — the mass the cell's
    # headroom is for, so the barrel line rides high over the deck
    m.box(3, 8, 4, 9, 6, 7, "hull")
    m.chamfer(3, 8, 4, 9, 6, 7)
    m.box(4, 7, 5, 8, 8, 9, "body")
    m.chamfer(4, 7, 5, 8, 8, 9)
    m.box(4, 5, 5, 6, 10, 10, "body_dk")  # commander cupola
    m.set(6, 8, 8, "body_lt")  # loader hatch glint
    m.box(4, 7, 4, 4, 8, 8, "hull_dk")  # stowage bustle
    # mantlet and a gun grown two voxels — the unmistakable barrel line
    m.box(4, 7, 10, 10, 6, 7, "hull_dk")
    m.box(5, 6, 10, 19, 7, 7, "gunmetal")
    m.box(5, 6, 14, 14, 7, 7, "gunmetal_dk")  # bore evacuator
    m.box(4, 7, 19, 19, 7, 7, "gunmetal_dk")  # muzzle brake
    m.box(5, 6, 20, 20, 7, 7, "bore")
    if pose is Pose.B:
        # the gun lays up two texels, mantlet and all, and the mantlet is
        # rebuilt down to the deck as the mount that holds it there
        _shift(m, (4, 7, 10, 20, 6, 7), dz=4)
        m.box(4, 7, 10, 10, 6, 9, "hull_dk")
    return m


def md_tank(pose: Pose = Pose.A) -> Model:
    """Heavy tank: wider, taller, skirted tracks, long heavy gun (cannon).
    The tallest thing the land roster puts on a tile.

    Pose B lays the heavy gun up one board texel, as the MBT does: the wide
    mantlet, the sleeved barrel and the muzzle brake take `dz = +2` off a
    turret that stays where it was. One texel is enough here because this
    barrel is three voxels wide — 6 changed silhouette texels at rung 1, 20
    at rung 2, where the MBT's thinner gun needed two.
    """
    m = Model()
    _track(m, 0, 2, 0, 15, 3, phase=pose)
    _track(m, 10, 12, 0, 15, 3, phase=pose)
    # hull with armoured side skirts over the tracks
    m.box(0, 12, 1, 14, 4, 6, "hull")
    m.box(10, 12, 2, 13, 4, 5, "hull_dk")
    m.box(0, 2, 2, 13, 4, 5, "hull_dk")
    # stepped heavy glacis
    m.box(1, 11, 15, 15, 4, 6, "hull")
    m.box(2, 10, 16, 16, 4, 5, "hull_lt")
    m.box(2, 10, 15, 15, 6, 6, "hull_lt")
    # rear engine deck and twin exhausts
    m.box(2, 10, 1, 2, 6, 6, "hull_dk")
    m.box(1, 2, 0, 0, 4, 6, "hull_dk")
    m.box(10, 11, 0, 0, 4, 6, "hull_dk")
    # big turret, two deep tiers: armour ring, rounded crown; the cupola and
    # hatch carry the team color
    m.box(3, 9, 4, 11, 7, 9, "hull")
    m.chamfer(3, 9, 4, 11, 7, 9)
    m.box(4, 8, 5, 10, 10, 11, "hull")
    m.chamfer(4, 8, 5, 10, 10, 11)
    m.box(4, 8, 4, 4, 10, 11, "hull_dk")  # bustle rack
    m.box(4, 5, 5, 6, 12, 12, "body_dk")  # cupola
    m.box(6, 7, 6, 7, 12, 12, "body")  # hatch
    # wide mantlet, longer gun with thermal-sleeve rings
    m.box(4, 8, 12, 12, 7, 11, "hull_dk")
    m.box(5, 7, 13, 19, 10, 10, "gunmetal")
    m.box(5, 7, 15, 15, 10, 10, "gunmetal_dk")
    m.box(5, 7, 17, 17, 10, 10, "gunmetal_dk")
    m.box(4, 8, 20, 20, 10, 10, "gunmetal_dk")  # muzzle brake
    m.box(5, 7, 21, 21, 10, 10, "bore")
    if pose is Pose.B:
        _shift(m, (4, 8, 12, 21, 7, 11), dz=2)
    return m


def anti_air(pose: Pose = Pose.A) -> Model:
    """Tracked flak: twin long barrels raked past 60 degrees over the battery
    box — the howitzer's climb, paired and thin — plus a search radar.

    Pose B walks both barrel runs up one board texel (`dz = +2`) on a cradle
    that grows the two voxels with them, so the battery tracks a target and
    the raked lines — the identity — are what the player sees move: 8 changed
    silhouette texels at rung 1, 31 at rung 2.
    """
    m = Model()
    _track(m, 0, 2, 0, 11, phase=pose)
    _track(m, 8, 10, 0, 11, phase=pose)
    # low hull in desaturated armour
    m.box(0, 10, 1, 11, 2, 3, "hull")
    m.box(1, 9, 12, 12, 2, 3, "hull_lt")
    m.box(2, 8, 1, 1, 3, 3, "hull_dk")
    # rotating battery box in livery armour; its base band and a roof panel
    # carry the team color
    m.box(2, 8, 3, 8, 4, 6, "hull")
    m.chamfer(2, 8, 3, 8, 6, 6)
    m.box(3, 7, 4, 5, 6, 6, "body")  # roof panel
    m.box(2, 8, 3, 8, 4, 4, "body_dk")
    m.box(3, 7, 3, 3, 5, 6, "hull_dk")  # ammo feed
    # elevating mount at the battery front: livery pedestal, gunmetal cradle
    m.box(4, 6, 6, 8, 6, 7, "hull")
    m.set(5, 7, 8, "amber")  # ranging light
    # twin long barrels climbing two z per tile like the howitzer, but
    # paired and one voxel thin — the raked lines ARE the identity
    for x in (3, 7):
        m.box(x, x, 8, 8, 6, 7, "gunmetal_dk")  # trunnion
        for i in range(5):
            m.box(x, x, 9 + i, 9 + i, 8 + 2 * i, 9 + 2 * i, "gunmetal")
        m.set(x, 14, 17, "gunmetal_dk")  # muzzle
        m.set(x, 14, 18, "bore")
    # search radar dish on a rear mast, big enough to read at map scale
    m.box(8, 8, 4, 4, 7, 8, "hull")
    m.box(7, 8, 3, 5, 9, 9, "hull_lt")
    m.box(7, 8, 4, 4, 10, 10, "hull_lt")
    m.set(8, 4, 9, "gunmetal_dk")
    if pose is Pose.B:
        # both runs elevate a texel; the trunnion column grows the two voxels
        # under them so the barrels stay carried instead of floating off the
        # cradle. The box is per-barrel so the battery roof between them, and
        # the pedestal it sits on, are left alone.
        for x in (3, 7):
            _shift(m, (x, x, 9, 14, 8, 18), dz=2)
            m.box(x, x, 8, 8, 8, 9, "gunmetal_dk")
    return m


def artillery(pose: Pose = Pose.A) -> Model:
    """SPG: open casemate, howitzer erected past 60 degrees, recoil spade.

    Pose B is the recoil stroke: trunnion pedestal, sleeved barrel and muzzle
    brake ride `dz = -2` back down into the pit — one board texel, so the
    spike visibly shortens against the casemate wall instead of shimmering
    inside it — 7 changed silhouette texels at rung 1, 30 at rung 2. The
    walls, the spade and the hull hold their ground, which is what makes it a
    gun firing rather than a vehicle sinking.
    """
    m = Model()
    _track(m, 0, 2, 0, 12, 2, phase=pose)
    _track(m, 8, 10, 0, 12, 2, phase=pose)
    m.box(0, 10, 1, 12, 3, 4, "hull")
    m.box(1, 9, 13, 13, 3, 3, "hull_lt")
    # open casemate: a deep armoured wall ring around the gun pit, no roof;
    # the team color caps the walls
    m.box(1, 9, 2, 8, 5, 7, "hull")
    m.clear(2, 8, 3, 7, 5, 7)
    m.box(1, 1, 2, 8, 7, 7, "body_dk")  # wall caps
    m.box(9, 9, 2, 8, 7, 7, "body_dk")
    m.box(1, 9, 2, 2, 7, 7, "body")
    m.box(2, 8, 8, 8, 7, 7, "body")
    m.box(2, 8, 3, 7, 4, 4, "hull_dk")  # pit floor
    # howitzer erected steeply out of the pit: the rising spike no other
    # land unit carries — two z per y, well clear of the hull mass, and one
    # step longer than the tile is tall; the lower barrel wears a livery
    # recoil sleeve, the muzzle stays steel
    m.box(4, 6, 4, 6, 5, 7, "hull_dk")  # trunnion pedestal
    for i in range(7):
        paint = "hull_dk" if i < 2 else "gunmetal"
        m.box(4, 6, 6 + i, 6 + i, 8 + 2 * i, 9 + 2 * i, paint)
    m.box(3, 7, 13, 13, 21, 21, "gunmetal_dk")  # muzzle brake
    m.box(4, 6, 13, 13, 22, 22, "bore")
    # recoil spade dug in at the rear
    m.box(3, 7, 0, 0, 2, 4, "hull_dk")  # spade arms
    m.box(2, 8, -1, -1, 1, 3, "hull")  # blade
    if pose is Pose.B:
        # the howitzer recoils one texel into the pit, pedestal and all. Two
        # boxes, not one: the casemate's front wall stands at y=8 inside the
        # gun's own x span, and it is the thing the barrel recoils PAST.
        _shift(m, (4, 6, 4, 6, 5, 7), dz=-2)  # trunnion pedestal
        _shift(m, (3, 7, 6, 13, 8, 22), dz=-2)  # barrel, brake and muzzle
    return m


def rockets(pose: Pose = Pose.A) -> Model:
    """Wheeled MLRS: long eight-wheel carrier, low cab, one wide flat rack
    pitched up over the tail — a tilted plane, never a turret.

    Pose B pitches the rack: the whole tube slab rides `dz = +2` on a launch
    frame that grows the same two voxels, one board texel of elevation on the
    biggest plane the unit owns, and the loudest idle on the land roster at
    11 changed silhouette texels at rung 1 and 43 at rung 2. The cab settle
    it replaces was one voxel — half a texel, and hidden under the rack
    besides — which is why the truck measured zero at both board rungs.
    """
    m = Model()
    for y in (1, 5, 9, 13):
        _tire(m, 0, y)
        _tire(m, 8, y)
    # long chassis bed
    m.box(1, 8, 0, 16, 2, 3, "hull")
    # low cab tucked at the front, one voxel of glass and a team roof patch
    m.box(2, 7, 13, 16, 4, 4, "hull")
    m.box(3, 6, 14, 15, 5, 5, "body")
    m.box(3, 6, 16, 16, 4, 4, "glass")
    m.box(7, 7, 14, 15, 4, 4, "glass_dk")
    m.box(2, 7, 17, 17, 2, 3, "hull_dk")  # bumper
    m.set(3, 17, 3, "amber")
    m.set(6, 17, 3, "amber")
    # the launcher: one full-width rectangular slab pitched up toward the
    # rear at the howitzer's own two z per tile, dark like a sealed tube pod;
    # mouths open on the high end, which clears the tile the carrier stands on
    for k in range(6):
        y0 = 11 - 2 * k
        m.box(1, 8, y0, y0 + 1, 4 + 2 * k, 5 + 2 * k, "hull_dk")
        m.set(1, y0, 5 + 2 * k, "body_dk")  # livery rail down the pod edge
        m.set(8, y0, 5 + 2 * k, "body_dk")
    for x in (2, 4, 6):
        m.set(x, 1, 15, "bore")
        m.set(x, 2, 15, "bore")
    # solid launch-frame wall carrying the slab's high end
    m.box(2, 7, 1, 2, 4, 13, "hull_dk")
    if pose is Pose.B:
        # the rack pitches up a texel: each slab row moves on its own y band,
        # which is what keeps the launch-frame wall — the same y as the slab's
        # high end, two voxels lower — out of the moved box. The frame then
        # grows the two voxels it has to, so the high end stays carried.
        for k in range(6):
            y0 = 11 - 2 * k
            _shift(m, (1, 8, y0, y0 + 1, 4 + 2 * k, 5 + 2 * k), dz=2)
        m.box(2, 7, 1, 2, 14, 15, "hull_dk")
    return m


def apc(pose: Pose = Pose.A) -> Model:
    """Tracked transport: the tall box — high flat-topped troop compartment
    over a sloped glacis, no turret at all — unarmed.

    Pose B dips the nose: glacis, bumper, visor and headlights ride `dz = -2`
    while the box behind them holds still, the transport nodding on its
    torsion bars as the engine loads. It is the one thing on this unit a
    board texel of movement can be SEEN on, and it is the roster's quietest
    beat even so: 3 changed silhouette texels at rung 1, 15 at rung 2. The
    transport carries no turret and no gun, and everything else it owns is
    interior to its own outline — this projection buries a roof detail under
    the roof's far edge unless it climbs more than its distance from that
    edge, so the open troop hatch tried first changed zero silhouette texels
    at either rung, and the comms whip, two pixels wide, changed six pixels
    and no whole texel.
    """
    m = Model()
    _track(m, 0, 2, 0, 12, phase=pose)
    _track(m, 7, 9, 0, 12, phase=pose)
    # tall narrow slab hull: the highest solid mass on the land roster,
    # a track narrower than the gun tanks so the box reads upright
    m.box(0, 9, 1, 12, 2, 6, "hull")
    m.box(1, 8, 2, 12, 7, 7, "hull")  # inset roof, dead-flat top line
    # sloped glacis nose stepping down to the bumper; the team stripe
    # across it keeps a pure accent on an unshaded face
    m.box(1, 8, 13, 13, 2, 5, "hull")
    m.box(2, 7, 13, 13, 5, 5, "hull_lt")
    m.box(3, 6, 13, 13, 5, 5, "body")
    m.box(2, 7, 14, 14, 2, 3, "hull_lt")
    # driver visor slit and headlights
    m.box(3, 5, 14, 14, 3, 3, "glass_dk")
    m.set(2, 14, 3, "amber")
    m.set(7, 14, 3, "amber")
    # livery roof: a broad team panel and hatch pair, painted flush so the
    # top stays a slab
    m.box(2, 7, 4, 10, 7, 7, "body")
    m.box(3, 4, 8, 9, 7, 7, "body_dk")  # troop hatches
    m.box(5, 6, 8, 9, 7, 7, "body_dk")
    m.box(0, 0, 2, 11, 4, 4, "hull_dk")  # side stowage rail
    m.box(9, 9, 2, 11, 4, 4, "hull_dk")
    # rear troop door, full height
    m.box(3, 6, 0, 0, 2, 6, "hull_dk")
    m.set(5, 0, 4, "steel")  # door handle
    # tall comms whip — the APC keeps one; the gun tanks lost theirs
    m.box(8, 8, 3, 3, 8, 9, "hull_lt")
    m.set(8, 3, 10, "amber")
    if pose is Pose.B:
        _shift(m, (1, 8, 13, 14, 2, 5), dz=-2)
    return m


def missiles(pose: Pose = Pose.A) -> Model:
    """Wheeled SAM battery: two big rounds erected near-vertical over the
    tail — thin steep spikes with daylight between — plus a radar dish.

    Pose B runs both rounds one board texel up the rail (`dz = +2`), seeker
    tips and all, so the two spikes — the identity — are what moves: 10
    changed silhouette texels at rung 1, 35 at rung 2. The cab
    settle it replaces was one voxel of a four-wheel chassis, half a texel:
    zero changed silhouette texels at rung 1 and 3 at rung 2, all of them
    boundary flicker.
    """
    m = Model()
    for y in (1, 8):
        _tire(m, 0, y)
        _tire(m, 8, y)
    # short four-wheel erector chassis
    m.box(1, 8, 0, 11, 2, 3, "hull")
    # livery cab forward, rounded roofline with a pure team patch
    m.box(2, 7, 8, 11, 4, 4, "hull")
    m.box(2, 7, 8, 11, 5, 5, "hull")
    m.box(3, 5, 10, 10, 5, 5, "body")
    m.chamfer(2, 7, 8, 11, 5, 5)
    m.box(3, 6, 11, 11, 4, 5, "glass")
    m.box(7, 7, 9, 10, 4, 4, "glass_dk")
    m.box(2, 7, 12, 12, 2, 3, "hull_dk")
    m.set(3, 12, 3, "amber")
    m.set(6, 12, 3, "amber")
    # erector pedestal over the tail axle
    m.box(2, 7, 1, 4, 4, 5, "hull_dk")
    m.box(2, 7, 1, 1, 6, 7, "hull_dk")  # raised launch-rail shoe
    # two fat rounds climbing two z per y — steep solid spikes, a clear
    # sky gap between them where the rockets truck is one joined slab;
    # livery booster sleeves and a pure team band under white warheads
    for x0 in (2, 6):
        for i in range(5):
            paint = ("hull", "hull", "body", "white", "white")[i]
            m.box(x0, x0 + 1, 3 + i, 4 + i, 5 + 2 * i, 7 + 2 * i, paint)
        m.set(x0, 9, 16, "amber")  # seeker tips
        m.set(x0 + 1, 9, 16, "amber")
    # fire-control dish on a rear mast, plate tilted up at the sky
    m.box(4, 5, 0, 1, 4, 6, "hull")
    m.box(3, 6, 0, 0, 7, 8, "hull_lt")
    m.box(3, 6, 1, 1, 9, 9, "hull_lt")
    m.set(4, 0, 9, "gunmetal_dk")
    m.set(5, 0, 9, "gunmetal_dk")
    if pose is Pose.B:
        # both rounds run a texel up the rail. The pedestal is repainted
        # because their seated tails were sitting in its top course, and each
        # round's own rail grows the two voxels under it, per round, so the
        # daylight gap between the two spikes stays open
        m.box(2, 7, 1, 4, 4, 5, "hull_dk")
        for x0 in (2, 6):
            _shift(m, (x0, x0 + 1, 3, 9, 5, 16), dz=2)
            m.box(x0, x0 + 1, 3, 4, 5, 6, "hull_dk")
    return m


# ---------------------------------------------------------------------------
# air
# ---------------------------------------------------------------------------


def fighter(pose: Pose = Pose.A) -> Model:
    """Swept-wing air-superiority jet (autocannon)."""
    m = Model()
    # fuselage in desaturated airframe grey, nose toward +y
    m.box(4, 5, 0, 17, 3, 4, "hull")
    m.box(4, 5, 16, 18, 3, 3, "hull")
    m.set(4, 19, 3, "hull_dk")  # radome tip
    m.set(5, 19, 3, "hull_dk")
    # canopy
    m.box(4, 5, 11, 13, 5, 5, "glass")
    m.set(4, 10, 5, "glass_dk")
    m.set(5, 10, 5, "glass_dk")
    # air intakes
    m.box(3, 3, 8, 11, 3, 4, "hull_dk")
    m.box(6, 6, 8, 11, 3, 4, "hull_dk")
    # swept wings in hull livery (the mass the player reads from above)
    for i in range(1, 7):
        wy = 9 - i
        m.box(4 - i, 4 - i, wy, wy + 4, 3, 3, "hull")
        m.box(5 + i, 5 + i, wy, wy + 4, 3, 3, "hull")
    # wingtip missiles
    m.box(-2, -2, 3, 6, 3, 3, "white")
    m.box(11, 11, 3, 6, 3, 3, "white")
    m.set(-2, 7, 3, "amber")
    m.set(11, 7, 3, "amber")
    # tailplane in livery; the twin canted fins keep the pure team accent
    m.box(2, 7, 0, 2, 3, 3, "hull")
    m.box(3, 3, 0, 1, 4, 6, "body_dk")
    m.box(6, 6, 0, 1, 4, 6, "body_dk")
    # engine nozzles
    m.box(4, 5, 0, 0, 3, 4, "gunmetal_dk")
    m.set(4, -1, 3, "bore")
    m.set(5, -1, 3, "bore")
    return m


def bomber(pose: Pose = Pose.A) -> Model:
    """Heavy strategic bomber: four podded engines, deep fuselage (bomb)."""
    m = Model()
    # deep fuselage in airframe grey; rounded nose
    m.box(4, 7, 0, 19, 3, 5, "hull")
    m.box(4, 7, 18, 19, 3, 4, "hull")
    m.chamfer(4, 7, 0, 19, 5, 5)
    m.box(5, 6, 20, 20, 3, 4, "hull_lt")  # nose cap
    # flight-deck glazing
    m.box(4, 7, 16, 17, 5, 5, "glass")
    # livery straight wings with slight rearward rake; dark trailing edge so
    # the big top surface doesn't read flat, pure team color on the wingtips
    for i in range(1, 9):
        wy = 10 - (i + 1) // 2
        wing = "body" if i == 8 else "hull"
        edge = "body_dk" if i == 8 else "hull_dk"
        m.box(4 - i, 4 - i, wy, wy + 5, 4, 4, wing)
        m.box(7 + i, 7 + i, wy, wy + 5, 4, 4, wing)
        m.set(4 - i, wy, 4, edge)
        m.set(7 + i, wy, 4, edge)
    # four engine pods slung under the wings, mirrored about the fuselage
    # centre; the outer pair sits one step back, following the wing rake
    for x, fwd in ((-3, 0), (-1, 1), (12, 1), (14, 0)):
        m.box(x, x, 9 + fwd, 12 + fwd, 3, 3, "gunmetal")
        m.set(x, 13 + fwd, 3, "bore")
    # bomb-bay doors line on the belly sides
    m.box(7, 7, 6, 12, 3, 3, "hull_dk")
    # tailplane in livery; the tall fin keeps the pure team accent
    m.box(1, 10, 0, 2, 4, 4, "hull")
    m.box(5, 6, 0, 1, 5, 8, "body_dk")
    m.box(5, 6, 2, 2, 5, 6, "body_dk")
    # tail turret hint
    m.box(5, 6, 0, 0, 3, 3, "gunmetal_dk")
    return m


def b_copter(pose: Pose = Pose.A) -> Model:
    """Attack helicopter: chin gun, stub-wing rocket pods, tail rotor.

    Pose B is the same aircraft with the same four blades a tick further
    round (`_BLADE_B`), so alternating the two poses turns the disc rather
    than swapping its shape. Nothing else may differ.
    """
    m = Model()
    # fuselage in hull livery, rounded nose
    m.box(3, 5, 6, 14, 3, 5, "hull")
    m.box(3, 5, 14, 15, 3, 4, "hull")
    m.unset(3, 15, 3)
    m.unset(5, 15, 3)
    m.chamfer(3, 5, 6, 14, 5, 5)
    # tandem canopy
    m.box(3, 5, 13, 14, 5, 5, "glass")
    m.box(3, 5, 11, 12, 6, 6, "glass_dk")
    m.box(3, 5, 10, 10, 6, 6, "body")
    # chin autocannon
    m.box(4, 4, 15, 17, 2, 2, "gunmetal")
    m.set(4, 18, 2, "bore")
    # stub wings with rocket pods
    m.box(1, 2, 9, 11, 4, 4, "hull_dk")
    m.box(6, 7, 9, 11, 4, 4, "hull_dk")
    m.box(1, 1, 9, 12, 3, 3, "hull_dk")
    m.box(7, 7, 9, 12, 3, 3, "hull_dk")
    m.set(1, 13, 3, "bore")
    m.set(7, 13, 3, "bore")
    # tail boom, fin and tail rotor
    m.box(4, 4, 0, 6, 4, 4, "hull")
    m.box(4, 4, 0, 1, 5, 6, "body_dk")
    m.box(5, 5, 0, 0, 5, 7, "rotor")
    m.set(5, 0, 6, "hub")
    # skids
    m.box(2, 2, 8, 14, 1, 1, "hull_dk")
    m.box(6, 6, 8, 14, 1, 1, "hull_dk")
    # main rotor: hub mast + four blades over the fuselage (pose B turns the
    # same four blades a notch; the tail rotor is vertical and stays)
    m.box(4, 4, 10, 10, 7, 8, "hull_dk")
    _rotor(m, 4, 10, 9, _BLADE_A if pose is Pose.A else _BLADE_B)
    return m


def t_copter(pose: Pose = Pose.A) -> Model:
    """Tandem-rotor transport helicopter — unarmed.

    Both discs are clipped along y so they do not meet over the hold, and
    both take pose B's tick together, as on b_copter.
    """
    m = Model()
    # boxy hold in hull livery, rounded top edges so it stops reading as a
    # brick; the roof spine keeps a pure team stripe
    m.box(3, 6, 2, 15, 3, 6, "hull")
    m.chamfer(3, 6, 2, 15, 6, 6)
    m.box(4, 5, 2, 15, 6, 6, "body")
    m.box(3, 6, 15, 16, 3, 5, "hull")
    # cockpit glazing
    m.box(3, 6, 15, 16, 5, 5, "glass")
    m.box(3, 6, 17, 17, 3, 4, "glass_dk")
    # side cargo door and stripe
    m.box(6, 6, 6, 9, 4, 5, "hull_dk")
    m.box(6, 6, 2, 15, 3, 3, "hull_dk")
    # rear loading ramp
    m.box(3, 6, 1, 1, 3, 5, "hull_dk")
    # fixed gear sponsons in dark livery
    m.box(2, 2, 4, 5, 1, 2, "hull_dk")
    m.box(7, 7, 4, 5, 1, 2, "hull_dk")
    m.box(2, 2, 12, 13, 1, 2, "hull_dk")
    m.box(7, 7, 12, 13, 1, 2, "hull_dk")
    # tandem rotor masts and overlapping blades
    m.box(4, 5, 4, 4, 7, 8, "hull_dk")
    m.box(4, 5, 13, 13, 7, 8, "hull_dk")
    # Both discs turn the same blade the same way, so the tandem reads as one
    # machine's two rotors advancing and not as a counter-rotating pair.
    blade = _BLADE_A if pose is Pose.A else _BLADE_B
    _rotor(m, 4, 4, 9, blade, clipped=True)
    _rotor(m, 5, 13, 9, blade, clipped=True)
    return m


# ---------------------------------------------------------------------------
# sea
# ---------------------------------------------------------------------------


def battleship(pose: Pose = Pose.A) -> Model:
    """Dreadnought: the fleet's LONG one — a hull with a clear margin over
    every other keel, turrets fore and aft, midships bridge mast (cannon).

    Pose B lays BOTH main batteries up one board texel (`dz = +2`): 33 changed
    silhouette texels at rung 1 against the bob's own 30, and the gun runs are
    what the extra three are. The batteries at both ends move together, so the
    beat reads along the ship's length, which is the identity.
    """
    m = Model()
    # long low naval-grey hull, tapered bow (+y) and stern; dark waterline.
    # Narrow beam on purpose: length is the identity, so the slab stays
    # 4 wide and spends the whole cell diagonal (sprite width 64, exactly).
    m.box(2, 5, 2, 23, 0, 1, "hull")
    m.box(3, 4, 24, 25, 0, 1, "hull")
    m.box(3, 4, 26, 26, 0, 1, "hull")
    m.box(3, 4, 0, 1, 0, 1, "hull")
    m.box(2, 5, 2, 23, 0, 0, "hull_dk")
    m.box(3, 4, 24, 26, 0, 0, "hull_dk")
    m.box(3, 4, 0, 1, 0, 0, "hull_dk")
    # deck in hull livery; the bow keeps the pure team flash
    m.box(2, 5, 2, 23, 2, 2, "hull")
    m.box(3, 4, 24, 25, 2, 2, "body")
    m.box(3, 4, 0, 1, 2, 2, "hull")
    # fore main turret: barbette + twin guns reaching up the long foredeck
    m.box(2, 5, 16, 18, 3, 3, "hull")
    m.box(3, 4, 16, 18, 4, 4, "hull_dk")
    for x in (3, 4):
        m.box(x, x, 19, 22, 4, 4, "gunmetal")
        m.set(x, 23, 4, "bore")
    # aft turret facing the stern
    m.box(2, 5, 3, 5, 3, 3, "hull")
    m.box(3, 4, 3, 5, 4, 4, "body_dk")
    for x in (3, 4):
        m.box(x, x, 1, 2, 4, 4, "gunmetal")
        m.set(x, 0, 4, "bore")
    # midships bridge with glazing toward the bow and a lattice mast — kept
    # below the cruiser's tower on purpose; the cruiser owns "tallest"
    m.box(2, 5, 10, 14, 3, 4, "hull")
    m.chamfer(2, 5, 10, 14, 4, 4)
    m.box(3, 4, 14, 14, 4, 4, "glass_dk")
    m.box(3, 4, 11, 13, 5, 5, "hull")
    m.box(3, 4, 13, 13, 5, 5, "glass_dk")
    m.box(3, 3, 12, 12, 6, 7, "steel")
    m.set(3, 12, 8, "gunmetal_dk")
    # lone funnel between bridge and aft turret — one more evenly spaced bump
    m.box(3, 4, 7, 8, 3, 4, "hull_dk")
    m.box(3, 4, 7, 8, 5, 5, "bore")
    if pose is Pose.B:
        # Both main batteries lay their guns up one board texel (`dz = +2`),
        # bores and all, and each gunhouse grows the two voxels behind its
        # barrels so the run stays carried by a mantlet instead of floating
        # off the roof — the joint the SAM erector keeps.
        for x in (3, 4):
            _shift(m, (x, x, 19, 23, 4, 4), dz=2)
            m.set(x, 18, 5, "hull_dk")
            _shift(m, (x, x, 0, 2, 4, 4), dz=2)
            m.set(x, 3, 5, "body_dk")
    return m


def cruiser(pose: Pose = Pose.A) -> Model:
    """Escort cruiser: the fleet's TOWER — one tall blocky superstructure
    amidships on a beamy mid-length hull, flat helipad aft (autocannon).

    Pose B elevates the forward autocannon one board texel (`dz = +2`), the
    one assembly on the ship that is not a slab: 24 changed silhouette texels
    at rung 1 against the bob's 22. The tower holds still — the cruiser owns
    "tallest", and a tower that swayed would be the ship rolling, not aiming.
    """
    m = Model()
    # mid-length hull, a strake beamier than the battleship's; dark waterline
    m.box(1, 6, 2, 15, 0, 1, "hull")
    m.box(2, 5, 16, 17, 0, 1, "hull")
    m.box(3, 4, 18, 18, 0, 1, "hull")
    m.box(2, 5, 0, 1, 0, 1, "hull")
    m.box(1, 6, 2, 15, 0, 0, "hull_dk")
    m.box(2, 5, 16, 17, 0, 0, "hull_dk")
    m.box(3, 4, 18, 18, 0, 0, "hull_dk")
    m.box(2, 5, 0, 1, 0, 0, "hull_dk")
    # deck in hull livery; the bow cells keep the pure team flash
    m.box(1, 6, 2, 15, 2, 2, "hull")
    m.box(2, 5, 16, 17, 2, 2, "hull")
    m.box(3, 4, 16, 17, 2, 2, "body")
    m.box(2, 5, 0, 1, 2, 2, "hull")
    # forward deck autocannon: twin thin barrels raked up over the bow
    m.box(3, 4, 12, 13, 3, 3, "hull_dk")
    for x in (3, 4):
        m.box(x, x, 14, 15, 3, 3, "gunmetal")
        m.set(x, 16, 4, "gunmetal_dk")
    # the tower: one tall blocky superstructure amidships, clearly the
    # tallest mass in the fleet; its band keeps the pure team accent
    m.box(2, 5, 6, 10, 3, 6, "hull")
    m.box(2, 5, 6, 10, 5, 5, "body")
    m.chamfer(2, 5, 6, 10, 6, 6)
    m.box(3, 4, 10, 10, 6, 6, "glass_dk")
    m.box(3, 4, 7, 9, 7, 8, "hull")
    m.box(3, 4, 9, 9, 7, 7, "glass_dk")
    m.box(3, 3, 8, 8, 9, 10, "steel")
    m.set(3, 8, 11, "gunmetal_dk")
    # flat helipad aft, painted on the deck: dark pad, white H
    m.box(2, 5, 1, 4, 2, 2, "hull_dk")
    m.set(3, 2, 2, "white")
    m.set(4, 2, 2, "white")
    if pose is Pose.B:
        # the forward autocannon elevates its twin barrels one board texel,
        # muzzles included, on a mount that grows the same two voxels
        _shift(m, (3, 4, 14, 16, 3, 4), dz=2)
        m.box(3, 4, 13, 13, 4, 5, "hull_dk")
    return m


def sub(pose: Pose = Pose.A) -> Model:
    """Attack submarine: the LOW one and the DARK one — decks awash, a beamy
    saddle amidships riding the waterline under one prominent sail with dive
    planes and periscopes.

    Pose B raises the search periscope one board texel out of the sail — the
    only thing on a boat with decks awash that CAN move without looking like
    it is diving — for 25 changed silhouette texels at rung 1 against the
    bob's 24, on the sprite's highest and most isolated line.
    """
    m = Model()
    # decks awash: one waterline row end to end, one deck row of freeboard
    # that stops short of the tapered bow and stern. The saddle tanks widen
    # both rows amidships: the round-4 mass finding measured the sub the
    # smallest sprite on the sheet at 22.9% legibility, and a hull two voxels
    # wide leaves a deck the player cannot see is a deck.
    #
    # Both rows sit in the under slot, two bands beneath every other keel, so
    # the sneak boat is the darkest ship in the line. One band was enough only
    # while the 4px contour band ate most of the awash hull: with 1px outlines
    # the deck's own lit faces show, and a shadow-slot deck lights to exactly
    # the body tone every other hull medians at (docs/outlines.md). Round 6
    # gave the hull its mass back and the hull then medianed into the water's
    # own value band, which is a hull-value contest the sub cannot win from a
    # mid slot; the separation it wins instead is a
    # contrast pair, dark hull against mid water with the light on the sail
    # and the wake edge.
    m.box(3, 4, 0, 21, 0, 0, "hull_under")
    m.box(2, 5, 3, 19, 0, 0, "hull_under")
    m.box(3, 4, 1, 19, 1, 1, "hull_under")
    m.box(2, 5, 4, 18, 1, 1, "hull_under")
    # the saddle-tank crowns amidships are the one lit run on the boat's own
    # hull: the water breaks over them beside the sail, and their leading
    # edges are what carry the sub's share of the band above L200. They stay
    # one band over the awash rows, which is the relationship that reads —
    # so they moved down with them.
    m.box(2, 2, 8, 14, 1, 1, "hull_dk")
    m.box(5, 5, 8, 14, 1, 1, "hull_dk")
    # deck hatches fore and aft of the sail
    m.set(3, 16, 1, "body_lt")
    m.set(4, 4, 1, "body_lt")
    # the sail: one prominent conning tower, the silhouette's single fin —
    # raised a voxel over the round-3 model so the fin, not the deck, is what
    # separates the boat from open sea. It carries the boat's light: body
    # slot up the tower, the pure team colour on its top band.
    m.box(3, 4, 9, 13, 2, 5, "hull")
    m.box(3, 4, 9, 13, 6, 6, "body")
    # dive planes off the sail flanks, in the sail's own band
    m.box(2, 2, 11, 12, 3, 3, "hull")
    m.box(5, 5, 11, 12, 3, 3, "hull")
    # periscope and attack scope over the sail
    m.box(3, 3, 11, 11, 7, 8, "steel")
    m.set(4, 13, 7, "steel")
    if pose is Pose.B:
        # the search periscope runs up one board texel and the shaft it came
        # out of fills in behind it: the mast is raised, not levitating. The
        # short attack scope stays down, so the pair reads as one scope
        # working
        _shift(m, (3, 3, 11, 11, 7, 8), dz=2)
        m.box(3, 3, 11, 11, 7, 8, "steel")
    return m


def lander(pose: Pose = Pose.A) -> Model:
    """Landing craft: the SHORT FAT one — stubbiest, beamiest hull, raised
    bow ramp, high cargo house aft. Unarmed.

    Pose B rides the bow visor one board texel UP its hinge posts (`dz = +2`),
    20 changed silhouette texels at rung 1 against the bob's 18. The dip the
    APC does was tried first and measured 17: dipping a texel while the hull
    bobs a texel the other way pins the bow's outline exactly where pose A
    left it, so the one part that moves is the one part the board cannot see.
    """
    m = Model()
    # short wide hull; dark waterline
    m.box(0, 8, 1, 9, 0, 1, "hull")
    m.box(1, 7, 10, 10, 0, 1, "hull")
    m.box(1, 7, 0, 0, 0, 1, "hull")
    m.box(0, 8, 1, 9, 0, 0, "hull_dk")
    m.box(1, 7, 10, 10, 0, 0, "hull_dk")
    m.box(1, 7, 0, 0, 0, 0, "hull_dk")
    # gunwales around the forward cargo well
    m.box(0, 8, 1, 9, 2, 2, "hull")
    m.clear(1, 7, 2, 8, 2, 2)
    # tie-down lanes on the well floor
    m.box(2, 6, 5, 8, 1, 1, "hull_lt")
    m.box(4, 4, 5, 8, 1, 1, "hull_dk")
    # high cargo house aft — the tall half of the stubby-block silhouette
    m.box(1, 7, 1, 4, 2, 5, "hull")
    m.chamfer(1, 7, 1, 4, 5, 5)
    m.box(2, 6, 4, 4, 4, 4, "glass_dk")
    m.box(2, 6, 2, 3, 6, 6, "body")  # team-colored house roof
    m.box(6, 6, 1, 1, 6, 7, "steel")  # exhaust stack
    # blunt bow ramp raised for sea travel; lip and ribs keep the team accent
    m.box(1, 7, 10, 10, 2, 4, "hull")
    m.box(2, 6, 10, 10, 2, 3, "body_lt")  # ramp ribs
    m.box(1, 7, 10, 10, 5, 5, "body_dk")  # ramp lip
    # bollards on the gunwale corners
    m.set(0, 1, 3, "gunmetal_dk")
    m.set(8, 1, 3, "gunmetal_dk")
    m.set(0, 9, 3, "gunmetal_dk")
    m.set(8, 9, 3, "gunmetal_dk")
    if pose is Pose.B:
        # the bow visor lifts one board texel, ribs and lip together, on two
        # dark hinge posts that grow the same two voxels at the gunwale
        # corners — the well between them stays open, so the visor reads as
        # standing off the bow rather than as the bow growing
        _shift(m, (1, 7, 10, 10, 2, 5), dz=2)
        m.box(1, 1, 10, 10, 2, 3, "hull_dk")
        m.box(7, 7, 10, 10, 2, 3, "hull_dk")
    return m


# ---------------------------------------------------------------------------
# registry: id -> (builder, cell kind), in atlas_col order 0..17
# ---------------------------------------------------------------------------

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


def build_model(uid: str, pose: Pose = Pose.A) -> Model:
    """The one seam a pose reaches a builder through.

    Every builder takes the pose, so there is no per-unit list of which
    models animate: a unit that has nothing to say in pose B simply draws
    the same voxels and lets composition (the air/sea bob) carry the beat.
    """
    return UNITS[uid][0](Pose(pose))


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
