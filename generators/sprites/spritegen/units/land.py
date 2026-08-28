"""The eight land vehicles, from the scout car to the missile launcher."""

from __future__ import annotations

from ..voxel import Model
from .parts import _gear_down, _roll, _shift, _tire, _track, _tread_phase
from .pose import Pose, moving


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

    The move clip holds the MG where pose A carries it — a scout on the move
    is not sweeping its arc — and holds the whip one diagonal step BACK over
    the tail on BOTH frames, trailing in the airstream. Because that step is
    taken against the model's own facing rather than against a screen side, a
    horizontal flip carries it: the mirrored car's antenna still lies back.

    The two frames are the car's two ends taking the ride, since the wheels
    cannot carry it at this scale (see `_tire`). MOVE_A pitches the NOSE one
    board texel — hood, bumper, headlights and front axle at `dz = +2`, tail
    axle and cabin holding — with the front tyres painted back onto the ground
    under it (`_gear_down`), so the car pitches ABOUT its contact patch on its
    springs instead of lifting off it. MOVE_B sets the nose down and runs the
    CABIN up instead: the roof, the glass, the rear plate and the pintle ride the
    texel on a one-course `hull_dk` band painted in under them, so the
    roofline moves against a level chassis and the body reads as working on
    its springs. Extending the nose pitch back to take the cabin with it was
    tried first and is what the band replaces: pitched together they moved 5
    silhouette texels between the frames, under the gate's 6, because the
    roofline and the hood rose as one line.

    The whole-hull `_roll` the tracked family jolts with is not available
    here, for the reason the MBT's rock documents: lifting all of a low car
    costs it its identity. Rolled, MOVE_B read closer to the apc's frame A
    (0.703) than to recon's own (0.700). Moving one end at a time keeps the
    shape: 0.806 and 0.904 against its own frame A, next best 0.675 and 0.765
    (cruiser). A against MOVE_A is 32 changed texels at rung 1, 16 of them
    silhouette; MOVE_A against MOVE_B is 44 and 13, at 2.38 shimmer. Mass
    drift 0.020 and 0.059: the planted tyres pay most of MOVE_A's back, and
    MOVE_B's band — which pays out more than the raised cabin uncovers — is
    now the whole of the unit's headroom question, with 0.021 left under the
    gate's 0.08.
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
    if moving(pose):
        # the whip trails one board texel BACKWARD on both frames —
        # `(dx +1, dy -1)` is the reverse of the models' forward step
        _shift(m, (2, 2, 1, 1, 4, 7), dx=1, dy=-1)
    if pose is Pose.MOVE_A:
        # The lifted box stops at z=6 so it takes the chassis and nothing
        # else: the only voxel above it inside the nose's x/y is the MG's
        # muzzle at (4, 10, 7), which overhangs the front axle from a barrel
        # rooted in the cabin. Lifted, it left the barrel behind and floated
        # two voxels off its own tip.
        _shift(m, (0, 9, 10, 15, 0, 6), dz=2)
        # ...and the front wheels stay down under it: the car pitches on its
        # springs about the contact patch rather than lifting off it
        for x in (0, 8):
            _gear_down(m, x, x + 1, 10, 12, "tire")
    if pose is Pose.MOVE_B:
        # the cabin runs up its springs over a level chassis, pintle and all
        # — the box reaches y=10 to take the muzzle with the barrel — and the
        # two courses it came off are painted back in dark, so the body rides
        # a texel high instead of floating a texel over its own bed
        _shift(m, (2, 7, 3, 10, 4, 7), dz=2)
        m.box(2, 7, 3, 9, 4, 5, "hull_dk")
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

    The move clip leaves the gun where pose A carries it — a tank under way
    does not lay its barrel — and ROCKS the hull over its running gear
    instead, one end at a time. MOVE_A takes the family's nose-up: the front
    hull course, the glacis and the leading track run at `dz = +2`, with that
    run's two bottom courses painted straight back onto the ground
    (`_gear_down`) — a track does not leave the ground when a hull pitches, and
    at rung 1 the texel it stands on is the one that bridges hull to shadow.
    MOVE_B sets that down and lifts the REAR — the back hull course, the vents,
    the exhausts and the trailing track run — so the link stripe walks under a
    hull that pitches back and forth instead of one holding still. The turret,
    the cupola, the mantlet and the gun lie outside both boxes and never move:
    the barrel line the player names this unit by is the fixed thing the rock
    is read against.

    It is a rock here and the whole-hull `_roll` the rest of the tracked
    family jolts with, for one measured reason: the MBT is the heavy tank's
    small brother, and `_roll` raises the whole silhouette into its brother's.
    Rolled, MOVE_B's rung-1 silhouette matched md_tank's frame A at IoU 0.799
    against 0.761 for its own — the unit stopped reading as itself. Lifting
    one end moves the same texel over a fifth of the mass, so the shape stays
    the tank's: 0.907 and 0.903 against its own frame A against 0.738 and
    0.798 against md_tank's, and md_tank's own move frames stay clear of it
    (0.943 and 0.781 own, 0.696 and 0.627 next).

    Both boxes stop at z=5, which is NARROWER than the nose pitch this
    replaces: that one carried the mantlet and the whole gun (z to 7, y to 20)
    and so moved a line lying inside the sprite's own outline at rung 1 — 46
    changed texels for 11 of silhouette, 3.18 shimmer, a frame re-toning its
    interior more than it moved its edge. Cut to the running gear and the
    glacis, the same one-texel move buys 46 changed for 14 of silhouette at
    2.29 shimmer, and A against MOVE_A is 32 changed with 8 of silhouette —
    fewer than the pitch moved before it kept its track down, because the
    contact courses are the sprite's lowest texels and they now hold still in
    every pose. Mass drift 0.004 and 0.049.
    """
    m = Model()
    _track(m, 0, 2, 0, 13, 2, phase=_tread_phase(pose))
    _track(m, 9, 11, 0, 13, 2, phase=_tread_phase(pose))
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
    if pose is Pose.MOVE_A:
        # nose up: hull front, glacis and the leading track run, gun excluded,
        # with the run's contact courses painted back onto the ground
        _shift(m, (0, 11, 10, 14, 0, 5), dz=2)
        for x0 in (0, 9):
            _gear_down(m, x0, x0 + 2, 10, 13)
    if pose is Pose.MOVE_B:
        # and the other end, clear of the turret ring at y=4
        _shift(m, (0, 11, 0, 3, 0, 5), dz=2)
    return m


def md_tank(pose: Pose = Pose.A) -> Model:
    """Heavy tank: wider, taller, skirted tracks, long heavy gun (cannon).
    The tallest thing the land roster puts on a tile.

    Pose B lays the heavy gun up one board texel, as the MBT does: the wide
    mantlet, the sleeved barrel and the muzzle brake take `dz = +2` off a
    turret that stays where it was. One texel is enough here because this
    barrel is three voxels wide — 6 changed silhouette texels at rung 1, 20
    at rung 2, where the MBT's thinner gun needed two.

    The move clip walks the stripe with the gun left at pose A's travel-lock
    and takes its two frames from the chassis. MOVE_A holds the family's
    nose-up — the stepped glacis, the front hull course and the leading track
    run at `dz = +2`, the turret and the gun untouched, so the heavy pulls
    away with its weight back over the drivers. MOVE_B sets the nose down and
    rolls the WHOLE hull the same texel (`_roll`), which is the off-beat jolt
    of a machine this heavy riding ground.

    Neither frame takes its track off the ground with it. Both stand the run's
    two bottom courses back at z=0 (`_gear_down`) — the lifted end's on MOVE_A,
    the leading four voxels of both runs on MOVE_B, which is where the sprite's
    lowest texel is drawn — so the hull rides its suspension and the texel that
    bridges hull to shadow at rung 1 is the parked one in every frame. The roll
    grounds the leading end only because a whole run brought back down under a
    rolled hull is a band of new pixels the mass gate cannot pay for: at full
    length the drift was 0.100 against the 0.08 bar.

    The roll is UP and never down even though this is the tallest thing on the
    land roster: `voxel.place_in_cell` still takes it, and a settle would read
    as the suspension giving way rather than the chassis riding. Nothing here
    has to borrow the MBT's rock, because it is the heavy that the MBT's roll
    collided with and not the other way about: rolled, MOVE_B still reads
    0.781 against its own frame A and 0.616 against the next unit's. A against
    MOVE_A is 26 changed texels at rung 1 with 4 of silhouette — the thinnest
    parked-to-moving reading on the land roster, since a nose pitch this short
    over a run that stays down moves the glacis line and nothing else; MOVE_A
    against MOVE_B is 77 and 22, at 2.50 shimmer, mass drift 0.006 and 0.050.
    """
    m = Model()
    _track(m, 0, 2, 0, 15, 3, phase=_tread_phase(pose))
    _track(m, 10, 12, 0, 15, 3, phase=_tread_phase(pose))
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
    if pose is Pose.MOVE_A:
        # nose up: stepped glacis, front hull and the leading track run
        _shift(m, (0, 12, 13, 16, 0, 6), dz=2)
        # ...and the lifted length of the run is stood back on the ground
        for x0 in (0, 10):
            _gear_down(m, x0, x0 + 2, 13, 15)
    if pose is Pose.MOVE_B:
        _roll(m, 2)
        # the leading end of both runs comes back down under the jolt
        for x0 in (0, 10):
            _gear_down(m, x0, x0 + 2, 12, 15)
    return m


def anti_air(pose: Pose = Pose.A) -> Model:
    """Tracked flak: twin long barrels raked past 60 degrees over the battery
    box — the howitzer's climb, paired and thin — plus a search radar.

    Pose B walks both barrel runs up one board texel (`dz = +2`) on a cradle
    that grows the two voxels with them, so the battery tracks a target and
    the raked lines — the identity — are what the player sees move: 8 changed
    silhouette texels at rung 1, 31 at rung 2.

    The move clip holds the battery at pose A's travelling elevation — a flak
    track under way is not tracking — and gives both frames to the running
    gear. MOVE_A pitches the chassis nose-up one texel under the battery: the
    front hull, its lip and the leading track run take `dz = +2` at z at most
    3, which is under the battery box, so the raked barrels stay exactly where
    the travelling lock put them and only the hull they ride on moves. MOVE_B
    levels that and rolls the whole model the same texel (`_roll`). Both frames
    stand the track back down where the lift took it (`_gear_down`): the front
    of the run on MOVE_A, the leading four voxels of both runs under the roll,
    which is the end the sprite's lowest texel is drawn from and so the texel
    that bridges hull to shadow at rung 1.

    Lifting the nose UNDER the roll — both at once — was tried and is what
    the alternation replaces: at MOVE_B the flak track's own frame A read
    0.615 against the apc's 0.635 and it stopped being itself. One at a time
    it reads 0.890 and 0.702 own, against 0.650 and 0.683 next. A against
    MOVE_A is 31 changed texels at rung 1 with 5 of silhouette; MOVE_A against
    MOVE_B is 53 and 19, at 1.79 shimmer, mass drift 0.001 and 0.068. The roll
    frame is the tightest mass reading of the eight land vehicles: this is the
    shortest hull that grounds four voxels of both runs, so the contact patch
    is the biggest share of a sprite here and the drift it buys leaves 0.012
    under the gate.
    """
    m = Model()
    _track(m, 0, 2, 0, 11, phase=_tread_phase(pose))
    _track(m, 8, 10, 0, 11, phase=_tread_phase(pose))
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
    if pose is Pose.MOVE_A:
        # nose up, under the battery: the box stops at the hull's top course
        _shift(m, (0, 10, 9, 12, 0, 3), dz=2)
        # ...over a track run that stays on the ground under it
        for x0 in (0, 8):
            _gear_down(m, x0, x0 + 2, 9, 11)
    if pose is Pose.MOVE_B:
        _roll(m, 2)
        # the leading end of both runs comes back down under the jolt
        for x0 in (0, 8):
            _gear_down(m, x0, x0 + 2, 8, 11)
    return m


def artillery(pose: Pose = Pose.A) -> Model:
    """SPG: open casemate, howitzer erected near-vertical, recoil spade.

    The gun climbs THREE z per y (2026-08-24), where it used to climb two.
    Two z per y draws a 2:1 screen slope, which is the slope of every roofline
    and every glacis in this projection and of the MBT's hull-hugging barrel:
    the howitzer ran along the tank's own gun line and the two units measured
    0.800 IoU at rung 1, one shape wearing two labels on the zoomed-out board
    (`Silhouette`). Three z per y draws a 5:2 slope the sheet has nothing else
    at, and the spike leaves the hull line for open sky — 0.764 now, and the
    unit is a foot taller into the cell's headroom for it.

    Pose B is the recoil stroke: the sleeved barrel, the flared brake and the
    bore ride `dz = -4` down into the pit while the TRUNNION PEDESTAL stays
    put, so the barrel slides through its own mount the way a recoiling gun
    does. Two board texels, not the one the shallower gun took: a near-
    vertical spike dropped one texel slides down its own column and changes
    almost nothing at the edges (3 silhouette texels against 23 interior ones,
    6.67 shimmer, over the 5.0 bar). The full stroke measures 12 changed
    silhouette texels at rung 1 and 46 at rung 2, at 1.75 shimmer. The walls,
    the spade and the hull hold their ground, which is what makes it a gun
    firing rather than a vehicle sinking.

    The move clip does NOT recoil: a gun fires from a halt, so both move
    frames carry pose A's erected howitzer and the animation is all chassis.
    MOVE_A pitches the nose up one texel — the front hull course, its lip and
    the leading track run, all of it below the casemate wall, so the spike and
    the pit it stands in are carried and not bent — and MOVE_B levels that and
    rolls the whole model the same texel (`_roll`), which swings the
    near-vertical spike a texel across open sky where nothing else on the
    sheet has anything. The track stays on the ground through both
    (`_gear_down`, the lifted front on MOVE_A and the leading four voxels of
    both runs under the roll), so the SPG rides its suspension rather than
    hovering a texel over its own shadow.

    A against MOVE_A is 36 changed texels at rung 1 with 7 of silhouette;
    MOVE_A against MOVE_B is 59 and 19, at 2.11 shimmer, mass drift 0.005 and
    0.061. Identity holds at 0.911 and 0.752 against its own frame A, next
    best 0.703 and 0.687.
    """
    m = Model()
    _track(m, 0, 2, 0, 12, 2, phase=_tread_phase(pose))
    _track(m, 8, 10, 0, 12, 2, phase=_tread_phase(pose))
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
    # howitzer erected out of the pit: the rising spike no other land unit
    # carries — THREE z per y, so it breaks away from the 2:1 line every
    # roofline and every tank barrel on the sheet runs at, well clear of the
    # hull mass and half again longer than the tile is tall; the lower barrel
    # wears a livery recoil sleeve, the muzzle stays steel
    m.box(4, 6, 4, 6, 5, 7, "hull_dk")  # trunnion pedestal
    for i in range(6):
        paint = "hull_dk" if i < 2 else "gunmetal"
        m.box(4, 6, 6 + i, 6 + i, 8 + 3 * i, 10 + 3 * i, paint)
    m.box(3, 7, 11, 11, 25, 25, "gunmetal_dk")  # muzzle brake, flared
    m.box(4, 6, 12, 12, 26, 26, "bore")
    # recoil spade dug in at the rear
    m.box(3, 7, 0, 0, 2, 4, "hull_dk")  # spade arms
    m.box(2, 8, -1, -1, 1, 3, "hull")  # blade
    if pose is Pose.B:
        # the howitzer recoils TWO board texels down into the pit, and the
        # trunnion pedestal stays put: the barrel slides through its own
        # mount, which is what a recoiling gun does and what leaves the pit
        # and the casemate as the fixed thing the stroke is read against.
        # Two, not the one the shallower gun took, because the erected barrel
        # is now near-vertical on screen — a texel of recoil slid it down its
        # OWN column and changed 3 silhouette texels against 23 interior
        # ones, over the 5.0 shimmer bar. The full stroke clears the spike's
        # own width off the top of the sky.
        _shift(m, (3, 7, 6, 12, 8, 27), dz=-4)
    if pose is Pose.MOVE_A:
        # nose up, clear of the casemate wall and the pit inside it
        _shift(m, (0, 10, 10, 13, 0, 4), dz=2)
        # ...over a track run that stays on the ground under it
        for x0 in (0, 8):
            _gear_down(m, x0, x0 + 2, 10, 12)
    if pose is Pose.MOVE_B:
        _roll(m, 2)
        # the leading end of both runs comes back down under the jolt
        for x0 in (0, 8):
            _gear_down(m, x0, x0 + 2, 9, 12)
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

    The move clip leaves the rack at pose A's travelling stow — a launcher
    elevates from a halt — and takes its frames from the carrier. MOVE_A rides
    the TAIL up one texel: the bed and the three rear axles behind the cab,
    everything below z=4 so the slab's own rows stay where the stow put them,
    which stands the loaded end of a long truck up over its rear bogies.
    MOVE_B levels that and rolls the whole truck the same texel (`_roll`), and
    the rack, being the biggest plane on the roster, carries the jolt across
    most of the sprite — with the FRONT pair of tyres painted back onto the
    ground under it (`_gear_down`), since that axle is where the sprite's
    lowest row is drawn and MOVE_A is already standing on it. The other three
    axles ride the roll: eight grounded wheels is a band of new pixels worth
    0.081 of mass drift against the gate's 0.08, and one axle answers the
    contact rule for both frames.

    It is the tail here and the nose everywhere else in the family, for a
    measured reason that belongs to the shadow rather than to the ride. This
    truck has the sheet's tightest cast-shadow margin — its rack overhangs the
    cell centre to the screen left, so the shadow's centroid sits 0.37px right
    of the hull's against a 0.2px floor (`OneSun` in
    `tests/test_generated_output.py`). Lifting the NOSE deletes the pixels the
    front of the bed was standing on, and in this projection the front is the
    screen-left end: the hull centroid walks right past the shadow's and the
    frame reads as lit from the wrong shoulder (-0.14px, a failure). Lifting
    the tail takes the same texel off the screen-RIGHT end and the margin
    widens to 0.77px.

    A against MOVE_A is 28 changed texels at rung 1 with 9 of silhouette;
    MOVE_A against MOVE_B is 65 and 14, at 3.64 shimmer, mass drift 0.048 and
    0.030. Identity 0.942 and 0.803 own, next best 0.646 and 0.607.
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
    if pose is Pose.MOVE_A:
        # tail up: the bed and the three rear axles, under the slab. The front
        # axle holds the ground here, and it is the front that carries the
        # sprite's lowest row, so this frame already stands on its contact
        # patch and the tightest shadow margin on the sheet is left alone.
        _shift(m, (0, 9, 0, 11, 0, 3), dz=2)
    if pose is Pose.MOVE_B:
        _roll(m, 2)
        # the roll takes all eight wheels up with the bed; the FRONT pair
        # comes back down, which is the axle the sprite's lowest row is drawn
        # from and the one the truck is already standing on in MOVE_A
        for x in (0, 8):
            _gear_down(m, x, x + 1, 13, 15, "tire")
    return m


def apc(pose: Pose = Pose.A) -> Model:
    """Tracked transport: a raised forward cab stepped down to a long OPEN
    cargo deck with the ramp dropped at the tail — unarmed.

    What this replaces (2026-08-24) was a tall flat-topped box, and a box is
    the one thing a tank also is. Measured at rung 1 — the zoomed-out board,
    16x24 texels, where `Silhouette`'s 32x48 reading cannot see the
    difference — the transport and the MBT came in at 0.810 IoU: a player
    picked between a gun tank and an unarmed carrier by colour alone. The
    answer is mass and not greebling (docs/density_128.md): a step in the top
    line and a hole where the roof used to be.

    Three changes carry it, and each is sized against the projection rather
    than against the drawing:

    - the cargo deck is a ONE-course wall ring with no roof over it, five
      courses under the cab roof. A roof gains 2px of screen height per
      course and gives 1px back per voxel it stands forward of the mass it is
      stepped up from, so with the cab 9 voxels ahead of the bay's rear
      corner the step only clears the iso slope at five;
    - the hull is 9 voxels wide against the MBT's 12 and the narrowest gun
      tank's 11, and its run is two voxels longer than the MBT's, which is a
      carrier's proportion and not a turret ring's;
    - the ramp is DOWN, three voxels of it stepping to the ground behind the
      tail. No gun vehicle on the sheet has anything at that corner.

    It reads 0.743 against the tank now, and tank/artillery's 0.764 is the
    roster's worst pair.

    Pose B dips the nose a whole board texel: the cab, its roof, the cupola,
    the glacis and the bumper all ride `dz = -2` while the open deck behind
    holds still, so the step between the two visibly shallows as the
    transport nods on its torsion bars. That is 8 changed silhouette texels
    at rung 1 and 32 at rung 2, against the 3 and 15 the old glacis-only dip
    scored — the old model had nothing else a texel could be seen on, and the
    open troop hatch tried then changed zero texels at either rung because
    this projection buries a roof detail under the roof's own far edge.

    The move clip never nods — the nod is a parked transport settling — and
    puts an attitude on both frames instead. MOVE_A pitches the transport
    nose-up: everything from the cab's rear bulkhead forward, the raised cab
    with its roof and cupola, the glacis, the bumper and the leading track run
    under all of it, rides `dz = +2` while the open cargo deck and the dropped
    ramp hold the ground — the loaded end squatting as the carrier pulls away,
    and the step between cab roof and bay wall deepening instead of shallowing
    the way pose B's nod makes it. MOVE_B levels that and rolls the whole
    hull, dropped ramp and all, the same texel (`_roll`). The ramp riding the
    roll is deliberate: it is bolted to the tail, so leaving it on the ground
    while the hull lifted would tear the outline. The TRACK is not bolted to
    anything and never leaves the ground: both frames paint its bottom two
    courses back at z=0 (`_gear_down`) — the whole lifted length on MOVE_A, the
    leading four voxels under the roll — which is the texel that bridges hull
    to shadow at rung 1.

    Pitch and roll TOGETHER on MOVE_B is what the alternation replaces: it put
    the cab a second texel up and the frame read 0.667 against the bomber's
    against 0.658 for its own, the one silhouette on the sheet a raised slab
    can be mistaken for. One at a time reads 0.871 and 0.759 own, next best
    0.718 and 0.695. A against MOVE_A is the loudest reading on the land
    roster at 47 changed texels at rung 1 with 9 of silhouette; MOVE_A
    against MOVE_B is 34 and 13, at 1.62 shimmer, mass drift 0.047 and 0.053.
    """
    m = Model()
    _track(m, 0, 2, 0, 15, phase=_tread_phase(pose))
    _track(m, 6, 8, 0, 15, phase=_tread_phase(pose))
    # low hull tub running the whole length — the floor the cargo bay and the
    # cab both stand on, and one voxel narrower than any gun tank's
    m.box(0, 8, 1, 15, 2, 4, "hull")
    # hull-side skirts: a dark plate down each flank, the full length of the
    # run, so the transport's flank is armour and the tracks read as covered.
    # They stop at the tub's own bottom course — a skirt dropped over the
    # tread would take the link stripe with it, and the stripe is the only
    # thing on the model that says tracked.
    m.box(0, 0, 1, 15, 2, 3, "hull_dk")
    m.box(8, 8, 1, 15, 2, 3, "hull_dk")
    # open cargo deck over the rear half: a ONE-course wall ring and no roof
    # at all. The team color has the whole ring, which is the largest pure
    # livery run on the land roster.
    m.box(0, 8, 1, 9, 5, 5, "hull")
    m.clear(1, 7, 2, 8, 5, 5)
    m.box(1, 7, 2, 8, 4, 4, "hull_dk")  # bay floor, in shadow under the walls
    m.box(0, 0, 1, 9, 5, 5, "body_dk")  # wall caps
    m.box(8, 8, 1, 9, 5, 5, "body_dk")
    m.box(0, 8, 1, 1, 5, 5, "body")
    m.box(2, 6, 8, 8, 5, 5, "body")
    # raised forward cab: five courses over the bay wall, which is what it
    # takes for the step to clear the projection — a roof gains 2px of screen
    # height per course and loses 1px per voxel it stands forward of the
    # thing it is stepped up from
    m.box(1, 7, 10, 15, 5, 9, "hull")
    m.box(2, 6, 10, 15, 10, 10, "hull")  # cab roof, inset
    m.chamfer(2, 6, 10, 15, 10, 10)
    m.box(3, 5, 11, 14, 10, 10, "body")  # roof panel
    m.box(1, 7, 10, 10, 5, 9, "hull_dk")  # cab rear bulkhead, over the bay
    # small commander's cupola on the cab roof
    m.box(3, 5, 11, 12, 11, 11, "body_dk")
    m.set(4, 12, 12, "steel")  # periscope
    # sloped glacis nose stepping down to the bumper; the team stripe
    # across it keeps a pure accent on an unshaded face
    m.box(1, 7, 16, 16, 2, 8, "hull")
    m.box(2, 6, 16, 16, 8, 8, "hull_lt")
    m.box(3, 5, 16, 16, 6, 7, "glass")  # driver's screen
    m.box(2, 6, 17, 17, 2, 3, "hull_lt")
    m.box(3, 5, 17, 17, 3, 3, "glass_dk")
    m.set(2, 17, 3, "amber")
    m.set(6, 17, 3, "amber")
    # rear ramp, dropped: it steps down out of the bay floor and lies on the
    # ground behind the hull — the one part of the outline that says troops
    # get out of this, and no gun vehicle on the sheet has anything like it
    m.box(2, 6, 0, 0, 2, 2, "hull_dk")
    m.box(2, 6, -1, -1, 1, 1, "hull_dk")
    m.box(2, 6, -2, -2, 0, 0, "hull")
    m.set(3, -2, 0, "steel")  # ramp lip
    m.set(5, -2, 0, "steel")
    if pose is Pose.B:
        # the nose dips a WHOLE board texel and the open bay holds still: cab,
        # roof, cupola, glacis and bumper all ride `dz = -2` together, so the
        # step between the cab roof and the bay wall visibly shallows as the
        # transport nods on its torsion bars. The glacis-only dip this
        # replaces moved a corner of a slab; this moves the tallest mass the
        # unit owns.
        _shift(m, (1, 7, 10, 17, 2, 12), dz=-2)
    if pose is Pose.MOVE_A:
        # nose up: the whole raised cab module from its rear bulkhead forward,
        # the track run under it included; the open bay and the ramp hold
        _shift(m, (0, 8, 10, 17, 0, 12), dz=2)
        # ...over the length of run the lift took up with it
        for x0 in (0, 6):
            _gear_down(m, x0, x0 + 2, 10, 15)
    if pose is Pose.MOVE_B:
        _roll(m, 2)
        # the leading end of both runs comes back down under the jolt
        for x0 in (0, 6):
            _gear_down(m, x0, x0 + 2, 12, 15)
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

    The move clip leaves both rounds seated at pose A, because running the
    rail is pose B's verb and belongs to the ambient clip: a battery that
    erected its rounds while driving would be firing on the move. So the two
    frames are the short chassis under them. MOVE_A lifts the front axle, the
    livery cab and the bumper one texel (z at most 5, which is the cab's own
    roof, so the erector pedestal and the seated rounds behind it never enter
    the box), and MOVE_B levels that and rolls the whole erector the same
    texel (`_roll`), which swings both spikes across open sky. The FRONT tyres
    are painted back onto the ground in both frames (`_gear_down`): they are
    the axle the sprite's lowest row is drawn from, so the battery pitches and
    jolts about its contact patch instead of hovering over its own shadow. The
    tail axle rides the roll, which is what keeps the mass drift payable.

    A against MOVE_A is 30 changed texels at rung 1 with 10 of silhouette;
    MOVE_A against MOVE_B is 43 and 17, at 1.53 shimmer, mass drift 0.009 and
    0.049. Identity 0.883 and 0.701 own, next best 0.604 and 0.587 — the
    thinnest own-to-next margin on the land roster, and it is the seated
    rounds that hold it, so a later pass may not move them under way.
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
    if pose is Pose.MOVE_A:
        # nose up: front axle, cab and bumper, below the seated rounds; the
        # front tyres are painted back onto the ground under it
        _shift(m, (0, 9, 8, 12, 0, 5), dz=2)
        for x in (0, 8):
            _gear_down(m, x, x + 1, 8, 10, "tire")
    if pose is Pose.MOVE_B:
        _roll(m, 2)
        # the front axle comes back down under the jolt, as in MOVE_A
        for x in (0, 8):
            _gear_down(m, x, x + 1, 8, 10, "tire")
    return m
