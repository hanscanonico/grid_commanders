extends GutTest
## A recording's envelope rather than its lines: the header ReplayCodec writes
## and refuses, and the per-command digest that catches a board drifting under a
## replay.
##
## Split from test_replay_codec.gd, which stays the command classes' own suite.
## The two halves share a file no longer than the ruler allows, and they answer
## different questions: what a line rebuilds into, and whether this build may
## read the recording at all.


func test_a_header_states_the_format_and_the_opening() -> void:
	var state := Fixture.state(Fixture.LONE_INFANTRY)
	var head := ReplayCodec.header(SaveCodec.encode(state, [2] as Array[int]), "a label", "now")
	assert_eq(ReplayCodec.header_error(head), "")
	assert_eq(head["label"], "a label")
	assert_eq(int(head["replay"]), ReplayCodec.FORMAT)


func test_a_header_that_is_not_one_says_which_part_is_missing() -> void:
	assert_string_contains(ReplayCodec.header_error({}), "replay")
	assert_string_contains(ReplayCodec.header_error({"replay": 1}), "opening")
	assert_string_contains(
		ReplayCodec.header_error({"replay": "one", "opening": {}}), "not a number"
	)


## The tripwire on the format number, in the tradition of the save version's:
## bumping it is a decision, and this is where it gets noticed. A replay is
## disposable, so the line under it is the whole migration policy — an older
## format is refused, out loud, rather than read.
func test_an_older_format_is_refused_rather_than_read() -> void:
	assert_eq(ReplayCodec.FORMAT, 4)
	assert_string_contains(ReplayCodec.header_error({"replay": 1, "opening": {}}), "format 1")


## The mission pair, and the half of it that matters most: a skirmish header is
## the line it has always been, so nothing about a match outside a campaign
## changed shape when the ids arrived.
func test_a_header_names_a_mission_only_when_there_is_one() -> void:
	var state := Fixture.state(Fixture.LONE_INFANTRY)
	var opening := SaveCodec.encode(state, [2] as Array[int])
	var skirmish := ReplayCodec.header(opening, "a label", "now")
	assert_false(skirmish.has("campaign"), "a skirmish is a recording of no mission")
	assert_false(skirmish.has("mission"))

	var mission := ReplayCodec.header(opening, "a label", "now", &"six_marshals", &"sm02")
	assert_eq(mission["campaign"], "six_marshals")
	assert_eq(mission["mission"], "sm02")
	assert_eq(ReplayCodec.header_error(mission), "")


## `header_error` reads every field's shape through `SaveSchema.is_shape` now
## (COM-175, moved off `SaveCodec` to `SaveSchema` by COM-184), rather than the
## hand-forked reader ReplayCodec used to keep beside it — so a StringName, which a
## save's own commander and difficulty ids decode as, validates against
## `Shape.STRING` exactly the way a save's would rather than failing the narrower
## `value is String` the fork checked instead.
func test_a_header_value_reads_a_string_name_the_way_a_save_would() -> void:
	assert_true(SaveSchema.is_shape(&"alina_ward", SaveSchema.Shape.STRING))


# --- the self-check (plan D3) ---------------------------------------------------


## Second Wind reads `refreshable`, so a rule change to which actions leave it
## set has to be able to move the checkpoint — otherwise a replay recorded under
## the old rule plays clean and only diverges at the next Second Wind (COM-173).
func test_the_digest_notices_refreshable() -> void:
	var state := Fixture.state("[terrain]\n....\n....\n[units]\n1 i 0 0")
	state.rng.seed = 1
	var before := ReplayCodec.checkpoint(state)
	state.units[0].refreshable = true
	assert_ne(ReplayCodec.checkpoint(state), before)
