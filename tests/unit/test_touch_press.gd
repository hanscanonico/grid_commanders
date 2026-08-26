extends GutTest
## The driven half of the touch gate: a real press, pushed through a real viewport,
## onto real UiKit widgets built under a pinned mobile profile.
##
## Here rather than beside test_touch_target.gd's arithmetic because the failure it
## exists for is a *wiring* failure, which no pure test can see: an area that flips
## `button_pressed` and stops there is silent to every control that reads `pressed`,
## and a segmented control reads `pressed`. Every wiring kind the shell uses gets a
## case, so the next control added to `UiKit.touchable` cannot answer only half the
## signals it is connected through.

const MIN := UiTheme.TOUCH_MIN

var _stage: Control
var _plane: CanvasLayer


func before_each() -> void:
	MobileProfile.pin(true)
	# On a canvas layer of its own above the runner's own screen: the viewport picks
	# the topmost layer first, and GUT's UI would otherwise eat every press.
	_plane = CanvasLayer.new()
	_plane.layer = 128
	get_tree().root.add_child(_plane)
	_stage = Control.new()
	_stage.set_anchors_preset(Control.PRESET_FULL_RECT)
	_plane.add_child(_stage)


func after_each() -> void:
	MobileProfile.unpin()
	_plane.queue_free()


func _area_over(button: BaseButton) -> TouchTarget:
	for child in button.get_children():
		if child is TouchTarget:
			return child
	return null


## Two frames: one for the container to place its children, one for the deferred
## fit that measures their neighbours.
func _settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


func _tap(area: Control) -> void:
	var at := area.get_global_rect().get_center()
	for down in [true, false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = down
		click.position = at
		click.global_position = at
		get_tree().root.push_input(click, true)
	await get_tree().process_frame


func _column(child: Control) -> void:
	var column := VBoxContainer.new()
	column.position = Vector2(40, 40)
	column.custom_minimum_size = Vector2(200, 0)
	_stage.add_child(column)
	column.add_child(child)


## A segmented control: toggle_mode, wired through `pressed`. The whole seat strip
## — seats, sides and the tier chip — is this control.
func test_a_segment_answers_a_tap() -> void:
	var picks: Array[int] = []
	var buttons: Array[Button] = []
	_column(
		UiKit.segment(
			"",
			PackedStringArray(["HUMAN", "CPU", "EMPTY"]),
			0,
			UiTheme.CAPTURE,
			"",
			"",
			func(index: int) -> void: picks.append(index),
			buttons
		)
	)
	await _settle()
	await _tap(_area_over(buttons[1]))
	assert_eq(picks, [1] as Array[int], "a tap on a segment selects it")


## The toggle row: toggle_mode, wired through `toggled`, and the row a finger aims
## at for the 12x12 check box inside it.
func test_a_toggle_row_answers_a_tap() -> void:
	var flips: Array[bool] = []
	var row := UiKit.toggle("Fog", true, "", "", func(on: bool) -> void: flips.append(on))
	_column(row)
	await _settle()
	await _tap(_area_over(row))
	assert_eq(flips, [false] as Array[bool], "a tap on the row flips it once")
	assert_false(row.button_pressed, "the control itself holds the new state")


## A plain Button, wired through `pressed` — the HUD chips and the action menu's
## rows. Counted rather than asserted true, because the defect on the other side of
## this seam is one finger making two receipts (mobile R1).
func test_a_plain_button_answers_exactly_once() -> void:
	var hits: Array[int] = []
	var button := Button.new()
	button.text = "T"
	button.custom_minimum_size = Vector2(8, 7)
	button.pressed.connect(func() -> void: hits.append(1))
	_column(UiKit.touchable(button))
	await _settle()
	await _tap(_area_over(button))
	assert_eq(hits.size(), 1, "one tap, one receipt")


func test_a_disabled_control_answers_nothing() -> void:
	var hits: Array[int] = []
	var button := Button.new()
	button.text = "SAVE"
	button.disabled = true
	button.custom_minimum_size = Vector2(8, 7)
	button.pressed.connect(func() -> void: hits.append(1))
	_column(UiKit.touchable(button))
	await _settle()
	await _tap(_area_over(button))
	assert_eq(hits.size(), 0, "a disabled control is disabled to a finger too")


## The area is the point of all this: the tap that proves it lands outside the drawn
## control and still arrives.
func test_the_area_reaches_past_the_drawn_control() -> void:
	var hits: Array[int] = []
	var button := Button.new()
	button.text = "T"
	button.custom_minimum_size = Vector2(8, 7)
	button.pressed.connect(func() -> void: hits.append(1))
	_column(UiKit.touchable(button))
	await _settle()
	var area := _area_over(button)
	assert_gt(area.get_global_rect().size.y, button.get_global_rect().size.y, "the area is taller")
	var below := Vector2(
		button.get_global_rect().get_center().x, button.get_global_rect().end.y + 4.0
	)
	assert_true(area.get_global_rect().has_point(below), "and it reaches under the control")
	for down in [true, false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = down
		click.position = below
		click.global_position = below
		get_tree().root.push_input(click, true)
	await get_tree().process_frame
	assert_eq(hits.size(), 1, "a tap beside the chrome is still the control's")
