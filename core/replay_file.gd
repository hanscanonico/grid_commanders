class_name ReplayFile
extends RefCounted
## Storage for a replay: a JSONL stream of one header line and one line per
## applied command, appended as the match is played.
##
## Everything about *what* a line contains belongs to ReplayCodec. This file only
## knows about files and JSON text, so a disk error and a malformed replay are
## separate failures with separate messages — the same split SaveGame and
## SaveCodec keep.
##
## ## Why appended rather than written at the end
##
## A replay records itself all match (plan D5), and the match you want to watch is
## the one you did not know was interesting until it ended. Holding the log in
## memory for a single write at the finish would lose the whole thing to a crash,
## a power cut or a player who kills the window — which are three of the reasons
## somebody wants the recording. Appending per command costs one flush per command
## and loses at worst the last line.
##
## Which is also why a replay whose **final** line will not parse is read as one
## line shorter rather than refused: that is exactly what an interrupted write
## leaves behind, and the match up to that point really happened. A bad line
## anywhere else is a corrupt file and is refused, because dropping one silently
## would play a different match.
##
## Unlike a save there is no temp-and-swap here, and deliberately: a replay is
## disposable (plan D3). Nothing resumes from one, so a half-written file costs a
## recording rather than a match, and the durability machinery SaveGame needs
## would buy nothing.

## Where a played match records itself. The Balance Lab writes its own files
## elsewhere — `open_at` takes any path — because a headless sweep's recordings
## belong beside its reports, not in the player's slots.
const DIR := "user://replays"
const EXTENSION := ".jsonl"
## How many recordings the player's directory keeps. Ten twenty-day matches is
## well under a megabyte.
const KEEP := 10


## Just enough of a replay to name it on a menu: read from the header line alone,
## without parsing a single command.
class Summary:
	var path := ""
	var label := ""
	var recorded := ""
	var map_path := ""
	var day: int = 0


var _file: FileAccess
var _path := ""


## Which file this is writing. Empty until one is open.
func path() -> String:
	return _path


func is_open() -> bool:
	return _file != null


## Opens a recording at `file_path`, replacing anything already there. Null (with
## a pushed error) when the directory cannot be made or the file cannot be opened
## — a recording that cannot start says so once, here, rather than at every
## command.
static func open_at(file_path: String) -> ReplayFile:
	var dir := file_path.get_base_dir()
	if not DirAccess.dir_exists_absolute(_absolute(dir)):
		var made := DirAccess.make_dir_recursive_absolute(_absolute(dir))
		if made != OK:
			push_error("ReplayFile: cannot make %s (error %d)" % [dir, made])
			return null
	var handle := FileAccess.open(file_path, FileAccess.WRITE)
	if handle == null:
		push_error(
			"ReplayFile: cannot write %s (error %d)" % [file_path, FileAccess.get_open_error()]
		)
		return null
	var replay := ReplayFile.new()
	replay._file = handle
	replay._path = file_path
	return replay


## Opens one of the rotating slots, having first pruned the directory back to
## `KEEP - 1` so the new one lands inside the budget rather than one over it.
##
## The name is the caller's, because a clock belongs to whoever is writing rather
## than to storage: a played match names its slot by the time it started, and the
## Balance Lab names its files after the match id so a sweep rerun writes the same
## names and two runs can be diffed.
static func open_slot(name: String, dir: String = DIR) -> ReplayFile:
	prune(KEEP - 1, dir)
	return open_at("%s/%s%s" % [dir, name, EXTENSION])


## Writes one line and flushes it. Flushed per line rather than per turn because
## the tail of a buffer is exactly what a crash takes.
func append(line: Dictionary) -> void:
	if _file == null:
		return
	_file.store_line(JSON.stringify(line))
	_file.flush()


func close() -> void:
	if _file == null:
		return
	_file.close()
	_file = null


# --- reading -----------------------------------------------------------------


## The whole replay, header and commands. Null (with a pushed error) when the file
## is missing, empty, or not a replay this build reads.
static func read(file_path: String) -> ReplayCodec.Replay:
	if not FileAccess.file_exists(file_path):
		push_error("ReplayFile: cannot read %s" % file_path)
		return null
	var text := FileAccess.get_file_as_string(file_path)
	var lines := text.split("\n", false)
	if lines.is_empty():
		push_error("ReplayFile: %s is empty" % file_path)
		return null
	var head := _parse_line(lines[0])
	if head.is_empty():
		push_error("ReplayFile: %s does not open with a header" % file_path)
		return null
	var header_error := ReplayCodec.header_error(head)
	if header_error != "":
		push_error("ReplayFile: %s — %s" % [file_path, header_error])
		return null

	var replay := ReplayCodec.Replay.new()
	replay.format = int(head["replay"])
	replay.opening = head["opening"]
	replay.label = String(head.get("label", ""))
	replay.recorded = String(head.get("recorded", ""))
	replay.campaign = StringName(String(head.get("campaign", "")))
	replay.mission = StringName(String(head.get("mission", "")))
	for i in range(1, lines.size()):
		var entry := _parse_line(lines[i])
		if entry.is_empty():
			if i == lines.size() - 1:
				# What an interrupted write leaves behind: the match up to here really
				# happened, so it is played back rather than thrown away.
				push_warning("ReplayFile: %s ends mid-line; dropping it" % file_path)
				break
			push_error("ReplayFile: %s has an unreadable line at %d" % [file_path, i])
			return null
		replay.entries.append(entry)
	return replay


## Which board and when, without parsing a command. Null when the file is not a
## replay — silently, because asking whether a file is worth naming on a menu is a
## query, and a stray file in the directory is an ordinary answer rather than a
## failure.
static func summarize(file_path: String) -> Summary:
	var handle := FileAccess.open(file_path, FileAccess.READ)
	if handle == null:
		return null
	var head := _parse_line(handle.get_line())
	handle.close()
	if head.is_empty() or ReplayCodec.header_error(head) != "":
		return null
	var opening: Dictionary = head["opening"]
	var summary := Summary.new()
	summary.path = file_path
	summary.label = String(head.get("label", ""))
	summary.recorded = String(head.get("recorded", ""))
	summary.map_path = String(opening.get("map_path", ""))
	summary.day = int(opening.get("day", 0))
	return summary


## The recordings in a directory, newest first. Slot names sort chronologically
## because a played match names its slot by its start time, so the ordering costs
## no second read of any file.
static func list(dir: String = DIR) -> Array[Summary]:
	var summaries: Array[Summary] = []
	for name in _slot_names(dir):
		var summary := summarize("%s/%s" % [dir, name])
		if summary != null:
			summaries.append(summary)
	summaries.reverse()
	return summaries


## Deletes the oldest slots until at most `keep` are left. A directory that is not
## there yet needs no pruning and is not an error.
static func prune(keep: int = KEEP, dir: String = DIR) -> void:
	var names := _slot_names(dir)
	var over := names.size() - maxi(keep, 0)
	for i in maxi(over, 0):
		DirAccess.remove_absolute(_absolute("%s/%s" % [dir, names[i]]))


## Slot file names, oldest first. Sorted rather than left in directory order,
## which no filesystem promises anything about.
static func _slot_names(dir: String) -> PackedStringArray:
	var names := PackedStringArray()
	if not DirAccess.dir_exists_absolute(_absolute(dir)):
		return names
	for name in DirAccess.get_files_at(dir):
		if name.ends_with(EXTENSION):
			names.append(name)
	names.sort()
	return names


## A parsed line, or an empty dictionary when the text is not one — which covers a
## blank line, a truncated one, and JSON that is not an object.
static func _parse_line(text: String) -> Dictionary:
	var trimmed := text.strip_edges()
	if trimmed.is_empty():
		return {}
	var json := JSON.new()
	if json.parse(trimmed) != OK or not json.data is Dictionary:
		return {}
	return json.data


static func _absolute(any_path: String) -> String:
	return ProjectSettings.globalize_path(any_path)
