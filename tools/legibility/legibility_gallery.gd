class_name LegibilityGallery
extends RefCounted
## The sweep's worst cells, drawn side by side on one sheet: the composite the
## harness judged, magnified, with the numbers it judged it by under it.
##
## Review evidence rather than illustration. A hero screenshot shows the cell
## somebody chose; this shows the cells the ruler chose, so the picture and the
## table cannot disagree. It is deterministic — the rows come from
## LegibilitySweep.failures, whose order is total, and every cell is rebuilt
## through LegibilitySweep.composite_for — so the same art in is the same sheet
## out, which is what lets it be committed under docs/images/.
##
## The captions are LegibilityLabel's; nothing here rasterises text.

const CELLS := 20
const GRID_COLUMNS := 5
## Side of one magnified composite. Every view's art divides it exactly, so a
## cell is nearest-magnified by a whole number and no texel is resampled.
const TILE := 128
const CELL_WIDTH := 168
const PAD := 8
const CAPTION_LINES := 3
const HEADER_HEIGHT := 16
## The whole sheet is magnified by this at the end, so an 8px caption reads at
## arm's length beside a board cell that is 16 pixels across.
const SCALE := 2
const PAPER := Color(0.09, 0.10, 0.13)
const INK := Color(0.93, 0.91, 0.84)
const FRAME := Color(0.35, 0.37, 0.44)


## One sheet of the `count` worst failing cells, or null when the sweep's art or
## the caption font cannot be read.
static func compose(sweep: LegibilitySweep, rows: Array[Dictionary], count: int) -> Image:
	var label := LegibilityLabel.create()
	if label == null:
		return null
	var failed := LegibilitySweep.failures(rows)
	var shown := mini(count, failed.size())
	var grid_rows := ceili(float(shown) / float(GRID_COLUMNS))
	var image := Image.create(_sheet_width(), _sheet_height(grid_rows), false, Image.FORMAT_RGBA8)
	image.fill(PAPER)
	label.draw(image, _header(failed.size(), shown), Vector2i(PAD, PAD / 2), INK)
	for index in shown:
		var at := Vector2i(
			PAD + (index % GRID_COLUMNS) * (CELL_WIDTH + PAD),
			HEADER_HEIGHT + PAD + (index / GRID_COLUMNS) * _cell_height()
		)
		_draw_cell(image, label, sweep, failed[index], at, index + 1)
	image.resize(image.get_width() * SCALE, image.get_height() * SCALE, Image.INTERPOLATE_NEAREST)
	return image


static func _draw_cell(
	image: Image,
	label: LegibilityLabel,
	sweep: LegibilitySweep,
	row: Dictionary,
	at: Vector2i,
	rank: int
) -> void:
	var origin := at + Vector2i((CELL_WIDTH - TILE) / 2, 0)
	_frame(image, origin - Vector2i.ONE, TILE + 2)
	var cell := sweep.composite_for(row)
	if cell != null:
		_blit(image, _magnified(cell), origin)
	var caption := at + Vector2i(0, TILE + PAD / 2)
	for line in _caption(row, rank):
		label.draw(image, line, caption, INK)
		caption.y += LegibilityLabel.LINE_HEIGHT


## The composite at TILE, nearest — a board cell and a cut-in crop are magnified
## by different whole numbers so both fill the same square.
static func _magnified(cell: LegibilityComposite) -> Image:
	var image := cell.to_image()
	image.resize(TILE, TILE, Image.INTERPOLATE_NEAREST)
	return image


static func _caption(row: Dictionary, rank: int) -> Array[String]:
	return [
		"%02d %s %s" % [rank, str(row["unit"]).to_upper(), str(row["faction"]).to_upper()],
		(
			"%s %s %s"
			% [
				str(row["terrain"]).to_upper(),
				str(row["overlay"]).to_upper(),
				str(row["state"]).to_upper()
			]
		),
		"%s %.2f STEPS HUE %.1f" % [str(row["view"]).to_upper(), row["steps"], row["hue"]],
	]


static func _header(failing: int, shown: int) -> String:
	return (
		"WORST %d OF %d FAILING COMPOSITES - BAR %.1f STEPS, HUE CLEARS AT %.0f"
		% [shown, failing, LegibilitySweep.PASS_STEPS, LegibilitySweep.HUE_CLEAR]
	)


static func _blit(image: Image, source: Image, at: Vector2i) -> void:
	image.blit_rect(source, Rect2i(Vector2i.ZERO, source.get_size()), at)


static func _frame(image: Image, at: Vector2i, side: int) -> void:
	image.fill_rect(Rect2i(at, Vector2i(side, side)), FRAME)


static func _sheet_width() -> int:
	return PAD + GRID_COLUMNS * (CELL_WIDTH + PAD)


static func _sheet_height(grid_rows: int) -> int:
	return HEADER_HEIGHT + PAD + grid_rows * _cell_height()


static func _cell_height() -> int:
	return TILE + PAD / 2 + CAPTION_LINES * LegibilityLabel.LINE_HEIGHT + PAD
