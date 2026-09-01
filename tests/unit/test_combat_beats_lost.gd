extends GutTest
## The seam field CombatBeats.plan hands back: how many figures each side's own
## casualty window was actually sized for.
##
## In scope on the same terms test_combat_beats.gd already earns (see
## docs/testing_exceptions.md's CombatBeats entry): plan() is still a pure
## function with no Node in it. Kept in its own file rather than folded into
## test_combat_beats.gd, which the animation-frames plan pins as untouched —
## its timing asserts do not move here, only a new field is read.
##
## Why it exists: CutsceneSide's own knock-back re-derived "how many figures
## were lost" from squad counts (`squad_was - squad_now`) rather than reading
## CombatBeats' own answer. The two agree today — CombatCutscene._squads applies
## the same "a dying side keeps its squad whole for the blast" rule the window
## was sized under, so both said 0 for a kill — but they agree by coincidence of
## two rules matching, not by construction. def_lost/atk_lost makes it one
## answer, so no frame was moved and none can drift.

var styles: BattleStyleDB


func before_each() -> void:
	styles = BattleStyleDB.load_default()


func test_def_lost_matches_the_defenders_own_figure_count_when_it_survives() -> void:
	var beats := CombatBeats.plan(_losing(2), _style(&"cannon"), _style(&"cannon"), 1.0, 1.0)
	assert_eq(beats.def_lost, 2)


func test_atk_lost_matches_the_attackers_own_figure_count_on_a_counter() -> void:
	var beats := CombatBeats.plan(
		_counter_losing(0, 1), _style(&"cannon"), _style(&"cannon"), 1.0, 1.0
	)
	assert_eq(beats.atk_lost, 1)


## The seam field's whole point: a dying side reports zero lost even though its
## squad, read off HP alone, would otherwise show every figure gone — because
## CutsceneSide keeps a dying side's squad whole for the blast rather than
## toppling it figure by figure first, and def_lost has to agree with that
## rather than with the raw HP swing.
func test_a_dying_defender_reports_zero_lost_despite_the_full_hp_swing() -> void:
	var result := _losing(5)
	result.defender_died = true
	var beats := CombatBeats.plan(result, _style(&"cannon"), _style(&"cannon"), 1.0, 1.0)
	assert_eq(beats.def_lost, 0)


func test_a_dying_attacker_reports_zero_lost_despite_the_full_hp_swing() -> void:
	var result := _counter_losing(0, 5)
	result.attacker_died = true
	var beats := CombatBeats.plan(result, _style(&"cannon"), _style(&"cannon"), 1.0, 1.0)
	assert_eq(beats.atk_lost, 0)


func _style(id: StringName) -> BattleStyle:
	return styles.by_id(id)


func _clean() -> CombatSnapshot.CombatResult:
	var result := CombatSnapshot.CombatResult.new()
	result.attacker_hp_before = 10
	result.attacker_hp_after = 10
	result.defender_hp_before = 10
	result.defender_hp_after = 10
	return result


func _losing(lost: int) -> CombatSnapshot.CombatResult:
	var result := _clean()
	result.defender_hp_after = result.defender_hp_before - lost * 2
	return result


func _counter_losing(defender_lost: int, attacker_lost: int) -> CombatSnapshot.CombatResult:
	var result := _losing(defender_lost)
	result.countered = true
	result.attacker_hp_after = result.attacker_hp_before - attacker_lost * 2
	return result
