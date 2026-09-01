"""The four aircraft: two jets and two helicopters."""

from __future__ import annotations

from ..voxel import Model
from .parts import _BLADE_A, _BLADE_B, _rotor, _shift
from .pose import Pose, beat, moving


def _burner_reach(pose: Pose) -> int:
    """How many courses of lit plume the fighter's two nozzles carry.

    Cold at rest (0: the mouths stay `bore`), 2 on the off-beat, 1 held
    between beats while the jet is under way.

    Only the SECOND course paints. The first sits at the nozzle mouths
    (y -1), occluded in every livery, so reach 0 and reach 1 render
    byte-identical cells — `MOVE_A`'s held burn is model space, not
    something the player sees. What the board gets is the two nozzles
    lighting one visible course together: rest none, `Pose.B` lit,
    `MOVE_A` none, `MOVE_B` lit, 11 px per cell in every livery — 7 newly
    opaque and 4 the softening pass takes around them. `beat` alone decides
    whether there is a plume, and `MOVE_B` shows it a course further out
    than `MOVE_A` does.
    """
    if beat(pose):
        return 2
    if moving(pose):
        return 1
    return 0


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
    reach = _burner_reach(pose)
    for x in (4, 5):
        for i in range(reach):
            m.set(x, -1 - i, 3, "flame")
    if beat(pose):
        # Off-beat, ticking with the frame rather than the clip like the
        # copters' rotor: a canopy glint and an elevon highlight, both
        # RETONED rather than moved. The glint is the bubble's own middle
        # course darkening a shade, the elevons the tailplane's outboard
        # tips catching the light — a voxel that already paints stays put
        # and only changes what it paints, so neither opens or closes a
        # silhouette texel the way `_shift` would. That restraint is the
        # legibility ratchet's, not a taste: fighter's contour already runs
        # within a fraction of a ramp step of the bar on most grounds
        # (`make legibility-ratchet`, whose baseline is the repo root's
        # `tests/fixtures/legibility_baseline.csv`), and even a texel-sized
        # notch or bump at the boundary — a slid glint, a lifted tip —
        # measurably dropped dozens of previously-passing cells under it.
        m.set(4, 12, 5, "glass_dk")
        m.set(5, 12, 5, "glass_dk")
        m.set(2, 1, 3, "hull_dk")
        m.set(7, 1, 3, "hull_dk")
    if moving(pose):
        # Under way the jet holds one board texel of nose-down (dz = -2): the
        # fuselage ahead of the cockpit and the radome drop, while the wings,
        # the intakes and the nozzles stay where pose A has them, so the
        # airframe's screen line ROTATES about the wing root instead of
        # translating. The break is AHEAD of the canopy (y14): taken through
        # it at y12 the glass split into two blocks two voxels apart and the
        # jet grew a second cockpit. The y13 course is repainted a voxel
        # deeper so the step down to the nose does not open a hole.
        _shift(m, (4, 5, 14, 19, 3, 5), dz=-2)
        m.box(4, 5, 13, 13, 2, 2, "hull")
    return m


# The four nacelles, x and forward offset, in wing order outer-to-inner and
# mirrored: the outer pair sits one step back, following the wing rake (see
# `bomber`). Shared with the off-beat exhaust so the two never disagree about
# where a pod is.
_NACELLES: tuple[tuple[int, int], ...] = ((-3, 0), (-1, 1), (12, 1), (14, 0))


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
    for x, fwd in _NACELLES:
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
    if beat(pose):
        # Off-beat, retoned like `fighter`'s canopy glint and for the same
        # reason (see its `beat(pose)` branch): the tail's two outboard
        # tips take a highlight in place, never opening or closing a
        # silhouette texel on an airframe the legibility ratchet already
        # holds to its tightest margin — measured 2026-09-01, every one of
        # the four engine mouths flaring to `flame` on the IDLE beat cost
        # two previously-passing cells (both the airframe's own fog reading
        # on plains, the thinnest ground this hull has), and no placement
        # of the fleck answered for it. `MOVE_B` alone lights the mouths —
        # gated on `moving`, so a parked idle stays cold and only a bank at
        # full power, one further beat under way, shows it — because the
        # nose's own deeper dip is already moving enough of the silhouette
        # that the same four retones cost nothing there.
        m.set(2, 1, 4, "hull_dk")
        m.set(9, 1, 4, "hull_dk")
        if moving(pose):
            for x, fwd in _NACELLES:
                m.set(x, 13 + fwd, 3, "flame")
    if moving(pose):
        # Same held nose-down as the fighter: the forward fuselage, the flight
        # deck and the nose cap drop a board texel, the wings, pods and tail
        # hold their line. One course of fuselage at y13 is repainted deeper
        # so the break behind the flight deck stays closed.
        _shift(m, (4, 7, 14, 20, 3, 5), dz=-2)
        m.box(4, 7, 13, 13, 2, 2, "hull")
        if beat(pose):
            # MOVE_B dips a further texel over MOVE_A's held trim: the same
            # section, carried down another whole board texel from where the
            # first dip already left it, with its own seam closing the new
            # step behind the flight deck.
            _shift(m, (4, 7, 14, 20, 1, 3), dz=-2)
            m.box(4, 7, 13, 13, 0, 1, "hull")
    return m


def b_copter(pose: Pose = Pose.A) -> Model:
    """Attack helicopter: chin gun, stub-wing rocket pods, tail rotor.

    Pose B is the same aircraft with the same four blades a tick further
    round (`_BLADE_B`), so alternating the two poses turns the disc rather
    than swapping its shape. Nothing else may differ. The blades are two
    voxels wide across the sweep at the tips, which is what makes the disc
    sample as an arc rather than as speckle — see `_BLADE_A`.
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
    # The rotor ticks with the FRAME, not the clip: a moving helicopter's
    # blades are at the off-beat position on MOVE_B exactly as on B.
    _rotor(m, 4, 10, 9, _BLADE_B if beat(pose) else _BLADE_A)
    if moving(pose):
        # A helicopter under way flies nose-down, and that attitude is what
        # says heading on a sheet that may never translate the hull. The
        # airframe RAKES about the mast, which stays where it is: the disc is
        # the part the eye tracks and tilting it would read as a second
        # animation, so every shift below is capped under z9 and the four
        # blades of both move frames are the ambient frames' voxel for voxel.
        #
        # Ahead of the mast the nose, the tandem canopy and the chin gun drop
        # one board texel (dz = -2). Behind it the boom comes UP, and it comes
        # up along its length — one texel at the fuselage (dz = +2), a voxel
        # more at the middle, two texels at the fin and the tail rotor — so
        # the boom draws one leaning line instead of a stepped one. The nose
        # alone was 17 changed / 6 silhouette rung-1 texels against pose A,
        # the smallest parked-vs-moving delta in the fleet; the rake is 30 and
        # 19.
        #
        # The break behind the canopy needs no repainting — the fuselage is
        # three voxels deep there, so the dropped section still shares a face
        # with the one it left. The two breaks along the BOOM do: aft of y7
        # the boom is one voxel of hull, so a section lifted a voxel above the
        # one ahead of it meets it edge-on, and the projection opens a pinhole
        # at the joint. A voxel of hull in each inner corner closes both and
        # keeps the boom one solid piece.
        _shift(m, (3, 5, 12, 18, 2, 6), dz=-2)
        _shift(m, (3, 5, 5, 9, 2, 6), dz=2)
        _shift(m, (3, 5, 3, 4, 2, 6), dz=3)
        _shift(m, (3, 5, 0, 2, 2, 7), dz=4)
        m.set(4, 4, 6, "hull")
        m.set(4, 2, 7, "hull")
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
    # Frame, not clip — see `b_copter`.
    blade = _BLADE_B if beat(pose) else _BLADE_A
    _rotor(m, 4, 4, 9, blade, clipped=True)
    _rotor(m, 5, 13, 9, blade, clipped=True)
    if moving(pose):
        # The tandem rakes like `b_copter`, but a machine with a rotor at each
        # end has to rake BETWEEN them. The nose-down starts ahead of the
        # forward mast (y14): the mast is bolted to the roof it stands on, so
        # a break at y11 would leave the disc hanging over two voxels of air.
        # Cockpit, glazing and the front of the hold drop a board texel and
        # the glazing itself a voxel further, so the nose reads as pointing
        # down and not merely as sitting lower; the belly course at y13 is
        # repainted a voxel deeper so the break stays closed.
        #
        # Aft of the forward mast the hull climbs: a voxel over the hold, a
        # whole texel from the rear mast bay back through the ramp, with the
        # rear gear sponsons riding along (they are bolted to the flank that
        # rose — left behind they hung in air two voxels under it). Both discs
        # sit at z9 and every shift stops at z6, so neither disc moves and
        # each keeps standing on roof. 14 changed / 9 silhouette rung-1 texels
        # against pose A before, 29 and 15 now.
        _shift(m, (3, 6, 14, 17, 3, 6), dz=-2)
        _shift(m, (3, 6, 16, 17, 1, 4), dz=-1)
        m.box(3, 6, 13, 13, 2, 2, "hull")
        _shift(m, (2, 7, 6, 9, 1, 6), dz=1)
        _shift(m, (2, 7, 0, 5, 1, 6), dz=2)
    return m
