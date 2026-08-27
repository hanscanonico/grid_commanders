extends GutTest
## The suite's own board builder. Small, because the helper is small — but the
## caching is worth a test of its own: a registry handed out once for the process
## is shared mutable state, and the argument that it is safe rests on the engine
## already sharing the resources behind it.


func test_a_board_becomes_a_match() -> void:
	var state := Fixture.state("[terrain]\n.C\n[units]\n1 t 0 0\n2 i 1 0")
	assert_not_null(state)
	assert_eq(state.map.width, 2)
	assert_eq(state.units.size(), 2)
	assert_eq(state.unit_at(Vector2i(0, 0)).type.id, &"tank")
	assert_true(state.map.terrain_at(Vector2i(1, 0)).is_property, "the terrain db is behind it")
	assert_eq(state.teams, [1, 2] as Array[int])


## Nobody is seated unless the caller says so, because that is what most boards
## want: a neutral commander is the doctrine-free match every rules test reads.
func test_a_board_seats_nobody_by_default() -> void:
	var state := Fixture.state("[terrain]\n..\n[units]\n1 t 0 0")
	assert_eq(state.commander_of(1).id, CommanderType.NEUTRAL_ID)


func test_commanders_are_seated_by_id_and_by_team() -> void:
	var state := Fixture.state(
		"[terrain]\n..\n[units]\n1 t 0 0\n2 t 1 0", {1: &"alina_ward", 2: &"viktor_draeg"}
	)
	assert_eq(state.commander_of(1).id, &"alina_ward")
	assert_eq(state.commander_of(2).id, &"viktor_draeg")


func test_a_path_comes_back_typed() -> void:
	var path := Fixture.path([Vector2i(0, 0), Vector2i(1, 0)])
	assert_eq(path.size(), 2)
	assert_true(path is Array[Vector2i], "the commands take a typed path")


## The cache hands back one registry per process, and the resources it indexes
## are the same objects a fresh `load_default()` finds — which is the whole of
## why sharing it adds no hazard the engine's own resource cache had not.
func test_the_cached_databases_are_the_shipped_ones() -> void:
	assert_same(Fixture.unit_db(), Fixture.unit_db(), "one registry per process")
	assert_same(Fixture.terrain_db(), Fixture.terrain_db())
	assert_same(
		Fixture.unit_db().by_id(&"tank"),
		UnitDB.load_default().by_id(&"tank"),
		"and the unit types in it are the ones every other loader gets"
	)
	assert_same(Fixture.chart(), load("res://data/damage_chart.tres"))


## COM-206's proof: a state built by the fixture draws combat luck from a fixed
## seed rather than the engine's own entropy, so the same shot resolves to the
## same HP on every run. A neutral Tank has no primary weapon entry against
## Infantry (the secondary MG is the shot the chart selects), so this is the
## unit_pricing plan's "only the secondary is in scope" matchup as well as the
## simplest deterministic one to pin.
func test_the_default_seed_is_pinned() -> void:
	var state := Fixture.state("[terrain]\n..\n[units]\n1 t 0 0\n2 i 1 0")
	var attacker := state.units[0]
	var defender := state.units[1]
	var command := AttackCommand.new(attacker, Fixture.path([Vector2i(0, 0)]), Vector2i(1, 0))
	assert_eq(command.validate(state), "")
	command.apply(state)
	assert_eq(defender.hp, 28, "seed %d's roll on a fixed matchup" % Fixture.DEFAULT_SEED)


## The from-disk sibling owes the same two things `state` does — the pinned seed
## and, additionally, the `map_path` a save, a replay and a resume read the board
## back through.
func test_a_board_from_disk_is_seeded_and_knows_where_it_came_from() -> void:
	var state := Fixture.state_from_file("res://maps/first_steps.txt")
	assert_not_null(state)
	assert_eq(state.map_path, "res://maps/first_steps.txt")
	assert_eq(state.rng.seed, Fixture.DEFAULT_SEED)
	assert_false(state.units.is_empty(), "the board on disk brought its army")


## A board that does not parse is refused rather than handed to `GameState.create`,
## which dereferences the map it is given — so a typo in a test's board reads as a
## failed assertion naming the board instead of a null dereference in the sim.
func test_a_board_that_does_not_parse_is_refused() -> void:
	assert_null(Fixture.state("this is not a board"))
	assert_push_error("line outside a known section")
