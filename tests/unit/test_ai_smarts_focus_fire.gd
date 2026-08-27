extends GutTest
## S2 · focus fire: the bonus that prefers the target the team can finish
## together, and the two things it must not do.
##
## Split off tests/unit/test_ai_smarts.gd, whose header states why almost every
## test here builds its own profile rather than loading a shipped tier.

var unit_db: UnitDB


func before_each() -> void:
	unit_db = Fixture.unit_db()


func _profile() -> AIProfile:
	return AIProfile.new()  # every capability off; the Normal baseline


## Two identical targets, both in reach of the acting tank. The far one is the
## one a second tank could also pile onto this turn; the near one nobody can
## follow up on. The base planner takes the near one because it is cheaper to
## reach; focus fire takes the one the team can finish together.
func test_focus_fire_picks_the_target_the_team_can_finish() -> void:
	var map_text := "[terrain]\n................\n[units]\n1 t 5 0\n1 t 15 0\n2 t 3 0\n2 t 8 0"

	var scattered := AIController.new(unit_db, _profile()).plan_next_command(
		Fixture.state(map_text)
	)
	assert_true(scattered is AttackCommand, "expected an attack, got %s" % scattered)
	assert_eq(
		(scattered as AttackCommand).target_cell,
		Vector2i(3, 0),
		"the base planner takes the cheapest shot it can reach"
	)

	var focused_profile := _profile()
	focused_profile.focus_fire_bonus = 0.4
	var focused_state := Fixture.state(map_text)
	var focused := AIController.new(unit_db, focused_profile).plan_next_command(focused_state)
	assert_true(focused is AttackCommand, "expected an attack, got %s" % focused)
	assert_eq(
		(focused as AttackCommand).target_cell,
		Vector2i(8, 0),
		"focus fire prefers the target a second tank can still add damage to"
	)
	assert_eq(focused.validate(focused_state), "")


## A shot that already kills needs no follow-up, so focus fire must not inflate
## it — otherwise the AI would rate finished targets above fresh ones.
func test_focus_fire_adds_nothing_to_a_shot_that_already_kills() -> void:
	var map_text := "[terrain]\n....\n[units]\n1 t 0 0\n2 i 1 0\n2 i 3 0"
	var state := Fixture.state(map_text)
	state.units[1].hp = 10  # one shot finishes it
	var focused_profile := _profile()
	focused_profile.focus_fire_bonus = 5.0
	var command := AIController.new(unit_db, focused_profile).plan_next_command(state)
	assert_true(command is AttackCommand)
	assert_eq(
		(command as AttackCommand).target_cell, Vector2i(1, 0), "the kill is still the best shot"
	)


## The follow-up total credits only friendlies that could actually land a shot,
## so it routes who-may-shoot through AttackRange.can_engage — not the damage
## chart raw. A battleship has a chart entry against subs but cannot hit a
## submerged one, exactly the shot AttackCommand.validate would refuse; crediting
## its follow-up would over-rank a cruiser's attack on a dived sub. The gate is
## the dive and only the dive: a cruiser hits submerged and a surfaced sub is an
## ordinary target, so both of those still count in full.
##
## One function rather than three because test_ai_smarts.gd is at the lint's
## public-method ceiling; the three scenarios read as one claim about the gate.
func test_follow_up_gates_a_dived_sub_on_can_engage() -> void:
	var planner := AIUnitActionPlanner.new(_profile())
	var context := AIPlanningContext.new(unit_db)
	var battleship_board := "[terrain]\nSSSSSSSS\n[units]\n1 c 0 0\n1 B 4 0\n2 s 7 0"

	# A battleship cannot hit a submerged sub, so it adds no follow-up.
	var dived := Fixture.state(battleship_board)
	var dived_sub := dived.units_of(2)[0]
	dived_sub.dived = true
	context.begin(dived)
	assert_eq(
		planner._follow_up_damage(context, dived.units_of(1)[0], dived_sub),
		0,
		"a battleship threatens a dived sub with nothing it could legally land",
	)

	# The same battleship against a surfaced sub is unchanged: an ordinary target.
	var surfaced := Fixture.state(battleship_board)
	context.begin(surfaced)
	assert_gt(
		planner._follow_up_damage(context, surfaced.units_of(1)[0], surfaced.units_of(2)[0]),
		0,
		"a surfaced sub is a legal battleship target, so its follow-up still counts",
	)

	# A cruiser can hit submerged, so a dive does not hide the sub from its follow-up.
	var hunted := Fixture.state("[terrain]\nSSSSSSSS\n[units]\n1 B 0 0\n1 c 6 0\n2 s 7 0")
	var hunted_sub := hunted.units_of(2)[0]
	hunted_sub.dived = true
	context.begin(hunted)
	assert_gt(
		planner._follow_up_damage(context, hunted.units_of(1)[0], hunted_sub),
		0,
		"a cruiser hits submerged, so its follow-up still counts against a dive",
	)
