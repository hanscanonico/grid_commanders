class_name EditorBoard
extends Control
## The draft under the brush: the board as the game will read it, at a whole
## number of pixels per tile, scrolled to keep the painted cell in the frame.
##
## It draws nothing of its own but the cursor. What a cell looks like is
## `MapThumbnail`'s answer — the one renderer the picker and the menu backdrop
## already share (menu-revamp R2) — so an author can never paint a board in art
## the match would not show them. That renderer wants a `MapData` and a draft is
## a `MapDocument`; the seam between the two is the text, so `preview_of` writes
## the draft and reads it straight back through `MapData.parse`. What is on
## screen is therefore the board the parser makes of the file the draft saves to,
## autotiled coasts and all, rather than a second opinion about it.
##
## The zoom is `BattleZoom`'s ladder, asked of it rather than restated: the rungs
## are whole numbers above a floor that frames the whole board, which is what
## keeps a nearest-filtered tile from dropping rows here as it does in a match.

## The gold every other surface marks a selection in.
const CURSOR_INK := UiTheme.SELECT_GOLD
## The ink a cell a complaint names is ringed in — the shell's one refusal
## colour, so a board's problems read as the strip's problems do.
const DEFECT_INK := UiTheme.DANGER
## The cursor's outline, in canvas pixels.
const CURSOR_WIDTH := 1.0

var cursor_cell := Vector2i.ZERO

var _marks: Array[Vector2i] = []

var _doc: MapDocument
var _db: TerrainDB
var _thumb: MapThumbnail
var _rungs := PackedFloat64Array([BattleZoom.DEFAULT_ZOOM])
## Which rung of `_rungs` the board stands on, and -1 for a board that has not
## framed itself yet: the ladder is measured against the frame, and a page one
## frame old has no frame to measure against.
var _rung := -1
var _origin := Vector2.ZERO


func _init() -> void:
	clip_contents = true
	_thumb = MapThumbnail.new()
	# Behind this control's own `_draw`, since a child paints over its parent and
	# the cursor is the one thing that may not be painted over.
	_thumb.show_behind_parent = true
	add_child(_thumb)


func _ready() -> void:
	resized.connect(refresh)


## Points the board at the draft it is painting, opening at the closest rung to
## the one a match opens on.
func show_document(doc: MapDocument, db: TerrainDB) -> void:
	_doc = doc
	_db = db
	_rung = -1
	cursor_cell = Vector2i.ZERO
	refresh()


## Re-reads the draft: the ladder, the scroll and every cell's art. Called after
## anything that could have changed what the board says about itself.
func refresh() -> void:
	if _doc == null:
		return
	_rungs = BattleZoom.rungs_for(BattleZoom.floor_for(size, _world_px()))
	_rung = opening_rung(_rungs) if _rung < 0 else clampi(_rung, 0, _rungs.size() - 1)
	var tile := tile_px()
	var board := Vector2(_doc.size()) * tile
	_origin = Vector2(
		scroll_axis(size.x, board.x, cursor_cell.x * tile, tile, _origin.x),
		scroll_axis(size.y, board.y, cursor_cell.y * tile, tile, _origin.y)
	)
	_thumb.position = _origin
	_thumb.size = board
	_thumb.setup(preview_of(_doc, _db), UiTheme.menu_identity(), board)
	queue_redraw()


## Rings the cells the validator's complaints name, replacing whatever was
## ringed before. The board picks none of them itself (see MapDefect).
func mark_cells(cells: Array[Vector2i]) -> void:
	_marks = cells
	queue_redraw()


## Puts the cursor back inside a board that has just changed size, keeping the
## rung the author is working at.
func fit_cursor() -> void:
	cursor_cell = cursor_cell.clamp(Vector2i.ZERO, _doc.size() - Vector2i.ONE)
	refresh()


func set_cursor(cell: Vector2i) -> void:
	if not _doc.in_bounds(cell) or cell == cursor_cell:
		return
	cursor_cell = cell
	refresh()


## One rung in or out, whichever end of the ladder the step falls off.
func zoom_step(rungs: int) -> void:
	_rung = clampi(_rung + rungs, 0, _rungs.size() - 1)
	refresh()


## A cell's width on screen, which is what the scroll and the cursor measure in.
func tile_px() -> float:
	return maxf(1.0, floorf(BattleView.TILE * _rungs[maxi(_rung, 0)]))


## Which cell a point in this control's own coordinates falls on. Out-of-bounds
## answers are the caller's to refuse — a drag that leaves the board keeps
## reporting where it went.
func cell_at(point: Vector2) -> Vector2i:
	return cell_from(point, _origin, tile_px())


func _draw() -> void:
	if _doc == null:
		return
	var tile := tile_px()
	for cell in _marks:
		var mark := _origin + Vector2(cell) * tile
		draw_rect(Rect2(mark, Vector2(tile, tile)), DEFECT_INK, false, CURSOR_WIDTH)
	var at := _origin + Vector2(cursor_cell) * tile
	draw_rect(Rect2(at, Vector2(tile, tile)), CURSOR_INK, false, CURSOR_WIDTH)


## The draft as the simulation reads it: written out and parsed straight back,
## which is exactly what saving it and launching it will do.
static func preview_of(doc: MapDocument, db: TerrainDB) -> MapData:
	return MapData.parse(doc.to_text(), db)


## Which rung a board opens on: the one a match opens on where the board can hold
## it, and the furthest-out rung — the whole-board view — where it cannot.
static func opening_rung(rungs: PackedFloat64Array) -> int:
	for i in rungs.size():
		if rungs[i] >= BattleZoom.DEFAULT_ZOOM:
			return i
	return 0


## Where the board's top-left sits on one axis: centred while the whole board
## fits the frame, and otherwise scrolled the least that keeps the focused cell
## inside it — so a cursor walked off the edge pulls the board along by one cell
## rather than recentring under it.
static func scroll_axis(
	view: float, board: float, focus_at: float, focus_size: float, current: float
) -> float:
	if board <= view:
		return floorf((view - board) / 2.0)
	var origin := clampf(current, -focus_at, view - focus_at - focus_size)
	return clampf(origin, view - board, 0.0)


static func cell_from(point: Vector2, origin: Vector2, tile: float) -> Vector2i:
	return Vector2i(((point - origin) / tile).floor())


## The board in world pixels — the board's own size, before a zoom — which is
## what the zoom ladder's floor is measured against.
func _world_px() -> Vector2:
	return Vector2(_doc.size()) * BattleView.TILE
