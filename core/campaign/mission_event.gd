class_name MissionEvent
extends Resource
## One scripted beat: what it waits for, what it says, and what it does to the
## board.
##
## Its triggers are a **conjunction** — every one of them must hold — which is
## what makes a small vocabulary expressive: `ObjectiveMet` plus `DayBefore` is
## "did it, and did it fast".
##
## Its effects are applied by `MissionEventCommand` in the order authored, and
## the events due at one boundary fire in the order the mission lists them, each
## as a command of its own, so a replay shows them landing one at a time
## (campaign-depth D3).

## Unique within the mission, and an identifier because the fired set records it
## and that set is saved: what has already happened has to survive a reload.
@export var id: StringName = &""
@export var triggers: Array[MissionTrigger] = []
@export var effects: Array[MissionEffect] = []
## Fires once and never again. False for a beat that should repeat every time its
## conditions come true — a bombardment each day the ridge is still theirs.
@export var once: bool = true
## What is said when it fires, drawn by `MissionSpeech` exactly as a briefing's
## lines are. Empty is a beat nobody comments on.
@export var lines: Array[MissionLine] = []


## Is this event due on the board as it now stands? Every trigger has to hold,
## and a `once` event that has already fired is never due again.
func is_due(state: GameState, team: int, progress: MissionProgress) -> bool:
	if once and progress.has_fired(id):
		return false
	for trigger: MissionTrigger in triggers:
		if trigger == null or not trigger.is_met(state, team, progress):
			return false
	return true


## Every name this beat gives a unit it lands, gathered from its effects. What
## `MissionDefinition` holds against the rest of the mission's script and against
## the board's own units, a tag naming two units naming neither.
func spawned_tags() -> Array[StringName]:
	var named: Array[StringName] = []
	for effect: MissionEffect in effects:
		if effect != null:
			named.append_array(effect.spawned_tags())
	return named


## Why this event could never fire or could never be applied on this mission's
## board, or "". An event with no triggers is refused rather than treated as
## always due: a beat nobody can read the conditions of is an authoring slip, and
## "at the opening" is `DayReached { day: 1 }` said out loud.
func definition_error(map: MapData, team: int, unit_db: UnitDB) -> String:
	if id == &"":
		return "event has no id"
	var key_error := MissionProgress.name_error(id)
	if key_error != "":
		return "event id %s" % key_error
	if not once and not spawned_tags().is_empty():
		return "event '%s' repeats and lands named units, which it would name twice" % id
	if triggers.is_empty():
		return "event '%s' waits for nothing" % id
	if effects.is_empty():
		return "event '%s' does nothing" % id
	for trigger: MissionTrigger in triggers:
		if trigger == null:
			return "event '%s' holds an empty trigger slot" % id
		var trigger_error := trigger.definition_error(map, team, unit_db)
		if trigger_error != "":
			return "event '%s': %s" % [id, trigger_error]
	for effect: MissionEffect in effects:
		if effect == null:
			return "event '%s' holds an empty effect slot" % id
		var effect_error := effect.definition_error(map, team, unit_db)
		if effect_error != "":
			return "event '%s': %s" % [id, effect_error]
	return ""
