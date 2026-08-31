extends GutTest
## The nine per-line readings behind `make prose`. Every one is pure arithmetic
## over a string, so each is checked twice: once on a line crafted to carry the
## defect, and once on an honest line that must stay silent.
##
## The silent half is the half that matters. A reading that fires on ordinary
## dialogue sends an author rewriting lines that were fine, which costs more than
## a miss — the same rule the replay analyser's detectors are held to.
##
## Fixtures only, never shipped content: the shipped numbers move whenever
## somebody writes a mission, and a suite pinned to them would fail on a
## dialogue pass rather than on a bug.

## The corpus's own mean sentence length, so the cadence reading is exercised at
## the distance it will actually see.
const CORPUS_MEAN := 9.7

const APHORISM := "The column has walked since the thaw and it has not eaten. That ends today."
const HONEST := "Get them off the road."


func test_sentences_keeps_an_unterminated_tail() -> void:
	assert_eq(ProseMetrics.sentences("One thing. Then another").size(), 2)
	assert_eq(ProseMetrics.sentences("Hold the bridge!").size(), 1)
	assert_eq(ProseMetrics.sentences("").size(), 0)


func test_word_count_ignores_bare_punctuation() -> void:
	assert_eq(ProseMetrics.word_count("Hold the line — now"), 4)
	assert_eq(ProseMetrics.word_count(""), 0)


func test_mean_sentence_words_is_zero_on_nothing() -> void:
	assert_almost_eq(ProseMetrics.mean_sentence_words("Two words. Two words."), 2.0, 0.001)
	assert_eq(ProseMetrics.mean_sentence_words("   "), 0.0)


func test_lockstep_fires_on_exactly_two_sentences() -> void:
	assert_eq(ProseMetrics.lockstep("One thing. Then another."), 1.0)
	assert_eq(ProseMetrics.lockstep("One thing."), 0.0)
	assert_eq(ProseMetrics.lockstep("One. Two. Three."), 0.0)


func test_aphorism_fires_on_a_long_line_closed_by_a_short_one() -> void:
	assert_eq(ProseMetrics.aphorism(APHORISM), 1.0)
	assert_eq(ProseMetrics.aphorism(HONEST), 0.0)


func test_aphorism_grades_the_question_and_the_near_miss() -> void:
	var asked := "The column has walked since the thaw and it has not eaten. Can they hold?"
	assert_eq(ProseMetrics.aphorism(asked), 0.0, "a closer that asks is not a pronouncement")
	var near := "One two three four five six seven eight nine ten. Eleven twelve thirteen fourteen."
	assert_eq(ProseMetrics.aphorism(near), 0.5)


func test_negation_climbs_with_each_written_out_form() -> void:
	assert_eq(ProseMetrics.negation("We do not move."), 0.6)
	assert_eq(ProseMetrics.negation("We do not move and they will not either."), 1.0)
	assert_eq(ProseMetrics.negation("We don't move."), 0.0)


func test_em_dash_weighs_the_dash_against_the_line_length() -> void:
	var short_line := "The road is open — take it."
	var long_line := "The road is open — take it. Then hold. Then wait for me."
	assert_eq(ProseMetrics.em_dash(short_line), 0.6)
	assert_lt(ProseMetrics.em_dash(long_line), ProseMetrics.em_dash(short_line))
	assert_eq(ProseMetrics.em_dash("The road is open. Take it."), 0.0)


func test_cadence_peaks_when_the_line_sits_on_both_means() -> void:
	var on_mean := "One two three four five six seven eight nine ten."
	assert_almost_eq(ProseMetrics.cadence(on_mean, 10.0, 10.0), 1.0, 0.01)
	assert_lt(ProseMetrics.cadence(on_mean, 3.0, 3.0), 0.2)


## A shout has no rhythm and no register, so both readings withhold rather than
## score it well — the difference matters, since a corpus of shouts would
## otherwise read as the least machine-written writing there is.
func test_a_short_line_is_scored_for_neither_rhythm_nor_register() -> void:
	assert_eq(ProseMetrics.cadence("Move.", CORPUS_MEAN, CORPUS_MEAN), 0.0)
	assert_eq(ProseMetrics.register("Move now."), 0.0)


func test_triad_fires_on_three_matched_clauses() -> void:
	assert_eq(ProseMetrics.triad("Three cities, four columns, one road."), 1.0)
	assert_eq(ProseMetrics.triad("We hold the bridge, and then we wait."), 0.0)


func test_stock_fires_on_each_blacklisted_construction() -> void:
	assert_eq(ProseMetrics.stock("It is not a retreat, but a redeployment."), 1.0)
	assert_eq(ProseMetrics.stock("A testament to what discipline buys."), 1.0)
	assert_eq(ProseMetrics.stock("In the end the ledger balances."), 1.0)
	assert_eq(ProseMetrics.stock("That is the price."), 1.0)
	assert_eq(ProseMetrics.stock("They took the depot at first light."), 0.0)


func test_vocative_fires_on_the_filler_address() -> void:
	assert_eq(ProseMetrics.vocative("Hold the bridge, Commander."), 1.0)
	assert_eq(ProseMetrics.vocative("Hold the bridge, Warden."), 1.0)
	assert_eq(ProseMetrics.vocative("Commander Holt is on the ridge."), 0.0)


func test_register_reads_contractions_and_latinate_density() -> void:
	var formal := "The disposition of the formation requires immediate consolidation."
	var spoken := "We don't have the men and I'm not waiting for them."
	assert_gt(ProseMetrics.register(formal), 0.7)
	assert_eq(ProseMetrics.register(spoken), 0.0)


func test_measure_answers_for_every_heuristic() -> void:
	var measures := ProseMetrics.measure(APHORISM, CORPUS_MEAN, CORPUS_MEAN)
	for key: String in ProseMetrics.HEURISTICS:
		assert_true(measures.has(key), "no reading for '%s'" % key)
		assert_between(float(measures[key]), 0.0, 1.0, key)


func test_every_heuristic_carries_a_weight() -> void:
	var total := 0.0
	for key: String in ProseMetrics.HEURISTICS:
		assert_true(ProseMetrics.WEIGHTS.has(key), "no weight for '%s'" % key)
		total += float(ProseMetrics.WEIGHTS[key])
	assert_eq(ProseMetrics.WEIGHTS.size(), ProseMetrics.HEURISTICS.size())
	assert_almost_eq(total, 1.0, 0.001)


func test_the_aphorism_is_the_heaviest_reading() -> void:
	for key: String in ProseMetrics.HEURISTICS:
		if key != "aphorism":
			assert_lt(
				float(ProseMetrics.WEIGHTS[key]), float(ProseMetrics.WEIGHTS["aphorism"]), key
			)


func test_score_ranks_the_crafted_line_over_the_honest_one() -> void:
	var slop := ProseMetrics.score(ProseMetrics.measure(APHORISM, CORPUS_MEAN, CORPUS_MEAN))
	var plain := ProseMetrics.score(ProseMetrics.measure(HONEST, CORPUS_MEAN, CORPUS_MEAN))
	assert_gt(slop, plain)
	assert_between(slop, 0.0, 1.0, "the composite stays a fraction")
	assert_eq(ProseMetrics.score({}), 0.0, "nothing measured is nothing scored")


## Dropping a reading has to change the composite, which is what stops a
## heuristic being retired by deleting its key and nothing failing.
func test_score_moves_when_a_reading_is_withheld() -> void:
	var full := ProseMetrics.measure(APHORISM, CORPUS_MEAN, CORPUS_MEAN)
	for key: String in ProseMetrics.HEURISTICS:
		if float(full[key]) == 0.0:
			continue
		var without := full.duplicate()
		without.erase(key)
		assert_ne(ProseMetrics.score(without), ProseMetrics.score(full), key)


func test_fired_names_the_readings_strongest_first() -> void:
	var measures := ProseMetrics.measure(APHORISM, CORPUS_MEAN, CORPUS_MEAN)
	var fired := ProseMetrics.fired(measures)
	assert_eq(fired[0], "aphorism")
	assert_does_not_have(fired, "stock")
	assert_eq(ProseMetrics.fired(ProseMetrics.measure(HONEST, 3.0, 3.0)).size(), 0)
