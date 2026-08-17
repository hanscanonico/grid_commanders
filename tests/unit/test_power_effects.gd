extends GutTest
## PowerEffects: what a fired Command Power leaves the board able to show.
##
## The class is presentation, but it is Node-free and pure — the marks are a diff
## of two snapshots — so what a power marks is checked here rather than by eye,
## the way PathArrow.segments and SeatStrip.normalised_sides are.


func _state(map_text: String, commander: StringName) -> GameState:
	return Fixture.state(map_text, {1: commander})


## Fires team 1's power and hands back the marks it earned, exactly as
## BattleCommandPipeline takes them: the snapshot before apply, the footprint
## from the doctrine, the marks after.
func _fire(state: GameState) -> Array[PowerEffects.Mark]:
	var team := state.current_team
	var before := PowerEffects.snapshot(state)
	var blast := state.commander_of(team).power_blast_cells(state, team, Vector2i.ZERO)
	assert_eq(Fixture.fire_power(state), "", "the power fires")
	return PowerEffects.marks(before, state, blast)


func _kinds_at(marks: Array[PowerEffects.Mark], cell: Vector2i) -> Array:
	var kinds := []
	for mark in marks:
		if mark.cell == cell:
			kinds.append(mark.kind)
	return kinds


# --- health ------------------------------------------------------------------


func test_a_heal_marks_the_pip_it_put_back() -> void:
	var state := _state("[terrain]\n=====\n[units]\n1 t 0 0\n1 t 2 0", &"gideon_holt")
	state.units[0].hp = 90
	state.units[1].fuel = 1
	var marks := _fire(state)
	assert_eq(_kinds_at(marks, Vector2i(0, 0)), [PowerEffects.Kind.HEALED], "a pip back")
	assert_eq(marks[0].pips, 1, "one displayed pip, not ten internal ones")
	assert_eq(_kinds_at(marks, Vector2i(2, 0)), [PowerEffects.Kind.RESUPPLIED], "a full tank")


func test_a_swing_marks_both_sides_of_the_board() -> void:
	var state := _state("[terrain]\n=====\n[units]\n1 t 0 0\n2 t 4 0", &"iona_vance")
	state.units[0].hp = 90
	var marks := _fire(state)
	assert_eq(_kinds_at(marks, Vector2i(0, 0)), [PowerEffects.Kind.HEALED], "her own unit heals")
	assert_eq(_kinds_at(marks, Vector2i(4, 0)), [PowerEffects.Kind.HARMED], "the enemy bleeds")


func test_a_refreshed_unit_is_marked_as_one() -> void:
	var state := _state("[terrain]\n=====\n[units]\n1 t 0 0", &"iris_colt")
	state.units[0].acted = true
	state.units[0].refreshable = true
	assert_eq(_kinds_at(_fire(state), Vector2i(0, 0)), [PowerEffects.Kind.REFRESHED])


# --- the aimed power ---------------------------------------------------------


func test_hammerfall_marks_its_whole_footprint() -> void:
	var state := _state("[terrain]\n=====\n=====\n=====\n[units]\n1 t 4 2\n2 t 1 1", &"radek_morn")
	var marks := _fire(state)
	assert_eq(_kinds_at(marks, Vector2i(1, 1)), [PowerEffects.Kind.DESTROYED], "the unit under it")
	assert_eq(
		_kinds_at(marks, Vector2i(0, 0)), [PowerEffects.Kind.DESTROYED], "and the empty ground"
	)
	assert_eq(marks.size(), 4, "the four in-bounds cells of the blast, once each")


# --- doctrine ----------------------------------------------------------------


func test_a_movement_power_marks_the_army_it_moves_and_nobody_else() -> void:
	var state := _state("[terrain]\n=====\n[units]\n1 t 0 0\n2 t 4 0", &"alina_ward")
	var marks := _fire(state)
	assert_eq(_kinds_at(marks, Vector2i(0, 0)), [PowerEffects.Kind.EMPOWERED])
	assert_eq(_kinds_at(marks, Vector2i(4, 0)), [], "the enemy is untouched by a push")


func test_a_jam_marks_the_army_it_is_aimed_at() -> void:
	var state := _state("[terrain]\n=====\n[units]\n1 t 0 0\n2 t 4 0", &"orin_flux")
	var marks := _fire(state)
	assert_eq(_kinds_at(marks, Vector2i(4, 0)), [PowerEffects.Kind.HINDERED], "the jammed enemy")
	assert_eq(_kinds_at(marks, Vector2i(0, 0)), [], "his own army is unchanged by it")


## A power whose whole effect is a combat number moves no fact on the board, so
## the army it was fired for is what the marks fall back to — never the enemy's.
func test_a_combat_only_power_marks_the_army_it_was_fired_for() -> void:
	var state := _state("[terrain]\n=====\n[units]\n1 t 0 0\n2 t 4 0", &"konrad_vale")
	var marks := _fire(state)
	assert_eq(_kinds_at(marks, Vector2i(0, 0)), [PowerEffects.Kind.EMPOWERED])
	assert_eq(_kinds_at(marks, Vector2i(4, 0)), [], "an opponent is not empowered by it")


func test_a_carried_unit_is_never_marked() -> void:
	var state := _state("[terrain]\n=====\n[units]\n1 p 0 0\n1 i 1 0", &"konrad_vale")
	state.units[1].carrier = state.units[0]
	var marks := _fire(state)
	assert_eq(marks.size(), 1, "only the transport standing on the board is marked")
