extends GutTest
## DialogueStaging: how a general acts out a line in a 3D story scene, read off
## the words alone. Pure, so the same line is always acted the same way — which
## is what lets a replay gesture exactly as the match did.


func test_plain_talk_is_talk_with_no_emote() -> void:
	var line := "They're in the square and the mill. Guns on the road first."
	assert_eq(DialogueStaging.gesture_for(line), &"talk")
	assert_eq(DialogueStaging.emote_for(line), DialogueStaging.NO_EMOTE)


## Two exclamations in a row alternate the raised fist and the pointed finger,
## so a general shouting twice does not do the same thing twice.
func test_an_exclamation_raises_a_fist_then_points() -> void:
	var line := "Riders, down the mill road, and bring it back!"
	assert_eq(DialogueStaging.gesture_for(line, 0), &"fist")
	assert_eq(DialogueStaging.gesture_for(line, 1), &"point")
	assert_eq(DialogueStaging.emote_for(line), DialogueStaging.EXCLAIM)


func test_a_question_is_a_shrug() -> void:
	var line := "The mill too, if anyone's asking?"
	assert_eq(DialogueStaging.gesture_for(line), &"shrug")
	assert_eq(DialogueStaging.emote_for(line), DialogueStaging.ASK)


func test_a_line_that_trails_off_is_a_sigh() -> void:
	for line: String in ["We lost the drill company...", "Four days before the parade…"]:
		assert_eq(DialogueStaging.gesture_for(line), &"sigh", line)
		assert_eq(DialogueStaging.emote_for(line), DialogueStaging.TRAIL, line)


## The words outrank the punctuation: a laugh is a laugh even shouted, an order
## acknowledged is a salute, and a refusal shakes its head.
func test_the_words_outrank_the_punctuation() -> void:
	assert_eq(DialogueStaging.gesture_for("Ha! He's charged us for the nails!"), &"laugh")
	assert_eq(DialogueStaging.gesture_for("Understood. Moving out."), &"salute")
	assert_eq(DialogueStaging.gesture_for("No. Nobody walks into that square yet."), &"shake")


## A cue is a whole word, and an acknowledgement opens the line: the campaign's
## "I stayed" and "hold 10 cities at once" are plain talk, not salutes.
func test_a_cue_is_a_whole_word_and_an_acknowledgement_opens_the_line() -> void:
	assert_eq(DialogueStaging.gesture_for("My rangers went home. I stayed."), &"talk")
	assert_eq(DialogueStaging.gesture_for("Hold 10 cities at once."), &"talk")
	assert_eq(DialogueStaging.gesture_for("The players are set."), &"talk")
	assert_eq(DialogueStaging.gesture_for("Aha! The mill."), &"fist")
	assert_eq(DialogueStaging.gesture_for("At once, General."), &"salute")
	assert_eq(DialogueStaging.gesture_for("Aye, the guns are ours."), &"salute")
	assert_eq(DialogueStaging.gesture_for("Heh. Fine."), &"laugh")


func test_every_gesture_is_a_clip_the_actor_plays() -> void:
	var lines: Array[String] = [
		"Plain words.",
		"Loud words!",
		"A question?",
		"Trailing off...",
		"Haha, fine.",
		"Yes, sir.",
		"Never."
	]
	for line in lines:
		for beat in 2:
			var clip := DialogueStaging.gesture_for(line, beat)
			assert_true(ActorPose3D.CLIPS.has(clip), "'%s' plays %s" % [line, clip])


# --- where a general stands ---------------------------------------------------

const LENS_SOUTH := Vector2i(0, 1)
const CENTRE := Vector2i(1, 1)


func _stand(rows: String, toward: Vector2i = LENS_SOUTH, taken: Array[Vector2i] = []) -> Vector2i:
	var map := MapData.parse("[terrain]\n" + rows, Fixture.terrain_db())
	var cells: Dictionary[Vector2i, bool] = {}
	for cell in taken:
		cells[cell] = true
	return DialogueStaging.stand_cell(map, CENTRE, toward, cells)


func test_a_general_steps_off_their_building_toward_the_lens() -> void:
	assert_eq(_stand("...\n.C.\n..."), Vector2i(1, 2))
	assert_eq(_stand("...\n.C.\n...", Vector2i(1, 0)), Vector2i(2, 1), "the lens turned east")


## Ff01's hologram stood inside the headquarters: every cell that has something
## standing on it, and water, is refused, however far from the lens the one
## open cell is.
func test_buildings_peaks_woods_and_water_are_never_stood_on() -> void:
	assert_eq(_stand("MF.\n~C_\nCSM"), Vector2i(2, 0))


## Ff39's hologram stood through Iris Colt and an artillery barrel.
func test_a_unit_or_another_general_keeps_their_cell() -> void:
	assert_eq(_stand("...\n.C.\n...", LENS_SOUTH, [Vector2i(1, 2)]), Vector2i(0, 2))


## Ff39's mountain stood in front of Alina Ward in her close-up.
func test_a_cell_with_a_peak_in_front_of_it_gives_way_to_a_clear_one() -> void:
	assert_eq(_stand("...\n.C.\n...\n.M."), Vector2i(0, 2))


func test_a_crowded_post_looks_one_ring_further_out() -> void:
	var map := MapData.parse("[terrain]\n.....\n.MMM.\n.MCM.\n.MMM.\n.....", Fixture.terrain_db())
	var post := Vector2i(2, 2)
	var stand := DialogueStaging.stand_cell(map, post, LENS_SOUTH, {})
	assert_eq(stand, Vector2i(2, 4))


func test_with_nowhere_open_a_general_keeps_their_post() -> void:
	assert_eq(_stand("MMM\nMCM\nMMM"), CENTRE)
