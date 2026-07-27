extends Node
## Global signal bus for presentation-level events.
##
## The simulation core in res://core/ must never reference this (or any Node).
## Scenes emit and subscribe here so UI widgets don't need direct references
## to the battle scene.
##
## **A signal lives here only while something listens to it** (architecture
## finding A0). `cursor_moved` and `power_activated` were deleted because nothing
## ever connected to them, and the first fired once per cursor keypress —
## unobserved work on the hot path. The bus itself stays on purpose: every signal
## below is consumed by `MissionStrip`, so the decoupling these five imply is a
## real one. Add the next one in the same commit as its first consumer, not
## before.

## A unit the player has taken command of — the start of a move, not its commit.
## Deliberately not emitted for the read-only preview of a unit that cannot be
## commanded: "I have picked this one up" and "show me what that one could do"
## are different events, and only the first is a player learning to play.
signal unit_selected(unit: Unit)
signal unit_moved(unit: Unit)
signal unit_built(unit: Unit)
signal property_captured(cell: Vector2i, team: int)
signal turn_started(team: int, day: int)
