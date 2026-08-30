class_name EditorSidebar
extends PanelContainer
## Everything about a board that is not its ground: who owns the building under
## the cursor, which army stands on it, and how big the board is.
##
## Named for where it stands rather than for what it does, because `Inspector` is
## a class the engine already has.
##
## The seat is one choice serving two brushes, deliberately. A property's owner
## and a starting unit's team are the same fact about the same army, and an
## editor that asked twice would let an author paint Red's base and stand Blue's
## infantry on it without ever noticing they had answered two questions.
##
## Nothing here decides the roster: the armies a board seats are what its
## properties and units name (four-players D1), which is `MapDocument.teams`.
## Seat 4 is offered on every board because painting seat 4's headquarters is
## exactly how a board becomes a four-army board.

## The seat the two brushes are aimed at, `MapData.NEUTRAL` for nobody's.
signal seat_picked(team: int)
## The unit brush, null for the eraser that clears a cell.
signal unit_picked(unit_type: UnitType)
signal resize_asked(board_size: Vector2i)

## A unit row's height and the inset its words sit at — the palette's, since the
## two columns flank the same board and a row that stood taller on one side would
## read as a different kind of control.
const ROW_HEIGHT := EditorPalette.ROW_HEIGHT
const ROW_INSET := EditorPalette.ROW_INSET
## A unit's icon is one tile wide, the size the palette's swatch and the HUD's
## unit icon are: the two columns flank the same board and read as one control.
const ICON := EditorPalette.SWATCH
## What the neutral seat is called on its chip. A dash rather than the word,
## because the chip is four characters wide.
const NEUTRAL_LABEL := "—"

var _units: Array[UnitType] = []
var _seat_buttons: Array[Button] = []
var _unit_buttons: Array[Button] = []
var _unit_labels: Array[Label] = []
## One icon per unit row, in `_units` order — the eraser's row carries a blank
## of the same width instead, so every name in the column starts at one inset.
var _unit_icons: Array[TextureRect] = []
var _seat: int = MapData.PLAYER_TEAMS[0]
## Which row of `_unit_buttons` is lit. Row 0 is the eraser, so a fresh column
## has no unit in hand and the first press on the board cannot stand one.
var _unit := 0
var _size := Vector2i.ZERO
var _width_value: Label
var _height_value: Label


## Stocks the column from the unit database and dresses it.
func configure(units: UnitDB) -> void:
	_units = units.all()
	add_theme_stylebox_override("panel", UiTheme.dark_panel_box())

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	add_child(col)

	col.add_child(_header("Owner"))
	col.add_child(UiKit.pad(_build_seats(), ROW_INSET, ROW_INSET))
	col.add_child(_header("Army"))
	col.add_child(_build_units())
	col.add_child(_header("Board"))
	col.add_child(UiKit.pad(_build_size(), ROW_INSET, ROW_INSET))
	_restyle()


## The seat every brush is aimed at: who owns a building the terrain brush lays,
## who owns one the owner brush hands over, and who a placed unit fights for.
func seat() -> int:
	return _seat


## The unit brush, or null for the eraser.
func unit() -> UnitType:
	return _units[_unit - 1] if _unit > 0 else null


## What the unit brush is called, eraser included — the status line's words.
func unit_name() -> String:
	var unit_type := unit()
	return unit_type.display_name if unit_type != null else "NO UNIT"


## Shows the board's size, which the steppers walk from.
func show_size(board_size: Vector2i) -> void:
	_size = board_size
	_width_value.text = "%d" % _size.x
	_height_value.text = "%d" % _size.y


func _build_seats() -> Control:
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override(
		"panel", UiTheme.bordered(UiTheme.PAPER, UiTheme.HARD_BORDER, UiTheme.BORDER, true)
	)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	frame.add_child(row)
	var teams: Array[int] = [MapData.NEUTRAL]
	teams.append_array(MapData.PLAYER_TEAMS)
	for team in teams:
		var chip := Button.new()
		chip.text = NEUTRAL_LABEL if team == MapData.NEUTRAL else "%d" % team
		chip.toggle_mode = true
		chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		chip.custom_minimum_size = Vector2(0, 16)
		chip.add_theme_font_override("font", UiTheme.display())
		chip.add_theme_font_size_override("font_size", UiTheme.SIZE_SEGMENT)
		chip.tooltip_text = (
			"Nobody owns it" if team == MapData.NEUTRAL else "Seat %d owns it" % team
		)
		chip.pressed.connect(_pick_seat.bind(team))
		row.add_child(UiKit.touchable(chip))
		_seat_buttons.append(chip)
	return frame


func _build_units() -> Control:
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 1)
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_child(_unit_row(0, "No unit", null))
	for i in _units.size():
		rows.add_child(_unit_row(i + 1, _units[i].display_name, _units[i]))
	var frame := UiKit.vscroll()
	frame.add_child(rows)
	var padded := UiKit.pad(frame, ROW_INSET, ROW_INSET)
	padded.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return padded


func _unit_row(index: int, text: String, unit_type: UnitType) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	button.tooltip_text = (
		"Clear the cell under the cursor" if index == 0 else "Stand one at the cursor"
	)
	button.pressed.connect(_pick_unit.bind(index))
	var face := ListRow.face(ROW_INSET)
	face.add_child(_icon(unit_type))
	var label := ListRow.cell(text.to_upper(), UiTheme.WHITE)
	face.add_child(label)
	button.add_child(face)
	UiKit.touchable(button)
	_unit_buttons.append(button)
	_unit_labels.append(label)
	return button


## The unit's own artwork, cut to the tile it stands on — the same call the HUD's
## unit icon and the build menu's rows make, so a row here and a row there are
## the same picture. The eraser gets a blank of the same width rather than no
## child at all, which is what keeps the names in one column.
func _icon(unit_type: UnitType) -> Control:
	if unit_type == null:
		var blank := Control.new()
		blank.custom_minimum_size = Vector2(ICON, ICON)
		return blank
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(ICON, ICON)
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_unit_icons.append(icon)
	return icon


## The two steppers a board is grown or cropped with. Resizing after creation is
## the only route back from a board the validator refuses for its size, and from
## one whose author wanted three more columns rather than a fresh start.
func _build_size() -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	_width_value = UiKit.micro_label("")
	_height_value = UiKit.micro_label("")
	col.add_child(UiKit.stepper("W", _width_value, func(step: int) -> void: _step(step, 0)))
	col.add_child(UiKit.stepper("H", _height_value, func(step: int) -> void: _step(step, 1)))
	return col


func _step(step: int, axis: int) -> void:
	var wanted := _size
	wanted[axis] = EditorNewMapPanel.clamp_side(wanted[axis] + step)
	if wanted == _size:
		return
	show_size(wanted)
	resize_asked.emit(wanted)


func _pick_seat(team: int) -> void:
	_seat = team
	_restyle()
	seat_picked.emit(team)


func _pick_unit(index: int) -> void:
	_unit = index
	_restyle()
	unit_picked.emit(unit())


func _header(text: String) -> Control:
	var header := PanelContainer.new()
	header.add_theme_stylebox_override("panel", UiTheme.header_box(UiTheme.SLATE_700))
	var heading := UiKit.micro_label(text)
	heading.add_theme_color_override("font_color", UiTheme.WHITE)
	header.add_child(heading)
	return header


## The seat in hand wears its own army's colour rather than one shared accent:
## the chip is the only place the editor says which army a brush belongs to, and
## a board painted in the wrong livery is the mistake this column exists to stop.
func _restyle() -> void:
	var identity := UiTheme.menu_identity(MapData.PLAYER_TEAMS.size())
	for i in _seat_buttons.size():
		var team: int = i  # the row order: neutral, then seats 1..N
		var accent := UiTheme.NEUTRAL if team == MapData.NEUTRAL else identity.theme(team).color
		UiKit.style_segment(_seat_buttons[i], team == _seat, i > 0, accent)
	for i in _unit_buttons.size():
		var chosen := i == _unit
		var variant := UiTheme.ButtonVariant.SECONDARY if chosen else UiTheme.ButtonVariant.GHOST
		UiTheme.apply_button(_unit_buttons[i], variant, null, UiTheme.SIZE_BUTTON)
		_unit_labels[i].add_theme_color_override(
			"font_color", UiTheme.INK if chosen else UiTheme.WHITE
		)
	# The column wears the seat in hand, since that is the army the next press
	# stands. The neutral chip owns no unit — `_stand_unit` refuses one — so its
	# rows keep seat 1's livery rather than going grey over a brush nobody owns.
	var row := identity.atlas_row(MapData.PLAYER_TEAMS[0] if _seat == MapData.NEUTRAL else _seat)
	for i in _unit_icons.size():
		_unit_icons[i].texture = UnitSprite.tile_texture_for(_units[i], row)
