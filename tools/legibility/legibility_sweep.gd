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
## the figure and the ground it stands on, after the wash has composited — and
## since round 9 half that under the fog shroud, which is drawn to hide (see
## FOG_PASS_STEPS). What a ramp step is, and how the sides of the comparison are
## chosen, is LegibilityMetric's to say.
##
## **The verdict is the edge reading** (round 8): the p25 of the luminance gap
## along the figure's own contour, against the ground just outside it, held to
## the same two steps. It replaced the whole-figure median as the headline
## because the median had run out of things to say — twenty worst cells scoring
## an identical 0.00 while their hues ranged over 68.8 to 98.8 are twenty ties,
## not twenty findings.
##
## The whole-figure medians stay in the table as a **cheap secondary**: they are
## what "is this figure, as a mass, a different value from this tile" means, and
## a cell where the two readings disagree is worth looking at.
##
## Both readings are taken twice, in value and in colour. The value bar is the
## verdict, because it is what predicts legibility at zoom 1 and because neutral
## and iron have barely any hue to lean on. The **hue** columns beside them are
## the CIE76 chroma-plane distance, a second reading rather than a second
## verdict: a cell that misses the value bar but clears HUE_CLEAR is one the
## value bar cannot see the truth about, so the report counts those separately
## instead of passing them.

## Every ground the board can stand a figure on: the five the spec names, then
## the five properties, which a unit sits on all match — capturing one, holding
## one, repairing on one. Each is measured as the art that terrain draws in a
## field of its own kind, a property composed over TerrainDB.ground() the way
## the board composes it — see LegibilityArt.board_cell.
const TERRAIN_IDS: Array[StringName] = [
	&"plains",
	&"woods",
	&"sea",
	&"mountain",
	&"shoal",
	&"city",
	&"base",
	&"hq",
	&"airport",
	&"port",
]
## Ramp steps of separation a composite on a clear tile has to clear: two steps
## is the shading gap the art itself uses to tell one face of a hull from the
## next, and a contour that stands less than that off its ground is painted in a
## value the ground already holds — which is the same sentence at the boundary as
## in the middle, so round 8 moved which sample it is asked of rather than what
## it asks. A fogged cell answers to FOG_PASS_STEPS instead.
const PASS_STEPS := 2.0
## The bar a **fogged** composite is held to instead, and the whole of round 9's
## answer to what the shroud is for. Fog is drawn to hide, so holding it to the
## bar a clear tile is held to measures the wash doing its job and reports it as
## an art defect. What a fogged cell still owes is that something is *there* —
## one ramp step of the figure's own boundary surviving the wash, half the clear
## bar — so a shrouded silhouette may go soft without going missing.
##
## It is also the class with the least real play behind it: nothing in the live
## scene ever *stands* under the shroud (see docs/sprite_legibility.md's fog
## question), which is why these cells are counted apart from the headline
## rather than folded into it.
const FOG_PASS_STEPS := 1.0
## Chroma-plane distance a figure and its ground have to differ by for the pair
## to count as told apart by colour alone. Round 8 left it where it was, for the
## reason it was set there: it is a property of the eye, not of the sample the
## reading is taken over. A stated bound rather than a measured one:
## about eight times the ~2.3 that is one just-noticeable difference, which is
## the distance at which two paints stop being shades of each other and start
## being different colours. Moving it supersedes a report rather than editing
## one, and it decides nothing — it only splits the failures into two counts.
const HUE_CLEAR := 20.0
const BOARD_VIEW := "board"
const CUTIN_VIEW := "cutin"
## Faction row -> the name that row's paint goes by. The rows themselves are
## SideIdentity's contract with the art pipeline; this is only how the report
## spells them.
const ROW_NAMES: Array[String] = ["neutral", "meridian", "aurora", "iron", "verdant"]
## The six fields that name one composite, in the order `--dump` spells them.
const KEYS: Array[String] = ["view", "unit", "faction", "state", "terrain", "overlay"]
const COLUMNS: Array[String] = [
	"view",
	"unit",
	"faction",
	"state",
	"terrain",
	"overlay",
	"figure",
	"ground",
	"edge_steps",
	"edge_hue",
	"steps",
	"hue",
	"verdict"
]

var art: LegibilityArt
var terrain_db: TerrainDB
var unit_db: UnitDB
## One ramp step in luminance, measured off the shipped units atlas.
var ramp_step := 0.0


static func create(p_terrain_db: TerrainDB, p_unit_db: UnitDB, units_path := "") -> LegibilitySweep:
	var sweep := LegibilitySweep.new()
	sweep.art = LegibilityArt.load_shipped(units_path)
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


## The composite one report row names, rebuilt from the row's own six keys. The
## gallery and `--dump` both come through here, so a picture is always of the
## cell whose numbers are printed beside it.
func composite_for(row: Dictionary) -> LegibilityComposite:
	var unit_type := unit_db.by_id(StringName(row["unit"]))
	var faction := ROW_NAMES.find(str(row["faction"]))
	var overlay := LegibilityComposite.Overlay.keys().find(str(row["overlay"]).to_upper())
	if unit_type == null or faction < 0 or overlay < 0:
		return null
	var cell := composite(unit_type, faction, StringName(row["terrain"]), overlay, str(row["view"]))
	cell.exhausted = row["state"] == "acted"
	return cell


## The rows that failed the bar, worst first. Ties are broken by the row's own
## keys rather than left to the sweep's order: Array.sort_custom is not stable,
## and the gallery is a committed artifact that has to come out the same twice.
static func failures(rows: Array[Dictionary]) -> Array[Dictionary]:
	var failed: Array[Dictionary] = []
	for row in rows:
		if row["verdict"] == "FAIL":
			failed.append(row)
	failed.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			if margin(a) != margin(b):
				return margin(a) < margin(b)
			return key_of(a) < key_of(b)
	)
	return failed


## How far a row's contour is from the two bars, as a share of the **further**
## one. Normalised because the two bars are in different units, and `max`
## because triage wants the cells no reading can see first: `min` ranks by
## whichever bar a cell misses hardest, so a figure that is invisible in value
## and obvious in colour outranks one that is invisible in both, which is how
## round 8's gallery came out twenty tiles of a single unit. `max` can only be
## small when both readings are, so the sheet opens on the doubly-blind class.
##
## `min` keeps the job it is right for and that job is not ordering: whether a
## cell missed a bar **at all** is `verdict` and the HUE_CLEAR test beside it —
## the two readings that decide membership — and a cell is in the failing set on
## the value bar alone.
static func margin(row: Dictionary) -> float:
	return maxf(float(row["edge_steps"]) / bar_for(row), float(row["edge_hue"]) / HUE_CLEAR)


## The ramp-step bar a row is judged against: its own, because the fog class has
## a different one.
static func bar_for(row: Dictionary) -> float:
	return (
		FOG_PASS_STEPS
		if row["overlay"] == overlay_name(LegibilityComposite.Overlay.FOG)
		else PASS_STEPS
	)


## The rows the fog shroud is over, and the rest. Counted apart everywhere the
## report states a rate, because the two are held to different bars and a rate
## mixing them answers no question.
static func fogged(rows: Array[Dictionary]) -> Array[Dictionary]:
	return _with_fog(rows, true)


static func unfogged(rows: Array[Dictionary]) -> Array[Dictionary]:
	return _with_fog(rows, false)


## How many of a set of rows miss the value bar but clear HUE_CLEAR — the cells
## the value-only reading is blind to, counted rather than passed.
static func hue_carried(rows: Array[Dictionary]) -> int:
	var carried := 0
	for row in rows:
		if row["verdict"] == "FAIL" and float(row["edge_hue"]) >= HUE_CLEAR:
			carried += 1
	return carried


## `view:unit:faction:state:terrain:overlay`, the way `--dump` names a cell.
static func key_of(row: Dictionary) -> String:
	var fields: Array[String] = []
	for key in KEYS:
		fields.append(str(row[key]))
	return ":".join(fields)


## Per key of one column: cells, of them failing, and of those failing ones the
## ones the hue reading clears. The report's tables are these three.
static func tally(rows: Array[Dictionary], column: String) -> Dictionary[String, Array]:
	var counts: Dictionary[String, Array] = {}
	for row in rows:
		var key := str(row[column])
		if not counts.has(key):
			counts[key] = [0, 0, 0]
		var triple: Array = counts[key]
		triple[0] += 1
		if row["verdict"] != "FAIL":
			continue
		triple[1] += 1
		if float(row["edge_hue"]) >= HUE_CLEAR:
			triple[2] += 1
	return counts


static func _with_fog(rows: Array[Dictionary], keep: bool) -> Array[Dictionary]:
	var picked: Array[Dictionary] = []
	var fog := overlay_name(LegibilityComposite.Overlay.FOG)
	for row in rows:
		if (row["overlay"] == fog) == keep:
			picked.append(row)
	return picked


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
	var figure := cell.figure_colours()
	var ground := cell.ground_colours()
	var figure_median := LegibilityMetric.median_colour(figure)
	var ground_median := LegibilityMetric.median_colour(ground)
	var steps := LegibilityMetric.separation(
		LegibilityMetric.luminances(figure), LegibilityMetric.luminances(ground), ramp_step
	)
	var edge := LegibilityMetric.edge_reading(cell.pixels(), cell.coverage(), cell.size)
	# Judged on the printed number rather than on the one behind it: a row that
	# reads 2.00 and says FAIL is a table nobody can check.
	var edge_steps := snappedf(LegibilityMetric.in_steps(edge.x, ramp_step), 0.01)
	var row_out := {
		"view": view,
		"unit": String(unit_type.id),
		"faction": ROW_NAMES[row],
		"state": "acted" if exhausted else "ready",
		"terrain": String(terrain_id),
		"overlay": overlay_name(overlay),
		"figure": "%.4f" % LegibilityMetric.luminance(figure_median),
		"ground": "%.4f" % LegibilityMetric.luminance(ground_median),
		"edge_steps": edge_steps,
		"edge_hue": snappedf(edge.y, 0.01),
		"steps": snappedf(steps, 0.01),
		"hue": snappedf(LegibilityMetric.hue_distance(figure_median, ground_median), 0.01),
		"verdict": "",
	}
	# Through bar_for like every other reader, so the verdict and the gallery's
	# order can never be told the fog class apart differently.
	row_out["verdict"] = "PASS" if edge_steps >= bar_for(row_out) else "FAIL"
	return row_out


static func overlay_name(overlay: int) -> String:
	return LegibilityComposite.Overlay.keys()[overlay].to_lower()
