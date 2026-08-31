extends GutTest
## A general commands one army: `CommanderPicks` is the whole of that rule, and
## these are the cases every surface asking it inherits — the picker greying a
## taken portrait, Random drawing without replacement, and `--co=` correcting a
## name written twice.
##
## The neutral cases matter as much as the refusals: "No Commander" is the
## absence of a general, so a table of seats all playing without one is not four
## seats fighting over the same pick.

const RED := 1
const BLUE := 2
const GREEN := 3

const ALINA := &"alina_ward"
const VIKTOR := &"viktor_draeg"
const NONE := CommanderType.NEUTRAL_ID


func test_no_commander_is_not_a_general_anybody_can_take() -> void:
	assert_true(CommanderPicks.is_general(ALINA), "a name on the roster")
	assert_false(CommanderPicks.is_general(NONE), "the absence of one")
	assert_false(CommanderPicks.is_general(&""), "nor is an unfilled seat")


func test_a_seat_is_never_in_its_own_way() -> void:
	var picks := {RED: ALINA}
	assert_true(CommanderPicks.available(picks, RED, ALINA), "red already has her")
	assert_false(CommanderPicks.available(picks, BLUE, ALINA), "blue may not take her too")


func test_every_seat_may_play_without_a_commander() -> void:
	var picks := {RED: NONE, BLUE: NONE}
	assert_true(CommanderPicks.available(picks, GREEN, NONE), "a third seat may too")


## The refusal names the army holding the general, which is what the picker's
## greyed portrait says out loud rather than merely being dead.
func test_the_holder_is_named_rather_than_only_counted() -> void:
	var picks := {RED: ALINA, BLUE: VIKTOR}
	assert_eq(CommanderPicks.holder(picks, VIKTOR), BLUE, "blue commands him")
	assert_eq(CommanderPicks.holder(picks, VIKTOR, BLUE), 0, "except to blue itself")
	assert_eq(CommanderPicks.holder(picks, &"nobody_at_all"), 0, "nobody holds a stranger")
	assert_eq(CommanderPicks.holder(picks, NONE), 0, "and No Commander is held by no one")


## The earlier seat keeps the general; the later one plays without one, which is
## already what a seat with no entry means. Dropped rather than seated neutral,
## so a corrected launch is the launch that never named a duplicate.
func test_a_repeat_is_dropped_in_seat_order() -> void:
	var settled := CommanderPicks.deduplicated({RED: ALINA, BLUE: ALINA}, [RED, BLUE])
	assert_push_error("can command only one army")
	assert_eq(settled, {RED: ALINA}, "red keeps her, blue plays without one")


func test_the_walk_order_decides_who_keeps_a_contested_general() -> void:
	var settled := CommanderPicks.deduplicated({RED: ALINA, BLUE: ALINA}, [BLUE, RED])
	assert_push_error("can command only one army")
	assert_eq(settled, {BLUE: ALINA}, "the seat walked first keeps her")


## `from_menu` takes `seats` empty to mean every seat plays, so the walk has to
## answer for an order that names nobody: the picks' own order is what is left,
## and a seat the order forgot is still walked rather than silently dropped.
func test_a_seat_the_order_does_not_name_is_still_walked() -> void:
	var settled := CommanderPicks.deduplicated({RED: ALINA, BLUE: ALINA}, [] as Array[int])
	assert_push_error("can command only one army")
	assert_eq(settled, {RED: ALINA}, "red was named first, so red keeps her")
	assert_eq(
		CommanderPicks.deduplicated({RED: ALINA, BLUE: VIKTOR}, [BLUE] as Array[int]),
		{BLUE: VIKTOR, RED: ALINA},
		"a half-named order keeps both, the named seat first"
	)


func test_distinct_picks_pass_through_untouched() -> void:
	var picks := {RED: ALINA, BLUE: VIKTOR, GREEN: NONE}
	assert_eq(CommanderPicks.deduplicated(picks, [RED, BLUE, GREEN]), picks, "nothing to correct")


# --- the launch paths ---------------------------------------------------------


## A duplicate on the command line is corrected out loud rather than played: a
## match with two of one general is a match nobody meant, and silently seating it
## would look exactly like the flag working.
func test_co_refuses_to_seat_one_general_twice() -> void:
	var request := MatchRequest.new()
	request.apply_cmdline(Fixture.args(["--co=alina_ward,alina_ward"]))
	assert_push_error("can command only one army")
	assert_eq(request.commanders[RED], ALINA, "the first seat named keeps her")
	assert_false(request.commanders.has(BLUE), "the second plays without a commander")


## The seating is read before the commander list, so the correction walks the
## seats that actually play rather than 1..n.
func test_co_corrects_over_the_seats_that_play() -> void:
	var request := MatchRequest.new()
	request.apply_cmdline(Fixture.args(["--seats=2,3", "--co=alina_ward,alina_ward"]))
	assert_push_error("can command only one army")
	assert_eq(request.commanders, {BLUE: ALINA}, "seat 2 keeps her; seat 3 goes without")


func test_the_menu_adapter_seats_each_general_once() -> void:
	var request := MatchRequest.from_menu(
		"res://maps/x.txt",
		[] as Array[int],
		false,
		&"normal",
		{RED: ALINA, BLUE: ALINA},
		false,
		{},
		[RED, BLUE] as Array[int]
	)
	assert_push_error("can command only one army")
	assert_eq(request.commanders, {RED: ALINA}, "one army each")
