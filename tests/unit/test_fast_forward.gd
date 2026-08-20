extends GutTest
## The held key that hurries the theatre along.
##
## FastForward is a Node-free static read and CutscenePlayback's clock is a
## RefCounted whose `advance` is plain arithmetic over its own fields — the same
## terms GameSpeed and BattleZoom.floor_for are checked on — so the whole rate
## path is checked here without a board, a camera or a cut-in.
##
## The key itself is pinned because nothing else fails loudly if it goes: an
## action the InputMap does not hold makes `Input.is_action_pressed` push an
## error on every frame of every cut-in.


func after_each() -> void:
	Input.action_release(&"fast_forward")


func test_the_input_map_holds_the_action_on_shift_and_the_right_trigger() -> void:
	assert_true(InputMap.has_action(&"fast_forward"), "the action ships in project.godot")
	var keys: Array[int] = []
	var axes: Array[int] = []
	for event in InputMap.action_get_events(&"fast_forward"):
		if event is InputEventKey:
			keys.append((event as InputEventKey).keycode)
		elif event is InputEventJoypadMotion:
			axes.append((event as InputEventJoypadMotion).axis)
	assert_eq(keys, [KEY_SHIFT] as Array[int], "held on Shift")
	assert_eq(axes, [JOY_AXIS_TRIGGER_RIGHT] as Array[int], "and on the pad's right trigger")


func test_the_rate_is_one_until_the_key_is_held() -> void:
	assert_false(FastForward.held(), "nothing is held to begin with")
	assert_eq(FastForward.rate(), 1.0, "so every headless capture and smoke frame is inert")
	Input.action_press(&"fast_forward")
	assert_true(FastForward.held(), "the action reads as held")
	assert_eq(FastForward.rate(), FastForward.SCALE, "and the rate is the held one")
	assert_gt(FastForward.SCALE, 1.0, "which is faster than normal, never slower")


func test_the_cutscene_clock_spends_more_of_itself_while_the_key_is_held() -> void:
	var play := CutscenePlayback.new()
	play.total = 100.0
	play.rate = 2.0
	play.advance(1.0)
	assert_eq(play.t, 2.0, "unheld, the clock runs at the tier's rate alone")
	Input.action_press(&"fast_forward")
	play.advance(1.0)
	assert_eq(play.t, 2.0 + 2.0 * FastForward.SCALE, "held, it spends the scaled second")


func test_releasing_the_key_resumes_from_where_the_clock_now_reads() -> void:
	var play := CutscenePlayback.new()
	play.total = 100.0
	play.rate = 1.0
	Input.action_press(&"fast_forward")
	play.advance(1.0)
	var hurried := play.t
	Input.action_release(&"fast_forward")
	play.advance(1.0)
	assert_eq(play.t, hurried + 1.0, "the next second is an ordinary one — no jump, no rewind")


func test_the_clock_still_stops_at_the_end_however_hard_the_key_is_held() -> void:
	var play := CutscenePlayback.new()
	play.total = 2.0
	play.rate = 1.0
	Input.action_press(&"fast_forward")
	assert_true(play.advance(1.0), "a hurried frame reaches the end")
	assert_eq(play.t, 2.0, "and the clock is clamped there rather than run past it")


func test_instant_is_a_no_op_because_it_prices_every_beat_at_zero() -> void:
	var instant := GameSpeed.by_id(&"instant")
	Input.action_press(&"fast_forward")
	assert_eq(
		instant.command_delay_seconds() / FastForward.rate(),
		0.0,
		"the runners' delay stays zero, so the held key never divides its way into a wait"
	)
