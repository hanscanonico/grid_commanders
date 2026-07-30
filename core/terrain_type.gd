class_name TerrainType
extends Resource
## Static properties of one terrain kind (plains, woods, city, ...).
## Pure data: usable from the simulation core and from tests.

const IMPASSABLE := -1

## Movement classes. Units reference these from their UnitType (M2).
const FOOT := &"foot"  # infantry
const BOOT := &"boot"  # mech: crosses mountains and rivers at cost 1
const TIRES := &"tires"  # recon, rockets, missiles
const TREADS := &"treads"  # tanks, artillery, anti-air, APC
const AIR := &"air"  # everything that flies: costs 1 on every terrain
const SHIP := &"ship"  # warships: deep water only
const LANDER := &"lander"  # transports that also beach on shoals

@export var id: StringName
@export var display_name: String
## Single character representing this terrain in .txt map files.
@export var symbol: String
@export_range(0, 4) var defense_stars: int = 0
## Movement cost per movement class (StringName -> int).
## A missing key means the terrain is impassable for that class.
@export var move_costs: Dictionary = {}
## Capturable property (city, base, HQ, airport, port).
@export var is_property: bool = false
## Move classes this terrain produces units of: a base builds what drives, a
## port what floats, an airport what flies. Empty means it builds nothing, which
## is every terrain that is not a factory of some kind.
##
## This list, and not a terrain id, is what BuildCommand, the build menu and the
## AI's production all ask — so adding a facility is a data edit and none of the
## three can be the one that was forgotten.
@export var builds: Array[StringName] = []
## Unit domains this property repairs and resupplies (see UnitType's LAND / AIR
## / SEA). A city refits what drives and nothing else, so a bomber parked on one
## gets no fuel out of it — which is the whole reason airports are worth taking.
@export var services: Array[StringName] = []
## Hides whatever stands here from more than one tile away, under fog. Woods and
## reefs; see Vision, which asks this rather than naming woods.
@export var conceals: bool = false
## Column of this terrain in the generated atlas texture.
@export var atlas_col: int = 0
## Properties have team-colored variants on rows 1+ of the atlas.
@export var team_tinted: bool = false
## Presentation key, like `atlas_col`: in the battle cut-in a terrain either
## *paves* the ground or *stands* on it, and this names the pavement for the ones
## that stand. Empty — the default, and every open surface — paves: the cut-in
## tiles this terrain's own art across the floor, which is what grass, road and
## water want. Set, it names the terrain whose art the floor is tiled with
## instead, and this one's art is stood up on it as scenery.
##
## The split is what the art itself already says. A cell of grass is a *texture*
## and tiles into a field; a cell of city is a *building*, and paving with it
## carpets the frame in tiny repeated towers. The capture cut-in has always drawn
## a property this way — a plane, with the board's own cell standing on it — so
## this is the combat cut-in learning its sibling's trick, not a new idea, and
## the art is still the board's own, blown up and never redrawn (plan D2).
@export var cutin_ground: StringName = &""

## Scenery shapes. What each looks like is CutsceneSide's business; this is the
## vocabulary the two agree on, the way BattleStyle's projectile kinds are the
## one CutsceneFx shares.
const NO_SCENERY := &""
const BUILDINGS := &"buildings"  # city, base, HQ, port, airport
const TREES := &"trees"  # woods
const PEAKS := &"peaks"  # mountain

## Which of those this terrain stands, for the terrains that stand rather than
## pave. The silhouette is drawn rather than blitted because the atlas cell is a
## square of ground with the object *on* it — stood up as-is, every building
## comes with a plate behind it and reads as a framed picture instead of a tower.
## Its colour is still sampled from that same cell, so a property standing here
## wears its owner's faction exactly as the board paints it.
@export var cutin_scenery: StringName = NO_SCENERY


## True when this terrain's art is an object that stands in the cut-in rather
## than a surface that paves it. Ask this; never test the id.
func stands_in_cutin() -> bool:
	return cutin_ground != &""


func move_cost(move_class: StringName) -> int:
	return move_costs.get(move_class, IMPASSABLE)


func is_passable(move_class: StringName) -> bool:
	return move_costs.has(move_class)


func can_build(move_class: StringName) -> bool:
	return move_class in builds


## True when a unit of `domain` standing here is repaired and refuelled — asked
## by TurnRules for both, so the two can never disagree about one property.
func services_domain(domain: StringName) -> bool:
	return domain in services
