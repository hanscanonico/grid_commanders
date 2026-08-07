class_name ActionFeedback
extends PanelContainer
## A one-line reason for an input the battle scene refused. It floats beside the
## cursor, dismisses itself, and never takes focus or blocks play.

const HOLD_SECONDS := 1.1
const FADE_SECONDS := 0.18
const PAD_X := 5
const PAD_Y := 3
const EDGE_GAP := 4.0

## Public for the driven acceptance scenario: the words are the behavior under
## test, while the label and dismissal tween stay private presentation detail.
var reason := ""

var _label: Label
var _dismiss_tween: Tween
var _built_this_turn: Dictionary = {}  # Unit -> true


func _ready() -> void:
	add_theme_stylebox_override("panel", _panel_box())

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", PAD_X)
	margin.add_theme_constant_override("margin_top", PAD_Y)
	margin.add_theme_constant_override("margin_right", PAD_X)
	margin.add_theme_constant_override("margin_bottom", PAD_Y)
	add_child(margin)

	_label = UiTheme.hud_label("", UiTheme.SIZE_TIP, UiTheme.WHITE)
	margin.add_child(_label)

	# The chip floats over the board, so nothing in it may eat a click meant for
	# the tile underneath: a Container child left on its own filter swallows the
	# press before _unhandled_input ever sees it. `make_decoration` walks the whole
	# subtree, which is what keeps that true when a piece is added later.
	UiTheme.make_decoration(self)
	hide()


func show_reason(text: String, anchor: Vector2) -> void:
	reason = text
	_label.text = text
	modulate = Color.WHITE
	show()
	reset_size()

	var panel_size := get_combined_minimum_size()
	size = panel_size
	var viewport_size := get_viewport_rect().size
	var pos := anchor + Vector2(EDGE_GAP, -panel_size.y - EDGE_GAP)
	if pos.x + panel_size.x > viewport_size.x - EDGE_GAP:
		pos.x = anchor.x - panel_size.x - EDGE_GAP
	pos.x = clampf(pos.x, EDGE_GAP, viewport_size.x - panel_size.x - EDGE_GAP)
	pos.y = clampf(
		pos.y,
		UiTheme.HUD_TOP_H + EDGE_GAP,
		viewport_size.y - UiTheme.HUD_BOTTOM_H - panel_size.y - EDGE_GAP
	)
	position = pos

	if _dismiss_tween != null and _dismiss_tween.is_valid():
		_dismiss_tween.kill()
	_dismiss_tween = create_tween()
	_dismiss_tween.tween_interval(HOLD_SECONDS)
	_dismiss_tween.tween_property(self, "modulate:a", 0.0, FADE_SECONDS)
	_dismiss_tween.tween_callback(hide)


func mark_built(unit: Unit) -> void:
	_built_this_turn[unit] = true


func was_built_this_turn(unit: Unit) -> bool:
	return _built_this_turn.has(unit)


func clear_turn() -> void:
	_built_this_turn.clear()


func _panel_box() -> StyleBoxFlat:
	var box := UiTheme.bordered(UiTheme.SLATE_800, UiTheme.HARD_BORDER, UiTheme.BORDER, true)
	box.set_corner_radius_all(UiTheme.RADIUS)
	return box
