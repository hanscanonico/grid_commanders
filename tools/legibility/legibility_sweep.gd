class_name LegibilitySweep
extends RefCounted
## The matrix: every unit kind, in every faction's colours, ready and acted,
## on every ground the board can put it on, under every wash the board can lay
## over it — plus the same figures at the cut-in's own resolution.
##
## An offline instrument, in the Balance Lab's sense: it observes shipped art
## and shipped constants, plays no match, and is not part of `make verify`.
## Nothing under core/ or ai/ knows it exists.
##
## The bar is the design spec's: at least two ramp steps of separation between
## the figure and the ground it stands on, after the wash has composited. What
## a ramp step is, and why the two medians are the sides of the comparison, is
## LegibilityMetric's to say.

## The five grounds the spec names. Each is measured as the art that terrain
## draws in a field of its own kind — see LegibilityArt.board_cell.
const TERRAIN_IDS: Array[StringName] = [&"plains", &"woods", &"sea", &"mountain", &"shoal"]
## Ramp steps of separation a composite has to clear.
const PASS_STEPS := 2.0
const BOARD_VIEW := "board"
const CUTIN_VIEW := "cutin"
## Faction row -> the name that row's paint goes by. The rows themselves are
## SideIdentity's contract with the art pipeline; this is only how the report
## spells them.
const ROW_NAMES: Array[String] = ["neutral", "meridian", "aurora", "iron", "verdant"]
const COLUMNS: Array[String] = [
	"view", "unit", "faction", "state", "terrain", "overlay", "figure", "ground", "steps", "verdict"
]

var art: LegibilityArt
var terrain_db: TerrainDB
var unit_db: UnitDB
## One ramp step in luminance, measured off the shipped units atlas.
var ramp_step := 0.0


static func create(p_terrain_db: TerrainDB, p_unit_db: UnitDB) -> LegibilitySweep:
	var sweep := LegibilitySweep.new()
	sweep.art = LegibilityArt.load_shipped()
	if sweep.art == null:
		return null
	sweep.terrain_db = p_terrain_db
	sweep.unit_db = p_unit_db
	sweep.ramp_step = LegibilityMetric.ramp_step(
		sweep.art.units, UnitSprite.SPRITE_PX, SideIdentity.FACTION_ROWS + 1
	)
	return sweep


## Every cell of the matrix, one row each, in a fixed walk so two runs of the
## same tree write the same file.
func run() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for unit_type in unit_db.all():
		for row in SideIdentity.FACTION_ROWS + 1:
			for terrain_id in TERRAIN_IDS:
				rows.append_array(_unit_rows(unit_type, row, terrain_id))
	return rows


## A composite ready to be measured or drawn. The one place a cell of this
## matrix is assembled, so `--dump` eyeballs exactly what the sweep judged.
func composite(
	unit_type: UnitType, row: int, terrain_id: StringName, overlay: int, view: String
) -> LegibilityComposite:
	var terrain_type := terrain_db.by_id(terrain_id)
	var cell := LegibilityComposite.new()
	cell.art = art
	cell.figure_cell = art.unit_cell(unit_type, row)
	cell.size = LegibilityComposite.CUTIN_PX if view == CUTIN_VIEW else LegibilityComposite.BOARD_PX
	cell.ground_cell = (
		art.cutin_cell(terrain_type, terrain_db)
		if view == CUTIN_VIEW
		else art.board_cell(terrain_type, terrain_db)
	)
	cell.overlay = overlay as LegibilityComposite.Overlay
	return cell


## The rows that failed the bar, worst first, then in the sweep's own order.
static func failures(rows: Array[Dictionary]) -> Array[Dictionary]:
	var failed: Array[Dictionary] = []
	for row in rows:
		if row["verdict"] == "FAIL":
			failed.append(row)
	failed.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["steps"] < b["steps"])
	return failed


## Counts of pass and fail per key of one column, for the report's tables.
static func tally(rows: Array[Dictionary], column: String) -> Dictionary[String, Array]:
	var counts: Dictionary[String, Array] = {}
	for row in rows:
		var key := str(row[column])
		if not counts.has(key):
			counts[key] = [0, 0]
		var pair: Array = counts[key]
		pair[0] += 1
		if row["verdict"] == "FAIL":
			pair[1] += 1
	return counts


func _unit_rows(unit_type: UnitType, row: int, terrain_id: StringName) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for overlay in LegibilityComposite.Overlay.values():
		for exhausted in [false, true]:
			rows.append(_row(unit_type, row, terrain_id, overlay, exhausted, BOARD_VIEW))
	# The cut-in draws neither the board's washes nor the acted scrim: it is the
	# figure against the surface its terrain paves with, and nothing else.
	rows.append(
		_row(unit_type, row, terrain_id, LegibilityComposite.Overlay.NONE, false, CUTIN_VIEW)
	)
	return rows


func _row(
	unit_type: UnitType,
	row: int,
	terrain_id: StringName,
	overlay: int,
	exhausted: bool,
	view: String
) -> Dictionary:
	var cell := composite(unit_type, row, terrain_id, overlay, view)
	cell.exhausted = exhausted
	var figure := cell.figure_luminances()
	var ground := cell.ground_luminances()
	var steps := LegibilityMetric.separation(figure, ground, ramp_step)
	return {
		"view": view,
		"unit": String(unit_type.id),
		"faction": ROW_NAMES[row],
		"state": "acted" if exhausted else "ready",
		"terrain": String(terrain_id),
		"overlay": overlay_name(overlay),
		"figure": "%.4f" % LegibilityMetric.median(figure),
		"ground": "%.4f" % LegibilityMetric.median(ground),
		"steps": snappedf(steps, 0.01),
		"verdict": "PASS" if steps >= PASS_STEPS else "FAIL",
	}


static func overlay_name(overlay: int) -> String:
	return LegibilityComposite.Overlay.keys()[overlay].to_lower()
