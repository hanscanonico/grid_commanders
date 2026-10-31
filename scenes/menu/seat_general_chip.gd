class_name SeatGeneralChip
extends Button
## A seat row's general (SeatStrip): who commands that army, by face and by name,
## pressed to open the commander page for that one seat.
##
## The face is the baked chip (`CommanderVisuals.face_for`) at one texel to one
## pixel. Drawn by `CommanderBust` like every other field that shows a general, so
## the 3D view's stills reach it too.

## The chip's narrowest: the face, and room for the longest name on the roster.
const MIN_WIDTH := 128.0
const _PAD := 2
const _GAP := 4
## The mark that says the chip opens something.
const _OPEN_MARK := " ▸"

var _bust: CommanderBust
var _name: Label
var _tip: Tooltip


func _init(height: int) -> void:
	custom_minimum_size = Vector2(MIN_WIDTH, height)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	clip_contents = true

	var face := Vector2(CommanderVisuals.FACE_SIZE)
	_bust = UiKit.commander_bust(null, face, UiKit.NO_FIELD)
	_bust.position = Vector2(_PAD, floorf((height - face.y) * 0.5))
	_bust.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bust)

	_name = Label.new()
	_name.add_theme_font_override("font", UiTheme.display())
	_name.add_theme_font_size_override("font_size", UiTheme.SIZE_BODY)
	_name.add_theme_color_override("font_color", UiTheme.INK)
	_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_name.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_name.clip_text = true
	_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_name)

	# The segment frame's own dress, so the chip reads as one more control on the
	# row: paper inside the hard border and shadow every run there wears.
	var box := UiTheme.bordered(UiTheme.PAPER, UiTheme.HARD_BORDER, UiTheme.BORDER, true)
	for state: StringName in [&"normal", &"hover", &"pressed", &"disabled"]:
		add_theme_stylebox_override(state, box)
	add_theme_stylebox_override("focus", UiTheme.focus_box())
	_tip = Tooltip.attach(self, "", "", Tooltip.Side.BOTTOM)
	UiKit.touchable(self)


## What the chip and its tooltip call the seat's general.
static func caption(commander: CommanderType) -> String:
	if commander == null or not CommanderPicks.is_general(commander.id):
		return "No commander"
	return commander.display_name


## Shows `commander` (neutral for none) on a field in `livery`.
func show_general(commander: CommanderType, livery: Color) -> void:
	var general := commander != null and CommanderPicks.is_general(commander.id)
	_bust.visible = general
	_name.offset_left = _PAD + _GAP + (CommanderVisuals.FACE_SIZE.x if general else 0)
	_name.text = caption(commander) + _OPEN_MARK
	if general:
		_bust.bind(commander, livery)
	_tip.set_copy(caption(commander), "Choose this seat's general")
