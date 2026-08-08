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
## The mission the header named, or null for a recording of a skirmish. Bound
## once, because an event line names its beat by id and the ids are the mission's.
var _mission: MissionDefinition
var _mission_error := ""


## `campaigns` is only consulted when the header names one, so a skirmish
## recording opens without a `res://` scan; a caller with a registry already in
## hand — a test, the analyser — passes it rather than paying for a second.
func _init(replay: ReplayCodec.Replay, unit_db: UnitDB, campaigns: CampaignDB = null) -> void:
	_replay = replay
	_unit_db = unit_db
	_bind_mission(campaigns)


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


## Why the mission this recording names cannot be found, or "" — which is every
## recording of a skirmish, and every one whose mission still ships. Asked before
## a single command is handed out, because a mission that has been renamed or
## retired takes every scripted beat in the file with it, and a playback that
## opened anyway would stop at the first of them with a message about the board.
func mission_error() -> String:
	return _mission_error


func _bind_mission(campaigns: CampaignDB) -> void:
	if _replay.campaign == &"":
		return
	var db := campaigns if campaigns != null else CampaignDB.load_default()
	var campaign := db.by_id(_replay.campaign)
	if campaign == null:
		_mission_error = "this build has no campaign '%s'" % _replay.campaign
		return
	_mission = campaign.mission(_replay.mission)
	if _mission == null:
		_mission_error = ("campaign '%s' has no mission '%s'" % [_replay.campaign, _replay.mission])


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
	var command := ReplayCodec.command_from(state, _unit_db, entry, _mission)
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
