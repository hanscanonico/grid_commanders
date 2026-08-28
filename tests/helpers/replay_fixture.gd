class_name ReplayFixture
extends RefCounted
## The recording an analyser test reads, in one call: `ReplayFixture.run(state, entries)`.
##
## `Fixture` retired the same duplication for boards and `CampaignFixture` for
## wars. The analyser half never got it: six suites carried private copies of the
## same five helpers over `res://maps/fixtures/analysis.txt`, and the detectors
## are the one place a drifting helper does the most damage — they are the plan's
## guard against false positives.
##
## Node-free like `Fixture`, so it is a `RefCounted` with statics and no scene.
##
## The board is a file rather than an inline one because a replay stores its
## opening as a save envelope, which names its map by path.

## The board every analyser case but the vision suite's is played on.
const BOARD := "res://maps/fixtures/analysis.txt"


## The board with no units on it, ready for a test to stand its own.
static func board(path: String = BOARD) -> GameState:
	var state := Fixture.state_from_file(path)
	state.units.clear()
	return state


static func stand(state: GameState, id: StringName, team: int, cell: Vector2i) -> Unit:
	var unit := Unit.create(Fixture.unit_db().by_id(id), team, cell)
	state.units.append(unit)
	return unit


## A recording of `entries` played from `state`. No checkpoints: a hand-made
## fixture is not describing a board some other build produced, and `drift` takes
## a line with none on trust for exactly that reason.
static func replay(state: GameState, entries: Array) -> ReplayCodec.Replay:
	var recording := ReplayCodec.Replay.new()
	recording.opening = SaveCodec.encode(state, [] as Array[int])
	for entry: Dictionary in entries:
		recording.entries.append(entry)
	return recording


## The report that recording produces. The caller keeps the `stopped` guard, this
## having no `GutTest` to assert with.
static func run(state: GameState, entries: Array) -> ReplayAnalysis.Report:
	return ReplayAnalysis.run(
		replay(state, entries),
		Fixture.terrain_db(),
		Fixture.unit_db(),
		Fixture.chart(),
		Fixture.commander_db()
	)


static func count(report: ReplayAnalysis.Report, kind: String) -> int:
	return int(report.counts().get(kind, 0))


## The first finding of a kind. Asked for by name rather than by index because a
## board that trips one detector usually trips another — a side with a purse has a
## purse whatever else is being tested.
static func first(report: ReplayAnalysis.Report, kind: String) -> ReplayAnalysis.Finding:
	for finding in report.findings:
		if finding.kind == kind:
			return finding
	return null


## Every finding of a kind one side earned. A streak detector counts per side, and
## a board with two purses on it has two of them.
static func for_team(report: ReplayAnalysis.Report, kind: String, team: int) -> Array:
	var found: Array = []
	for finding in report.findings:
		if finding.kind == kind and finding.team == team:
			found.append(finding)
	return found
