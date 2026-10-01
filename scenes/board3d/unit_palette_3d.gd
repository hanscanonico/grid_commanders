class_name UnitPalette3D
extends RefCounted
## The colours a 3D unit wears that are not its army's: one named colour per
## role, read by every unit. An army's own tones are `FactionRamp3D`'s.
##
## Every value here is held clear of every army's ramp, the Iron Dominion's
## near-black grey most of all: running gear sits under every army's dark tone
## and a weapon over every army's light one but gold's, so neither melts into
## the hull it is mounted on. `test_unit_models_3d.gd` pins both.

## A weapon — a barrel, a gun, a rifle — and a bare-metal hub cap or antenna.
## Never an army colour: an army's light tone is for trim and top panels.
const STEEL := Color("9aa3ad")
## A mount, a pod, a muzzle brake, a hatch fitting: dark metal that is not rubber.
const GUNMETAL := Color("3c4249")
## Running gear — treads, tyres, skids, boots — and every opening: a bore, a
## rocket mouth, a funnel, an exhaust.
const RUBBER := Color("1a1d21")
## Every window, canopy and visor.
const GLASS := Color("56718c")
## A missile's or a bomb's body; its band is the army's and its tip `ORDNANCE_TIP`.
const ORDNANCE := Color("e9e6df")
const ORDNANCE_TIP := Color("f0a42a")
## A rotor blade: mid steel, so a spinning rotor reads as a disc over the
## ground shadow rather than as ink lines merged with it.
const ROTOR := Color("78818b")
## A panel the sprites paint white: a recon's cabin roof. Light, so it carries
## on a top face at 52° on every army, the Iron Dominion's included.
const LIVERY := Color("c9ced4")
const SKIN := Color("e3b58e")
## The battleship's planked deck, its tell among the ships.
const DECK := Color("b9b3a3")
## The cruiser's steel deck: a second value under its hull, grey where the
## battleship's is planked.
const PLATING := Color("7d858e")
## Foam on the water: the sub's wake, the white line the sprites draw it by.
const WAKE := Color("eef3f6")
## A jet's nozzle glow.
const EXHAUST := Color("ff9a3c")
