extends GutTest
## AR6c · two half-dead units become one whole one.
##
## `JoinCommand` has existed since the transports landed and `ai/` had never
## named it, so the computer accumulated wounded units all match: two 4-HP
## infantry are the same funds as one 8-HP infantry, with half the board presence
## and twice the exposure to a kill bonus. The join is a scored candidate beside
## the dive and the withdrawal (AI Judgement D4), never a rule.
##
## Every test is one board reached twice, with the dial off and on. The off runs
## are the inertness pin the Judgement contract owes: they are what makes "0
## skips the code" a fact about the board rather than about a guard clause.

## Two 40-HP infantry side by side with the enemy far enough east that neither
## can reach it this turn. Merging is the only thing on the board worth doing.
const TWO_WOUNDED_TWINS := (
	"[terrain]\n" + "........................\n" + "[units]\n1 i 0 0\n1 i 1 0\n2 i 23 0"
)

## The tie, built to be exact. Our 40-HP tank at (2, 0) can spend one step to
## kill the 20-HP enemy tank — worth 7 000 x 20/100 — or one step to merge into
## the 30-HP twin behind it, worth join_weight x 7 000 x 40/100. At 0.5 the two
## come to the same number, down to the step each of them pays.
const A_KILL_AND_A_MERGE := "[terrain]\n.....\n[units]\n1 t 1 0\n1 t 2 0\n2 t 4 0"

const TWIN := Vector2i(1, 0)
const OUR_TANK := Vector2i(2, 0)
const ENEMY_TANK := Vector2i(4, 0)

var terrain_db: TerrainDB
var unit_db: UnitDB
var chart: DamageChart


func before_each() -> void:
	terrain_db = TerrainDB.load_default()
	unit_db = UnitDB.load_default()
	chart = load("res://data/damage_chart.tres")


## Normal's shipped numbers with the join dial moved. `kill_bonus` is exposed
## because the tie board needs it at 1.0 to be a tie at all — what that test pins
## is the comparison, not the bonus.
func _profile(join_weight: float, kill_bonus := 1.6) -> AIProfile:
	var profile := AIProfile.new()
	profile.join_weight = join_weight
	profile.kill_bonus = kill_bonus
	return profile


func _state(map_text: String, wounds: Dictionary) -> GameState:
	var map := MapData.parse(map_text, terrain_db)
	var state := GameState.create(map, unit_db, chart)
	assert_not_null(state)
	for unit in state.units:
		if wounds.has(unit.cell):
			unit.hp = wounds[unit.cell]
	return state


func _plan(map_text: String, profile: AIProfile, wounds: Dictionary = {}) -> Command:
	return _plan_on(_state(map_text, wounds), profile)


func _plan_on(state: GameState, profile: AIProfile) -> Command:
	return AIController.new(unit_db, profile).plan_next_command(state)


## Plays team 1's whole turn and returns its surviving units' HP, by cell.
func _play_a_turn(map_text: String, profile: AIProfile, wounds: Dictionary) -> Dictionary:
	var state := _state(map_text, wounds)
	var ai := AIController.new(unit_db, profile)
	for _step in range(8):
		var command := ai.plan_next_command(state)
		if command is EndTurnCommand or command.validate(state) != "":
			break
		command.apply(state)
	var left: Dictionary = {}
	for unit in state.units:
		if unit.team == 1:
			left[unit.cell] = unit.hp
	return left


## The ticket's own case: the AI keeps two halves of a unit it could have made
## whole, all match.
func test_two_wounded_twins_merge_into_one() -> void:
	var wounds := {Vector2i(0, 0): 40, Vector2i(1, 0): 40}

	var apart := _play_a_turn(TWO_WOUNDED_TWINS, _profile(0.0), wounds)
	assert_eq(apart.size(), 2, "blind, both units act for themselves and stay two units")
	for cell: Vector2i in apart:
		assert_eq(apart[cell], 40, "and neither of them is any healthier for it")

	var merged := _play_a_turn(TWO_WOUNDED_TWINS, _profile(0.5), wounds)
	assert_eq(merged.size(), 1, "with the dial on, the two halves become one unit")
	assert_eq(merged.values()[0], 80, "carrying every point of the mover onto the target")


## The strict comparison the dive precedent sets, on a board where the two
## candidates are worth *exactly* the same: 1 396 each, one step apart. Attacks
## are weighed before joins and every comparison is `>`, so a merge that merely
## ties with a shot loses to it.
func test_a_join_that_ties_with_a_shot_loses_to_it() -> void:
	var wounds := {TWIN: 30, OUR_TANK: 40, ENEMY_TANK: 20}
	var tied := _plan(A_KILL_AND_A_MERGE, _profile(0.5, 1.0), wounds)
	assert_true(tied is AttackCommand, "expected the kill, got %s" % tied)
	assert_eq(
		(tied as AttackCommand).target_cell, ENEMY_TANK, "and the kill is the one on the ballot"
	)


## The other side of that boundary, which is what makes the tie a tie rather than
## a candidate nobody scored: a hair more weight and the merge wins the same
## board.
func test_a_join_worth_more_than_the_shot_wins_it() -> void:
	var wounds := {TWIN: 30, OUR_TANK: 40, ENEMY_TANK: 20}
	var command := _plan(A_KILL_AND_A_MERGE, _profile(0.51, 1.0), wounds)
	if not (command is JoinCommand):
		fail_test("expected a merge, got %s" % command)
		return
	var path: Array[Vector2i] = (command as JoinCommand).path
	assert_eq(path[path.size() - 1], TWIN, "into the twin one step behind it")


## The play a dial that could not see the cap would make constantly: a fresh unit
## folded into a wounded one, where three fifths of it hits the ceiling and is
## gone. The overflow is charged at face value, so this never scores above doing
## nothing — and it is the healthy unit that would have to move, because
## JoinCommand refuses a target at full strength.
func test_a_healthy_unit_is_never_poured_into_a_wounded_one() -> void:
	var wounds := {Vector2i(1, 0): 60}
	var left := _play_a_turn(TWO_WOUNDED_TWINS, _profile(0.5), wounds)
	assert_eq(left.size(), 2, "the merge would destroy 60 of the 100 points that moved")
	assert_true(left.values().has(100), "so the healthy unit is still whole and still its own unit")


## Whether a merge is legal at all is JoinCommand's answer and this asks for it
## rather than keeping a copy: a target that has already acted is refused there,
## and a planner that decided for itself would hand the pipeline a command it
## rejects — which costs the army the whole turn, not just the merge.
func test_a_twin_that_has_already_acted_is_not_a_join_at_all() -> void:
	var state := _state(TWO_WOUNDED_TWINS, {Vector2i(0, 0): 40, Vector2i(1, 0): 40})
	for unit in state.units:
		if unit.cell == Vector2i(1, 0):
			unit.acted = true
	var command := _plan_on(state, _profile(0.5))
	assert_false(command is JoinCommand, "a spent twin cannot be merged into, at any weight")
	assert_eq(command.validate(state), "", "and whatever is planned instead has to be playable")
