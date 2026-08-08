class_name MissionProgress
extends RefCounted
## The mission's own tally: the few facts an objective or an event needs that no
## single board can answer — how long a square has been ours, how many units we
## have lost, which beats have already played and which hidden objectives are
## live.
##
## **One writer** (campaign-depth D2), which is a place rather than a method:
## `observe` advances the counters once per command boundary and `record_fired` /
## `reveal` note what that same boundary did, all three from `CampaignSession`
## and none of them from anywhere else. A second writer is a tally two boundaries
## can disagree about, with nothing left to say which count was the mission's.
##
## It is mission bookkeeping rather than board state, which is why `SaveCodec`
## grows no field for it: the counters ride in the campaign profile beside the
## embedded battle, and a skirmish save is untouched. Only the counters persist.
## What `observe` needs in order to see a *change* — the units it last saw, the
## day it last saw — is working state rebuilt from the first board after a load,
## so a resumed mission neither forgets its losses nor counts them a second time.

## Counter keys, as the profile stores them. A hold is keyed by its cell, so one
## tally answers for every square a mission might ask about; a fired event, a
## revealed objective and a staged flag are keyed by their own names, which is
## why all three are authored as identifiers.
const LOSSES := "losses"
const HELD := "held:"
const FIRED := "fired:"
const REVEALED := "revealed:"
const FLAG_SET := "flagset:"
const FLAG_ADD := "flagadd:"

var _counters: Dictionary[String, int] = {}
## Instance ids of our side's units at the last boundary — the identity a
## departure is diffed against, and one that does not hold a dead unit alive.
var _standing: Dictionary[int, bool] = {}
var _day := 0
## False until a board has been seen. The first observation — an opening, or the
## first after a load — is a baseline, and no delta can be taken from it.
var _observed := false


## Advance the tally over the board as it now stands. The one writer.
func observe(state: GameState, team: int) -> void:
	var ids := _side_ids(state, team)
	if _observed:
		_tally_losses(ids)
	_settle_holds(state, team, _observed and state.day > _day)
	_standing = ids
	_day = state.day
	_observed = true


## Units of our side that have left the board: killed, sunk with the transport
## they rode, or crashed out of fuel. Two units merged into one spends one the
## same way and reads as a loss here.
func losses() -> int:
	return _counters.get(LOSSES, 0)


## Whole days our side has held `cell` without once losing it.
func days_held(cell: Vector2i) -> int:
	return _counters.get(_hold_key(cell), 0)


## Note that an event has fired. Recorded rather than derived, because what a
## beat did to the board is not something the board remembers having been done
## once: a `once` event that re-fired after a reload would land its column twice.
func record_fired(event_id: StringName) -> void:
	_counters[FIRED + String(event_id)] = 1


func has_fired(event_id: StringName) -> bool:
	return _counters.has(FIRED + String(event_id))


## Bring a hidden objective out of hiding. What `RevealObjective` asks for, and
## it rides in the tally for the same reason the fired set does — an objective
## revealed before a save is still revealed after one.
func reveal(objective_id: StringName) -> void:
	_counters[REVEALED + String(objective_id)] = 1


func is_revealed(objective_id: StringName) -> bool:
	return _counters.has(REVEALED + String(objective_id))


## Note a fact a `SetFlag` beat wrote, for the campaign's ledger to take when the
## mission is finished. It waits here rather than going straight to the ledger
## for the reason every other counter follows the board: an attempt that was
## abandoned or lost banks nothing, so a retry cannot count a fact twice.
func stage_flag(name: StringName, value: int, accumulate: bool) -> void:
	if not accumulate:
		_counters[FLAG_SET + String(name)] = value
		return
	var key := FLAG_ADD + String(name)
	_counters[key] = _counters.get(key, 0) + value


## Facts this mission has assigned outright, by name.
func flag_assignments() -> Dictionary[String, int]:
	return _staged(FLAG_SET)


## Facts this mission has raised, by name and by how much.
func flag_increments() -> Dictionary[String, int]:
	return _staged(FLAG_ADD)


func is_empty() -> bool:
	return _counters.is_empty()


## The counters as the profile stores them; the working state is deliberately not
## among them.
func to_dict() -> Dictionary:
	return _counters.duplicate()


## The tally these counters are. Shapes no writer could have produced are
## `tally_error`'s to refuse, so anything reaching here has been validated.
static func from_dict(data: Dictionary) -> MissionProgress:
	var progress := MissionProgress.new()
	for key: String in data:
		progress._counters[key] = int(data[key])
	return progress


## Why `name` could not key a counter, or "". A fired event and a revealed
## objective are both recorded under their own name, and `_is_counter` refuses a
## key no writer could have produced — so a name refused here is a mission that
## writes a profile it can never read back, and the player's mid-mission save is
## discarded on the way in. Asked by every author of such a name, so the rule is
## stated once (`UnitTag.name_error`'s shape, and for the same reason).
static func name_error(name: StringName) -> String:
	if String(name).is_valid_ascii_identifier():
		return ""
	return "'%s' is not an identifier" % name


## Why this dictionary is not a tally, or "". Held to the same bar as the rest of
## the profile: a counter no writer could have produced is refused rather than
## loaded.
static func tally_error(data: Dictionary) -> String:
	for key in data:
		if not (key is String) or not _is_counter(String(key)):
			return "tally holds '%s', which is not a counter" % [key]
		var count = data[key]
		if not (count is float or count is int) or int(count) < 0:
			return "counter '%s' holds %s" % [key, count]
	return ""


func _staged(prefix: String) -> Dictionary[String, int]:
	var staged: Dictionary[String, int] = {}
	for key: String in _counters:
		if key.begins_with(prefix):
			staged[key.trim_prefix(prefix)] = _counters[key]
	return staged


## Our side's units on this board, keyed by instance id. Cargo counts: a
## passenger is aboard rather than gone, and it is lost with the transport it
## rode down.
func _side_ids(state: GameState, team: int) -> Dictionary[int, bool]:
	var ids: Dictionary[int, bool] = {}
	for unit in state.units:
		if state.allied(unit.team, team):
			ids[unit.get_instance_id()] = true
	return ids


## A difference against the units we last saw, rather than "started with, minus
## have now": a unit built between two boundaries would otherwise mask a unit
## killed between them.
func _tally_losses(ids: Dictionary[int, bool]) -> void:
	var lost := 0
	for id: int in _standing:
		if not ids.has(id):
			lost += 1
	if lost > 0:
		_counters[LOSSES] = losses() + lost


## Ground we no longer hold drops its count at once — that is what makes a hold
## consecutive — while a day rolling over is what advances the ground we do, so
## several turns inside one day cannot finish one. Every property the side holds
## is counted, because the tally does not read the mission and so cannot know
## which square an objective is about.
func _settle_holds(state: GameState, team: int, day_rolled: bool) -> void:
	for cell: Vector2i in state.property_owners:
		var key := _hold_key(cell)
		var owner := state.owner_at(cell)
		if owner == 0 or not state.allied(owner, team):
			_counters.erase(key)
		elif day_rolled:
			_counters[key] = _counters.get(key, 0) + 1


static func _hold_key(cell: Vector2i) -> String:
	return "%s%d,%d" % [HELD, cell.x, cell.y]


static func _is_counter(key: String) -> bool:
	if key == LOSSES:
		return true
	for prefix: String in [FIRED, REVEALED, FLAG_SET, FLAG_ADD]:
		if key.begins_with(prefix):
			return key.trim_prefix(prefix).is_valid_ascii_identifier()
	if not key.begins_with(HELD):
		return false
	var coords := key.trim_prefix(HELD).split(",")
	return coords.size() == 2 and coords[0].is_valid_int() and coords[1].is_valid_int()
