extends GutTest
## The page half of TransitionInput: the visible guard, the press test and the
## receipt, folded into one answer the five full-screen panels each used to
## restate. Its own suite because test_transition_input.gd is at the public
## method ceiling, and because these are the branches that need a real Control in
## a real viewport — the receipt a touch build double-fires without is a viewport
## call.


## Each page gets a viewport of its own, because the receipt is a flag on the
## viewport and nothing outside an input frame clears it — pages sharing one
## would inherit the receipt of whichever test ran first.
func _page() -> Control:
	var frame := SubViewport.new()
	add_child_autofree(frame)
	var page := Control.new()
	frame.add_child(page)
	return page


func _cancel_event() -> InputEventAction:
	var event := InputEventAction.new()
	event.action = &"cancel"
	event.pressed = true
	return event


func test_a_cancel_press_dismisses_a_visible_page() -> void:
	var page := _page()
	assert_true(TransitionInput.dismissed_by_cancel(page, _cancel_event()))
	assert_true(page.get_viewport().is_input_handled(), "and the press is receipted")


func test_a_hidden_page_is_dismissed_by_nothing() -> void:
	var page := _page()
	page.hide()
	assert_false(TransitionInput.dismissed_by_cancel(page, _cancel_event()))
	assert_false(page.get_viewport().is_input_handled(), "so the press stays available")


func test_another_action_leaves_a_page_up() -> void:
	var event := InputEventAction.new()
	event.action = &"confirm"
	event.pressed = true
	var page := _page()
	assert_false(TransitionInput.dismissed_by_cancel(page, event))
	assert_false(page.get_viewport().is_input_handled())


func test_a_cancel_release_leaves_a_page_up() -> void:
	var event := _cancel_event()
	event.pressed = false
	assert_false(TransitionInput.dismissed_by_cancel(_page(), event))


func test_any_press_dismisses_a_press_page() -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_ENTER
	event.pressed = true
	var page := _page()
	assert_true(TransitionInput.dismissed_by_press(page, event))
	assert_true(page.get_viewport().is_input_handled())


func test_a_press_page_ignores_motion_and_stays_up_while_hidden() -> void:
	var page := _page()
	assert_false(TransitionInput.dismissed_by_press(page, InputEventMouseMotion.new()))
	page.hide()
	var event := InputEventKey.new()
	event.keycode = KEY_ENTER
	event.pressed = true
	assert_false(TransitionInput.dismissed_by_press(page, event))
	assert_false(page.get_viewport().is_input_handled())
