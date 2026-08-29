class_name LegibilityArt
extends RefCounted
## The shipped pixels and the shipped numbers the legibility sweep composes
## from. Nothing here is a second opinion: every image is the one the battle
## scene loads, and every number is read out of the file that owns it —
##
##   units / terrain atlas  UnitSprite's six unit sheets, BattleView.ATLAS_PATH
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
## What a cell off the base atlas is called, there being exactly one of it: a
## terrain whose family is NONE draws the same column wherever it stands.
const ATLAS_VARIANT := "atlas"
## How far along a row of its own terrain the probe walks a cell. A
## connection-keyed family answers with the one mask its neighbours give at every
## step; a phase-keyed one (open water) answers with a different cell per
## position, so the walk is what turns a family into every tile it holds.
## `_sheet_cells` checks what the walk found against the sheet rather than
## trusting this span: a family answering with some of its cells and not others
## is a hole in the measurement.
const VARIANT_PROBE_SPAN := 24

## A frame names a clip and a beat, never a file: the board beats an idle clip
## and, while a unit walks its path, a gait clip, and each is two poses
## (UnitSprite._sheet_path). Which file a frame is drawn from is the view's —
## the board draws its own cells, shadow and all, and the cut-in draws the pair
## with that shadow subtracted, which is a surface rather than a third clip
## (UnitSprite.figure_texture_for).
const FRAME_IDLE_A := "idle_a"
const FRAME_IDLE_B := "idle_b"
const FRAME_WALK_A := "walk_a"
const FRAME_WALK_B := "walk_b"
## Frame -> the sheet the board draws it from. All four, in the order the beat
## plays them.
const BOARD_SHEETS: Dictionary[String, String] = {
	FRAME_IDLE_A: UnitSprite.UNITS_ATLAS_PATH,
	FRAME_IDLE_B: UnitSprite.UNITS_ATLAS_B_PATH,
	FRAME_WALK_A: UnitSprite.UNITS_ATLAS_MOVE_PATH,
	FRAME_WALK_B: UnitSprite.UNITS_ATLAS_MOVE_B_PATH,
}
## Frame -> the sheet the cut-in draws it from. The idle clip only: a cut-in
## poses a unit rather than walking it, so there is no gait sheet without the
## tile's cast shadow to read.
const CUTIN_SHEETS: Dictionary[String, String] = {
	FRAME_IDLE_A: UnitSprite.UNITS_ATLAS_FIGURES_PATH,
	FRAME_IDLE_B: UnitSprite.UNITS_ATLAS_FIGURES_B_PATH,
}

## The units atlas at the board's idle frame A — the sheet the ramp step is
## measured off and the one a `--units=` run replaces. The other five reach the
## harness through `frame_sheet`.
var units: Image
## Where `units` was read from — the shipped path, or the file a `--units=` run
## put in its place. The ramp step is measured off that sheet, so a report has
## to be able to say which one it read.
var units_source := UnitSprite.UNITS_ATLAS_PATH
var terrain: Image
var overlay: Image
var fog_modulate: Color
var acted_scrim: float
## Terrain id -> one cell per variant that terrain's family offers, each the
## region it is cut from and the sheet it belongs to; filled on demand by
## `board_cells`.
var _board_cells: Dictionary[StringName, Array] = {}
var _sheets: Dictionary[String, Image] = {}


## The shipped art, or the same art with the units atlas taken from a file on
## disk instead — which is how a past generation of the sheet is scored through
## today's ruler (`--units=`). Only that one sheet is swappable, and deliberately:
## the grounds are then held fixed, so a generation's numbers move because its
## figures moved, and an older tree's terrain sheets are not always a set this
## code can read at all.
static func load_shipped(units_path := "") -> LegibilityArt:
	var art := LegibilityArt.new()
	if units_path == "":
		art.units = _image(art.units_source)
	else:
		art.units_source = units_path
		art.units = _file(units_path)
	art.terrain = _image(BattleView.ATLAS_PATH)
	art.overlay = _image(BattleOverlays.OVERLAY_PATH)
	art.fog_modulate = _fog_modulate()
	art.acted_scrim = _acted_scrim()
	if art.units == null or art.terrain == null or art.overlay == null:
		return null
	return art


## Every image and region a cell of `terrain_type` can draw from when its four
## neighbours are the same terrain — a reef off the base atlas, a wood inside a
## wood keeping its full-bleed canopy, a beach off the shoal sheet, open water,
## a field and a range once per phase of their own sheets. Which of those it is,
## and how many
## there are, is TerrainAutotiles' answer over a run of probe cells, never a rule
## or a family list restated here: whether a family is keyed by its neighbours or
## by where it stands is exactly what the walk finds out.
##
## Each cell names its own `variant`, so a report can say which tile it read.
##
## A property carries an `under`: its column is a transparent overlay and the
## board paints TerrainDB.ground() beneath it, so the composite does too.
func board_cells(terrain_type: TerrainType, db: TerrainDB) -> Array[Dictionary]:
	if _board_cells.has(terrain_type.id):
		return _board_cells[terrain_type.id]
	var field := MapData.parse(_field_text(terrain_type), db)
	var family := TerrainAutotiles.family(field, Vector2i(1, 1))
	var cells: Array[Dictionary] = []
	if family == TerrainAutotiles.Family.NONE:
		cells.append(_atlas_cell(terrain_type, db))
	else:
		cells = _sheet_cells(field, family)
	_board_cells[terrain_type.id] = cells
	return cells


## The one cell of `terrain_type` that variant names, or an empty dictionary when
## its family has no such tile.
func board_cell(terrain_type: TerrainType, db: TerrainDB, variant: String) -> Dictionary:
	for cell in board_cells(terrain_type, db):
		if cell["variant"] == variant:
			return cell
	return {}


## The surface a terrain paves the cut-in with — its own art, or the art of the
## terrain it stands on. Always a base-atlas cell: the cut-in tiles the board's
## own ground plane and redraws nothing (battle-animations plan D2).
func cutin_cell(terrain_type: TerrainType, db: TerrainDB) -> Dictionary:
	var paving := terrain_type
	if terrain_type.stands_in_cutin():
		paving = db.by_id(terrain_type.cutin_ground)
	return {"image": terrain, "origin": Vector2i(paving.atlas_col * CELL_PX, 0), "px": CELL_PX}


## One of the six shipped unit sheets, read once. The board's idle frame A comes
## back as `units` rather than off disk, so a `--units=` run scores the sheet it
## named there and the shipped art everywhere else.
func frame_sheet(sheet_path: String) -> Image:
	if sheet_path == UnitSprite.UNITS_ATLAS_PATH:
		return units
	return _sheet(sheet_path)


## The region one unit kind occupies in one faction row of a unit sheet. Its
## cell is UnitSprite's own size rather than the terrain's: the two happen to
## match in width today, and nothing here may depend on their staying equal.
##
## The ruler measures one tile, and the unit's tile is the BOTTOM square of a
## cell taller than it is wide — the board anchors the art by its footprint, so
## that square is what a unit shows against the ground it stands on. What a
## raised silhouette overflows upward reads against the row behind it, which is
## a different tile and outside this measurement.
func unit_cell(unit_type: UnitType, atlas_row: int, sheet_path: String) -> Dictionary:
	var footprint := Vector2i(0, UnitSprite.SPRITE_H - UnitSprite.SPRITE_W)
	return {
		"image": frame_sheet(sheet_path),
		"origin":
		(
			Vector2i(unit_type.atlas_col * UnitSprite.SPRITE_W, atlas_row * UnitSprite.SPRITE_H)
			+ footprint
		),
		"px": UnitSprite.SPRITE_W,
	}


func _atlas_cell(terrain_type: TerrainType, db: TerrainDB) -> Dictionary:
	var cell := {
		"image": terrain,
		"origin": Vector2i(terrain_type.atlas_col * CELL_PX, 0),
		"px": CELL_PX,
		"variant": ATLAS_VARIANT,
	}
	# A property column is a transparent overlay, so what a figure stands on
	# there is the ground the board paints under it, seen through the building.
	if terrain_type.is_property:
		cell["under"] = Vector2i(db.ground().atlas_col * CELL_PX, 0)
	return cell


## One cell per variant the probe row wears, in variant order. A family that
## answers with neither one tile nor its whole sheet has variants the walk never
## reached, which is a hole in the measurement rather than a finding about art.
func _sheet_cells(field: MapData, family: int) -> Array[Dictionary]:
	var by_variant: Dictionary[int, Dictionary] = {}
	for x in range(1, VARIANT_PROBE_SPAN + 1):
		var variant := TerrainAutotiles.variant(field, Vector2i(x, 1))
		by_variant[variant] = _sheet_cell(family, variant)
	var variants: Array = by_variant.keys()
	variants.sort()
	var cells: Array[Dictionary] = []
	for variant: int in variants:
		cells.append(by_variant[variant])
	var held := TerrainAutotiles.sheet_cells(family).size()
	if cells.size() != 1 and cells.size() != held:
		push_error(
			(
				"legibility: %d of family %d's %d variants in %d probes"
				% [cells.size(), family, held, VARIANT_PROBE_SPAN]
			)
		)
	return cells


func _sheet_cell(family: int, variant: int) -> Dictionary:
	var coords := TerrainAutotiles.atlas_coords(family, variant)
	var margin := TerrainAutotiles.SHEET_MARGIN
	var stride := CELL_PX + TerrainAutotiles.SHEET_SEPARATION
	return {
		"image": _sheet(TerrainAutotiles.SHEET_PATHS[family]),
		"origin": Vector2i(margin, margin) + coords * stride,
		"px": CELL_PX,
		"variant": str(variant),
	}


func _sheet(path: String) -> Image:
	if not _sheets.has(path):
		_sheets[path] = _image(path)
	return _sheets[path]


## Three rows of one terrain, wide enough that the probe row walks
## VARIANT_PROBE_SPAN cells with that terrain on all four sides of each.
static func _field_text(terrain_type: TerrainType) -> String:
	var row := terrain_type.symbol.repeat(VARIANT_PROBE_SPAN + 2)
	return "# legibility probe field\n[terrain]\n%s\n%s\n%s\n" % [row, row, row]


## A PNG read straight off disk, outside the project's imported art.
static func _file(path: String) -> Image:
	var image := Image.load_from_file(path)
	if image == null:
		push_error("legibility: cannot read %s" % path)
	return image


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
