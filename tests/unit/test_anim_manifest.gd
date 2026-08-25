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
## gate says so by name.

const MANIFEST_PATH := "res://assets/tiles/anim.json"
const TILES_DIR := "res://assets/tiles/"
## Installed by the generator and read by nothing yet: the cut-in's idle pair and
## the move clip's two sheets are wired in by their own slices. Named here so the
## manifest still answers for them and the next reader does not take them for
## dead weight. The sea's frame B has left this list — SeaBeat draws it.
const UNREAD_SHEETS := [
	"res://assets/tiles/units_atlas_figures_b.png",
	"res://assets/tiles/units_atlas_move.png",
	"res://assets/tiles/units_atlas_move_b.png",
]

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


func test_the_clips_name_the_sheets_the_game_loads() -> void:
	assert_eq(
		_clip_sheets("ambient"),
		[UnitSprite.UNITS_ATLAS_PATH, UnitSprite.UNITS_ATLAS_B_PATH],
		"the ambient pair"
	)
	assert_eq(
		_clip_sheets("ambient_figures")[0], UnitSprite.UNITS_ATLAS_FIGURES_PATH, "the figure sheet"
	)
	assert_eq(
		_clip_sheets("sea"),
		[
			TerrainAutotiles.sheet_path(TerrainAutotiles.Family.SEA),
			TerrainAutotiles.sheet_path(TerrainAutotiles.Family.SEA, 1)
		],
		"the sea pair"
	)


func test_every_sheet_the_manifest_names_is_installed() -> void:
	for clip: String in manifest["clips"]:
		for path: String in _clip_sheets(clip):
			assert_true(
				ResourceLoader.exists(path), "%s names a sheet that is not installed" % clip
			)
	for path: String in UNREAD_SHEETS:
		assert_true(ResourceLoader.exists(path), "%s ships installed for a later slice" % path)


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
