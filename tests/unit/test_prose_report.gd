extends GutTest
## The corpus-wide half of `make prose`: the means the per-line cadence reading
## rests on, the spread and overlap tables, the worst-N ordering, and the empty
## corpus that must not divide by zero.
##
## Built from `ProseLine`s spelled here rather than from the shipped campaigns,
## for `test_prose_metrics.gd`'s reason: a suite pinned to authored dialogue
## fails when somebody writes a mission.

const CAMPAIGN := &"fixture_war"


func _line(mission: String, slot: String, index: int, speaker: String, text: String) -> ProseLine:
	var source := MissionLine.of(StringName(speaker), text)
	return ProseLine.of(CAMPAIGN, StringName(mission), slot, index, source)


## Two voices, one of them written in a single flat cadence and the other varied
## — the shape every table below is read against.
func _corpus() -> Array[ProseLine]:
	return [
		_line("m01", "briefing", 0, "flat", "One two three four. Five six seven eight."),
		_line("m01", "briefing", 1, "flat", "One two three four. Five six seven eight."),
		_line("m01", "briefing", 2, "varied", "Go."),
		_line("m01", "victory", 0, "varied", "One two three four five six seven eight nine ten."),
		_line("m02", "briefing", 0, "flat", "One two three four. Five six seven eight."),
	]


func test_gathering_a_line_keeps_its_provenance() -> void:
	var line := _line("m01", "briefing", 2, "vale", "Hold the bridge.")
	assert_eq(line.source(), "fixture_war/m01")
	assert_eq(line.where(), "fixture_war/m01 briefing#2")
	assert_eq(line.voice(), &"vale")


func test_narration_is_a_voice_rather_than_a_gap() -> void:
	var narrated := _line("m01", "briefing", 0, "", "The line goes dark.")
	assert_eq(narrated.voice(), &"(narration)")
	assert_false(narrated.is_spoken())
	assert_true(_line("m01", "briefing", 0, "vale", "Dark.").is_spoken())


func test_slot_kind_folds_every_event_into_one() -> void:
	assert_eq(_line("m01", "event:relief", 0, "vale", "Relief.").slot_kind(), "event")
	assert_eq(_line("m01", "defeat", 0, "vale", "Lost.").slot_kind(), "defeat")


func test_excerpt_flattens_and_elides() -> void:
	var line := _line(
		"m01", "briefing", 0, "vale", "Hold\nthe   bridge until the relief column arrives"
	)
	assert_eq(line.excerpt(12), "Hold the br…")
	assert_eq(line.excerpt(80), "Hold the bridge until the relief column arrives")


func test_corpus_mean_is_the_mean_of_the_line_means() -> void:
	assert_almost_eq(ProseReport.corpus_mean(_corpus()), 4.6, 0.05)
	assert_eq(ProseReport.corpus_mean([] as Array[ProseLine]), 0.0)


func test_speaker_means_split_by_voice() -> void:
	var means := ProseReport.speaker_means(_corpus())
	assert_almost_eq(float(means[&"flat"]), 4.0, 0.01)
	assert_almost_eq(float(means[&"varied"]), 5.5, 0.01)


func test_speaker_spread_orders_the_narrowest_cadence_first() -> void:
	var spread := ProseReport.speaker_spread(_corpus())
	assert_eq(spread[0]["speaker"], "flat")
	assert_eq(spread[0]["sigma"], 0.0)
	assert_gt(float(spread[1]["sigma"]), 0.0)


func test_sentence_count_entropy_is_zero_when_every_line_is_one_shape() -> void:
	var lockstep: Array[ProseLine] = [
		_line("m01", "briefing", 0, "a", "One two. Three four."),
		_line("m01", "briefing", 1, "b", "Five six. Seven eight."),
	]
	assert_eq(ProseReport.sentence_count_entropy(lockstep), 0.0)
	assert_gt(ProseReport.sentence_count_entropy(_corpus()), 0.5)
	assert_eq(ProseReport.sentence_count_entropy([] as Array[ProseLine]), 0.0)


func test_shared_openings_only_count_pairs_more_than_one_voice_uses() -> void:
	var lines: Array[ProseLine] = [
		_line("m01", "briefing", 0, "a", "Then we take the depot."),
		_line("m01", "briefing", 1, "b", "Then we hold it."),
		_line("m01", "briefing", 2, "a", "Then we go home."),
		_line("m01", "briefing", 3, "a", "Cold morning on the ridge."),
	]
	var openings := ProseReport.shared_openings(lines)
	assert_eq(openings.size(), 1)
	assert_eq(openings[0]["opening"], "then we")
	assert_eq(openings[0]["uses"], 3)
	assert_eq(openings[0]["speakers"], 2)


func test_voice_overlap_finds_the_interchangeable_pair() -> void:
	var shared := "the relief column will cross the river before the thaw takes the ford out"
	var apart := "coins buy columns and columns buy ground so nothing here is ever free"
	var lines: Array[ProseLine] = [
		_line("m01", "briefing", 0, "twin_a", shared),
		_line("m01", "briefing", 1, "twin_b", shared),
		_line("m01", "briefing", 2, "own_voice", apart),
	]
	var overlap := ProseReport.voice_overlap(lines)
	assert_eq(overlap[0]["a"], "twin_a")
	assert_eq(overlap[0]["b"], "twin_b")
	assert_almost_eq(float(overlap[0]["jaccard"]), 1.0, 0.01)


## The short voice's three trigrams are all shared with the long one, so the pair
## would top the table on five words if `MIN_TRIGRAMS` did not drop it first.
func test_voice_overlap_ignores_a_voice_too_small_to_judge() -> void:
	var lines: Array[ProseLine] = [
		_line(
			"m01",
			"briefing",
			0,
			"wordy",
			"the relief column will cross the river before the thaw takes the ford out"
		),
		_line("m01", "briefing", 1, "brief", "the relief column will cross"),
	]
	assert_eq(ProseReport.voice_overlap(lines).size(), 0)


func test_worst_orders_by_score_and_breaks_ties_by_place() -> void:
	var lines: Array[ProseLine] = [
		_line("m01", "briefing", 1, "a", "Get them off the road."),
		_line("m01", "briefing", 0, "a", "Get them off the road."),
		_line(
			"m01",
			"briefing",
			2,
			"a",
			"The column has been walking since the thaw and it has not eaten. That ends today."
		),
	]
	var worst := ProseReport.worst(ProseReport.rows(lines), 3)
	assert_eq(worst[0]["line"].index, 2)
	assert_eq(worst[1]["line"].index, 0, "a tie falls back to provenance")
	assert_eq(worst[2]["line"].index, 1)


func test_worst_takes_at_most_what_was_asked_for() -> void:
	var scored := ProseReport.rows(_corpus())
	assert_eq(ProseReport.worst(scored, 2).size(), 2)
	assert_eq(ProseReport.worst(scored, 0).size(), 0)


func test_worst_sources_skips_a_page_too_short_to_rank() -> void:
	var scored := ProseReport.rows(_corpus())
	var sources := ProseReport.worst_sources(scored, 10, 4)
	assert_eq(sources.size(), 1, "m02's single line is not a mission's worth of dialogue")
	assert_eq(sources[0]["source"], "fixture_war/m01")
	assert_eq(sources[0]["lines"], 4)


func test_vocative_sources_flag_only_the_missions_over_the_rate() -> void:
	var lines: Array[ProseLine] = [
		_line("m01", "briefing", 0, "a", "Hold the bridge, Commander."),
		_line("m01", "briefing", 1, "a", "Hold the bridge, Commander."),
		_line("m02", "briefing", 0, "a", "Hold the bridge, Commander."),
		_line("m02", "briefing", 1, "a", "Hold the bridge."),
		_line("m02", "briefing", 2, "a", "Hold the bridge."),
		_line("m02", "briefing", 3, "a", "Hold the bridge."),
		_line("m02", "briefing", 4, "a", "Hold the bridge."),
	]
	var flagged := ProseReport.vocative_sources(ProseReport.rows(lines))
	assert_eq(flagged.size(), 1)
	assert_eq(flagged[0]["source"], "fixture_war/m01")


## Two defeat lines, one of them the narrator's, beside one briefing and two
## events with different ids: the defeat row counts both and halves its spoken
## share, the events fold into one row, and the rows come in a mission's order.
func test_slot_table_counts_each_slot_and_its_spoken_share() -> void:
	var lines: Array[ProseLine] = [
		_line("m01", "defeat", 0, "vale", "The road held. We did not."),
		_line("m01", "defeat", 1, "", "The road stayed shut, and the toll went on."),
		_line("m01", "briefing", 0, "vale", "Hold the bridge."),
		_line("m01", "event:relief", 0, "vale", "Relief is on the road."),
		_line("m01", "event:fall", 0, "quill", "The ridge is gone."),
	]
	var table := ProseReport.slot_table(ProseReport.rows(lines))
	assert_eq(table.size(), 3)
	assert_eq(table[0]["slot"], "briefing")
	assert_eq(table[1]["slot"], "event")
	assert_eq(table[1]["lines"], 2)
	assert_eq(table[2]["slot"], "defeat")
	assert_eq(table[2]["lines"], 2)
	assert_almost_eq(float(table[2]["spoken_share"]), 0.5, 0.001)
	assert_almost_eq(float(table[2]["two_sentence_share"]), 0.5, 0.001)
	assert_almost_eq(float(table[0]["spoken_share"]), 1.0, 0.001)
	assert_almost_eq(float(table[0]["two_sentence_share"]), 0.0, 0.001)


func test_aggregate_answers_for_every_heuristic() -> void:
	var lines := _corpus()
	var totals := ProseReport.aggregate(lines, ProseReport.rows(lines))
	assert_eq(totals["lines"], lines.size())
	assert_eq(totals["speakers"], 2)
	for key: String in ProseMetrics.HEURISTICS:
		assert_true(totals["rates"].has(key), "no rate for '%s'" % key)


func test_an_empty_corpus_answers_without_dividing_by_zero() -> void:
	var empty: Array[ProseLine] = []
	var scored := ProseReport.rows(empty)
	assert_eq(scored.size(), 0)
	assert_eq(ProseReport.worst(scored, 25).size(), 0)
	assert_eq(ProseReport.worst_sources(scored, 10).size(), 0)
	assert_eq(ProseReport.speaker_spread(empty).size(), 0)
	assert_eq(ProseReport.shared_openings(empty).size(), 0)
	assert_eq(ProseReport.voice_overlap(empty).size(), 0)
	assert_eq(ProseReport.vocative_sources(scored).size(), 0)
	assert_eq(ProseReport.slot_table(scored).size(), 0)
	var totals := ProseReport.aggregate(empty, scored)
	assert_eq(totals["lines"], 0)
	assert_eq(totals["mean_score"], 0.0)
	assert_eq(totals["narrowest_speaker_sigma"], 0.0)


## The one reading of shipped content, and deliberately not of a number: which
## slots the corpus admits. An objective's wording is a convention
## `docs/campaign_authoring.md` owns rather than a line anybody says, so a gather
## that started scoring it would report that convention as slop.
func test_gather_admits_only_spoken_slots() -> void:
	var allowed := ["briefing", "victory", "defeat", "interlude"]
	for line: ProseLine in ProseCorpus.gather(CampaignDB.load_default()):
		assert_ne(line.text.strip_edges(), "", line.where())
		if line.slot.begins_with("event:"):
			continue
		assert_has(allowed, line.slot, line.where())


func test_narrow_filters_by_campaign_and_by_voice() -> void:
	var lines := _corpus()
	assert_eq(ProseCorpus.narrow(lines, "fixture_war", "").size(), lines.size())
	assert_eq(ProseCorpus.narrow(lines, "another_war", "").size(), 0)
	assert_eq(ProseCorpus.narrow(lines, "", "flat").size(), 3)
	assert_eq(ProseCorpus.narrow(lines, "fixture_war", "varied").size(), 2)
