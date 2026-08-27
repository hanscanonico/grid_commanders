extends GutTest
## S3 · counter-building: buying what the damage chart says hurts the roster in
## front of us, rather than the next thing on the list.
##
## Split off tests/unit/test_ai_smarts.gd, whose header states why almost every
## test here builds its own profile rather than loading a shipped tier.

var unit_db: UnitDB


func before_each() -> void:
	unit_db = Fixture.unit_db()


func _profile() -> AIProfile:
	return AIProfile.new()  # every capability off; the Normal baseline


## An armour-heavy enemy roster with the heavy hammer priced out of reach. The
## static list buys the next thing on it; reactivity buys what the damage chart
## says actually hurts tanks.
func test_reactive_building_answers_an_armour_roster() -> void:
	var map_text := (
		"[terrain]\nB.......\n[owners]\n1 0 0\n"
		+ "[units]\n1 i 1 0\n1 i 2 0\n1 i 3 0\n2 t 5 0\n2 t 6 0\n2 t 7 0"
	)

	var static_pick := _build_pick(map_text, _profile())
	assert_eq(
		static_pick, &"tank", "the static list buys the best thing on it that the funds allow"
	)

	var reactive_profile := _profile()
	reactive_profile.build_reactivity = 1.0
	assert_eq(
		_build_pick(map_text, reactive_profile),
		&"rockets",
		"against tank spam the chart's answer is rockets, which the list never names"
	)


## Reactivity re-ranks the buy; it never buys something the funds do not cover.
func test_reactive_building_still_respects_the_purse() -> void:
	var map_text := (
		"[terrain]\nB.......\n[owners]\n1 0 0\n"
		+ "[units]\n1 i 1 0\n1 i 2 0\n1 i 3 0\n2 t 5 0\n2 t 6 0\n2 t 7 0"
	)
	var reactive_profile := _profile()
	reactive_profile.build_reactivity = 1.0
	var state := Fixture.state(map_text)
	state.funds[1] = 6500  # rockets and tank both out of reach
	for unit in state.units:
		unit.acted = true
	var command := AIController.new(unit_db, reactive_profile).plan_next_command(state)
	assert_true(command is BuildCommand, "expected a build, got %s" % command)
	var built: UnitType = (command as BuildCommand).unit_type
	assert_lt(built.cost, 6500, "never buys what it cannot pay for")
	assert_eq(built.id, &"artillery", "the best affordable answer to armour")
	assert_eq(command.validate(state), "")


## Before contact there is no roster to answer, so reactivity must fall back to
## the order the profile already ships rather than picking off a table of zeroes.
func test_reactive_building_falls_back_to_the_list_with_no_enemy_seen() -> void:
	var map_text := "[terrain]\nB...\n[owners]\n1 0 0\n[units]\n1 i 1 0\n1 i 2 0\n1 i 3 0"
	var reactive_profile := _profile()
	reactive_profile.build_reactivity = 1.0
	assert_eq(
		_build_pick(map_text, reactive_profile),
		_build_pick(map_text, _profile()),
		"with no enemy in sight the static list decides, exactly as it always did"
	)


## Plans the one build the given profile makes on `map_text` with 15,000 in the
## bank — enough for everything but the md_tank, which is where counter-building
## has anything to say.
##
## Saving up is switched off because it would answer a different question: with
## the md_tank one turn of income out of reach, the planner would rightly bank
## rather than buy, and these tests pin *what* the team buys, not *when*.
func _build_pick(map_text: String, profile: AIProfile) -> StringName:
	var state := Fixture.state(map_text)
	profile.save_up_turns = 0
	state.funds[1] = 15000
	for unit in state.units:
		unit.acted = true
	var command := AIController.new(unit_db, profile).plan_next_command(state)
	assert_true(command is BuildCommand, "expected a build, got %s" % command)
	if not (command is BuildCommand):
		return &""
	assert_eq(command.validate(state), "")
	return (command as BuildCommand).unit_type.id
