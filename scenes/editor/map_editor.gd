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
## Whether the draft *plays* is `MapValidator`'s answer, taken again just as
## often and shown under the board. The editor decides nothing about a board and
## refuses nothing of its own: Save is closed while a complaint stands because
## the validator says one does, and the marks on the board are the very cells the
## complaints name (`MapDefect`).
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

## What the page says the board answers to. Two legends because a touch build has
## no arrows and a desktop one has no second finger; which is printed is
## `MobileProfile`'s answer, never a caller's.
const LEGEND_KEYS := "ARROWS  MOVE      ENTER  APPLY      +/-  ZOOM      ESC  MENU"
const LEGEND_TOUCH := "TAP  PAINT      DRAG  PAN      PINCH  ZOOM      BRUSHES  TOOLS"

## How wide the two columns stand. Wide enough for the longest terrain and unit
## name in the display face beside its swatch.
const _PALETTE_W := 108
const _INSPECTOR_W := 96

## What the next press on the board lays. Picking from a column arms that
## column's brush, because the last thing an author chose is the thing they mean
## — an editor with a separate mode switch asks the same question twice.
enum Brush { TERRAIN, OWNER, UNIT }

var _db: TerrainDB
var _unit_db: UnitDB
var _doc: MapDocument
## The armies the new-map page said this board is meant to seat. Carried, not
## enforced: the roster is what the board's properties name (four-players D1).
var _seats: int = MapData.DEFAULT_TEAMS.size()
var _board: EditorBoard
var _palette: EditorPalette
var _inspector: EditorSidebar
var _strip: EditorValidationStrip
var _new_map: EditorNewMapPanel
## The two brush columns as a page, on a touch build only — null on a desktop
## one, where they flank the board and there is no sheet to build (mobile D5).
var _sheet: EditorToolSheet
## The hand on the board, null on a desktop build for the same reason.
var _touch: EditorTouch
var _open_panel: EditorOpenPanel
var _save_dialog: EditorSaveDialog
var _headline: Label
var _status: Label
var _brush := Brush.TERRAIN
## Everything wrong with the draft as it stands, re-read after every edit.
var _defects: Array[MapDefect] = []
## Why the press that just landed changed nothing, in the author's words. Set by
## a brush that refused and printed instead of the cursor's usual reading.
var _refusal := ""
## True while a held mouse button is dragging a stroke across the board.
var _painting := false
## One step per gesture, the board's convention (see DirectionalInput).
var _dirs := DirectionalInput.new()


func _ready() -> void:
	_db = TerrainDB.load_default()
	_unit_db = UnitDB.load_default()
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
	if _doc == null or _page_is_open():
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
		_apply_at(_board.cursor_cell)
		return
	var dir := _dirs.step(event, DIR_ACTIONS.keys())
	if not dir.is_empty():
		_board.set_cursor(_board.cursor_cell + DIR_ACTIONS[dir])
		_say_cursor()


## Whether a full-screen page stands over the board. The board keeps no state
## while one is up — a cursor walked behind a dialog is a cursor the author did
## not move.
func _page_is_open() -> bool:
	return (
		_new_map.visible
		or _open_panel.visible
		or _save_dialog.visible
		or (_sheet != null and _sheet.visible)
	)


# --- the draft ---------------------------------------------------------------


## Opens a fresh draft of `board_size` on open ground.
func _open(board_size: Vector2i, seats: int) -> void:
	_seats = seats
	_adopt(MapDocument.blank(board_size.x, board_size.y, _db))


## Opens a board that already exists. A shipped one opens nameless: `UserMaps`
## refuses a name the game already ships, and finding that out at the save dialog
## costs the author a whole board's work.
func _open_path(path: String) -> void:
	var map := MapData.load_from_file(path, _db)
	if map == null:
		_status.text = "THAT BOARD COULD NOT BE READ"
		return
	var doc := MapDocument.from_map(map, _db)
	if not path.begins_with(MapCatalog.USER_DIR):
		doc.map_name = ""
	_seats = doc.player_count()
	_adopt(doc)


func _adopt(doc: MapDocument) -> void:
	_doc = doc
	_board.show_document(_doc, _db)
	_inspector.show_size(_doc.size())
	_revalidate()
	_say_cursor()


## Lays the brush on `cell`, and does nothing at all where it would change
## nothing — a drag crosses the same cell many times, and each stroke re-reads
## the whole board.
func _apply_at(cell: Vector2i) -> void:
	if not _doc.in_bounds(cell):
		return
	_board.set_cursor(cell)
	_refusal = ""
	if _apply_brush(cell):
		_board.refresh()
		_revalidate()
	if _refusal.is_empty():
		_say_cursor()
	else:
		_status.text = _refusal.to_upper()


## Whether the draft changed. A brush that cannot be laid here says why in
## `_refusal` rather than through the document, which would only push an error
## into a log the author is not reading.
func _apply_brush(cell: Vector2i) -> bool:
	match _brush:
		Brush.OWNER:
			if not _doc.terrain_at(cell).is_property:
				_refusal = "only a building can be owned"
				return false
			return (
				_doc.owner_at(cell) != _inspector.seat() and _doc.set_owner(cell, _inspector.seat())
			)
		Brush.UNIT:
			return _stand_unit(cell)
	var terrain := _palette.selected()
	if terrain == null or _doc.terrain_at(cell).id == terrain.id:
		return false
	return _doc.paint(cell, terrain.id)


func _stand_unit(cell: Vector2i) -> bool:
	var unit_type := _inspector.unit()
	if unit_type == null:
		if _doc.unit_at(cell).is_empty():
			return false
		_doc.remove_unit(cell)
		return true
	if _inspector.seat() == MapData.NEUTRAL:
		_refusal = "pick the seat this unit fights for"
		return false
	return _doc.place_unit(cell, unit_type, _inspector.seat())


## What still stands between the draft and a playable board, said under the board
## and marked on it. Both readings are the one list, so a complaint and its mark
## can never name different cells.
func _revalidate() -> void:
	_defects = MapValidator.draft_defects(_doc, _db)
	_strip.show_defects(_defects)
	_board.mark_cells(EditorValidationStrip.marked_cells(_defects))


# --- saving and opening ------------------------------------------------------


func _ask_save() -> void:
	_hand_the_board_back()
	if not _defects.is_empty():
		_status.text = "FIX WHAT IS LISTED BELOW THE BOARD FIRST"
		return
	_save_dialog.begin(_doc.map_name, _doc.description)


func _on_saved(map_name: String, description: String) -> void:
	_doc.description = description
	var error := UserMaps.save(map_name, _doc.to_text())
	if error != "":
		_save_dialog.refuse(error)
		return
	_doc.map_name = UserMaps.slug(map_name)
	_save_dialog.close()
	_hand_the_board_back()
	_status.text = "SAVED AS %s" % _doc.map_name.to_upper()


## Backing out of the new-map page is backing out of the editor while there is no
## draft behind it, and an ordinary cancel once there is one.
func _on_page_cancelled() -> void:
	if _doc == null:
		_leave()
		return
	_hand_the_board_back()
	_say_cursor()


## Backing out of the open list lands on the page it was reached from, which is
## the new-map page while there is no draft to go back to.
func _on_open_cancelled() -> void:
	if _doc == null:
		_new_map.begin()
		return
	_on_page_cancelled()


func _leave() -> void:
	get_tree().change_scene_to_file(MENU_SCENE)


# --- the columns -------------------------------------------------------------


## The brush is chosen and the board is what the next press is meant for, so a
## column lets the arrows go rather than keeping them — and the status line says
## the new brush at once rather than at the next thing the cursor does.
func _arm(brush: Brush) -> void:
	_brush = brush
	if _sheet != null:
		_sheet.close()
	_hand_the_board_back()
	if _doc != null:
		_say_cursor()


## Takes the focus off whatever menu control holds it. **The board is not a
## focusable control**, and cannot be: a focused Control makes the viewport read
## the arrow keys as focus navigation, which walked the cursor out of the board
## and into the palette. So the board answers the arrows only while nothing else
## has claimed them, and choosing a brush or clicking the board gives them back.
func _hand_the_board_back() -> void:
	get_viewport().gui_release_focus()


## Grows or crops the draft under the cursor, which is the only way back from a
## board the validator refuses for its size.
func _on_resize_asked(board_size: Vector2i) -> void:
	_doc.resize(board_size.x, board_size.y)
	_board.fit_cursor()
	_revalidate()
	_say_cursor()


# --- input on the board ------------------------------------------------------


## The mouse's half of painting: a press paints and arms the drag, a release
## disarms it, and motion under a held button keeps painting. Every mouse button
## is swallowed, so a right-click on the board cannot read as the cancel it also
## is and walk the author out of their draft.
func _on_board_input(event: InputEvent) -> void:
	if _touch != null:
		if _touch.handle(event):
			_board.accept_event()
		return
	var click := event as InputEventMouseButton
	if click != null:
		_board.accept_event()
		if click.button_index != MOUSE_BUTTON_LEFT:
			return
		_hand_the_board_back()
		_painting = click.pressed
		if click.pressed:
			_apply_at(_board.cell_at(_board.get_local_mouse_position()))
		return
	if event is InputEventMouseMotion:
		var cell := _board.cell_at(_board.get_local_mouse_position())
		if _painting:
			_apply_at(cell)
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
	_palette.configure(_db)
	_palette.picked.connect(func(_terrain: TerrainType) -> void: _arm(Brush.TERRAIN))

	_inspector = EditorSidebar.new()
	_inspector.custom_minimum_size = Vector2(_INSPECTOR_W, 0)
	_inspector.configure(_unit_db)
	_inspector.seat_picked.connect(func(_team: int) -> void: _arm(Brush.OWNER))
	_inspector.unit_picked.connect(func(_unit_type: UnitType) -> void: _arm(Brush.UNIT))
	_inspector.resize_asked.connect(_on_resize_asked)

	if MobileProfile.active():
		body.add_child(_build_board_column())
	else:
		body.add_child(_palette)
		body.add_child(_build_board_column())
		body.add_child(_inspector)

	_status = UiKit.key_legend("")
	main.add_child(_status)
	main.add_child(UiKit.key_legend(LEGEND_TOUCH if MobileProfile.active() else LEGEND_KEYS))

	_build_pages()


func _build_board_column() -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", UiTheme.dark_panel_box(UiTheme.SLATE_900))
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(frame)
	_board = EditorBoard.new()
	_board.gui_input.connect(_on_board_input)
	frame.add_child(_board)

	_strip = EditorValidationStrip.new()
	_strip.focused.connect(_on_defect_focused)
	col.add_child(_strip)
	return col


func _on_defect_focused(cell: Vector2i) -> void:
	_hand_the_board_back()
	_board.set_cursor(cell)
	_say_cursor()


func _build_pages() -> void:
	_new_map = EditorNewMapPanel.new()
	add_child(_new_map)
	_new_map.created.connect(_open)
	_new_map.open_asked.connect(func() -> void: _open_panel.begin())
	_new_map.cancelled.connect(_on_page_cancelled)

	_open_panel = EditorOpenPanel.new()
	add_child(_open_panel)
	_open_panel.chosen.connect(_open_path)
	_open_panel.cancelled.connect(_on_open_cancelled)

	_save_dialog = EditorSaveDialog.new()
	add_child(_save_dialog)
	_save_dialog.saved.connect(_on_saved)
	_save_dialog.cancelled.connect(_on_page_cancelled)

	if not MobileProfile.active():
		return
	_sheet = EditorToolSheet.new()
	add_child(_sheet)
	var columns: Array[Control] = [_palette, _inspector]
	_sheet.configure(columns)
	_sheet.closed.connect(_hand_the_board_back)
	_touch = EditorTouch.new(_board, _apply_at, _on_defect_focused)


func _build_header() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var title := UiKit.page_title("MAP EDITOR")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)
	if MobileProfile.active():
		row.add_child(_header_button("Brushes", func() -> void: _sheet.begin()))
	row.add_child(_header_button("Open", func() -> void: _open_panel.begin()))
	row.add_child(_header_button("Save", _ask_save))
	_headline = UiKit.micro_label("")
	_headline.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_headline)
	return row


func _header_button(text: String, on_press: Callable) -> Button:
	var button := UiKit.action_button(text, "", UiTheme.ButtonVariant.SECONDARY, null, 44)
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.pressed.connect(on_press)
	return button


## What the draft is and what is under the brush — the two lines the page keeps
## current, since neither is anything the board itself draws.
func _say_cursor() -> void:
	_headline.text = (
		"%d x %d · SEATS %d/%d" % [_doc.width, _doc.height, _doc.player_count(), _seats]
	)
	_status.text = "%s      BRUSH  %s" % [_cell_words(_board.cursor_cell), _brush_words()]


## The cell under the cursor: its ground, then whatever stands on it.
func _cell_words(cell: Vector2i) -> String:
	var words := "%d,%d  %s" % [cell.x, cell.y, _doc.terrain_at(cell).display_name.to_upper()]
	if _doc.owner_at(cell) != MapData.NEUTRAL:
		words += " · SEAT %d" % _doc.owner_at(cell)
	var standing := _doc.unit_at(cell)
	if not standing.is_empty():
		words += " · %s" % _unit_db.by_symbol(standing.symbol).display_name.to_upper()
	return words


func _brush_words() -> String:
	match _brush:
		Brush.OWNER:
			var seat := _inspector.seat()
			return "NOBODY OWNS IT" if seat == MapData.NEUTRAL else "SEAT %d OWNS IT" % seat
		Brush.UNIT:
			return _inspector.unit_name().to_upper()
	return _palette.selected().display_name.to_upper()
