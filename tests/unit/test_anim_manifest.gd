extends GutTest
## The generator's sheet contract, held against the game's constants.
##
## assets/tiles/anim.json is sprite_generator's machine-readable statement of the
## cell, the clips and their cadences, the atlas columns and rows, and the phase
## counts. The game deliberately does **not** read it at runtime — the constants
## it would replace are read while a TileSet is being built and by Node-free
## statics the suite calls without a scene, so loading them would put a JSON parse
## in the draw path and give an install a silent way to change behaviour. What the
## manifest is worth is drift detection, and this suite is the one place it is
## consumed: regenerate the art with a different cell, cadence or column and the
## gate says so by name. Every sheet it names is now drawn by something: the six
## clips are the board's ambient beat, the cut-ins' idle, the walk cycle, the
## sea's swell, ko — the authored casualty frame the cut-in's death beat swaps
## to as a figure topples — and fire, the authored muzzle-lit pair the cut-in's
## fire window (CutsceneSide.fire_p) swaps to while a shot is going out.

const MANIFEST_PATH := "res://assets/tiles/anim.json"
const TILES_DIR := "res://assets/tiles/"
var manifest: Dictionary


func before_each() -> void:
	manifest = _load_manifest()


## A later version is a contract this game has not read. Fail loudly rather than
## checking the fields that happen to still be there.
func test_the_manifest_is_the_version_the_game_was_written_against() -> void:
	assert_eq(int(manifest.get("version", -1)), 1, "regenerate the consumers: anim.json moved on")


func test_the_cell_is_the_sprite_the_board_draws() -> void:
	var cell: Dictionary = manifest["cell"]
	assert_eq(int(cell["w"]), UnitSprite.SPRITE_W, "cell width")
	assert_eq(int(cell["h"]), UnitSprite.SPRITE_H, "cell height")
	assert_eq(int(cell["overflow"]), UnitSprite.SPRITE_OVERFLOW, "cell overflow")
	assert_eq(int(cell["ground_px"]), UnitSprite.CELL_GROUND_PX, "the cell's ground line")


func test_the_clips_run_at_the_cadences_the_board_beats_on() -> void:
	assert_eq(_clip_ms("ambient"), BoardBeat.AMBIENT_MS, "the ambient cadence")
	assert_eq(_clip_ms("ambient_figures"), BoardBeat.AMBIENT_MS, "the figures' cadence")
	assert_eq(_clip_ms("move"), BoardBeat.MOVE_MS, "the move cadence")
	assert_eq(_clip_ms("sea"), BoardBeat.SEA_MS, "the sea's cadence")
	# The fire pair reuses the ambient period outright on the director's own
	# clock (CutscenePlates.figure_now, off CutscenePlayback's `t`) rather
	# than the wall one — the ninth animation slice's idiom for a cut-in-only
	# pair, and the cadence-disjointness lock's own exemption for it.
	assert_eq(_clip_ms("fire"), BoardBeat.AMBIENT_MS, "the fire pair's cadence")


func test_the_clips_name_the_sheets_the_game_loads() -> void:
	assert_eq(
		_clip_sheets("ambient"),
		[UnitSprite.UNITS_ATLAS_PATH, UnitSprite.UNITS_ATLAS_B_PATH],
		"the ambient pair"
	)
	assert_eq(
		_clip_sheets("ambient_figures"),
		[UnitSprite.UNITS_ATLAS_FIGURES_PATH, UnitSprite.UNITS_ATLAS_FIGURES_B_PATH],
		"the figures' pair"
	)
	assert_eq(
		_clip_sheets("move"),
		[UnitSprite.UNITS_ATLAS_MOVE_PATH, UnitSprite.UNITS_ATLAS_MOVE_B_PATH],
		"the move pair"
	)
	assert_eq(
		_clip_sheets("sea"),
		[
			TerrainAutotiles.sheet_path(TerrainAutotiles.Family.SEA),
			TerrainAutotiles.sheet_path(TerrainAutotiles.Family.SEA, 1)
		],
		"the sea pair"
	)
	assert_eq(_clip_sheets("ko"), [UnitSprite.UNITS_ATLAS_FIGURES_KO_PATH], "the ko sheet")
	assert_eq(
		_clip_sheets("fire"),
		[UnitSprite.UNITS_ATLAS_FIGURES_FIRE_PATH, UnitSprite.UNITS_ATLAS_FIGURES_FIRE_B_PATH],
		"the fire pair"
	)


## The dead don't loop: one frame, held rather than cycled, and a fallback
## key naming the clip a consumer with no authored frame plays instead —
## the manifest's own restatement of the move clip's `fallback` idiom.
func test_the_ko_clip_is_a_single_held_frame() -> void:
	var clip: Dictionary = manifest["clips"]["ko"]
	assert_eq(clip["sheets"].size(), 1, "the dead don't loop")
	assert_eq(clip["mode"], "hold", "a KO frame is held, never cycled")
	assert_eq(
		clip["fallback"], "ambient", "air keeps the transform-topple until it authors its own frame"
	)


## A pair, looped — unlike ko's single held frame, since the two SUSTAINED
## weapon families need a second key for the stream to read as a blaze — with
## the same fallback idiom (a unit outside the generator's FIRES draws its own
## rest key, same as an unauthored move or KO column).
func test_the_fire_clip_is_a_looped_pair() -> void:
	var clip: Dictionary = manifest["clips"]["fire"]
	assert_eq(clip["sheets"].size(), 2, "the sustained pair needs a second key")
	assert_eq(clip["mode"], "loop", "the fire pair loops on the director's clock")
	assert_eq(clip["fallback"], "ambient", "an unarmed unit keeps its idle key")


func test_every_sheet_the_manifest_names_is_installed() -> void:
	for clip: String in manifest["clips"]:
		for path: String in _clip_sheets(clip):
			assert_true(
				ResourceLoader.exists(path), "%s names a sheet that is not installed" % clip
			)


func test_the_phase_counts_are_the_autotiles_own() -> void:
	var phases: Dictionary = manifest["terrain_phases"]
	assert_eq(phases.size(), TerrainAutotiles.PHASE_COUNTS.size(), "a phase-keyed family appeared")
	for family: int in TerrainAutotiles.PHASE_COUNTS:
		var key := _family_key(family)
		assert_eq(
			int(phases.get(key, -1)), TerrainAutotiles.PHASE_COUNTS[family], "%s phases" % key
		)


func test_every_unit_stands_in_the_column_the_manifest_gives_it() -> void:
	var units := Fixture.unit_db()
	var columns: Dictionary = manifest["columns"]
	assert_eq(columns.size(), units.size(), "the roster and the atlas hold different unit counts")
	for type in units.all():
		assert_eq(int(columns.get(String(type.id), -1)), type.atlas_col, "%s's column" % type.id)


## The atlas-row order is the faction-identity plan's contract between
## SideIdentity and the art pipeline; the manifest is the pipeline's half of it.
func test_the_rows_are_the_faction_order_side_identity_resolves() -> void:
	var rows: Array = manifest["rows"]
	assert_eq(rows.size(), SideIdentity.FACTION_ROWS + 1, "the atlas holds a different row count")
	for row in rows.size():
		var key: String = rows[row]["key"]
		assert_eq(int(SideIdentity._ROW_FOR_KEY.get(StringName(key), -1)), row, "%s's row" % key)


func _clip_ms(clip: String) -> int:
	return int(manifest["clips"][clip]["ms_per_frame"])


func _clip_sheets(clip: String) -> Array:
	var paths: Array = []
	for sheet: String in manifest["clips"][clip]["sheets"]:
		paths.append(TILES_DIR + sheet)
	return paths


func _family_key(family: int) -> String:
	return TerrainAutotiles.SHEET_PATHS[family].get_file().trim_suffix(".png")


func _load_manifest() -> Dictionary:
	var file := FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	assert_not_null(file, "anim.json did not open")
	var parsed = JSON.parse_string(file.get_as_text())
	assert_true(parsed is Dictionary, "anim.json did not parse as an object")
	return parsed
