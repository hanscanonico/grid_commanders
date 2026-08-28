extends SceneTree
## Scores an arena run: match records in, one row per candidate out.
##
## It plays nothing. `run_ai_arena.gd` produces the records and this reads them,
## which is the split that lets a finished run be re-scored after the fitness
## function moves without replaying a single match (plan D4).
##
## Usage (headless; see `make arena-report`):
##   Godot --headless --path . -s res://tools/run_arena_report.gd -- [flags]
##     --matches=<path>[,<path>…]  a matches.json, or a directory holding one
##     --out=<dir>                 where leaderboard.json goes (default: the
##                                 first input's own directory)
##
## Exits 1 when the run cannot be read as a leaderboard — a mirror merged in, a
## pairing played from one seat only, a candidate that never played a pool the
## others did, or a match the AI and the rules disagreed about. Each is reported
## rather than quietly averaged away.

const RECORD_FILE := "matches.json"
const LEADERBOARD_FILE := "leaderboard.json"

var _inputs: Array[String] = []
var _out_dir := ""


func _init() -> void:
	if not _parse_args():
		quit(2)
		return
	var records := _records()
	if records.is_empty():
		push_error("arena-report: no match records in %s" % ", ".join(_inputs))
		quit(2)
		return
	var board := ArenaLeaderboard.build(records)
	_print(board, records.size())
	_write(board)
	var problem := board.problem()
	if problem != "":
		push_error("arena-report: %s" % problem)
	quit(1 if problem != "" else 0)


func _parse_args() -> bool:
	for arg in CmdArgs.user():
		if arg.begins_with("--matches="):
			for path in arg.get_slice("=", 1).split(",", false):
				_inputs.append(path.strip_edges())
		elif arg.begins_with("--out="):
			_out_dir = arg.get_slice("=", 1).strip_edges()
		else:
			push_error("arena-report: unknown flag '%s'" % arg)
			return false
	if _inputs.is_empty():
		push_error("arena-report: --matches=<matches.json or a directory> names what to score")
		return false
	if _out_dir != "":
		_out_dir = BalanceHarness.out_flag("arena-report", _out_dir)
		if _out_dir == "":
			return false
	return true


## Every record of every input, in the order they were named — the order the
## pool merged them in, which is the order they were played.
func _records() -> Array:
	var records: Array = []
	for input in _inputs:
		var path := _record_file(input)
		if path == "" or not FileAccess.file_exists(path):
			push_error("arena-report: no records at '%s'" % input)
			return []
		var json := JSON.new()
		if json.parse(FileAccess.get_file_as_string(path)) != OK or not (json.data is Array):
			push_error("arena-report: '%s' is not a list of match records" % path)
			return []
		var listed: Array = json.data
		for entry: Variant in listed:
			var problem := ArenaLeaderboard.record_error(entry)
			if problem != "":
				push_error("arena-report: '%s': %s" % [path, problem])
				return []
		records.append_array(listed)
	return records


## An input names either a run directory or the record file inside one.
func _record_file(input: String) -> String:
	var path := ArenaRequest.project_path(input)
	if path != "" and _is_dir(path):
		return path.path_join(RECORD_FILE)
	return path


static func _is_dir(res_path: String) -> bool:
	return DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(res_path))


## The directory the first input's records live in: the one it named, or the one
## holding the record file it named.
func _records_dir() -> String:
	var path := ArenaRequest.project_path(_inputs[0])
	return path if _is_dir(path) else path.get_base_dir()


func _print(board: ArenaLeaderboard, played: int) -> void:
	print("\n=== ai arena: %d matches, %d candidates ===" % [played, board.rows.size()])
	print(
		(
			"fitness: win %.1f + %.1f x (%d - day)/%d, unresolved %.1f, both seatings counted"
			% [
				ArenaFitness.DECISIVE,
				ArenaFitness.SPEED_WEIGHT,
				ArenaFitness.HORIZON,
				ArenaFitness.HORIZON,
				ArenaFitness.UNRESOLVED,
			]
		)
	)
	for pool: String in ArenaPools.REPORTED:
		var listed := board.rows.filter(
			func(row: ArenaLeaderboard.Row) -> bool: return row.matches(pool) > 0
		)
		if listed.is_empty():
			continue
		print("\n-- %s --" % pool)
		print("  %-34s %8s %6s %6s %6s %6s" % ["candidate", "mean", "n", "won", "lost", "unres"])
		for row: ArenaLeaderboard.Row in listed:
			var tally: ArenaLeaderboard.Tally = row.pools[pool]
			print(
				(
					"  %-34s %+8.3f %6d %6d %6d %6d"
					% [
						row.candidate,
						tally.mean(),
						tally.matches,
						tally.wins,
						tally.losses,
						tally.unresolved,
					]
				)
			)
	if board.problem() != "":
		print("\nFAIL: %s" % board.problem())


## Beside the records it scored, unless told otherwise: a leaderboard belongs
## with the run it reads. Both spellings answer to `BalanceReportWriter`, so the
## line it prints is the path it wrote.
func _write(board: ArenaLeaderboard) -> void:
	var out := _out_dir if _out_dir != "" else BalanceReportWriter.resolve_out(_records_dir())
	if out == "":
		push_error("arena-report: records outside reports/ have no leaderboard to sit beside")
		return
	var dir := BalanceReportWriter.prepare_dir(out)
	BalanceReportWriter.write_json(dir.path_join(LEADERBOARD_FILE), board.to_dict())
	print("\narena-report: wrote %s/%s" % [out, LEADERBOARD_FILE])
