"""The two units that walk: the rifleman and the mech."""

from __future__ import annotations

from ..voxel import Model
from .parts import _shift
from .pose import Pose, beat, moving


def _stride(m: Model, lead: str, rise: int = 0) -> None:
    """The rifleman's leg pair, as a named LEAD under hips raised by `rise`.

    `lead="planted"`, `rise=0` is pose A's stance, voxel for voxel: two boots
    two voxels apart on BOTH axes with the shins running up to the belt line.
    The other two leads are the same pair with the trailing leg at TOE-OFF —
    its boot rides one board texel up (`dz = +2`) and its shin is that much
    shorter, the knee having taken the difference. `rise` is the passing
    frame's hip height: both shins grow with it so the planted boot stays on
    the ground row while the body over them goes up.

    The legs are the LAST thing a builder draws, because the hips move
    between poses and the legs do not: a shin is authored from its own boot
    up to whatever hip line this pose ended up with, and nothing above the
    belt has to know which leg is at toe-off.

    Which leg leads is a point reflection through the hip centre,
    `(x, y) -> (8 - x, 8 - y)`, so `"near"` and `"far"` are one another's
    mirror and neither is authored twice. That reflection is also why the
    toe-off is what carries the lead at all: the planted pair is already its
    own image under that reflection, boot for boot and shin for shin, so the
    reflection maps it ONTO ITSELF and a swap of two identical planted legs
    is a no-op on the sheet, whatever it is in the model. The lifted foot is the asymmetry that makes the mirror
    visible, which is why the lift lives in here rather than in the caller.
    """
    legs: dict[tuple[int, int, int], str] = {}

    def block(x0: int, x1: int, y0: int, y1: int, z0: int, z1: int, mat: str) -> None:
        for x in range(x0, x1 + 1):
            for y in range(y0, y1 + 1):
                for z in range(z0, z1 + 1):
                    legs[(x, y, z)] = mat

    # The leading leg, planted: the boot's toe breaks a voxel past the shin,
    # and the pair stands two voxels apart on both axes, which opens a wedge
    # of sky wide enough to survive the 4:1 board sample at every phase — at
    # one voxel the legs fused into a plinth on half of them.
    block(2, 3, 5, 7, 0, 0, "tire")  # boot
    block(2, 3, 5, 6, 1, 5 + rise, "hull_dk")  # shin
    # The trailing leg: standing it is the leading leg's mirror, striding it
    # hangs off the hips with a board texel of daylight under the boot.
    lift = 0 if lead == "planted" else 2
    block(5, 6, 1, 3, lift, lift, "tire")  # boot
    block(5, 6, 2, 3, 1 + lift, 5 + rise, "hull_dk")  # shin
    if lead == "far":
        legs = {(8 - x, 8 - y, z): mat for (x, y, z), mat in legs.items()}
    m.vox.update(legs)


def _infantry_ko() -> Model:
    """The rifleman down: a crumpled silhouette at roughly a third of the
    standing model's height (z tops out at 2 against pose A's 16), head
    toward the low end of y and boots trailing off the high end, a splay of
    daylight left open between the legs the way the stride keeps one. The
    rifle is dropped clear of the body rather than pinned under it — a hand
    still gripping it would read as a man resting, not a casualty — and the
    helmet has come off, face turned up in the one skin patch on him.
    """
    m = Model()
    m.box(1, 8, 3, 9, 0, 1, "hull_dk")  # the far side, in shadow
    m.box(2, 7, 4, 8, 1, 2, "hull")  # the lit half of him, catching the sky
    m.box(1, 3, 8, 10, 0, 1, "hull_dk")  # legs trailing off, splayed apart
    m.box(6, 8, 8, 10, 0, 1, "hull_dk")
    m.box(4, 6, 2, 3, 1, 2, "skin")  # face turned to the sky
    m.box(3, 6, 1, 2, 0, 1, "hull_dk")  # helmet, knocked clear of the head
    # rifle, dropped alongside, well off the body it was carried against
    m.set(9, 4, 0, "gunmetal_dk")
    m.set(10, 3, 0, "gunmetal")
    m.set(11, 2, 0, "bore")
    m.set(8, 5, 0, "gunmetal_dk")
    return m


def infantry(pose: Pose = Pose.A) -> Model:
    """Rifleman: a full stride under a fatigue torso, a lit shoulder line, a
    helmeted head notched well inside that line, and a short dark rifle held
    at low ready across the chest — two hands on it, muzzle breaking the
    silhouette to the right and tipped a voxel down, the opposite corner from
    the mech's tube.

    KO: see `_infantry_ko`.

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

    The move clip walks him: a held forward lean, a hip line that bobs a
    board texel, and the two legs taking it in turns to be at toe-off
    (`_stride` and the `moving(pose)` branch below).
    """
    if pose is Pose.KO:
        return _infantry_ko()
    m = Model()
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
    if moving(pose):
        # The gait is two things at once, and both are one board texel.
        #
        # The LEAN is forward — `(dx -1, dy +1)`, the way the man faces, the
        # opposite diagonal from the idle beat's settle back over his trailing
        # boot — and it is HELD across both frames. A lean that alternated
        # would be the man rocking on the spot at 160 ms, which reads as a
        # stumble, not as travel; held, it is simply the attitude of someone
        # walking. The belt stays out of it: the hips stay over the feet, the
        # way the hull may not translate along its own run.
        #
        # The RISE is the walk's bob, and it is what alternates. On the beat
        # the man is at his passing position — over a straight planted leg,
        # hips and everything above them a texel higher, both shins grown to
        # meet them so the planted boot never leaves the ground row. That bob
        # is the same jolt of ride height the tracked family takes on its
        # off-beat (`_roll`), and on a figure it is the difference between a
        # walk and a foot that twitches: the toe-off alone measured 6 changed
        # silhouette texels at rung 1, one over the `MoveFrames` floor, and 5
        # on the mech, which is under it. Bobbing the body carries the whole
        # upper mass with it — rifle bar, shoulder line, helmet — and the
        # pair measures 16 texels at rung 1 and 66 at rung 2, at a shimmer of
        # 1.75 (`tests/measure_motion.py`).
        #
        # Up rather than down: `dz = -2` costs this sprite its own floors, as
        # pose B's note records (33 px tall and 619 opaque against a
        # `test_infantry_read` MIN_HEIGHT of 34 and MIN_PIXELS of 640).
        rise = 2 if beat(pose) else 0
        if rise:
            _shift(m, (0, 12, 0, 9, 6, 16), dz=rise)
        _shift(m, (0, 12, 0, 9, 7 + rise, 16 + rise), dx=-1, dy=1)
        _stride(m, "far" if beat(pose) else "near", rise)
    else:
        _stride(m, "planted")
    return m


def _mech_legs(m: Model, swing: int | None = None) -> None:
    """The rocket trooper's stance: two armoured legs under a fixed hip line,
    with the leg at `swing` — an x0 of 1 or 6, or None when he is standing —
    stepped a board texel FORWARD and the other one the same texel BACK.

    The rifleman's legs stand apart on both axes and swap through the hip
    centre; these two stand apart in x alone, side by side on screen, so a
    swap is a no-op and the gait has to be a SCISSOR instead: the boots
    take a whole board texel each along the run, in opposite directions, and
    exchange those places on the next frame. Two texels of stride open
    between them, and the leg that shows — the near one, out against sky —
    carries one of them by itself. A LIFT instead is what this walked as
    first and it is worth five silhouette texels, under the move clip's
    floor of six (`tests/measure_motion.py`): the raised leg has to be the
    far one half the time, where it crosses inside the torso's own field and
    the board never sees it, and a raised NEAR leg takes the whole sprite
    off the ground row, which drops a tenth of its mass and floats it over
    its own shadow.

    Both boots therefore stay on the ground row. The board's tween is what
    travels, so a planted boot is not a contact the art has to hold — it is
    only the line the figure stands on, and both frames stand on it.

    Only the boots and shins step. The knee plates stay in the column under
    their own hip, one voxel below the belt band, so each leg still hangs
    off the hips rather than floating and the caller's hip line is never
    punched through; the one-voxel diagonal between a knee and its stepped
    shin is the bend.
    """
    for x0 in (1, 6):
        # `step` is signed along the run: -1 is the forward `(dx -1, dy +1)`
        # diagonal, +1 is back, 0 is the standing pair, voxel for voxel.
        if swing is None:
            step = 0
        else:
            step = -1 if x0 == swing else 1
        bx, by = x0 + step, 4 - step
        m.box(bx, bx + 1, by, by + 2, 0, 0, "tire")  # boot
        m.box(bx, bx + 1, by, by + 2, 1, 2, "hull")  # shin
        m.box(x0, x0 + 1, 4, 6, 3, 3, "hull_dk")  # knee plate


def _mech_ko() -> Model:
    """The trooper down: bulkier and squarer than the rifleman's own wreck,
    at the same third-height floor. One pauldron is still strapped on; the
    other went with the launch tube, dropped clear of the shoulder that
    carried it, warhead tip still live in the amber it fires with.
    """
    m = Model()
    m.box(0, 8, 3, 8, 0, 1, "hull_dk")  # bulk, low and in shadow
    m.box(1, 7, 4, 7, 1, 3, "hull")  # the armoured back, catching the light
    m.box(1, 2, 5, 6, 3, 4, "body")  # one pauldron, still strapped on
    m.box(2, 4, 1, 2, 1, 2, "skin")  # visor, face down
    m.box(1, 5, 0, 1, 0, 1, "hull_dk")  # helmet, torn loose
    # the launch tube, dropped clear of the shoulder it rode
    m.box(6, 8, 0, 2, 0, 1, "gunmetal")
    m.set(8, 1, 1, "amber")  # warhead tip, still live
    return m


def mech(pose: Pose = Pose.A) -> Model:
    """Rocket trooper: planted wide stance, heavy pauldrons over a bulky
    torso, and a fat launch tube climbing forward over the left shoulder —
    taller, wider and squarer than the rifleman's stride (bazooka).

    KO: see `_mech_ko`.

    Pose B leans the loaded tube in a whole board texel: the left pauldron
    and everything it carries ride `dz = -2`, measured at 7 changed
    silhouette texels at rung 1 against the 2 the old one-voxel settle
    scored.

    The move clip walks him on the rifleman's held forward lean, but the
    beat is his legs alone: torso and launcher hold still while the boots
    scissor a board texel each along the run, so the warhead tip is a fixed
    landmark and what moves is a stride (`_mech_legs` and the `moving(pose)`
    branch below)."""
    if pose is Pose.KO:
        return _mech_ko()
    m = Model()
    # The legs are drawn last, off whatever hip line this pose ends up with
    # (`_mech_legs`); the belt band bridging the stance sits on top of them.
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
    if moving(pose):
        # The rifleman's held forward `(dx -1, dy +1)` lean — the attitude of
        # a man walking, the same on both frames, because a lean that
        # alternated at 160 ms is a stumble — and under it a scissor of the
        # legs (`_mech_legs`).
        #
        # The beat stops at the belt. Everything over it — torso, backpack,
        # helmet, pauldrons, launcher and its amber warhead tip — is placed
        # identically on both frames, so the tip is a landmark the eye holds
        # while the stance swaps beneath it. Bobbing the body a texel too,
        # which is what this walked as first, translated every landmark at
        # once and read as a HOP in place rather than as travel. A hip that
        # rose on its own instead was no better: pinned under a pinned torso
        # it only buries the belt in the chest and stretches the stance leg
        # into a slab.
        #
        # WHICH leg leads is what alternates: the near one on the beat, the
        # far one off it, so the pair opens into a stride and closes through
        # a passing position at 160 ms.
        #
        # Measured 14 changed silhouette texels at rung 1 and 47 at rung 2,
        # at a shimmer of 0.14-0.19 (`tests/measure_motion.py`). The hop
        # scored 20 and 72, but nine tenths of that was the body: this is
        # what the LEGS are worth, and it is the cleanest ratio of shape to
        # tone on the sheet.
        _shift(m, (-1, 9, 1, 10, 5, 16), dx=-1, dy=1)
        _mech_legs(m, 6 if beat(pose) else 1)
    else:
        _mech_legs(m)
    return m
