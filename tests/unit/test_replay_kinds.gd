extends GutTest
## The analyser's finding kinds, and which fixture suite fires each one.
##
## `ReplayAnalysis.SEVERITY` is the ranking, so a kind missing from it used to
## score 1 and sink to the bottom of the report, where a typo and a detector that
## never fires read the same. `_add_at` refuses an unscored kind out loud now,
## and this suite is the other half: every kind the analyser can report is
## scored, and every scored kind names the suite that fires it — so a detector
## cannot arrive without a fixture, and one cannot be retired quietly. It is the
## replay side of `test_commander_ai_advice.gd`'s ADVICE_COVERAGE.

const ANALYSIS_PATH := "res://tools/replay/replay_analysis.gd"

## kind -> the suite whose fixture fires it, named as a path so the claim is
## checked rather than merely recorded.
const KIND_COVERAGE := {
	"undefended_hq": "res://tests/unit/test_replay_detectors.gd",
	"walk_into_fire": "res://tests/unit/test_replay_detectors.gd",
	"worse_shot": "res://tests/unit/test_replay_detectors.gd",
	"hoarding": "res://tests/unit/test_replay_analysis.gd",
	"missed_capture": "res://tests/unit/test_replay_capture_chance.gd",
	"idle_unit": "res://tests/unit/test_replay_analysis.gd",
	"abandoned_capture": "res://tests/unit/test_replay_abandoned_capture.gd",
	"banked_power": "res://tests/unit/test_replay_power_waste.gd",
	"spent_power": "res://tests/unit/test_replay_power_waste.gd",
	"stranded_transport": "res://tests/unit/test_replay_analysis.gd",
	"oscillation": "res://tests/unit/test_replay_detectors.gd",
}

## The four places a kind is named on its way to a finding: the two `_add`s and
## the two streak releases that pass one through.
const REPORTING_CALLS := "_(?:add|add_at|release|close_all)"


## Every kind the analyser names on a reporting call, read off its own source
## rather than kept as a second list here.
func _reported_kinds() -> Array[String]:
	var source := FileAccess.get_file_as_string(ANALYSIS_PATH)
	assert_ne(source, "", "could not read %s" % ANALYSIS_PATH)
	var pattern := RegEx.create_from_string('%s\\(\\s*walk[^)"]*"([a-z_]+)"' % REPORTING_CALLS)
	var found: Array[String] = []
	for hit in pattern.search_all(source):
		var kind := hit.get_string(1)
		if not found.has(kind):
			found.append(kind)
	return found


func test_every_reported_kind_is_scored() -> void:
	var kinds := _reported_kinds()
	assert_gt(kinds.size(), 0, "no kinds found in the analyser, so this would pass vacuously")
	for kind in kinds:
		assert_true(
			ReplayAnalysis.SEVERITY.has(kind),
			"%s is reported but SEVERITY does not score it" % kind
		)
	assert_eq(
		kinds.size(),
		ReplayAnalysis.SEVERITY.size(),
		"SEVERITY scores a kind the analyser never reports"
	)


func test_every_scored_kind_names_the_suite_that_fires_it() -> void:
	for kind: String in ReplayAnalysis.SEVERITY:
		assert_true(KIND_COVERAGE.has(kind), "%s is scored but not in KIND_COVERAGE" % kind)
	assert_eq(
		KIND_COVERAGE.size(),
		ReplayAnalysis.SEVERITY.size(),
		"KIND_COVERAGE names a kind SEVERITY does not score"
	)


func test_every_named_suite_exercises_its_kind() -> void:
	for kind: String in KIND_COVERAGE:
		var path: String = KIND_COVERAGE[kind]
		var source := FileAccess.get_file_as_string(path)
		assert_ne(source, "", "%s names a suite that does not exist: %s" % [kind, path])
		assert_true(source.contains('"%s"' % kind), "%s never names %s" % [path, kind])
