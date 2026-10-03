class_name SeatGeneralChip
extends Button
## A seat row's general (SeatStrip): who commands that army, pressed to open the
## commander page for that one seat. A window onto the general's face chip, or
## NO CO for a seat with none — the name rides the tooltip, since a seat row
## already squeezes "Human" and has no room for "Cassian Rook" beside it.
##
## The face is the baked chip (`CommanderVisuals.face_for`) at one texel to one
## pixel, cropped rather than resampled: a row is shorter than the chip, so the
## window opens on its brow-to-chin band. Drawn by `CommanderBust` like every
## other field that shows a general, so the 3D view's stills reach it too.

## The window's size: the face chip's whole width, and its eyes-to-mouth band —
## what fits inside the row's border.
const FACE_WINDOW := Vector2i(CommanderVisuals.FACE_SIZE.x, 12)
## The face chip's row the window opens at — the brow.
const FACE_TOP := 10
const NEUTRAL_TEXT := "NO CO"
## The air either side of whatever the chip shows, over the segment box's own.
const _PAD := 2.0

var _window: Control
var _bust: CommanderBust
var _none: Label
var _tip: Tooltip


func _init(height: int) -> void:
	custom_minimum_size = Vector2(width(), height)
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	clip_contents = true

	_window = Control.new()
	_window.clip_contents = true
	_window.custom_minimum_size = Vector2(FACE_WINDOW)
	_window.size = Vector2(FACE_WINDOW)
	_window.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_KEEP_SIZE)
	_window.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_window)
	_bust = UiKit.commander_bust(null, Vector2(CommanderVisuals.FACE_SIZE), UiKit.NO_FIELD)
	_bust.position = Vector2(
		-floorf((CommanderVisuals.FACE_SIZE.x - FACE_WINDOW.x) * 0.5), -FACE_TOP
	)
	_bust.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_window.add_child(_bust)

	_none = Label.new()
	_none.text = NEUTRAL_TEXT
	_none.add_theme_font_override("font", UiTheme.stat())
	_none.add_theme_font_size_override("font_size", UiTheme.SIZE_STAT)
	_none.add_theme_color_override("font_color", UiTheme.INK)
	_none.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_none.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_none.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_none.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_none)

	# The segment frame's own dress, so the chip reads as one more control on the
	# row: paper inside the hard border and shadow every run there wears.
	var box := UiTheme.bordered(UiTheme.PAPER, UiTheme.HARD_BORDER, UiTheme.BORDER, true)
	for state: StringName in [&"normal", &"hover", &"pressed", &"disabled"]:
		add_theme_stylebox_override(state, box)
	add_theme_stylebox_override("focus", UiTheme.focus_box())
	_tip = Tooltip.attach(self, "", "", Tooltip.Side.BOTTOM)
	UiKit.touchable(self)


## The chip's one width, whoever it shows: the wider of the face window and the
## NO CO caption, so picking a general never moves the row.
static func width() -> float:
	var words := UiTheme.stat().get_string_size(
		NEUTRAL_TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.SIZE_STAT
	)
	return maxf(FACE_WINDOW.x, words.x) + 2.0 * _PAD


## What the tooltip calls the seat's general.
static func caption(commander: CommanderType) -> String:
	if commander == null or not CommanderPicks.is_general(commander.id):
		return "No commander"
	return commander.display_name


## Shows `commander` (neutral for none) on a field in `livery`.
func show_general(commander: CommanderType, livery: Color) -> void:
	var general := commander != null and CommanderPicks.is_general(commander.id)
	_window.visible = general
	_none.visible = not general
	if general:
		_bust.bind(commander, livery)
	_tip.set_copy(caption(commander), "Choose this seat's general")
