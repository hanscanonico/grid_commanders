class_name ReplayRecorder
extends RefCounted
## Turns a match into replay lines while it is played.
##
## It **observes** (plan D2), the same discipline BalanceMatchRecorder holds to
## and for the same reason: nothing under `core/` or `ai/` gained a signal, a hook
## or a field for it. The recorder is handed each command either side of `apply()`
## — which both of the repo's command brokers already do, the live
## `BattleCommandPipeline` and the headless `BalanceMatchEngine` — and otherwise
## reads nothing but public `GameState`. What is recorded is therefore bit-for-bit
## the shipped game, and the recording cannot bend the game toward being
## recordable.
##
## ## Why either side of apply, rather than after it
##
## Two of the three fields a line needs are only answerable before: which side is
## acting, since an `EndTurnCommand` changes it, and which passenger a `Drop`
## names, since after the apply that rider has left the cargo it was named in. The
## checkpoint is only answerable after, being a digest of what the command left
## behind. So the pair, exactly as the Balance Lab's recorder already takes it.
##
## Only applied commands are recorded: a plan the pipeline refused never touched
## the board, so it never touches the file, which is what keeps "re-apply every
## line in order" a complete description of the match rather than a description
## plus a filter.
##
## ## Why the file is opened by the first command
##
## A match records itself from its first move, not from its boot. The slots are
## rotating and few (`ReplayFile.KEEP`), so a file claimed at boot means booting a
## match and leaving it evicts the oldest recording of a match somebody played and
## leaves a header nobody can watch. The opener is therefore a Callable held until
## there is a line worth writing, and the header goes down ahead of it.

## Opens the file finished lines go to, called once and only when the first
## command has been recorded. Unset records to memory instead, which is what a
## test wants and what `lines()` reads back.
var _open_sink: Callable
var _sink: ReplayFile
var _sink_opened := false
var _lines: Array[Dictionary] = []
var _seq := 0
## The line the opening was encoded as, written ahead of the first command line.
## Left generic: both are assigned straight from ReplayCodec's plain-Dictionary
## return, and GDScript refuses that assignment into a typed dictionary variable
## even with Variant values (a runtime check on the source dictionary's own type,
## not on what it holds).
var _header: Dictionary = {}
## The line being built between `before_apply` and `after_apply`.
var _pending: Dictionary = {}


func _init(open_sink: Callable = Callable()) -> void:
	_open_sink = open_sink


## Opens the recording on the board the match starts from — after the state is
## built and before a single command. The opening is a `SaveCodec` envelope
## verbatim (plan D1), so a match resumed from a save records correctly from
## wherever it was picked up.
##
## `campaign` and `mission` are what a scripted beat is resolved against on the
## way back, and they ride in the header for the reason `label` does: the
## envelope describes a board, and which war that board is being fought in is the
## recorder's to say. Both empty is a skirmish.
func begin(
	state: GameState,
	ai_teams: Array[int],
	difficulty: StringName = Difficulty.DEFAULT_ID,
	label: String = "",
	recorded: String = "",
	campaign: StringName = &"",
	mission: StringName = &""
) -> void:
	_header = ReplayCodec.header(
		SaveCodec.encode(state, ai_teams, difficulty), label, recorded, campaign, mission
	)
	if _open_sink.is_null():
		_lines.append(_header)


## Called once a command has been validated and is about to be applied.
func before_apply(state: GameState, command: Command) -> void:
	_pending = {"n": _seq, "d": state.day, "t": state.current_team}
	_pending.merge(ReplayCodec.encode_command(state, command))


## Called once it has been. Silent when nothing is pending, so a caller that
## records only one half of a command loses that line rather than mis-stamping the
## next one.
func after_apply(state: GameState) -> void:
	if _pending.is_empty():
		return
	_pending["ck"] = ReplayCodec.checkpoint(state)
	_emit(_pending)
	_pending = {}
	_seq += 1


## Which file this match is recording into, empty while there is not one yet: a
## recorder writing to memory has no file, and one with a sink has none until the
## first command claims a slot — see the class note above.
func path() -> String:
	return _sink.path() if _sink != null else ""


## Lines recorded so far, when nothing is being written to. A recorder with a sink
## holds none — a thousand-match sweep must not pay for a log nobody reads back.
func lines() -> Array[Dictionary]:
	return _lines


func close() -> void:
	if _sink != null:
		_sink.close()


## Writes one command line, opening the file on the first of them. A failed open
## is tried once and never again: the match plays on unrecorded rather than
## pushing the same disk error at every command.
func _emit(line: Dictionary) -> void:
	if _open_sink.is_null():
		_lines.append(line)
		return
	if not _sink_opened:
		_sink_opened = true
		_sink = _open_sink.call()
		if _sink != null:
			_sink.append(_header)
	if _sink == null:
		return
	_sink.append(line)
