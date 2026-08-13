"""The 18 curated unit models, one per atlas column.

Every model is hand-placed voxels — no randomness — so each unit is a single
authored design that renders byte-identically on every run. Units face +y
(screen lower-left), the facing the game's atlas has always used. Column
order and ids mirror data/units/*.tres in grid_commanders.

Weapon silhouettes follow each unit's battle_style: small_arms carry rifles
or a pintle MG, rocket units carry tubes and pods, cannon units carry a
single big gun, autocannon units carry thin multi-barrels, and the unarmed
transports carry none.
"""

from __future__ import annotations

from .voxel import Model

# ---------------------------------------------------------------------------
# shared chassis parts
# ---------------------------------------------------------------------------


def _track(m: Model, x0: int, x1: int, y0: int, y1: int, z1: int = 1) -> None:
    """One tread block with link texture on its visible faces and road wheels."""
    m.box(x0, x1, y0, y1, 0, z1, "track")
    # alternating link texture along the outer (+x) face and the front (+y) face
    for y in range(y0, y1 + 1):
        m.set(x1, y, z1 if (y - y0) % 2 == 0 else 0, "track_lt")
    for x in range(x0, x1 + 1):
        m.set(x, y1, z1 if (x - x0) % 2 == 0 else 0, "track_lt")
    # road wheel hubs peeking out of the lower run
    for y in range(y0 + 1, y1, 3):
        m.set(x1, y, 0, "hub")


def _tire(m: Model, x: int, y: int, big: bool = False) -> None:
    """One wheel: dark tire block with a hub dot on the outer face."""
    m.box(x, x + 1, y, y + 2, 0, 1, "tire")
    if big:
        m.box(x, x + 1, y, y + 2, 2, 2, "tire")
    m.set(x + 1, y + 1, 1, "hub")


# ---------------------------------------------------------------------------
# land
# ---------------------------------------------------------------------------


def infantry() -> Model:
    """Rifleman: chibi proportions — big helmet and face, rifle at the ready."""
    m = Model()
    # boots and legs, one leg a half-step forward
    m.box(3, 3, 4, 5, 0, 0, "tire")
    m.box(5, 6, 5, 6, 0, 0, "tire")
    m.box(3, 3, 4, 5, 1, 2, "body_dk")
    m.box(5, 6, 5, 6, 1, 2, "body_dk")
    # torso with belt line
    m.box(2, 6, 3, 6, 3, 5, "body")
    m.box(2, 6, 3, 6, 3, 3, "body_dk")
    # backpack
    m.box(3, 5, 2, 2, 4, 6, "body_dk")
    # left arm at the side; right hand holds the rifle column
    m.box(1, 1, 3, 5, 4, 5, "body")
    m.set(7, 6, 6, "skin")  # trigger hand
    # rifle shouldered above the torso line so it silhouettes clear of the
    # body instead of reading as a slab across the waist
    m.set(7, 5, 6, "wood")  # stock
    m.box(7, 7, 6, 10, 6, 6, "gunmetal")
    m.set(7, 11, 6, "gunmetal_dk")
    # big head: full face under an overhanging dome helmet
    m.box(3, 5, 3, 6, 6, 7, "skin")
    m.box(3, 5, 2, 2, 6, 7, "body_dk")  # nape strap
    m.box(2, 6, 2, 6, 8, 9, "body")  # helmet
    for cx, cy in ((2, 2), (2, 6), (6, 2), (6, 6)):
        m.unset(cx, cy, 9)  # round the dome
    m.box(3, 5, 3, 5, 10, 10, "body")  # crown
    return m


def mech() -> Model:
    """Armoured trooper, shoulder bazooka riding above the helmet (rocket)."""
    m = Model()
    # wide armoured legs
    for x in (2, 6):
        m.box(x, x, 4, 5, 0, 0, "tire")
        m.box(x, x, 4, 6, 1, 2, "body")
        m.box(x, x, 4, 6, 3, 3, "body_dk")  # knee plate
    # broad torso with a light chest plate
    m.box(1, 7, 3, 6, 4, 8, "body")
    m.box(2, 6, 6, 6, 5, 7, "body_lt")
    m.box(1, 7, 3, 6, 4, 4, "body_dk")
    # ammo backpack with two spare-rocket tips
    m.box(2, 6, 2, 2, 5, 8, "body_dk")
    m.set(3, 2, 9, "steel")
    m.set(5, 2, 9, "steel")
    # shoulder pads
    m.box(0, 0, 3, 6, 7, 8, "body_dk")
    m.box(8, 8, 3, 6, 7, 8, "body_dk")
    # big helmet with a glass visor band across the face
    m.box(3, 5, 3, 6, 9, 9, "skin")
    m.box(3, 5, 6, 6, 10, 10, "glass")
    m.box(3, 5, 3, 5, 10, 10, "body")
    m.box(2, 6, 2, 6, 11, 12, "body")
    for cx, cy in ((2, 2), (2, 6), (6, 2), (6, 6)):
        m.unset(cx, cy, 12)  # round the dome
    # bazooka tube above the right shoulder, muzzle toward +y
    m.box(7, 8, 1, 11, 10, 10, "gunmetal")
    m.box(7, 8, 1, 1, 10, 10, "bore")  # exhaust
    m.box(7, 8, 11, 11, 10, 10, "gunmetal_dk")
    m.set(7, 12, 10, "amber")  # loaded warhead tip
    m.set(8, 12, 10, "amber")
    m.box(7, 7, 7, 7, 6, 9, "body")  # supporting arm
    return m


def recon() -> Model:
    """Scout car: four wheels, sloped hood, roof MG, whip antenna."""
    m = Model()
    for x in (0, 8):
        _tire(m, x, 2)
        _tire(m, x, 10)
    # hull bed in desaturated armour; the cab carries the team color
    m.box(1, 8, 0, 13, 2, 3, "hull")
    # sloped hood toward the front
    m.box(1, 8, 14, 14, 2, 2, "hull")
    m.box(2, 7, 14, 15, 2, 2, "hull_lt")
    m.box(2, 7, 12, 13, 3, 3, "hull_lt")  # hood top
    # bumper and headlights
    m.box(1, 8, 15, 15, 2, 2, "hull_dk")
    m.set(2, 15, 2, "amber")
    m.set(7, 15, 2, "amber")
    # team-colored cabin with windshield and side glass, rounded roofline
    m.box(2, 7, 3, 9, 4, 5, "body")
    m.chamfer(2, 7, 3, 9, 5, 5)
    m.box(3, 6, 9, 9, 4, 5, "glass")
    m.box(7, 7, 4, 7, 4, 4, "glass_dk")
    m.box(2, 7, 3, 3, 4, 4, "body_dk")  # rear cabin plate
    # pintle MG on a rear roof ring mount (small_arms)
    m.box(4, 5, 4, 5, 6, 6, "gunmetal_dk")
    m.box(4, 4, 5, 5, 7, 7, "gunmetal_dk")
    m.box(4, 4, 6, 9, 7, 7, "gunmetal")
    m.set(4, 10, 7, "bore")
    # spare tire on the tail
    m.box(3, 6, 0, 0, 3, 4, "tire")
    m.set(4, 0, 3, "hub")
    # antenna
    m.box(2, 2, 1, 1, 4, 7, "steel")
    return m


def tank() -> Model:
    """MBT: treads, glacis, round turret, single cannon (cannon)."""
    m = Model()
    _track(m, 0, 2, 0, 13)
    _track(m, 9, 11, 0, 13)
    # hull in desaturated armour; the turret crown carries the team color
    m.box(0, 11, 1, 12, 2, 3, "hull")
    m.box(1, 10, 13, 13, 2, 3, "hull")
    m.box(2, 9, 14, 14, 2, 2, "hull_lt")  # glacis lip
    m.box(2, 9, 13, 13, 3, 3, "hull_lt")  # glacis top
    # rear deck vents and exhausts
    m.box(2, 9, 1, 1, 3, 3, "hull_dk")
    m.box(2, 9, 3, 3, 3, 3, "hull_dk")
    m.box(0, 1, 0, 0, 2, 3, "gunmetal_dk")
    # turret: octagonal ring under a team-colored rounded crown
    m.box(3, 8, 4, 9, 4, 5, "hull")
    m.chamfer(3, 8, 4, 9, 4, 5)
    m.box(4, 7, 5, 8, 6, 6, "body")
    m.chamfer(4, 7, 5, 8, 6, 6)
    m.box(4, 5, 5, 6, 7, 7, "body_dk")  # commander cupola
    m.set(6, 8, 6, "body_lt")  # loader hatch glint
    m.box(4, 7, 4, 4, 6, 6, "hull_dk")  # stowage bustle
    # mantlet and a long gun that owns the silhouette
    m.box(4, 7, 10, 10, 4, 5, "hull_dk")
    m.box(5, 6, 10, 17, 5, 5, "gunmetal")
    m.box(5, 6, 13, 13, 5, 5, "gunmetal_dk")  # bore evacuator
    m.box(4, 7, 17, 17, 5, 5, "gunmetal_dk")  # muzzle brake
    m.box(5, 6, 18, 18, 5, 5, "bore")
    return m


def md_tank() -> Model:
    """Heavy tank: wider, taller, skirted tracks, long heavy gun (cannon)."""
    m = Model()
    _track(m, 0, 2, 0, 15, 2)
    _track(m, 10, 12, 0, 15, 2)
    # hull with armoured side skirts over the tracks
    m.box(0, 12, 1, 14, 3, 4, "hull")
    m.box(10, 12, 2, 13, 3, 3, "hull_dk")
    m.box(0, 2, 2, 13, 3, 3, "hull_dk")
    # stepped heavy glacis
    m.box(1, 11, 15, 15, 3, 4, "hull")
    m.box(2, 10, 16, 16, 3, 3, "hull_lt")
    m.box(2, 10, 15, 15, 4, 4, "hull_lt")
    # rear engine deck and twin exhausts
    m.box(2, 10, 1, 2, 4, 4, "hull_dk")
    m.box(1, 2, 0, 0, 3, 4, "gunmetal_dk")
    m.box(10, 11, 0, 0, 3, 4, "gunmetal_dk")
    # big turret, two tiers: armour ring, team-colored rounded crown
    m.box(3, 9, 4, 11, 5, 6, "hull")
    m.chamfer(3, 9, 4, 11, 5, 6)
    m.box(4, 8, 5, 10, 7, 7, "body")
    m.chamfer(4, 8, 5, 10, 7, 7)
    m.box(4, 8, 4, 4, 7, 7, "hull_dk")  # bustle rack
    m.box(4, 5, 5, 6, 8, 8, "body_dk")  # cupola
    m.box(6, 7, 6, 7, 8, 8, "body_lt")  # hatch
    # wide mantlet, longer gun with thermal-sleeve rings
    m.box(4, 8, 12, 12, 5, 7, "hull_dk")
    m.box(5, 7, 13, 19, 6, 6, "gunmetal")
    m.box(5, 7, 15, 15, 6, 6, "gunmetal_dk")
    m.box(5, 7, 17, 17, 6, 6, "gunmetal_dk")
    m.box(4, 8, 20, 20, 6, 6, "gunmetal_dk")  # muzzle brake
    m.box(5, 7, 21, 21, 6, 6, "bore")
    return m


def anti_air() -> Model:
    """Tracked flak: quad autocannon battery angled up, search radar."""
    m = Model()
    _track(m, 0, 2, 0, 11)
    _track(m, 8, 10, 0, 11)
    # low hull in desaturated armour
    m.box(0, 10, 1, 11, 2, 3, "hull")
    m.box(1, 9, 12, 12, 2, 3, "hull_lt")
    m.box(2, 8, 1, 1, 3, 3, "hull_dk")
    # rotating battery box carries the team color, rounded top
    m.box(2, 8, 3, 8, 4, 6, "body")
    m.chamfer(2, 8, 3, 8, 6, 6)
    m.box(2, 8, 3, 8, 4, 4, "body_dk")
    m.box(3, 7, 3, 3, 5, 6, "body_dk")  # ammo feed
    # twin flak tubes climbing steeply skyward — the class-defining pose
    for x in (3, 7):
        m.box(x, x, 9, 10, 6, 6, "gunmetal")
        m.box(x, x, 11, 11, 7, 7, "gunmetal")
        m.box(x, x, 12, 12, 8, 8, "gunmetal")
        m.set(x, 13, 9, "gunmetal_dk")
        m.set(x, 14, 9, "bore")
    # ranging light on the battery roof
    m.set(5, 8, 7, "amber")
    # search radar dish on a rear mast, big enough to read at map scale
    m.box(8, 8, 4, 4, 7, 8, "steel")
    m.box(7, 8, 3, 5, 9, 9, "steel")
    m.box(7, 8, 4, 4, 10, 10, "steel")
    m.set(8, 4, 9, "gunmetal_dk")
    return m


def artillery() -> Model:
    """SPG: casemate hull, short howitzer at high elevation, recoil spade."""
    m = Model()
    _track(m, 0, 2, 0, 12)
    _track(m, 8, 10, 0, 12)
    m.box(0, 10, 1, 12, 2, 3, "hull")
    m.box(1, 9, 13, 13, 2, 2, "hull_lt")
    # casemate rising toward the rear; team color on its upper tier
    m.box(1, 9, 2, 8, 4, 5, "hull")
    m.box(2, 8, 2, 6, 6, 6, "body")
    m.chamfer(2, 8, 2, 6, 6, 6)
    m.box(1, 9, 2, 2, 4, 5, "hull_dk")  # rear plate
    m.box(2, 8, 8, 8, 4, 5, "hull_dk")  # front casemate slope
    m.set(3, 4, 7, "body_dk")  # top hatch
    m.set(4, 4, 7, "body_dk")
    # howitzer: fat tube climbing at ~45 degrees toward +y, longer and
    # taller than any flat tank gun so the class reads at a glance
    m.box(4, 6, 8, 9, 6, 6, "gunmetal_dk")  # cradle
    m.box(4, 6, 9, 10, 7, 7, "gunmetal")
    m.box(4, 6, 10, 11, 8, 8, "gunmetal")
    m.box(4, 6, 11, 12, 9, 9, "gunmetal")
    m.box(4, 6, 12, 13, 10, 10, "gunmetal")
    m.box(4, 6, 13, 14, 11, 11, "gunmetal")
    m.box(3, 7, 14, 14, 12, 12, "gunmetal_dk")  # double-baffle muzzle brake
    m.box(3, 7, 15, 15, 12, 12, "gunmetal_dk")
    m.box(4, 6, 16, 16, 12, 12, "bore")
    # recoil spade dug in at the rear
    m.box(3, 7, 0, 0, 1, 2, "gunmetal_dk")
    m.box(3, 7, 0, 0, 0, 0, "gunmetal")
    return m


def rockets() -> Model:
    """Wheeled MLRS: six tires, cab forward, tilted pod of rocket tubes."""
    m = Model()
    for y in (1, 6, 11):
        _tire(m, 0, y)
        _tire(m, 8, y)
    # chassis bed
    m.box(1, 8, 0, 14, 2, 3, "hull")
    # team-colored cab at the front with windshield, rounded roofline
    m.box(2, 7, 10, 14, 4, 5, "body")
    m.chamfer(2, 7, 10, 14, 5, 5)
    m.box(3, 6, 14, 14, 4, 5, "glass")
    m.box(7, 7, 11, 13, 4, 4, "glass_dk")
    m.box(2, 7, 15, 15, 2, 3, "hull_dk")  # bumper
    m.set(3, 15, 3, "amber")
    m.set(6, 15, 3, "amber")
    # launcher pod: a slab raked up toward the rear in three clean terraces,
    # each terrace top showing a row of tube mouths
    for k in range(3):
        y1 = 8 - 3 * k
        m.box(1, 8, max(1, y1 - 2), y1, 5 + k, 6 + k, "body_dk")
        for x in (2, 4, 6):
            m.set(x, y1, 6 + k, "bore")
    m.box(1, 8, 7, 8, 4, 4, "hull_dk")  # pod underside toward the cab
    m.box(1, 1, 1, 8, 5, 5, "gunmetal_dk")  # cradle rail
    # elevation ram under the pod's front lip
    m.box(4, 5, 8, 8, 4, 4, "gunmetal")
    return m


def apc() -> Model:
    """Tracked transport: tall hull, troop door, cargo rack — unarmed."""
    m = Model()
    _track(m, 0, 2, 0, 12)
    _track(m, 8, 10, 0, 12)
    # tall box hull in desaturated armour
    m.box(0, 10, 1, 12, 2, 5, "hull")
    m.box(1, 9, 13, 13, 2, 4, "hull")
    m.box(2, 8, 13, 13, 5, 5, "hull_lt")  # nose slope
    m.box(2, 8, 14, 14, 2, 3, "hull_lt")
    # driver visor slit and headlights
    m.box(3, 5, 14, 14, 4, 4, "glass_dk")
    m.set(2, 14, 4, "amber")
    m.set(8, 14, 4, "amber")
    # team-colored rounded roof: troop hatch and low cargo rail with a crate
    m.box(1, 9, 2, 12, 6, 6, "body")
    m.chamfer(1, 9, 2, 12, 6, 6)
    m.box(3, 7, 8, 11, 6, 6, "body_dk")
    m.box(2, 4, 3, 5, 7, 7, "wood")
    m.box(8, 8, 3, 6, 7, 7, "body_dk")  # rail
    # rear troop door
    m.box(3, 7, 0, 0, 2, 5, "hull_dk")
    m.set(5, 0, 3, "steel")  # door handle
    # tall comms whip — the APC keeps one; the gun tanks lost theirs
    m.box(9, 9, 3, 3, 7, 9, "steel")
    m.set(9, 3, 10, "amber")
    return m


def missiles() -> Model:
    """Wheeled SAM battery: three big canisters raked skyward (rocket)."""
    m = Model()
    for y in (1, 6, 11):
        _tire(m, 0, y)
        _tire(m, 8, y)
    m.box(1, 8, 0, 14, 2, 3, "hull")
    # team-colored cab forward, rounded roofline
    m.box(2, 7, 11, 14, 4, 5, "body")
    m.chamfer(2, 7, 11, 14, 5, 5)
    m.box(3, 6, 14, 14, 4, 5, "glass")
    m.box(7, 7, 12, 13, 4, 4, "glass_dk")
    m.box(2, 7, 15, 15, 2, 3, "hull_dk")
    m.set(3, 15, 3, "amber")
    m.set(6, 15, 3, "amber")
    # raked launch rack over the bed
    m.box(1, 8, 1, 3, 4, 5, "hull_dk")
    m.box(1, 8, 4, 6, 5, 6, "hull_dk")
    m.box(1, 8, 7, 8, 6, 7, "hull_dk")
    # three white missiles with amber seeker tips, lying on the rake
    for x in (1, 4, 7):
        m.set(x, 2, 6, "white")
        m.set(x, 3, 6, "white")
        m.set(x, 4, 7, "white")
        m.set(x, 5, 7, "white")
        m.set(x, 6, 8, "white")
        m.set(x, 7, 8, "steel")
        m.set(x, 8, 9, "amber")
    # fire-control radar on the cab roof
    m.box(4, 5, 12, 13, 6, 6, "steel")
    return m


# ---------------------------------------------------------------------------
# air
# ---------------------------------------------------------------------------


def fighter() -> Model:
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
    # swept wings carry the team color (the mass the player reads from above)
    for i in range(1, 7):
        wy = 9 - i
        m.box(4 - i, 4 - i, wy, wy + 4, 3, 3, "body")
        m.box(5 + i, 5 + i, wy, wy + 4, 3, 3, "body")
    # wingtip missiles
    m.box(-2, -2, 3, 6, 3, 3, "white")
    m.box(11, 11, 3, 6, 3, 3, "white")
    m.set(-2, 7, 3, "amber")
    m.set(11, 7, 3, "amber")
    # tailplane and twin canted fins
    m.box(2, 7, 0, 2, 3, 3, "body")
    m.box(3, 3, 0, 1, 4, 6, "body_dk")
    m.box(6, 6, 0, 1, 4, 6, "body_dk")
    # engine nozzles
    m.box(4, 5, 0, 0, 3, 4, "gunmetal_dk")
    m.set(4, -1, 3, "bore")
    m.set(5, -1, 3, "bore")
    return m


def bomber() -> Model:
    """Heavy strategic bomber: four podded engines, deep fuselage (bomb)."""
    m = Model()
    # deep fuselage in airframe grey; rounded nose
    m.box(4, 7, 0, 19, 3, 5, "hull")
    m.box(4, 7, 18, 19, 3, 4, "hull")
    m.chamfer(4, 7, 0, 19, 5, 5)
    m.box(5, 6, 20, 20, 3, 4, "hull_lt")  # nose cap
    # flight-deck glazing
    m.box(4, 7, 16, 17, 5, 5, "glass")
    # team-colored straight wings with slight rearward rake; dark trailing
    # edge so the big top surface doesn't read flat
    for i in range(1, 9):
        wy = 10 - (i + 1) // 2
        m.box(4 - i, 4 - i, wy, wy + 5, 4, 4, "body")
        m.box(7 + i, 7 + i, wy, wy + 5, 4, 4, "body")
        m.set(4 - i, wy, 4, "body_dk")
        m.set(7 + i, wy, 4, "body_dk")
    # four engine pods slung under the wings, mirrored about the fuselage
    # centre; the outer pair sits one step back, following the wing rake
    for x, fwd in ((-3, 0), (-1, 1), (12, 1), (14, 0)):
        m.box(x, x, 9 + fwd, 12 + fwd, 3, 3, "gunmetal")
        m.set(x, 13 + fwd, 3, "bore")
    # bomb-bay doors line on the belly sides
    m.box(7, 7, 6, 12, 3, 3, "hull_dk")
    # tailplane and tall team-colored fin
    m.box(1, 10, 0, 2, 4, 4, "body")
    m.box(5, 6, 0, 1, 5, 8, "body_dk")
    m.box(5, 6, 2, 2, 5, 6, "body_dk")
    # tail turret hint
    m.box(5, 6, 0, 0, 3, 3, "gunmetal_dk")
    return m


def b_copter() -> Model:
    """Attack helicopter: chin gun, stub-wing rocket pods, tail rotor."""
    m = Model()
    # fuselage: team color on the body, rounded nose
    m.box(3, 5, 6, 14, 3, 5, "body")
    m.box(3, 5, 14, 15, 3, 4, "body")
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
    m.box(1, 1, 9, 12, 3, 3, "gunmetal")
    m.box(7, 7, 9, 12, 3, 3, "gunmetal")
    m.set(1, 13, 3, "bore")
    m.set(7, 13, 3, "bore")
    # tail boom, fin and tail rotor
    m.box(4, 4, 0, 6, 4, 4, "hull")
    m.box(4, 4, 0, 1, 5, 6, "body_dk")
    m.box(5, 5, 0, 0, 5, 7, "rotor")
    m.set(5, 0, 6, "hub")
    # skids
    m.box(2, 2, 8, 14, 1, 1, "gunmetal_dk")
    m.box(6, 6, 8, 14, 1, 1, "gunmetal_dk")
    # main rotor: hub mast + four blades over the fuselage
    m.box(4, 4, 10, 10, 7, 8, "gunmetal_dk")
    m.box(4, 4, 5, 15, 9, 9, "rotor")
    m.box(-1, 9, 10, 10, 9, 9, "rotor")
    return m


def t_copter() -> Model:
    """Tandem-rotor transport helicopter — unarmed."""
    m = Model()
    # boxy hold, rounded top edges so it stops reading as a brick
    m.box(3, 6, 2, 15, 3, 6, "body")
    m.chamfer(3, 6, 2, 15, 6, 6)
    m.box(3, 6, 15, 16, 3, 5, "body")
    # cockpit glazing
    m.box(3, 6, 15, 16, 5, 5, "glass")
    m.box(3, 6, 17, 17, 3, 4, "glass_dk")
    # side cargo door and stripe
    m.box(6, 6, 6, 9, 4, 5, "hull_dk")
    m.box(6, 6, 2, 15, 3, 3, "hull_dk")
    # rear loading ramp
    m.box(3, 6, 1, 1, 3, 5, "hull_dk")
    # fixed wheels
    m.box(2, 2, 4, 5, 1, 2, "tire")
    m.box(7, 7, 4, 5, 1, 2, "tire")
    m.box(2, 2, 12, 13, 1, 2, "tire")
    m.box(7, 7, 12, 13, 1, 2, "tire")
    # tandem rotor masts and overlapping blades
    m.box(4, 5, 4, 4, 7, 8, "gunmetal_dk")
    m.box(4, 5, 13, 13, 7, 8, "gunmetal_dk")
    m.box(4, 4, 0, 8, 9, 9, "rotor")
    m.box(-1, 9, 4, 4, 9, 9, "rotor")
    m.box(5, 5, 9, 17, 9, 9, "rotor")
    m.box(0, 10, 13, 13, 9, 9, "rotor")
    return m


# ---------------------------------------------------------------------------
# sea
# ---------------------------------------------------------------------------


def battleship() -> Model:
    """Dreadnought: two twin-gun turrets, midships tower, aft funnel (cannon)."""
    m = Model()
    # naval-grey hull with tapered bow (+y) and stern; dark waterline
    m.box(1, 6, 2, 20, 0, 1, "hull")
    m.box(2, 5, 21, 22, 0, 1, "hull")
    m.box(3, 4, 23, 23, 0, 1, "hull")
    m.box(2, 5, 0, 1, 0, 1, "hull")
    m.box(1, 6, 2, 20, 0, 0, "hull_dk")
    m.box(2, 5, 21, 22, 0, 0, "hull_dk")
    m.box(2, 5, 0, 1, 0, 0, "hull_dk")
    # the deck is the faction's flag surface — pure team color read from above
    m.box(2, 5, 2, 20, 2, 2, "body")
    m.box(3, 4, 21, 22, 2, 2, "body")
    m.box(3, 4, 0, 1, 2, 2, "body")
    m.box(3, 4, 19, 20, 2, 2, "body_dk")  # bow capstan plate
    # fore main turret: barbette + twin guns toward the bow
    m.box(2, 5, 15, 17, 3, 3, "hull")
    m.box(3, 4, 15, 17, 4, 4, "body_dk")
    for x in (3, 4):
        m.box(x, x, 18, 21, 4, 4, "gunmetal")
        m.set(x, 22, 4, "bore")
    # aft turret facing the stern
    m.box(2, 5, 4, 6, 3, 3, "hull")
    m.box(3, 4, 4, 6, 4, 4, "body_dk")
    for x in (3, 4):
        m.box(x, x, 1, 3, 4, 4, "gunmetal")
        m.set(x, 0, 4, "bore")
    # superstructure tower midships, bridge glazing facing the bow
    m.box(2, 5, 9, 13, 3, 5, "hull")
    m.chamfer(2, 5, 9, 13, 5, 5)
    m.box(3, 4, 13, 13, 5, 5, "glass_dk")
    m.box(3, 4, 10, 12, 6, 6, "hull")
    m.box(3, 4, 12, 12, 6, 6, "glass_dk")
    # compact funnel aft of the tower, tall lattice mast with radar above
    m.box(3, 4, 8, 8, 6, 7, "hull_dk")
    m.set(3, 8, 8, "bore")
    m.set(4, 8, 8, "bore")
    m.box(3, 3, 11, 11, 7, 9, "steel")
    m.set(3, 11, 10, "gunmetal_dk")
    return m


def cruiser() -> Model:
    """Escort cruiser: deck gun, AA autocannons, aft helipad (autocannon)."""
    m = Model()
    # naval-grey hull with dark waterline
    m.box(1, 6, 2, 17, 0, 1, "hull")
    m.box(2, 5, 18, 19, 0, 1, "hull")
    m.box(3, 4, 20, 20, 0, 1, "hull")
    m.box(2, 5, 0, 1, 0, 1, "hull")
    m.box(1, 6, 2, 17, 0, 0, "hull_dk")
    m.box(2, 5, 18, 19, 0, 0, "hull_dk")
    m.box(2, 5, 0, 1, 0, 0, "hull_dk")
    # deck in the faction color
    m.box(2, 5, 2, 17, 2, 2, "body")
    m.box(3, 4, 18, 19, 2, 2, "body")
    m.box(3, 4, 0, 1, 2, 2, "body")
    # forward AA mount: twin thin barrels raked up
    m.box(3, 4, 14, 15, 3, 3, "body_dk")
    for x in (3, 4):
        m.set(x, 16, 4, "gunmetal")
        m.set(x, 17, 4, "gunmetal")
        m.set(x, 18, 5, "gunmetal_dk")
    # blocky bridge with glazing facing the bow; short mast (the battleship
    # keeps the tall one — silhouettes differ at a glance)
    m.box(2, 5, 8, 12, 3, 4, "hull")
    m.chamfer(2, 5, 8, 12, 4, 4)
    m.box(3, 4, 12, 12, 4, 4, "glass_dk")
    m.box(3, 4, 9, 11, 5, 5, "hull")
    m.box(3, 4, 11, 11, 5, 5, "glass_dk")
    m.box(3, 3, 10, 10, 6, 6, "steel")  # mast
    # second AA mount on the aft superstructure
    m.box(4, 5, 8, 8, 5, 5, "gunmetal_dk")
    # aft helipad: dark pad, light border dots, white H
    m.box(2, 5, 2, 6, 3, 3, "body_dk")
    m.set(3, 4, 3, "white")
    m.set(4, 4, 3, "white")
    # depth-charge rack at the stern
    m.box(3, 4, 0, 0, 3, 3, "track")
    return m


def sub() -> Model:
    """Attack submarine running surfaced: sail, periscopes, bow wake."""
    m = Model()
    # cigar hull, rounded by stepped tapers; the sail carries the team color
    m.box(2, 5, 2, 18, 1, 2, "hull")
    m.box(3, 4, 19, 20, 1, 2, "hull")
    m.box(3, 4, 21, 21, 1, 1, "hull")
    m.box(3, 4, 0, 1, 1, 2, "hull")
    m.box(2, 5, 4, 16, 3, 3, "hull")  # hull crown
    m.box(3, 4, 17, 18, 3, 3, "hull")
    # dark anti-fouling waterline
    m.box(2, 5, 2, 18, 0, 0, "hull_dk")
    m.box(3, 4, 0, 1, 0, 0, "hull_dk")
    m.box(3, 4, 19, 21, 0, 0, "hull_dk")
    # sail (conning tower) with dive planes and periscopes
    m.box(3, 4, 9, 13, 4, 6, "body_dk")
    m.box(3, 4, 9, 13, 6, 6, "body")
    m.box(2, 2, 10, 12, 4, 4, "body_dk")
    m.box(5, 5, 10, 12, 4, 4, "body_dk")
    m.box(3, 3, 10, 10, 7, 8, "steel")
    m.box(4, 4, 12, 12, 7, 7, "steel")
    # deck hatch and towed-array fairing
    m.set(3, 6, 4, "body_lt")
    m.set(4, 16, 4, "body_lt")
    # stern rudder tip
    m.box(3, 4, 0, 0, 3, 4, "hull_dk")
    # bow wake foam
    m.set(2, 20, 0, "white")
    m.set(5, 20, 0, "white")
    m.set(3, 22, 0, "white")
    m.set(4, 22, 0, "white")
    return m


def lander() -> Model:
    """Landing craft: flat cargo well, blunt bow ramp, aft wheelhouse."""
    m = Model()
    # wide flat naval-grey hull
    m.box(0, 8, 1, 16, 0, 1, "hull")
    m.box(1, 7, 17, 17, 0, 1, "hull")
    # gunwales around the cargo well
    m.box(0, 8, 1, 16, 2, 2, "hull")
    m.clear(1, 7, 2, 15, 2, 2)
    # cargo well floor with tie-down lane
    m.box(1, 7, 2, 15, 1, 1, "deck_dk")
    m.box(3, 5, 3, 14, 1, 1, "deck")
    m.box(4, 4, 3, 14, 1, 1, "hull_dk")
    # blunt team-colored bow ramp, raised for sea travel — the identity patch
    m.box(1, 7, 18, 18, 0, 3, "body")
    m.box(1, 7, 18, 18, 4, 4, "body_dk")  # ramp lip
    m.box(2, 6, 18, 18, 2, 3, "body_lt")  # ramp ribs
    # aft wheelhouse
    m.box(2, 6, 1, 4, 2, 4, "hull")
    m.chamfer(2, 6, 1, 4, 4, 4)
    m.box(3, 5, 4, 4, 4, 4, "glass_dk")
    m.box(3, 5, 2, 3, 5, 5, "body")  # team-colored cabin roof
    m.box(6, 6, 1, 1, 4, 6, "steel")  # exhaust stack
    # bollards on the gunwale corners
    m.set(0, 2, 3, "gunmetal_dk")
    m.set(8, 2, 3, "gunmetal_dk")
    m.set(0, 15, 3, "gunmetal_dk")
    m.set(8, 15, 3, "gunmetal_dk")
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
