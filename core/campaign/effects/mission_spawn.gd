class_name MissionSpawn
extends Resource
## One unit a `SpawnUnits` effect lands: what it is, where it stands, what the
## mission calls it and how used-up it arrives.
##
## The type is a `UnitType` rather than the map format's symbol because an effect
## is applied through a `Command`, and a command is handed a board and nothing
## else — there is no `UnitDB` at that point to resolve a symbol against.
## `BuildCommand` takes a resolved type for the same reason.

@export var unit_type: UnitType
@export var cell: Vector2i = Vector2i.ZERO
## Optional name, so a later event or an objective can reach what just landed.
@export var tag: StringName = &""
## Internal HP it arrives on, 100 being whole — a relief column that has already
## been fighting somewhere else arrives showing it.
@export_range(1, 100) var hp: int = 100
