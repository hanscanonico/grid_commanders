class_name MissionEffect
extends Resource
## One thing a scripted event does. Subclasses live in `core/campaign/effects/`
## and each does exactly one of them.
##
## An effect reaches the board through `MissionEventCommand` and never by the
## campaign layer writing `GameState` between commands (campaign-depth D1) —
## which is what puts a scripted beat in the log, the save and the replay with no
## special case anywhere.
##
## `apply` is handed a board and the mission's player team, and the board is all
## it may touch. The two effects whose payload is the *mission* rather than the
## board — a hidden objective becoming live, a scripted ending — declare it
## instead: `revealed_objective` and `mission_end` are pure reads the command
## collects, and the campaign layer, which is the one writer of both the tally
## and the verdict, acts on them at the same boundary.


## Mutates the board. Only called after `MissionEventCommand.validate` returned
## "". `team` is the mission's player team, for an effect that wants to speak in
## the mission's own voice; the ones that name a seat outright ignore it.
func apply(_state: GameState, _team: int) -> void:
	pass


## Why this effect could not be applied to the board as it now stands, or "".
## `MissionEventCommand.validate` asks every effect, so a beat that would corrupt
## the board — a unit off the map, a purse for a seat nobody is playing — is
## refused whole rather than half-applied.
##
## Distinct from `definition_error`, which asks the *map* when the mission loads:
## a map deals every seat it names, while a match may have closed some of them.
func board_error(_state: GameState, _team: int) -> String:
	return ""


## Why this effect could never be applied on this mission's board, or "". Called
## once when a mission loads, so an authoring mistake is loud at the door rather
## than silent in the middle of an act.
func definition_error(_map: MapData, _team: int, _unit_db: UnitDB) -> String:
	return ""


## The objective this effect brings out of hiding, or &"" — `RevealObjective`
## alone answers with anything.
func revealed_objective() -> StringName:
	return &""


## The names this effect gives the units it lands, in the order it lands them —
## `SpawnUnits` alone answers with anything. A tag names exactly one unit on a
## board (`UnitTag.duplicate_error`), and a mission can put units on its board
## from several beats, so the whole script has to be counted together: this is
## what `MissionDefinition` counts.
func spawned_tags() -> Array[StringName]:
	var none: Array[StringName] = []
	return none


## The ending this effect declares, or null — `EndMission` alone answers, and it
## answers with itself. It is a fact `MissionRuntime` reads, never a second
## verdict authority: precedence stays that class's (D3).
func mission_end() -> EndMissionEffect:
	return null
