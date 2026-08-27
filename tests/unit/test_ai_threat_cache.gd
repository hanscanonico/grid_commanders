extends GutTest
## What the threat map is cached against: the day, the planning team and the
## visible enemy set, each read exactly. The map survives between the commands
## of one turn on purpose, so a signature that misses a change hands the planner
## a stale reading of ground that has moved — a defect no board-diff test can
## see, the plan cache dropping its plans on the diff rather than on this key.


func _context(state: GameState) -> AIPlanningContext:
	var context := AIPlanningContext.new(Fixture.unit_db())
	context.begin(state)
	return context


func test_the_map_is_reused_while_the_board_stands_still() -> void:
	var state := Fixture.state("[terrain]\n........\n[units]\n1 i 0 0\n2 t 6 0")
	var context := _context(state)
	var first := context.threat_map()
	assert_true(context.threat_map_built(), "the board has not moved since the build")
	assert_eq(context.threat_map(), first, "so the second ask is the same map")


## The tank drives and then shoots, so the ground it threatens reaches far past
## its own cell — the probe is the first cell outside that envelope, which one
## tile of movement brings inside it.
func test_an_enemys_step_rebuilds_the_map() -> void:
	var state := Fixture.state("[terrain]\n%s\n[units]\n1 i 0 0\n2 t 29 0" % ".".repeat(30))
	var context := _context(state)
	var infantry := state.units_of(1)[0]
	var tank := state.units_of(2)[0]
	var before := context.threat_map()
	var probe := Vector2i(21, 0)
	assert_eq(before.incoming_damage(state, infantry, probe), 0, "the tank cannot reach (21, 0)")

	MoveCommand.new(tank, Fixture.path([Vector2i(29, 0), Vector2i(28, 0)])).apply(state)
	context.begin(state)
	assert_false(context.threat_map_built(), "one tile of enemy movement is a different board")
	var after := context.threat_map()
	assert_ne(after, before, "so the map is built again")
	assert_gt(
		after.incoming_damage(state, infantry, probe), 0, "and it fears the cell it now covers"
	)


func test_the_same_enemies_on_a_new_day_rebuild_the_map() -> void:
	var state := Fixture.state("[terrain]\n........\n[units]\n1 i 0 0\n2 t 6 0")
	var context := _context(state)
	var before := context.threat_map()
	state.day += 1
	context.begin(state)
	assert_false(context.threat_map_built(), "a map belongs to the turn it was built in")
	assert_ne(context.threat_map(), before, "so a new day builds its own")
