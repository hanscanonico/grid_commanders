extends GutTest
## The unit menu's Fire row, and the three refusals it now wears instead of
## vanishing. `BattleMenus` is content, gated by the authorities the rows would
## run, so which rows come back is read straight off the static.
##
## The bug this pins: an artillery that moved, a gun that ran dry and a ring with
## nothing in it all left `attackable_cells` empty, and the menu answered every
## one of them by deleting the row — which is the only answer a player cannot
## read.

const NO_CARGO: Array[BattlePerspective.DropOption] = []


func _rows(game: GameState, unit: Unit, block: BattlePerspective.FireBlock) -> Array[Dictionary]:
	return BattleMenus.unit_actions(game, unit, Fixture.path([unit.cell]), block, NO_CARGO)


func _fire_row(rows: Array[Dictionary]) -> Dictionary:
	for row in rows:
		if row["id"] == &"fire":
			return row
	return {}


func test_a_shot_in_reach_offers_a_live_row() -> void:
	var game := Fixture.state(Fixture.ARTILLERY_VS_TANK)
	var row := _fire_row(
		_rows(game, game.unit_at(Vector2i(0, 0)), BattlePerspective.FireBlock.NONE)
	)
	assert_eq(row.get("label", ""), "Fire")
	assert_false(row.get("disabled", false))


func test_each_refusal_greys_the_row_and_names_itself() -> void:
	var game := Fixture.state(Fixture.ARTILLERY_VS_TANK)
	var gun := game.unit_at(Vector2i(0, 0))
	for block: BattlePerspective.FireBlock in BattleMenus.FIRE_REFUSALS:
		var row := _fire_row(_rows(game, gun, block))
		assert_true(row.get("disabled", false), "the row is offered but refused")
		assert_eq(row.get("label", ""), "Fire · %s" % BattleMenus.FIRE_REFUSALS[block])


## A transport has no shot to explain, so it keeps getting no row — a greyed
## "Fire" on every APC on the board would be noise rather than an answer.
func test_an_unarmed_hull_still_gets_no_row() -> void:
	var game := Fixture.state("[terrain]\n..\n[units]\n1 p 0 0\n2 i 1 0")
	var apc := game.unit_at(Vector2i(0, 0))
	assert_eq(_fire_row(_rows(game, apc, BattlePerspective.FireBlock.UNARMED)), {})
