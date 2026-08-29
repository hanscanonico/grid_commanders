class_name MapEditor
extends Control
## The map editor: a board somebody paints (COM-263).
##
## The draft is a `MapDocument` and nothing else — the editor holds one from the
## moment the new-map page is answered until it leaves for the menu, and every
## edit is a call on it. Which cell holds what is therefore the document's
## answer, never this page's: what is on screen is `EditorBoard`'s reading of the
## draft, taken again after every stroke, so there is no second copy of the board
## here to fall out of step with the file it saves to.
##
## This slice paints terrain. Ownership, armies, validation and saving are the
## next one; they are panels beside the palette and calls on the same document,
## which is why the document is kept whole rather than flattened into a grid.
##
## Boot with:  Godot --path . scenes/editor/map_editor.tscn   (see `make run`'s
## Map Editor button, and `make editor-screenshot`).

const MENU_SCENE := "res://scenes/menu/main_menu.tscn"

## The board cursor's four steps, the board's own action names — an editor that
## bound its own directions would be a second convention for the one gesture.
const DIR_ACTIONS: Dictionary = {
	&"cursor_up": Vector2i.UP,
	&"cursor_down": Vector2i.DOWN,
	&"cursor_left": Vector2i.LEFT,
	&"cursor_right": Vector2i.RIGHT,
}

## How wide the palette column stands. Wide enough for the longest terrain name
## in the display face beside its swatch.
const _PALETTE_W := 108

var _db: TerrainDB
var _doc: MapDocument
## The armies the new-map page said this board is meant to seat. Carried, not
## enforced: the roster is what the board's properties name (four-players D1).
var _seats: int = MapData.DEFAULT_TEAMS.size()
var _board: EditorBoard
var _palette: EditorPalette
var _new_map: EditorNewMapPanel
var _headline: Label
var _status: Label
## True while a held mouse button is dragging a stroke across the board.
var _painting := false
## One step per gesture, the board's convention (see DirectionalInput).
var _dirs := DirectionalInput.new()


func _ready() -> void:
	_db = TerrainDB.load_default()
	_build()
	var shot_path := ScreenshotUtil.requested()
	if shot_path != "":
		# A capture photographs the editor, not the page it opens on: the frame is
		# of a board under a palette, which is the thing this scene is.
		_open(EditorNewMapPanel.DEFAULT_SIZE, _seats)
		await ScreenshotUtil.capture_and_quit(self, shot_path)
		return
	_new_map.begin()


func _unhandled_input(event: InputEvent) -> void:
	if _doc == null:
		return
	if event.is_action_pressed(&"cancel"):
		_leave()
		return
	if event.is_action_pressed(&"zoom_in"):
		_board.zoom_step(1)
		return
	if event.is_action_pressed(&"zoom_out"):
		_board.zoom_step(-1)
		return
	if event.is_action_pressed(&"confirm"):
		_paint_at(_board.cursor_cell)
		return
	var dir := _dirs.step(event, DIR_ACTIONS.keys())
	if not dir.is_empty():
		_board.set_cursor(_board.cursor_cell + DIR_ACTIONS[dir])
		_say_cursor()


# --- the draft ---------------------------------------------------------------


## Opens a fresh draft of `board_size` on open ground.
func _open(board_size: Vector2i, seats: int) -> void:
	_seats = seats
	_doc = MapDocument.blank(board_size.x, board_size.y, _db)
	_board.show_document(_doc, _db)
	_say_cursor()


## Lays the brush on `cell`, and does nothing at all where it would change
## nothing — a drag crosses the same cell many times, and each stroke re-reads
## the whole board.
func _paint_at(cell: Vector2i) -> void:
	if not _doc.in_bounds(cell):
		return
	_board.set_cursor(cell)
	var brush := _palette.selected()
	if brush == null or _doc.terrain_at(cell).id == brush.id:
		_say_cursor()
		return
	_doc.paint(cell, brush.id)
	_board.refresh()
	_say_cursor()


## Takes the focus off whatever menu control holds it. **The board is not a
## focusable control**, and cannot be: a focused Control makes the viewport read
## the arrow keys as focus navigation, which walked the cursor out of the board
## and into the palette. So the board answers the arrows only while nothing else
## has claimed them, and choosing a brush or clicking the board gives them back.
func _hand_the_board_back() -> void:
	get_viewport().gui_release_focus()


func _leave() -> void:
	get_tree().change_scene_to_file(MENU_SCENE)


# --- input on the board ------------------------------------------------------


## The mouse's half of painting: a press paints and arms the drag, a release
## disarms it, and motion under a held button keeps painting. Every mouse button
## is swallowed, so a right-click on the board cannot read as the cancel it also
## is and walk the author out of their draft.
func _on_board_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click != null:
		_board.accept_event()
		if click.button_index != MOUSE_BUTTON_LEFT:
			return
		_hand_the_board_back()
		_painting = click.pressed
		if click.pressed:
			_paint_at(_board.cell_at(_board.get_local_mouse_position()))
		return
	if event is InputEventMouseMotion:
		var cell := _board.cell_at(_board.get_local_mouse_position())
		if _painting:
			_paint_at(cell)
		elif _doc.in_bounds(cell):
			_board.set_cursor(cell)
			_say_cursor()


# --- layout ------------------------------------------------------------------


func _build() -> void:
	UiKit.page_veil(self, 1.0)
	var main := UiKit.page_body(self, 5)
	main.add_child(_build_header())

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", UiTheme.GAP)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_child(body)

	_palette = EditorPalette.new()
	_palette.custom_minimum_size = Vector2(_PALETTE_W, 0)
	body.add_child(_palette)
	_palette.configure(_db)
	# The brush is chosen and the board is what the next press is meant for, so
	# the palette lets the arrows go rather than keeping them.
	_palette.picked.connect(func(_terrain: TerrainType) -> void: _hand_the_board_back())

	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", UiTheme.dark_panel_box(UiTheme.SLATE_900))
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(frame)
	_board = EditorBoard.new()
	_board.gui_input.connect(_on_board_input)
	frame.add_child(_board)

	_status = UiKit.key_legend("")
	main.add_child(_status)
	main.add_child(UiKit.key_legend("ARROWS  MOVE      ENTER  PAINT      +/-  ZOOM      ESC  MENU"))

	_new_map = EditorNewMapPanel.new()
	add_child(_new_map)
	_new_map.created.connect(_open)
	# Nothing stands behind the new-map page but an empty frame, so backing out of
	# it is backing out of the editor.
	_new_map.cancelled.connect(_leave)


func _build_header() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var title := UiKit.page_title("MAP EDITOR")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)
	_headline = UiKit.micro_label("")
	_headline.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_headline)
	return row


## What the draft is and where the brush is standing — the two lines the page
## keeps current, since neither is anything the board itself draws.
func _say_cursor() -> void:
	var cell := _board.cursor_cell
	_headline.text = "%d x %d · %d ARMIES" % [_doc.width, _doc.height, _seats]
	_status.text = (
		"%d,%d  %s      BRUSH  %s"
		% [
			cell.x,
			cell.y,
			_doc.terrain_at(cell).display_name.to_upper(),
			_palette.selected().display_name.to_upper()
		]
	)
