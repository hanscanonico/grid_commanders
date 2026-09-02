"""The four hulls: battleship, cruiser, submarine and lander.

Every one authors a KO pose: settled by the stern — the freeboard that end
carries is gone and whatever stood on it settles into the gap, the waterline
course itself untouched, the same invariant the move clip's trim already
holds — plus a mast or a hatch lost. `voxel.wreck_tone` is what darkens it.

Every ARMED one (every hull but the transport, `lander`) also authors a fire
pose, live rather than dead-toned: batteries trained and recoiled, a forward
mount blazing, bow caps open. `cruiser`'s autocannon is the one sea style in
`units.pose.FIRE_PAIRS`, so it alone draws a second key; `battleship` and
`sub` draw the same model into both.
"""

from __future__ import annotations

from ..voxel import Model
from .parts import _shift
from .pose import Pose, beat, moving


def battleship(pose: Pose = Pose.A) -> Model:
    """Dreadnought: the fleet's LONG one — a hull with a clear margin over
    every other keel, turrets fore and aft, midships bridge mast (cannon).

    FIRE: see the branch below.

    Pose B lays BOTH main batteries up one board texel (`dz = +2`): 33 changed
    silhouette texels at rung 1 against the bob's own 30, and the gun runs are
    what the extra three are. The batteries at both ends move together, so the
    beat reads along the ship's length, which is the identity.

    The move clip is the ship UNDER WAY, and what a hull under way has that a
    hull at anchor does not is TRIM: both move frames hold the bow up one board
    texel, so the long deck line rakes over the whole length the battleship is
    named for. Frame to frame it trains the AFT battery a texel, the one the
    idle does not touch — 30 changed silhouette texels at rung 1, shimmer 1.23.
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
    if pose in (Pose.FIRE_A, Pose.FIRE_B):
        # Batteries trained out: both turrets slew their guns one board
        # texel to the same broadside — the safe traverse direction the
        # under-way beat's own aft training already uses, since this hull
        # has no margin the other way (`place_in_cell` refuses `dx = +1`
        # here) — and the barrels recoil back through their gunhouses
        # rather than laying up. Cannon is not sustained, so FIRE_B draws
        # this same key.
        _shift(m, (3, 4, 19, 23, 4, 4), dx=-1, dy=-2)
        _shift(m, (3, 4, 0, 2, 4, 4), dx=-1, dy=2)
    if moving(pose):
        # Under way the dreadnought carries a held BOW-UP trim, both frames:
        # everything forward of the bridge above the waterline — foredeck,
        # fore turret, bow flash — rides one board texel up and the stern
        # holds, so the long deck line rakes over the ship's whole length,
        # which is this hull's identity. The `hull_dk` waterline course at
        # z0 never moves: `voxel._waterline_foam` places the foam against the
        # composed cell's lowest spans, and a bow lifted out of them would
        # drag the foam line up the sheet with it.
        _shift(m, (2, 5, 16, 26, 1, 5), dz=2)
        m.box(2, 5, 16, 23, 1, 2, "hull")
        m.box(3, 4, 24, 26, 1, 2, "hull")
        if beat(pose):
            # The frame-to-frame delta is the AFT battery training one board
            # texel across the stern — deliberately not the fore battery the
            # idle lays up, so the two clips read apart at a glance. The
            # barbette grows under the trained gunhouse so the guns keep a
            # mount instead of hanging over the deck.
            #
            # The traverse runs `(dx -1, dy +1)` and not the other diagonal
            # because this hull has no room for the other one: pose A's sprite
            # is 64px wide in a 64px cell (length is the battleship's identity)
            # and `(dx +1, dy -1)` carries the stern bore off the right edge —
            # `place_in_cell` refuses the 65px sprite outright. Screen-wise the
            # two are the same traverse mirrored, and the consumer mirrors the
            # clip anyway.
            _shift(m, (3, 4, 0, 5, 4, 4), dx=-1, dy=1)
            m.box(2, 3, 6, 6, 3, 3, "hull")
    if pose is Pose.KO:
        # settled by the stern: the freeboard is gone at the aft end, and the
        # deck, aft turret and funnel above it settle into the gap it left —
        # the waterline course itself stays fixed, the same rule the move
        # clip holds, so the sea does not appear to move under it
        m.clear(2, 5, 0, 9, 1, 1)
        _shift(m, (2, 5, 0, 9, 2, 8), dz=-1)
        m.clear(3, 3, 12, 12, 6, 7)  # the mast, gone
    return m


def cruiser(pose: Pose = Pose.A) -> Model:
    """Escort cruiser: the fleet's TOWER — one tall blocky superstructure
    amidships on a beamy mid-length hull, flat helipad aft (autocannon).

    FIRE: see the branch below.

    Pose B elevates the forward autocannon one board texel (`dz = +2`), the
    one assembly on the ship that is not a slab: 24 changed silhouette texels
    at rung 1 against the bob's 22. The tower holds still — the cruiser owns
    "tallest", and a tower that swayed would be the ship rolling, not aiming.

    Under way it carries the fleet's held bow-up trim (see `battleship`) with
    the autocannon riding up on the raised foredeck, and its frame-to-frame
    delta is the mast HEAD alone running up the lattice — the tower still holds
    still: 23 changed silhouette texels at rung 1, shimmer 1.70.
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
    if pose in (Pose.FIRE_A, Pose.FIRE_B):
        # Forward mount blazing: the twin autocannon barrels recoil a board
        # texel back through their pedestal, muzzles included. FIRE_B kicks
        # them one further texel back, the jitter a sustained stream reads
        # as between two held keys — cruiser is one of `pose.FIRE_PAIRS`.
        _shift(m, (3, 4, 14, 16, 3, 4), dy=-2)
        my = 14
        if pose is Pose.FIRE_B:
            _shift(m, (3, 4, 12, 14, 3, 4), dy=-2)
            my = 12
        m.set(3, my, 4, "flame")
        m.set(4, my, 4, "flame")
    if moving(pose):
        # The escort's held BOW-UP trim: hull, deck, bow flash and the forward
        # autocannon forward of the tower all ride one board texel up while
        # the stern and the helipad hold. The waterline course stays put for
        # the foam (see `battleship`), and the freeboard under the raised
        # section is repainted so the rake is a hull and not a gap.
        _shift(m, (1, 6, 11, 18, 1, 4), dz=2)
        m.box(1, 6, 11, 15, 1, 2, "hull")
        m.box(2, 5, 16, 17, 1, 2, "hull")
        m.box(3, 4, 18, 18, 1, 2, "hull")
        if beat(pose):
            # The delta is the mast HEAD alone, run one board texel up its own
            # lattice: the tower itself holds still, which is the cruiser's
            # recorded rule — a tower that swayed would be the ship rolling.
            _shift(m, (3, 3, 8, 8, 11, 11), dz=2)
            m.box(3, 3, 8, 8, 11, 12, "steel")
    if pose is Pose.KO:
        # settled by the stern, same rule as the battleship's: the freeboard
        # under the helipad is gone and the deck it carried settles into the
        # gap, the waterline course untouched
        m.clear(1, 6, 0, 6, 1, 1)
        _shift(m, (1, 6, 0, 6, 2, 2), dz=-1)
        m.clear(3, 3, 8, 8, 9, 10)  # the mast, gone
    return m


def sub(pose: Pose = Pose.A) -> Model:
    """Attack submarine: the LOW one and the DARK one — decks awash, a beamy
    saddle amidships riding the waterline under one prominent sail with dive
    planes and periscopes.

    Pose B raises the search periscope one board texel out of the sail — the
    only thing on a boat with decks awash that CAN move without looking like
    it is diving — for 25 changed silhouette texels at rung 1 against the
    bob's 24, on the sprite's highest and most isolated line.

    It is the one hull that does NOT take the move clip's bow-up trim: decks
    awash is the whole identity, and a bow lifted clear of the water is a boat
    that has surfaced. It runs DOWN BY THE HEAD instead — the one attitude a
    surfaced boat never holds — with its search mast up and its planes rigged
    down: the bow's freeboard course goes under, the after casing stands a
    board texel out of the water, the sail's forward end comes down with the
    bow, and the attack scope is the off-beat.

    FIRE reuses this trim rather than authoring its own: down-by-the-head is
    already "a boat about to put a fish in the water", so both fire keys take
    the `moving(pose)` branch below whole, hold the attack scope up every
    frame instead of on the off-beat alone, and add one thing the move clip
    has no reason to draw — the bow tube caps, open.

    The masts alone were the first attempt at this and they are not enough at
    board scale. Pose A against MOVE_A measured 3 changed / 1 silhouette texel
    at rung 1 — the raised search periscope is one voxel in x and 4 atlas px
    of it, so the 4:1 sample ate the whole clip and the moving sub was the
    parked sub. With the trim it is 23 changed / 7 silhouette against pose A,
    and MOVE_A against MOVE_B is 43 / 25.

    Which way the trim is drawn is forced by the water, not chosen. The bow
    cannot be shifted down: `voxel._waterline_foam` reads the boat's wake off
    the composed cell's own lowest spans, and z=0 is that course end to end,
    so a bow that dropped a texel would take the foam line with it and the sea
    would read as heaving. So the bow buries by LOSING its freeboard course
    (z=1 forward of the sail) while the after casing lifts `dz +2` over water
    filled in beneath it, and the deck line runs down to the bow with z=0
    never touched — foam pixel-identical in all four poses, all five liveries.
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
    if moving(pose) or pose in (Pose.FIRE_A, Pose.FIRE_B):
        # Search mast up TWO board texels and standing in its own shaft, not
        # the one texel pose B rides: at rung 1 a mast is at most a texel wide
        # whatever it is made of, so its length is the only thing the board
        # can count. Widening it to x3..4 as well was measured and dropped —
        # it bought no rung-1 texel in any livery and cost 10 px of the mass
        # budget the trim needs.
        m.box(3, 3, 11, 11, 7, 10, "steel")
        # planes rigged down onto the saddle for the run
        _shift(m, (2, 2, 11, 12, 3, 3), dz=-2)
        _shift(m, (5, 5, 11, 12, 3, 3), dz=-2)
        # ...and the trim, bow first. The sail's forward two courses come down
        # a texel with the head, attack scope and all — a sail is fixed to the
        # casing it stands on, so it pitches with it.
        _shift(m, (3, 4, 12, 13, 3, 7), dz=-2)
        # The after casing rides `dz +2` clear of the water, with the water it
        # left filled in dark beneath it so the raised deck is hull and not a
        # box floating over a hole. It runs from the stern up to the sail's
        # own base at y8, which is what keeps it reading as one hull sitting
        # deeper forward instead of a deckhouse someone bolted on aft.
        _shift(m, (2, 5, 1, 8, 1, 1), dz=2)
        m.box(3, 4, 1, 8, 1, 2, "hull_under")
        m.box(2, 5, 4, 8, 1, 2, "hull_under")
        # ...and the bow's freeboard goes under. It is deleted rather than
        # shifted because there is nowhere below z=0 to shift it to, and the
        # mass it gives back is what pays for the raised casing: 6.1% drift on
        # MOVE_A and 7.1% on MOVE_B of the hull's own pixels, which is 4.5%
        # and 5.2% as `MoveFrames` reads it (the cast shadow counts there,
        # and it is pose-invariant) against the 8% that gate allows.
        for y in range(14, 20):
            for x in (2, 3, 4, 5):
                m.unset(x, y, 1)
        if beat(pose) or pose in (Pose.FIRE_A, Pose.FIRE_B):
            # The delta is the short ATTACK scope coming up beside the search
            # one — the search mast is already up in both frames, so what the
            # board sees moving is the second mast and not the first. It came
            # down with the sail, so it goes up from where the trim left it.
            # FIRE holds it up on both keys rather than alternating it — a
            # boat that has opened its bow caps keeps its scope up.
            _shift(m, (4, 4, 13, 13, 5, 5), dz=2)
            m.set(4, 13, 5, "steel")
        if pose in (Pose.FIRE_A, Pose.FIRE_B):
            # Bow caps open: the tapered bow tip's own deck row goes dark, two
            # tube doors on the waterline the trim above already bared.
            # Torpedo is not sustained, so FIRE_B draws this same key.
            m.set(3, 20, 0, "bore")
            m.set(4, 20, 0, "bore")
    if pose is Pose.KO:
        # the sail settles half a texel into the saddle it stands on — the
        # one silhouette move this hull can make without reading as
        # surfaced or diving — and both deck hatches spring open
        _shift(m, (3, 4, 9, 13, 2, 6), dz=-1)
        m.unset(4, 4, 1)
        m.unset(3, 16, 1)
    return m


def lander(pose: Pose = Pose.A) -> Model:
    """Landing craft: the SHORT FAT one — stubbiest, beamiest hull, raised
    bow ramp, high cargo house aft. Unarmed.

    Pose B rides the bow visor one board texel UP its hinge posts (`dz = +2`),
    20 changed silhouette texels at rung 1 against the bob's 18. The dip the
    APC does was tried first and measured 17: dipping a texel while the hull
    bobs a texel the other way pins the bow's outline exactly where pose A
    left it, so the one part that moves is the one part the board cannot see.

    Under way it runs bow-up like the two warships, visor DOWN in both frames —
    a loaded lander does not carry its ramp open at sea — and cracks the visor's
    centre lip a texel on the off-beat: 20 changed silhouette texels at rung 1,
    shimmer 1.40. The lip is cracked and not thrown open because the mass gate
    is what is scarce here: the rake alone spends 3.6% of the 8% drift and a
    full-width visor lift spends another 5.1%.
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
    if moving(pose):
        # The craft runs bow-up with the visor DOWN — pose A's closed ramp, a
        # loaded lander does not carry its bow open at sea. The forward third
        # of the hull, the forward end of the well floor and the whole ramp
        # ride one board texel up; the cargo house aft holds, so the stubby
        # block rakes. Waterline course untouched for the foam
        # (see `battleship`), freeboard repainted under the raised section.
        _shift(m, (0, 8, 7, 10, 1, 5), dz=2)
        m.box(0, 8, 7, 9, 1, 2, "hull")
        m.box(1, 7, 10, 10, 1, 2, "hull")
        if beat(pose):
            # The delta is the ramp LIP alone lifting off its ribs — the
            # visor cracked, not opened — with the ramp face grown behind it
            # so nothing floats.
            _shift(m, (3, 5, 10, 10, 7, 7), dz=2)
            m.box(3, 5, 10, 10, 7, 7, "hull")
    if pose is Pose.KO:
        # settled by the stern, same rule as the two warships': the aft
        # freeboard under the cargo house is gone and the house settles into
        # the gap it left, the waterline course untouched
        m.clear(0, 8, 0, 4, 1, 1)
        _shift(m, (1, 7, 1, 4, 2, 5), dz=-1)
        m.clear(6, 6, 1, 1, 6, 7)  # the exhaust stack, gone
    return m
