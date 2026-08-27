extends GutTest
## The advisory seam between a commander's doctrine and the AI planner: the
## stand_value / build_bias / retreat_hp_delta hooks on CommanderType, scaled by
## AIProfile.doctrine_weight.
##
## Checked with test-local advisers rather than shipped generals, so the seam is
## pinned independently of any doctrine's numbers: the neutral commander must
## advise nothing, a zero weight must restore the doctrine-blind planner, and
## each hook must be able to move the decision it is wired to.
##
## It is also the roster's advice inventory (ADVICE_COVERAGE below) and the
## purity gate the doctrine plan's D4 states in prose. What D4 asks for is
## OBSERVATIONAL purity — the same board answers the same way — rather than a
## commander that stores nothing: two doctrines memoise on the instance under a
## key any relevant board change moves, which is what keeps that true.
## RadekMorn's `_blast` cache is the older one, and is deliberately outside the
## gate entirely so `power_target` cannot aim somewhere `wants_power` did not
## want; MaraVoss's `_reach` memo is inside it, keyed to Morn's shape, and
## `test_mara_voss.gd::test_stand_advice_re_reads_reach_on_a_later_turn` is
## where that key is held to invalidating.


## Prefers standing in woods, strongly enough to give up five tiles for it.
class WoodsAdviser:
	extends CommanderType

	func stand_value(state: GameState, _unit: Unit, cell: Vector2i) -> int:
		var terrain := state.map.terrain_at(cell)
		return 5 if terrain != null and terrain.id == &"woods" else 0


## Pulls artillery to the top of the build list and nudges the md tank down.
class ArtilleryAdviser:
	extends CommanderType

	func build_bias(_state: GameState, _team: int, unit_type: UnitType) -> int:
		if unit_type.id == &"artillery":
			return -9
		if unit_type.id == &"md_tank":
			return 1
		return 0


## Tries to talk the planner into transports and out of its air answer —
## advice the ranking must refuse to follow.
class SaboteurAdviser:
	extends CommanderType

	func build_bias(_state: GameState, _team: int, unit_type: UnitType) -> int:
		if unit_type.id == &"apc":
			return -20
		if unit_type.id == &"anti_air":
			return 50
		return 0


## Rotates wounded units home a pip and a half earlier than the profile does.
class EarlyRepairAdviser:
	extends CommanderType

	func retreat_hp_delta(_state: GameState, _unit: Unit) -> int:
		return 15


var terrain_db: TerrainDB
var unit_db: UnitDB
var chart: DamageChart
var commander_db: CommanderDB


func before_each() -> void:
	terrain_db = Fixture.terrain_db()
	unit_db = Fixture.unit_db()
	chart = Fixture.chart()
	commander_db = Fixture.commander_db()


func _blind_profile() -> AIProfile:
	var profile := AIProfile.new()
	profile.doctrine_weight = 0.0
	return profile


# --- the neutral commander ---------------------------------------------------


func test_the_neutral_commander_advises_nothing() -> void:
	var state := Fixture.state(Fixture.TANK_VS_INFANTRY)
	var co := state.commander_of(1)
	var tank := state.units[0]
	assert_eq(co.stand_value(state, tank, Vector2i(1, 0)), 0)
	assert_eq(co.build_bias(state, 1, tank.type), 0)
	assert_eq(co.retreat_hp_delta(state, tank), 0)


# --- stand_value -------------------------------------------------------------

## A tank with no shot this turn and a distant enemy to march on. The
## doctrine-blind planner closes the distance; the adviser gives up four tiles
## of that march to hold the woods; turning the dial to zero blinds it again.
const QUIET_WOODS_BOARD := """
[terrain]
.F..................
[units]
1 t 0 0
2 i 19 0
"""


func _advance_destination(state: GameState, profile: AIProfile) -> Vector2i:
	var command := AIController.new(unit_db, profile).plan_next_command(state)
	assert_true(command is MoveCommand, "expected an advance, got %s" % command)
	var path: Array[Vector2i] = (command as MoveCommand).path
	return path[path.size() - 1]


func test_stand_advice_moves_a_quiet_advance() -> void:
	var advised := Fixture.state(QUIET_WOODS_BOARD)
	advised.set_commander(1, WoodsAdviser.new())
	assert_eq(
		_advance_destination(advised, AIProfile.new()),
		Vector2i(1, 0),
		"five tiles of woods preference should beat four tiles of progress"
	)


func test_a_zero_doctrine_weight_ignores_stand_advice() -> void:
	var advised := Fixture.state(QUIET_WOODS_BOARD)
	advised.set_commander(1, WoodsAdviser.new())
	var neutral := Fixture.state(QUIET_WOODS_BOARD)
	assert_eq(
		_advance_destination(advised, _blind_profile()),
		_advance_destination(neutral, AIProfile.new()),
		"weight zero must plan exactly as the neutral commander does"
	)


# --- build_bias --------------------------------------------------------------

## A funded base with the capture roster already filled, so production reaches
## the priority tier where doctrine bias applies.
const FUNDED_BASE_BOARD := """
[terrain]
B....
.....
[owners]
1 0 0
[units]
1 i 1 0
1 i 2 0
1 i 3 0
2 i 4 1
"""


func _planned_build(state: GameState, profile: AIProfile) -> StringName:
	for unit in state.units:
		unit.acted = true
	state.funds[1] = 99999
	var command := AIController.new(unit_db, profile).plan_next_command(state)
	assert_true(command is BuildCommand, "expected a build, got %s" % command)
	return (command as BuildCommand).unit_type.id


func test_build_bias_reranks_the_priority_tier() -> void:
	var neutral := Fixture.state(FUNDED_BASE_BOARD)
	assert_eq(_planned_build(neutral, AIProfile.new()), &"md_tank")

	var advised := Fixture.state(FUNDED_BASE_BOARD)
	advised.set_commander(1, ArtilleryAdviser.new())
	assert_eq(_planned_build(advised, AIProfile.new()), &"artillery")

	var blinded := Fixture.state(FUNDED_BASE_BOARD)
	blinded.set_commander(1, ArtilleryAdviser.new())
	assert_eq(_planned_build(blinded, _blind_profile()), &"md_tank")


## The urgent tiers stay urgent: with an enemy bomber overhead the planner
## builds its air answer whatever the doctrine thinks of it, and no bias pulls
## a transport onto the list's tail (the mechanism build_bias uses for an
## unlisted combat unit; a truck already on the board has no supply want of
## its own for a bias to move instead, isolating this from COM-180's clamp).
func test_urgent_tiers_and_transports_ignore_the_bias() -> void:
	var bombed := Fixture.state(
		"[terrain]\nB....\n.....\n[owners]\n1 0 0\n[units]\n1 i 1 0\n2 b 4 1"
	)
	bombed.set_commander(1, SaboteurAdviser.new())
	assert_eq(
		_planned_build(bombed, AIProfile.new()),
		&"anti_air",
		"the air-answer tier outranks any doctrine bias"
	)

	var quiet := Fixture.state(FUNDED_BASE_BOARD + "\n1 p 4 0")
	quiet.set_commander(1, SaboteurAdviser.new())
	assert_eq(
		_planned_build(quiet, AIProfile.new()),
		&"md_tank",
		"an unarmed transport has no rank on the list's tail for a bias to move"
	)


# --- the shipped economy doctrines -------------------------------------------


func _build_as(map_text: String, commander_id: StringName, funds: int) -> Command:
	var state := Fixture.state(map_text)
	if commander_id != CommanderType.NEUTRAL_ID:
		state.set_commander(1, commander_db.by_id(commander_id))
	for unit in state.units:
		unit.acted = true
	state.funds[1] = funds
	return AIController.new(unit_db).plan_next_command(state)


func _built_id(command: Command) -> StringName:
	assert_true(command is BuildCommand, "expected a build, got %s" % command)
	return (command as BuildCommand).unit_type.id


## Seven thousand in the bank buys the doctrine, not the list: the neutral
## commander takes the default's tank, Tomas Reed pulls a mech ahead of it,
## and Viktor Draeg still buys armour. Rhea Sol buys the tank too — her pull is
## deliberately too mild to divert top-end funds (test_rhea_sol.gd pins it).
func test_seven_thousand_buys_each_doctrine_its_own_unit() -> void:
	var funds := 7000
	assert_eq(_built_id(_build_as(FUNDED_BASE_BOARD, CommanderType.NEUTRAL_ID, funds)), &"tank")
	assert_eq(_built_id(_build_as(FUNDED_BASE_BOARD, &"tomas_reed", funds)), &"mech")
	assert_eq(_built_id(_build_as(FUNDED_BASE_BOARD, &"rhea_sol", funds)), &"tank")
	assert_eq(_built_id(_build_as(FUNDED_BASE_BOARD, &"viktor_draeg", funds)), &"tank")


## Four thousand is where the scouts show: the neutral commander takes the mech
## its list ranks next, while Orin Flux and Cassian Rook pull the recon — a unit
## the default list never buys at all — onto its tail and take it instead. The
## neutral one banked this board until the spend ceiling was seated
## (docs/causeway_measure.md).
func test_four_thousand_buys_the_scout_doctrines_a_recon() -> void:
	assert_eq(_built_id(_build_as(FUNDED_BASE_BOARD, CommanderType.NEUTRAL_ID, 4000)), &"mech")
	assert_eq(_built_id(_build_as(FUNDED_BASE_BOARD, &"orin_flux", 4000)), &"recon")
	assert_eq(_built_id(_build_as(FUNDED_BASE_BOARD, &"cassian_rook", 4000)), &"recon")


# --- retreat_hp_delta --------------------------------------------------------

## A tank at 55 HP sits between the profile's line (45) and the advised one
## (60): the neutral planner advances on the distant enemy, the advised one
## turns for the repair city behind it.
const WOUNDED_TANK_BOARD := """
[terrain]
C.............
[owners]
1 0 0
[units]
1 t 4 0
2 i 13 0
"""


func _advised_destination_at(hp: int) -> Vector2i:
	var advised := Fixture.state(WOUNDED_TANK_BOARD)
	advised.units[0].hp = hp
	advised.set_commander(1, EarlyRepairAdviser.new())
	return _advance_destination(advised, AIProfile.new())


func test_retreat_advice_moves_the_repair_line() -> void:
	var neutral := Fixture.state(WOUNDED_TANK_BOARD)
	neutral.units[0].hp = 55
	assert_gt(
		_advance_destination(neutral, AIProfile.new()).x,
		4,
		"at 55 HP the neutral tank still advances"
	)

	assert_lt(_advised_destination_at(55).x, 4, "the advised tank turns for the repair city")


## The delta is internal HP, not displayed pips: 45 + 15 puts the line at 60, so
## a tank on 65 fights on. Read as fifteen pips it would land at 195 and every
## unit on the board would be walking home — which is the mistake this pins.
func test_the_retreat_delta_is_internal_hp() -> void:
	assert_gt(_advised_destination_at(65).x, 4, "65 HP is above the advised line of 45 + 15 = 60")


# --- the roster's advice inventory -------------------------------------------

## The three hooks, in CommanderType's own order.
const ADVICE_HOOKS: Array[StringName] = [&"stand_value", &"build_bias", &"retreat_hp_delta"]

## Which hooks each playable general overrides. Asserted against CommanderDB's
## roster in both directions, so seating a new commander fails here until the
## table records a yes-or-no per hook — which is what keeps "advises nothing on
## purpose" distinguishable from "nobody wrote the advice yet".
const ADVICE_COVERAGE := {
	&"alina_ward": [&"stand_value"],
	&"cass_orlov": [],
	&"cassian_rook": [&"build_bias"],
	&"dane_ferrow": [],
	&"gideon_holt": [&"retreat_hp_delta"],
	&"halden_marr": [&"stand_value"],
	&"ines_calder": [&"build_bias"],
	&"iona_vance": [],
	&"iris_colt": [],
	&"ivar_thorne": [],
	&"konrad_vale": [&"build_bias"],
	&"lyra_quill": [],
	&"mara_voss": [&"stand_value"],
	&"nia_rowan": [],
	&"orin_flux": [&"build_bias"],
	&"perrin_ash": [],
	&"radek_morn": [],
	&"rhea_sol": [&"build_bias"],
	&"sable_wren": [&"stand_value"],
	&"sera_lark": [],
	&"tomas_reed": [&"build_bias"],
	&"viktor_draeg": [&"build_bias"],
}

## Why each silent doctrine is silent. A commander with no advice needs a reason
## on the record, because the seam working and the seam being unwired look the
## same from the planner's side.
const SILENT_REASONS := {
	&"cass_orlov": "A finisher: the forecasts already see the wounded target she is paid for.",
	&"dane_ferrow": "The bounty is a funds transfer on a kill the forecasts already price.",
	&"iona_vance": "Flat combat percentages in every exchange; the forecasts carry them whole.",
	&"iris_colt": "Tempo: the refresh is a rule, and a flat combat malus the forecasts read.",
	&"ivar_thorne": "Paid for staying hurt, which is an attack bonus the forecasts already have.",
	&"lyra_quill": "Her luck floor stays unpriced on purpose — forecasts are luck-free (D4).",
	&"nia_rowan": "Positional only, and MovementResolver already walks her discounted ground.",
	&"perrin_ash": "Domain-only air percentages; the forecasts carry them with no advice.",
	&"radek_morn": "Flat combat percentages, and the aim is the doctrine's own (more-CO D5).",
	&"sera_lark": "A movement bonus, so MovementResolver already plans the further reach.",
}


## The method list walks the whole script chain, so a base hook a doctrine never
## touches appears once and one it overrides appears twice — its own beside
## CommanderType's. Counting is what tells the two apart.
func _overridden_hooks(commander: CommanderType) -> Array[StringName]:
	var seen: Dictionary[StringName, int] = {}
	for method in commander.get_script().get_script_method_list():
		var name := StringName(method["name"])
		seen[name] = seen.get(name, 0) + 1
	var found: Array[StringName] = []
	for hook in ADVICE_HOOKS:
		if seen.get(hook, 0) > 1:
			found.append(hook)
	return found


func test_every_general_records_which_hooks_it_advises_through() -> void:
	var roster := commander_db.playable()
	assert_gt(roster.size(), 0, "no playable commanders loaded, so this would pass vacuously")
	for commander in roster:
		assert_true(
			ADVICE_COVERAGE.has(commander.id),
			"%s is on the roster but not in ADVICE_COVERAGE" % commander.id
		)
		assert_eq(
			_overridden_hooks(commander),
			ADVICE_COVERAGE.get(commander.id, [] as Array[StringName]),
			"%s advises through different hooks than the table records" % commander.id
		)
	assert_eq(
		ADVICE_COVERAGE.size(), roster.size(), "ADVICE_COVERAGE names a commander off the roster"
	)


func test_every_silent_doctrine_records_why() -> void:
	for id: StringName in ADVICE_COVERAGE:
		var silent: bool = (ADVICE_COVERAGE[id] as Array).is_empty()
		assert_eq(
			SILENT_REASONS.has(id),
			silent,
			"%s: SILENT_REASONS and ADVICE_COVERAGE disagree about whether it advises" % id
		)


# --- D4: advice is a pure read -----------------------------------------------


## Every hook, asked twice on one board: the same answer both times and the board
## untouched between them, so a replan off one board cannot disagree with itself.
## An unkeyed memo is out of this case's reach by construction — an unchanged
## board is what a stale memo answers correctly — so the invalidating half is
## `test_mara_voss.gd::test_stand_advice_re_reads_reach_on_a_later_turn`.
func test_advice_is_pure() -> void:
	var state := Fixture.state("[terrain]\nCF.\n...\n[owners]\n1 0 0\n[units]\n1 t 1 0\n2 i 2 1")
	var tank := state.units[0]
	for commander in commander_db.playable():
		state.set_commander(1, commander)
		var before := ReplayCodec.checkpoint(state)
		var cell := Vector2i(1, 1)
		assert_eq(
			commander.stand_value(state, tank, cell),
			commander.stand_value(state, tank, cell),
			"%s.stand_value answered twice differently" % commander.id
		)
		assert_eq(
			commander.build_bias(state, 1, tank.type),
			commander.build_bias(state, 1, tank.type),
			"%s.build_bias answered twice differently" % commander.id
		)
		assert_eq(
			commander.retreat_hp_delta(state, tank),
			commander.retreat_hp_delta(state, tank),
			"%s.retreat_hp_delta answered twice differently" % commander.id
		)
		assert_eq(ReplayCodec.checkpoint(state), before, "%s advice moved the board" % commander.id)
