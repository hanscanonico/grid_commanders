class_name UnitPalette3D
extends RefCounted
## The colours a 3D unit wears that are not its army's: one named colour per
## role, read by every unit. An army's own tones are `FactionRamp3D`'s.
##
## Every value here is held clear of every army's ramp, the Iron Dominion's
## near-black grey most of all: running gear sits under every army's dark tone
## and a weapon over every army's light one but gold's, so neither melts into
## the hull it is mounted on. `test_unit_models_3d.gd` pins both.
##
## White is spent on two things only, ordnance and an aircraft's livery, so it
## keeps meaning "this is what it fires". No other part is lighter than
## `STEEL_LIGHT`: the board's sun lifts a steel top face to about #b8c0c8 and a
## light-steel one a step past it, both well short of white.

## A panel the sprites paint white on a vehicle — a recon's cabin, a lander's
## cargo: the lightest a part may be that is not ordnance or livery.
const STEEL_LIGHT := Color("9aa3ad")
## A weapon — a barrel, a gun, a rifle — and a bare-metal hub cap. Never an
## army colour: an army's light tone is for trim and top panels.
const STEEL := Color("8c959f")
## A step under steel: a rotor blade, so a spinning rotor reads as a disc over
## the ground rather than as a white sheet; a rack or a heavy gun whose wide
## top would otherwise outshine the ordnance; a mount that must clear the Iron
## Dominion's hull where gunmetal would sink into it.
const STEEL_MID := Color("78818b")
const ROTOR := STEEL_MID
## A mount, a pod, a turret house, a fitting: dark metal that is not rubber.
const GUNMETAL := Color("3c4249")
## Running gear — treads, tyres, skids, boots — and every opening: a bore, a
## rocket mouth, a funnel, an exhaust, a gun's muzzle ring.
const RUBBER := Color("1a1d21")
## Every window, canopy and visor.
const GLASS := Color("56718c")
## A missile's or a bomb's body; its band is the army's and its tip `ORDNANCE_TIP`.
const ORDNANCE := Color("e9e6df")
## The tip of anything fired: a missile, a rocket pod's warheads, a mech's tube.
const ORDNANCE_TIP := Color("f0a42a")
## An aircraft's white wing and fin tips and nose band, as the sprites paint
## them. Aircraft only: a vehicle's light panel is `STEEL_LIGHT`.
const LIVERY := Color("c9ced4")
const SKIN := Color("e3b58e")
## The battleship's planked deck, its tell among the ships: no other part is cream.
const DECK := Color("b9b3a3")
## The cruiser's steel deck: a second value under its hull, grey where the
## battleship's is planked.
const PLATING := Color("7d858e")
## Foam on the water: the sub's wake, the white line the sprites draw it by.
const WAKE := Color("eef3f6")
## A jet's nozzle glow.
const EXHAUST := Color("ff9a3c")
