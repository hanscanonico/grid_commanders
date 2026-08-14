extends GutTest
## The Music autoload's contract: one looping track at a time, a track already
## playing is left alone, and anything it cannot load is silently skipped.
##
## Music is an autoload rather than a Node-free class, which is normally outside
## what tests/ targets. It earns MatchConfig's exception the same way as
## CampaignSession: the singleton is up for the whole run and reachable without
## a scene, and what a scene asks of it — `play` in `_ready`, `stop` at victory —
## is exactly what these tests are about.
##
## The bars and the tempo each track was composed at, in the sibling
## audio_generator repo (`make audio` installs its renders).
## A loop is seamless only if the file is a whole number of beats long, so the
## length is pinned here rather than eyeballed.
const TEMPOS := {&"parade": 104.0, &"advance": 132.0}
const BARS := 32


func after_each() -> void:
	Music.stop()


func _player() -> AudioStreamPlayer:
	return Music.find_children("", "AudioStreamPlayer", false, false)[0] as AudioStreamPlayer


func test_each_shipped_track_plays_and_loops_its_whole_length() -> void:
	for track: StringName in Music.NAMES:
		Music.play(track)
		var stream := _player().stream as AudioStreamWAV
		assert_not_null(stream, "%s should be loaded" % track)
		assert_eq(stream.resource_path, "res://assets/music/%s.wav" % track)
		assert_true(_player().playing, "%s should be playing" % track)
		assert_eq(stream.loop_mode, AudioStreamWAV.LOOP_FORWARD, "%s should loop" % track)
		var bar_frames: float = BARS * 4 * 60.0 / TEMPOS[track] * stream.mix_rate
		assert_eq(stream.loop_begin, 0, "%s should loop from the top" % track)
		assert_almost_eq(
			float(stream.loop_end),
			bar_frames,
			1.0,
			"%s should loop over all %d bars" % [track, BARS]
		)


func test_each_track_is_a_whole_number_of_bars() -> void:
	for track: StringName in Music.NAMES:
		Music.play(track)
		var beats: float = (_player().stream as AudioStreamWAV).get_length() * TEMPOS[track] / 60.0
		assert_almost_eq(beats, float(BARS * 4), 0.001, "%s should be %d bars" % [track, BARS])


func test_restating_the_playing_track_is_a_no_op() -> void:
	Music.play(&"parade", -10.0)
	Music.play(&"parade", -30.0)  # a rematch stating its theme must not restart it
	assert_eq(_player().volume_db, -10.0, "the second call should have returned early")
	assert_true(_player().playing)


func test_the_battle_theme_replaces_the_menu_theme() -> void:
	Music.play(&"parade")
	Music.play(&"advance")
	assert_eq(_player().stream.resource_path, "res://assets/music/advance.wav")
	assert_true(_player().playing)


func test_stop_silences_the_track_and_lets_it_start_again() -> void:
	Music.play(&"advance")
	Music.stop()  # the victory fanfare stands alone
	assert_false(_player().playing)
	Music.play(&"advance")
	assert_true(_player().playing, "a fresh match should start the theme again")


func test_a_missing_track_is_silently_skipped() -> void:
	Music.play(&"parade")
	Music.play(&"nothing_was_generated")  # a track no release ever shipped
	assert_false(_player().playing, "an absent stream should leave the player silent")
