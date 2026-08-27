extends GutTest
## What the threat map reads, and what it must not do while reading it: a pure
## measurement of a cell, taken through the same authorities the rules use.
##
## The dials that spend its numbers are tests/unit/test_ai_smarts.gd's.

## Twin of the const in tests/unit/test_ai_smarts.gd.
const ARTILLERY_RING_BOARD := "[terrain]\n..........\n[units]\n1 t 0 0\n2 g 9 0"

var terrain_db: TerrainDB
var unit_db: UnitDB
var chart: DamageChart
var commander_db: CommanderDB


func before_each() -> void:
	terrain_db = Fixture.terrain_db()
	unit_db = Fixture.unit_db()
	chart = Fixture.chart()
	commander_db = Fixture.commander_db()


func _profile() -> AIProfile:
	return AIProfile.new()  # every capability off; the Normal baseline


## The threat map reads the board through the same authorities as everything
## else, so a unit that cannot be hurt at all registers no threat.
func test_an_unreachable_enemy_threatens_nothing() -> void:
	# Sea splits the board: the enemy tank can never reach the left half.
	var map_text := "[terrain]\n...S...\n[units]\n1 t 0 0\n2 t 6 0"
	var wary_profile := _profile()
	wary_profile.threat_aversion = 5.0
	wary_profile.advance_threat_tiles = 5.0
	var wary := AIController.new(unit_db, wary_profile).plan_next_command(Fixture.state(map_text))
	var blind := AIController.new(unit_db, _profile()).plan_next_command(Fixture.state(map_text))
	assert_true(wary is MoveCommand and blind is MoveCommand)
	assert_eq(
		(wary as MoveCommand).path,
		(blind as MoveCommand).path,
		"with nothing able to shoot us, threat awareness changes nothing"
	)


## The map measures a cell by asking what the damage would be with the defender
## *at* it — the terrain it would move onto is exactly what changes the number —
## and asks through an effective cell rather than by moving anything. Scoring a
## move must leave no trace on the board at all.
func test_measuring_a_cell_never_moves_the_unit() -> void:
	var state := Fixture.state(ARTILLERY_RING_BOARD)
	var tank := state.units_of(1)[0]
	var origin := tank.cell
	var before := _board_snapshot(state)
	var map := ThreatMap.build(state, state.units_of(2))
	assert_gt(
		map.incoming_damage(state, tank, Vector2i(7, 0)), 0, "the ring must actually threaten"
	)
	assert_eq(_board_snapshot(state), before, "measuring a cell changed the board")
	assert_eq(state.unit_at(origin), tank, "and the board still finds it where it was")


## A battleship on the surface threatens a sea cell, and the map routes its
## who-may-shoot question through AttackRange.can_engage — so a dived friendly sub
## sitting in that cell is charged nothing. The battleship has a chart entry
## against subs but cannot hit a submerged one, exactly the shot AttackCommand
## would refuse; pricing it in would make the boat flee threats that do not exist.
func test_a_battleship_does_not_threaten_a_dived_sub() -> void:
	var state := Fixture.state("[terrain]\nSSSSSSS\n[units]\n1 s 0 0\n2 B 3 0")
	var sub := state.units_of(1)[0]
	sub.dived = true
	var map := ThreatMap.build(state, state.units_of(2))
	assert_eq(
		map.incoming_damage(state, sub, Vector2i(0, 0)),
		0,
		"a battleship cannot hit a submerged sub, so it threatens it with nothing",
	)


## The gate is the dive and only the dive: a cruiser can hit submerged, so going
## under does not hide the boat from it and the map still prices its forecast.
func test_a_cruiser_still_threatens_a_dived_sub() -> void:
	var state := Fixture.state("[terrain]\nSSSSSSS\n[units]\n1 s 0 0\n2 c 3 0")
	var sub := state.units_of(1)[0]
	sub.dived = true
	var map := ThreatMap.build(state, state.units_of(2))
	assert_gt(
		map.incoming_damage(state, sub, Vector2i(0, 0)),
		0,
		"a cruiser can hit submerged, so a dive does not hide the sub from it",
	)


## And an undived sub is an ordinary battleship target, so the gate leaves the
## surfaced number untouched: routing through can_engage changed nothing here.
func test_an_undived_sub_still_takes_the_battleships_forecast() -> void:
	var state := Fixture.state("[terrain]\nSSSSSSS\n[units]\n1 s 0 0\n2 B 3 0")
	var sub := state.units_of(1)[0]
	var map := ThreatMap.build(state, state.units_of(2))
	assert_gt(
		map.incoming_damage(state, sub, Vector2i(0, 0)),
		0,
		"a surfaced sub is a legal battleship target and takes its forecast",
	)


## COM-176: the map's "any in-range origin gives the same number" claim is false
## against Alina Ward, whose combined_arms_pct reads the firing cell. This tank
## has two legal firing cells for the same target — its own cell, beside a
## mixed-class friendly, and a cell it could walk to with no friendly beside it
## — and CombatResolver.forecast_at genuinely disagrees between them. The map
## still prices the cell from the enemy's current position (threat_map.gd), so
## it happens to agree with the mixed origin here; that is the approximation
## being pinned, not a claim that the map is right in general.
func test_ward_combined_arms_makes_the_firing_cell_matter_to_the_map() -> void:
	var state := Fixture.state("[terrain]\n......\n......\n[units]\n1 t 3 0\n1 i 3 1\n2 i 4 0")
	state.rng.seed = 1
	state.set_commander(1, commander_db.by_id(&"alina_ward"))
	var tank := state.units[0]
	var defender := state.units[2]
	var mixed_origin := tank.cell  # (3,0): the infantry at (3,1) stands beside it
	var lone_origin := Vector2i(5, 0)  # reachable, and nothing stands beside it
	assert_true(
		lone_origin in AttackRange.firing_cells(state, tank),
		"both cells are legal firing positions for this tank"
	)
	var mixed := CombatResolver.forecast_at(state, tank, mixed_origin, defender, defender.cell)
	var lone := CombatResolver.forecast_at(state, tank, lone_origin, defender, defender.cell)
	assert_eq(mixed.attack_damage, 74, "combined arms lifts the shot fired beside the infantry")
	assert_eq(lone.attack_damage, 68, "the neutral number from a firing cell with no neighbour")

	var map := ThreatMap.build(state, [tank])
	assert_eq(
		map.incoming_damage(state, defender, defender.cell),
		mixed.attack_damage,
		(
			"the map prices every threat from the enemy's current cell, so it matches"
			+ " the mixed origin here rather than the (also legal) lone one"
		)
	)


## The same guarantee across a whole Difficult turn on a real board: the sim
## changes when a command is *applied*, never while one is being planned. Guards
## the pure read above from anything a future capability adds beside it.
func test_planning_a_difficult_turn_leaves_the_board_untouched() -> void:
	var map := MapData.load_from_file("res://maps/first_steps.txt", terrain_db)
	var state := GameState.create(map, unit_db, chart)
	state.rng.seed = 7
	EndTurnCommand.new().apply(state)  # Blue, the AI side, is to move
	var ai := AIController.new(unit_db, DifficultyDB.load_default().by_id(&"hard").profile())
	var planned := 0
	for i in 60:
		var before := _board_snapshot(state)
		var command := ai.plan_next_command(state)
		assert_eq(_board_snapshot(state), before, "planning moved or hurt something")
		command.apply(state)
		planned += 1
		if command is EndTurnCommand:
			break
	assert_gt(planned, 3, "the reference turn should be more than a formality")


## Every unit's side, kind, position and HP, in the order the sim holds them.
func _board_snapshot(state: GameState) -> Array[String]:
	var rows: Array[String] = []
	for unit in state.units:
		rows.append("%d %s %s hp=%d" % [unit.team, unit.type.id, unit.cell, unit.hp])
	return rows
