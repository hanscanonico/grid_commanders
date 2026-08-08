class_name SetFlagEffect
extends MissionEffect
## Writes a fact to the consequence ledger — Greenwater held, the courier lost,
## three marshals still standing.
##
## It changes no board, which is why `apply` does nothing: a flag is a fact about
## the war and a `Command` is handed a board and nothing else.
## `MissionEventCommand` collects it and the campaign layer — the one writer of
## the mission's tally — stages it, at the same boundary the beat fired on.
##
## **The ledger takes it when the mission is finished, not when the beat fires**
## (`CampaignState.complete`), for the reason the tally itself is dropped with its
## board: an attempt that was abandoned or lost is retried, and a fact banked by
## the bad attempt would be counted twice. So the rule an author holds is one
## sentence — a mission reads the war as it stood when it began, and what it
## writes is read by the next one.

enum Mode {
	## The fact is this number: "three marshals still standing".
	SET,
	## The fact goes up by it: "one more town saved".
	ADD,
}

@export var flag: StringName = &""
@export var mode: Mode = Mode.SET
@export var value: int = 1
## What the debrief says this changed, in the voice an objective's `text` is
## written in. Empty is a fact the player is not told about in so many words.
@export_multiline var note: String = ""


func written_flag() -> SetFlagEffect:
	return self


func definition_error(_map: MapData, _team: int, _unit_db: UnitDB) -> String:
	var name_error := CampaignState.flag_name_error(flag)
	if name_error != "":
		return name_error
	if CampaignState.is_derived(flag):
		return "'%s' is the campaign's own record of a mission, not a fact a beat writes" % flag
	if value < 0:
		return "flag '%s' is written as %d, and a fact is never negative" % [flag, value]
	return ""
