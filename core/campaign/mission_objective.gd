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


## Is this condition satisfied on the board as it now stands?
## `team` is the mission's player team; a side-wide reading asks `state.allied`.
func is_met(_state: GameState, _team: int) -> bool:
	return false


## Why this objective could never be satisfied on this mission's board, or "".
## Called once when a mission loads so an authoring mistake — a cell that is not
## a property, a count no board can reach — fails visibly at the door rather
## than as a mission that silently cannot be won.
func definition_error(_map: MapData, _team: int) -> String:
	return ""
