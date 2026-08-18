class_name LegibilityArt
extends RefCounted
## The shipped pixels and the shipped numbers the legibility sweep composes
## from. Nothing here is a second opinion: every image is the one the battle
## scene loads, and every number is read out of the file that owns it —
##
##   units / terrain atlas  UnitSprite.UNITS_ATLAS_PATH, BattleView.ATLAS_PATH
##   the reach / fire / threat washes  OverlayPalette.MOVE / ATTACK / THREAT
##   the threat stripe period           BattleOverlays.THREAT_STRIPE
##   the fog shroud                     FogLayer's modulate in battle.tscn
##   the acted scrim's darkening        UnitSprite._ACTED_SCRIM's own shader
##   which art a terrain cell draws     TerrainAutotiles, asked about a field
##                                      of that terrain
##   which surface a terrain paves the
##   cut-in with                        TerrainType.stands_in_cutin / cutin_ground
##
## The two things the harness does restate are the two one-line patterns that
## live inside a shader and inside a generated tile and cannot be run without a
## viewport: the acted scrim's screen-space checkerboard and the threat lens's
## diagonal stripe. Both are cited where they are spelled, in
## LegibilityComposite.

## Where the fog shroud's colour and depth live: the FogLayer node's modulate in
## the battle scene, which is deliberately the scene's rather than a constant
## (BattleView._build_fog_tile_set says so). Read as text because instancing the
## battle scene means booting the match it renders.
const BATTLE_SCENE := "res://scenes/battle/battle.tscn"
const FOG_NODE := "FogLayer"
## The board draws its atlases at 4x the world grid and scales back down, with
## the project's default texture filter set to nearest
## (project.godot: textures/canvas_textures/default_texture_filter=0), so a board
## pixel is one texel rather than an average of sixteen.
const CELL_PX := BattleView.TERRAIN_PX

## The units atlas at ambient frame A. The board also beats to frame B
## (UnitSprite.UNITS_ATLAS_B_PATH), which this sweep does not measure: a frame is
## a sixth axis, and adding it is a widening that supersedes a whole report
## rather than an option on one.
var units: Image
var terrain: Image
var overlay: Image
var fog_modulate: Color
var acted_scrim: float
## Terrain id -> the region of `_sheet_for` that terrain's cell is cut from,
## with the sheet it belongs to; filled on demand by `board_cell`.
var _board_cells: Dictionary[StringName, Dictionary] = {}
var _sheets: Dictionary[String, Image] = {}


static func load_shipped() -> LegibilityArt:
	var art := LegibilityArt.new()
	art.units = _image(UnitSprite.UNITS_ATLAS_PATH)
	art.terrain = _image(BattleView.ATLAS_PATH)
	art.overlay = _image(BattleOverlays.OVERLAY_PATH)
	art.fog_modulate = _fog_modulate()
	art.acted_scrim = _acted_scrim()
	if art.units == null or art.terrain == null or art.overlay == null:
		return null
	return art


## The image and region a cell of `terrain_type` draws from when its four
## neighbours are the same terrain — plains and mountain off the base atlas,
## a wood inside a wood keeping its full-bleed canopy, open water keeping the
## base tile, a beach off the shoal sheet. Which of those it is, is
## TerrainAutotiles' answer about a small field of that terrain, never a rule
## restated here.
##
## A property carries an `under`: its column is a transparent overlay and the
## board paints TerrainDB.ground() beneath it, so the composite does too.
func board_cell(terrain_type: TerrainType, db: TerrainDB) -> Dictionary:
	if _board_cells.has(terrain_type.id):
		return _board_cells[terrain_type.id]
	var field := MapData.parse(_field_text(terrain_type), db)
	var centre := Vector2i(1, 1)
	var family := TerrainAutotiles.family(field, centre)
	var cell := {}
	if family == TerrainAutotiles.Family.NONE:
		cell = {
			"image": terrain,
			"origin": Vector2i(terrain_type.atlas_col * CELL_PX, 0),
			"px": CELL_PX,
		}
		# A property column is a transparent overlay, so what a figure stands on
		# there is the ground the board paints under it, seen through the building.
		if terrain_type.is_property:
			cell["under"] = Vector2i(db.ground().atlas_col * CELL_PX, 0)
	else:
		var mask := TerrainAutotiles.mask(field, centre)
		var coords := TerrainAutotiles.atlas_coords(family, mask)
		var margin := TerrainAutotiles.SHEET_MARGIN
		var stride := CELL_PX + TerrainAutotiles.SHEET_SEPARATION
		cell = {
			"image": _sheet(TerrainAutotiles.SHEET_PATHS[family]),
			"origin": Vector2i(margin, margin) + coords * stride,
			"px": CELL_PX,
		}
	_board_cells[terrain_type.id] = cell
	return cell


## The surface a terrain paves the cut-in with — its own art, or the art of the
## terrain it stands on. Always a base-atlas cell: the cut-in tiles the board's
## own ground plane and redraws nothing (battle-animations plan D2).
func cutin_cell(terrain_type: TerrainType, db: TerrainDB) -> Dictionary:
	var paving := terrain_type
	if terrain_type.stands_in_cutin():
		paving = db.by_id(terrain_type.cutin_ground)
	return {"image": terrain, "origin": Vector2i(paving.atlas_col * CELL_PX, 0), "px": CELL_PX}


## The region one unit kind occupies in one faction row of the units atlas. Its
## cell is UnitSprite's own size rather than the terrain's: the two happen to
## match today, and nothing here may depend on their staying equal.
func unit_cell(unit_type: UnitType, atlas_row: int) -> Dictionary:
	var size := UnitSprite.SPRITE_PX
	return {
		"image": units,
		"origin": Vector2i(unit_type.atlas_col * size, atlas_row * size),
		"px": size,
	}


func _sheet(path: String) -> Image:
	if not _sheets.has(path):
		_sheets[path] = _image(path)
	return _sheets[path]


static func _field_text(terrain_type: TerrainType) -> String:
	var row := terrain_type.symbol.repeat(3)
	return "# legibility probe field\n[terrain]\n%s\n%s\n%s\n" % [row, row, row]


static func _image(path: String) -> Image:
	var texture := load(path) as Texture2D
	if texture == null:
		push_error("legibility: cannot load %s" % path)
		return null
	return texture.get_image()


static func _fog_modulate() -> Color:
	var text := FileAccess.get_file_as_string(BATTLE_SCENE)
	var node := text.find('[node name="%s"' % FOG_NODE)
	var expression := RegEx.create_from_string(
		r"modulate = Color\(([\d.]+), ([\d.]+), ([\d.]+), ([\d.]+)\)"
	)
	var found := expression.search(text, node) if node >= 0 else null
	if found == null:
		push_error("legibility: no %s modulate in %s" % [FOG_NODE, BATTLE_SCENE])
		return Color(0, 0, 0, 0)
	return Color(
		found.get_string(1).to_float(),
		found.get_string(2).to_float(),
		found.get_string(3).to_float(),
		found.get_string(4).to_float()
	)


## The factor the acted checkerboard darkens a pixel by, read out of the shader
## that applies it. The number lives in exactly one place and this is that place.
static func _acted_scrim() -> float:
	var expression := RegEx.create_from_string(r"COLOR\.rgb \*= ([\d.]+);")
	var found := expression.search(UnitSprite._ACTED_SCRIM)
	if found == null:
		push_error("legibility: no darkening factor in UnitSprite._ACTED_SCRIM")
		return 1.0
	return found.get_string(1).to_float()
