class_name MissionObjective
extends Resource
## One condition a mission is won or lost by. Subclasses live in
## `core/campaign/objectives/` and each answers exactly one question about a
## committed board.
##
## An objective is a pure read. It is asked after a command has been applied,
## it never mutates the state it is handed, and it re-derives nothing the sim
## already owns — property ownership is `GameState.owner_at`, a side is
## `GameState.allied`, a fallen army is `GameState.is_eliminated`. That is the
## same single-authority rule the resolvers live under: an objective that
## counted properties its own way would be a second opinion about who holds the
## board.
##
## Ground and armies are read **by side**, never by team. `GameState.allied` is
## the hostility authority, so "our cities" means the player's side's cities and
## an ally taking one advances the objective rather than blocking it. Counting a
## bare team here is how an allied capture makes a mission unwinnable.

## Shown in the objective HUD and the briefing. Authored per mission, because
## "Take the relay at Kestrel" reads better than anything derivable from a cell.
@export_multiline var text: String = ""
## Stable name, needed only by a `hidden` objective: it is what a
## `RevealObjective` effect names and what the mission's revealed set records, so
## it has to outlive both a save and a reshuffle of the authored list. Every
## other objective leaves it empty.
@export var id: StringName = &""
## A hidden objective is not asked until an event reveals it — the mission whose
## real goal is only named once you are in it. Nothing is hidden by default, so a
## mission with none is judged exactly as it was before events existed.
@export var hidden: bool = false


## Is this condition satisfied on the board as it now stands?
## `team` is the mission's player team; a side-wide reading asks `state.allied`.
## `progress` is the mission's tally, for the two conditions no single board can
## answer; every other objective ignores it.
func is_met(_state: GameState, _team: int, _progress: MissionProgress) -> bool:
	return false


## How far along this condition is, in a handful of characters — "DAY 4/8",
## "2/3 DAYS", "1/2 LOST". Empty when there is nothing to count and the tick
## beside the text is the whole story.
##
## Here rather than in the panel that prints it, for the same reason `is_met` is:
## a readout worked out from an objective's `@export`s somewhere else is a second
## opinion about what that objective is measuring, and it would drift the first
## time one of them learns to count something new.
func readout(_state: GameState, _team: int, _progress: MissionProgress) -> String:
	return ""


## Is this condition being judged yet? False only for a hidden objective no event
## has revealed, and `MissionRuntime` skips those wherever it walks a list: an
## unrevealed objective can be neither required, nor lost by, nor earn a star.
func is_live(progress: MissionProgress) -> bool:
	return not hidden or (progress != null and progress.is_revealed(id))


## The ground one of our units must be **standing on** for this condition to
## hold, or empty. Occupancy, never ownership: `CaptureCell` and `HoldCell` name
## cells and answer with nothing here, because both stay satisfied long after the
## unit that took the ground has walked off it.
##
## Declared here for the reason `MissionEffect.spawned_tags` is: what a mission
## may not do with that ground is the *mission's* question, not this class's.
func occupied_cells() -> Array[Vector2i]:
	var none: Array[Vector2i] = []
	return none


## Why this objective could never be satisfied on this mission's board, or "".
## Called once when a mission loads so an authoring mistake — a cell that is not
## a property, a count no board can reach — fails visibly at the door rather
## than as a mission that silently cannot be won.
##
## `unit_db` is handed over rather than loaded here, so this stays the pure read
## it claims to be: the caller checking a mission already holds one.
func definition_error(_map: MapData, _team: int, _unit_db: UnitDB) -> String:
	return ""


## The unit this board calls `tag`, or null when nothing on it does. The one
## place a name is resolved, so two conditions asking after the same marshal
## cannot disagree about who it is; a tag names at most one unit per board
## (`UnitTag.duplicate_error`), so the first match is the answer. An empty tag
## names nobody, though most units carry one.
static func tagged_unit(state: GameState, tag: StringName) -> Unit:
	if tag == &"":
		return null
	for unit in state.units:
		if unit.tag == tag:
			return unit
	return null


## Does this board deal a unit called `tag`? What a `definition_error` asks, so a
## mission naming a unit its map never names fails at the door rather than as an
## objective that is satisfied before the first command.
static func board_names(map: MapData, tag: StringName) -> bool:
	return tag != &"" and board_tags(map).has(tag)


## Every name this board's own units carry, in row order. The board's half of the
## uniqueness a tag promises: a mission's scripted arrivals are counted against
## these as well as against each other, so nothing a mission can put on the board
## can end up sharing a name with what was already standing on it.
static func board_tags(map: MapData) -> Array[StringName]:
	var tags: Array[StringName] = []
	for entry: Dictionary in map.starting_units:
		if entry["tag"] != &"":
			tags.append(entry["tag"])
	return tags
