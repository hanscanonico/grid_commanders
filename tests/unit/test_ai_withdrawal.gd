extends GutTest
## AJ2 · survival can outbid a shot.
##
## Before this, retreat lived only past the min_useful_score gate, so it reached
## a unit only when that unit had nothing better to do — and a wounded tank with
## any half-decent shot took the shot and died. `_consider_withdraw` puts
## stepping out of the enemy's reach into the same UnitPlan competition the shot
## is in, priced in what the unit is *worth*.
##
## Every test is one board reached twice, with the dial off and on; the off runs
## are the inertness pin D1 owes. Profiles are built here rather than loaded, so
## the shipped tiers staying at 0 (D2 — BL2 sets the live value) is a balance
## fact and never a test failure.

## Our md tank at (7,1) beside an enemy infantry it could shoot, inside the ring
## of a bomber eight tiles off that would take most of what it has left. One step
## west leaves the ring.
const LETHAL := (
	"[terrain]\n"
	+ "................\n"
	+ "................\n"
	+ "[units]\n1 T 7 1\n2 i 7 0\n2 b 15 1"
)

## The same shape with the bomber swapped for an infantry, whose shot an md tank
## barely notices. Nothing here is worth running from.
const SURVIVABLE := (
	"[terrain]\n"
	+ "................\n"
	+ "................\n"
	+ "[units]\n1 T 7 1\n2 i 7 0\n2 i 14 1"
)

## The lethal board with one of our cities at (2,1) — as safe as the cell the
## tank would otherwise pick, and one step further away.
const LETHAL_WITH_CITY := (
	"[terrain]\n"
	+ "................\n"
	+ "..C.............\n"
	+ "[owners]\n1 2 1\n"
	+ "[units]\n1 T 7 1\n2 i 7 0\n2 b 15 1"
)

const OUR_TANK := Vector2i(7, 1)

var terrain_db: TerrainDB
var unit_db: UnitDB
var chart: DamageChart


func before_each() -> void:
	terrain_db = TerrainDB.load_default()
	unit_db = UnitDB.load_default()
	chart = load("res://data/damage_chart.tres")


func _plan(map_text: String, withdraw_weight: float, hp: int) -> Command:
	var map := MapData.parse(map_text, terrain_db)
	var state := GameState.create(map, unit_db, chart)
	assert_not_null(state)
	for unit in state.units:
		if unit.cell == OUR_TANK:
			unit.hp = hp
	var profile := AIProfile.new()  # Normal's shipped numbers; only withdraw_weight varies
	profile.withdraw_weight = withdraw_weight
	return AIController.new(unit_db, profile).plan_next_command(state)


func _destination(command: Command) -> Vector2i:
	assert_true(command is MoveCommand, "expected a withdrawal, got %s" % command)
	var path: Array[Vector2i] = (command as MoveCommand).path
	assert_false(path.is_empty(), "a withdrawal must carry a path")
	return path[path.size() - 1]


## The bug report's own case: the AI throws a unit into a fight it cannot
## survive because the shot is the only thing on the ballot.
func test_a_wounded_unit_steps_out_of_a_lethal_ring_instead_of_shooting() -> void:
	var blind := _plan(LETHAL, 0.0, 30)
	assert_true(blind is AttackCommand, "expected an attack, got %s" % blind)
	assert_eq(
		(blind as AttackCommand).target_cell,
		Vector2i(7, 0),
		"blind, the only candidate is the shot, so the tank takes it and dies to the bomber"
	)

	assert_eq(
		_destination(_plan(LETHAL, 0.2, 30)),
		Vector2i(3, 1),
		"with survival on the ballot it leaves the ring, on the cheapest safe cell"
	)


## The R3 boundary, and the reason this dial is priced in value rather than in
## tiles: a healthy md tank must not run from a shot that costs it almost
## nothing, however high the weight goes. A dial that flinches at everything is
## the coward the ladder already measured at 11.7%.
func test_a_healthy_unit_does_not_flinch_from_a_survivable_shot() -> void:
	for weight in [0.2, 1.0, 2.0]:
		var command := _plan(SURVIVABLE, weight, 100)
		assert_true(
			command is AttackCommand,
			"at weight %s a pinprick must not outbid the shot, got %s" % [weight, command]
		)


## Nothing is aiming at us, so there is nothing to buy and no move to make: the
## planner must fall through to its ordinary business rather than shuffle.
func test_a_unit_out_of_every_ring_never_withdraws() -> void:
	var far := (
		"[terrain]\n" + "................\n" + "................\n" + "[units]\n1 T 0 1\n2 i 15 0"
	)
	var blind := _plan(far, 0.0, 30)
	var wary := _plan(far, 1.0, 30)
	assert_eq(_destination(wary), _destination(blind), "with no threat the turn must be unchanged")


## Safety first, then ground that puts the unit back together. Proved by HP
## alone: the same board at the same weight sends a healthy tank to the cheapest
## safe cell and a wounded one a step further, onto the city that repairs it.
func test_a_wounded_unit_withdraws_onto_ground_that_repairs_it() -> void:
	assert_eq(
		_destination(_plan(LETHAL_WITH_CITY, 0.5, 100)),
		Vector2i(3, 1),
		"an unhurt tank has no use for a workshop and takes the nearest safe cell"
	)
	assert_eq(
		_destination(_plan(LETHAL_WITH_CITY, 0.5, 30)),
		Vector2i(2, 1),
		"a hurt one spends the extra step to land somewhere that repairs it"
	)


## Danger outranks repair, never the other way round: a city inside a firing ring
## is not a refuge. Pinned because the comparator's whole correctness is the
## order of its three keys.
func test_safety_outranks_repair() -> void:
	# The city sits at (4,0), three tiles from the enemy infantry, so it is inside
	# that unit's reach while (3,1) is outside every ring.
	var exposed_city := (
		"[terrain]\n"
		+ "....C...........\n"
		+ "................\n"
		+ "[owners]\n1 4 0\n"
		+ "[units]\n1 T 7 1\n2 i 7 0\n2 b 15 1"
	)
	assert_eq(
		_destination(_plan(exposed_city, 0.5, 30)),
		Vector2i(3, 1),
		"a repair property under fire loses to open ground that is actually safe"
	)
