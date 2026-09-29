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


func test_every_gesture_is_a_clip_the_actor_plays() -> void:
	var lines: Array[String] = [
		"Plain words.", "Loud words!", "A question?", "Trailing off...", "Haha, fine.",
		"Yes, sir.", "Never."
	]
	for line in lines:
		for beat in 2:
			var clip := DialogueStaging.gesture_for(line, beat)
			assert_true(ActorPose3D.CLIPS.has(clip), "'%s' plays %s" % [line, clip])
