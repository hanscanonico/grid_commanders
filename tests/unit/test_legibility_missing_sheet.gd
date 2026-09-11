extends GutTest
## What the sweep does with art this tree does not hold — the case the grind box
## walked into: a checkout whose imported assets predate a sheet the matrix
## reads. A cell it cannot compose is skipped, so the missing file is one error
## where it failed to load rather than one per pixel of every cell that would
## have used it.


func _sweep() -> LegibilitySweep:
	return LegibilitySweep.create(TerrainDB.load_default(), UnitDB.load_default())


func _board_variant(sweep: LegibilitySweep, terrain_id: StringName) -> String:
	var db := sweep.terrain_db
	return str(sweep.art.board_cells(db.by_id(terrain_id), db)[0]["variant"])


func test_a_cell_whose_figure_sheet_is_missing_is_skipped() -> void:
	var sweep := _sweep()
	var unit: UnitType = sweep.unit_db.all()[0]
	var variant := _board_variant(sweep, &"plains")
	var args: Array = [
		unit,
		1,
		&"plains",
		variant,
		LegibilityComposite.Overlay.NONE,
		LegibilitySweep.BOARD_VIEW,
		LegibilityArt.FRAME_IDLE_A,
	]
	assert_not_null(sweep.composite.callv(args), "the shipped art composes")
	sweep.art.units = null
	assert_null(sweep.composite.callv(args), "no figure sheet, no cell to sample")


func test_a_cell_whose_ground_sheet_is_missing_is_skipped() -> void:
	var sweep := _sweep()
	var unit: UnitType = sweep.unit_db.all()[0]
	var args: Array = [
		unit,
		1,
		&"plains",
		LegibilityArt.ATLAS_VARIANT,
		LegibilityComposite.Overlay.NONE,
		LegibilitySweep.CUTIN_VIEW,
		LegibilityArt.FRAME_IDLE_A,
	]
	assert_not_null(sweep.composite.callv(args), "the shipped art composes")
	sweep.art.terrain = null
	assert_null(sweep.composite.callv(args), "no ground sheet, no cell to sample")


func test_a_sheet_that_will_not_load_is_read_once() -> void:
	var art := LegibilityArt.load_shipped()
	var missing := "res://assets/sprites/units/no_such_sheet.png"
	assert_null(art.frame_sheet(missing))
	assert_null(art.frame_sheet(missing), "the cache holds the failure, so it is not retried")
	assert_push_error_count(1, "the missing file is said once, not once per cell")
	assert_engine_error_count(1, "the loader says its piece once as well")
