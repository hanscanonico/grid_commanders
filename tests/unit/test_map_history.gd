extends GutTest
## MapHistory, the editor's undo stack.
##
## The claims are all about *steps*: a step is a whole stroke however many cells
## it crossed, a step restores the board exactly, a new stroke drops whatever was
## undone away, and the stack has a floor and a ceiling.

var terrain_db: TerrainDB
var unit_db: UnitDB
var doc: MapDocument
var history: MapHistory


func before_each() -> void:
	terrain_db = Fixture.terrain_db()
	unit_db = Fixture.unit_db()
	doc = MapDocument.blank(4, 3, terrain_db)
	history = MapHistory.new()
	history.begin(doc)


func test_a_fresh_history_has_nothing_behind_or_ahead() -> void:
	assert_false(history.can_undo(), "a board just opened has no stroke behind it")
	assert_false(history.can_redo(), "nor one ahead")
	assert_false(history.undo(doc), "so undo does nothing")
	assert_false(history.redo(doc), "and so does redo")


func test_a_whole_stroke_is_one_step() -> void:
	for x in 4:
		doc.paint(Vector2i(x, 0), &"woods")
	history.record(doc)

	assert_true(history.undo(doc), "the drag comes back off in one press")
	for x in 4:
		assert_eq(
			doc.terrain_at(Vector2i(x, 0)).id,
			TerrainDB.GROUND_ID,
			"every cell the drag crossed is open ground again"
		)
	assert_false(history.can_undo(), "and there is nothing behind the board it opened on")


func test_undo_and_redo_walk_the_strokes_in_order() -> void:
	doc.paint(Vector2i(0, 0), &"hq", 1)
	history.record(doc)
	doc.place_unit(Vector2i(1, 0), unit_db.by_id(&"tank"), 1)
	history.record(doc)

	assert_true(history.undo(doc), "the unit goes first")
	assert_true(doc.unit_at(Vector2i(1, 0)).is_empty(), "and the cell it stood on is empty")
	assert_eq(doc.terrain_at(Vector2i(0, 0)).id, &"hq", "the stroke before it still stands")
	assert_true(history.undo(doc), "then the building")
	assert_eq(doc.terrain_at(Vector2i(0, 0)).id, TerrainDB.GROUND_ID, "leaving the blank board")
	assert_eq(doc.owner_at(Vector2i(0, 0)), MapData.NEUTRAL, "with nobody owning anything")

	assert_true(history.redo(doc), "redo puts the building back")
	assert_eq(doc.owner_at(Vector2i(0, 0)), 1, "for the seat it was painted for")
	assert_true(history.redo(doc), "and then the unit")
	assert_eq(doc.unit_at(Vector2i(1, 0)).symbol, "t", "exactly as it stood")
	assert_false(history.can_redo(), "which is the last thing that was done")


func test_a_fresh_stroke_drops_the_redo_tail() -> void:
	doc.paint(Vector2i(0, 0), &"woods")
	history.record(doc)
	history.undo(doc)
	assert_true(history.can_redo(), "the undone stroke is ahead of the board")

	doc.paint(Vector2i(1, 1), &"mountain")
	history.record(doc)
	assert_false(history.can_redo(), "painting somewhere else is a different future")
	assert_true(history.undo(doc), "and the new stroke is the one behind")
	assert_eq(doc.terrain_at(Vector2i(1, 1)).id, TerrainDB.GROUND_ID, "so it is what comes off")


func test_the_stack_keeps_the_last_hundred_strokes() -> void:
	for i in MapHistory.DEPTH + 10:
		doc.paint(Vector2i(i % 4, 0), &"woods" if i % 2 == 0 else &"mountain")
		history.record(doc)

	var steps := 0
	while history.undo(doc):
		steps += 1
	assert_eq(steps, MapHistory.DEPTH, "the stack is capped rather than growing without end")


func test_undo_restores_a_resize() -> void:
	doc.paint(Vector2i(3, 2), &"city", 2)
	history.record(doc)
	doc.resize(2, 2)
	history.record(doc)
	assert_eq(doc.size(), Vector2i(2, 2), "the board was cropped")

	assert_true(history.undo(doc), "and the crop comes back off")
	assert_eq(doc.size(), Vector2i(4, 3), "at the size it was drawn at")
	assert_eq(doc.terrain_at(Vector2i(3, 2)).id, &"city", "with the corner it dropped")
	assert_eq(doc.owner_at(Vector2i(3, 2)), 2, "and who owned it")


func test_a_restored_draft_is_the_same_object_and_saves_the_same_text() -> void:
	doc.paint(Vector2i(0, 0), &"base", 1)
	history.record(doc)
	var drawn := doc.to_text()
	doc.paint(Vector2i(0, 0), &"woods")
	history.record(doc)
	history.undo(doc)
	assert_eq(doc.to_text(), drawn, "an undone board writes exactly what it wrote before")


func test_beginning_again_forgets_everything() -> void:
	doc.paint(Vector2i(0, 0), &"woods")
	history.record(doc)
	history.begin(doc)
	assert_false(history.can_undo(), "opening a board is the start of its history")
	assert_false(history.can_redo(), "in both directions")
