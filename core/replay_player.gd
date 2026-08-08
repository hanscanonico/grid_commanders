class_name ReplayPlayer
extends RefCounted
## A cursor over a recorded match: hands out the next command, then says whether
## the board it produced is the board that was recorded.
##
## It deliberately does **not** apply anything. Applying is the caller's, because
## the two callers have to keep their own: the live scene goes through
## `Battle.execute_command` so every animation, cut-in and banner is the shipped
## one, and the offline analyser applies straight to a state it owns. A player
## that applied for them would be a third route into the sim, which is the seam
## `BattleCommandPipeline` exists to be the only one of.
##
## `drift` is plan D3 in one method. The one thing a command log cannot survive is
## the *game* moving underneath it — retune a `.tres`, fix a rule, add a doctrine
## hook, and yesterday's replay describes a match this build would not play. Ask
## after each command and a stale replay stops on the exact line whose meaning
## moved; never ask, and it quietly plays a different match and looks fine.

var _replay: ReplayCodec.Replay
var _unit_db: UnitDB
var _at := 0
## The line handed out by the last `next_command`, which `drift` checks against.
## Left generic: assigned straight from `_replay.entries`, a plain Array[Dictionary]
## whose elements GDScript refuses to narrow into a typed dictionary variable even
## with Variant values (a runtime check on the source dictionary's own type).
var _applied: Dictionary = {}


func _init(replay: ReplayCodec.Replay, unit_db: UnitDB) -> void:
	_replay = replay
	_unit_db = unit_db


## The board the match opened on, rebuilt through the same `SaveCodec.decode`
## route a resumed save takes. Null (with a pushed error) when the envelope is not
## one this build reads — which is the same refusal, in the same words, that a
## damaged save gets.
func opening(
	terrain_db: TerrainDB, damage_chart: DamageChart, commander_db: CommanderDB = null
) -> SaveCodec.LoadedMatch:
	return SaveCodec.decode(_replay.opening, terrain_db, _unit_db, damage_chart, commander_db)


func label() -> String:
	return _replay.label


## How many commands the recording holds, and how many have been handed out.
func length() -> int:
	return _replay.entries.size()


func played() -> int:
	return _at


func finished() -> bool:
	return _at >= _replay.entries.size()


## The next recorded command, bound to the units standing on `state` right now,
## and the cursor moves past it. Null at the end of the recording, and null (with
## a pushed error) on a line this build cannot rebuild — a caller treats both as
## "the replay is over", because there is nothing honest to play after a line that
## could not be read.
func next_command(state: GameState) -> Command:
	if finished():
		_applied = {}
		return null
	var entry: Dictionary = _replay.entries[_at]
	_at += 1
	var command := ReplayCodec.command_from(state, _unit_db, entry)
	_applied = entry if command != null else {}
	return command


## "" when the board matches what the recording says this command left behind,
## else what to say about the mismatch. Asked after the command handed out by
## `next_command` has been applied.
##
## A line with no checkpoint — there are none today, but a format is a contract
## with files older than the code reading them — is taken on trust rather than
## treated as a mismatch.
func drift(state: GameState) -> String:
	if _applied.is_empty() or not _applied.has("ck"):
		return ""
	var recorded := int(_applied["ck"])
	var actual := ReplayCodec.checkpoint(state)
	if recorded == actual:
		return ""
	var what := (
		"command %d (day %d, %s)"
		% [int(_applied.get("n", _at - 1)), int(_applied.get("d", 0)), _applied.get("c", "?")]
	)
	return "a different build made this replay: %s left a board it does not describe" % what
