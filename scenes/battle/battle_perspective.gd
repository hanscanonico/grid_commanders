class_name BattlePerspective
extends RefCounted
## Viewer-safe battle queries.
##
## This is presentation policy, not simulation: it combines the viewing team
## and hot-seat blackout with the existing rule authorities, then exposes only
## what that viewer may act on or watch. `Vision` still owns sight geometry and
## `AttackRange` still owns firing geometry.


## One cargo choice and the cells where that passenger may be unloaded. Keeping
## the pair together prevents a menu index from being resolved once for its
## label and again for a potentially different set of cells.
class DropOption:
	var passenger: Unit
	var cells: Array[Vector2i]

	func _init(p_passenger: Unit, p_cells: Array[Vector2i]) -> void:
		passenger = p_passenger
		cells = p_cells


var _game: GameState
var _viewing_team: int = GameState.TEAMS[0]
var _blacked_out := false
var _visible_cells: Dictionary = {}


func _init(p_game: GameState) -> void:
	_game = p_game


## Recomputes the read model after a committed action or turn change. A hot-seat
## handoff hides every cell and unit, including the incoming team's own pieces.
func refresh(viewing_team: int, blacked_out: bool) -> void:
	_viewing_team = viewing_team
	_blacked_out = blacked_out
	_visible_cells = {} if blacked_out else Vision.visible_cells(_game, viewing_team)


## Whether the viewer may see activity on `cell`. Cell and unit visibility stay
## separate because a doctrine or a dive can hide a unit on visible ground.
func can_see_cell(cell: Vector2i) -> bool:
	return not _blacked_out and (not _game.fog_enabled or _visible_cells.has(cell))


## Whether the viewer may see `unit`, including doctrine and dive hiding.
func can_see_unit(unit: Unit) -> bool:
	if _blacked_out:
		return false
	return Vision.can_see_unit(_game, _viewing_team, unit, _visible_cells)


## The unit the viewer can actually see on `cell`, or null when the tile reads
## empty to them. A hidden occupant therefore cannot turn a click into a fog
## probe; command validation still owns whether anything may land there.
func visible_unit_at(cell: Vector2i) -> Unit:
	var unit := _game.unit_at(cell)
	if unit != null and not can_see_unit(unit):
		return null
	return unit


## Enemy cells `unit` may fire at from `dest`. Ammo and indirect movement gate
## the action; `AttackRange` remains the authority on reach and targetability.
func attackable_cells(unit: Unit, dest: Vector2i, moved: bool) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if not unit.has_ammo() or (AttackRange.is_indirect(unit) and moved):
		return cells
	for other in _game.units:
		if other.team == unit.team or other.carrier != null:
			continue
		if not can_see_unit(other):
			continue
		if not AttackRange.covers(_game, unit, dest, other.cell):
			continue
		if AttackRange.can_engage(_game, unit, other):
			cells.append(other.cell)
	cells.sort()
	return cells


## Every passenger with at least one viewer-safe unload cell from `dest`, in
## cargo order. A hidden enemy is left for DropCommand to discover on apply
## rather than disclosed here.
func drop_options(transport: Unit, dest: Vector2i) -> Array[DropOption]:
	var options: Array[DropOption] = []
	for passenger in _game.cargo_of(transport):
		var cells := _drop_cells(transport, dest, passenger)
		if not cells.is_empty():
			options.append(DropOption.new(passenger, cells))
	return options


func _drop_cells(transport: Unit, dest: Vector2i, passenger: Unit) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if passenger == null or not transport.type.can_unload_from(_game.map.terrain_at(dest).id):
		return cells
	for direction in MovementResolver.DIRECTIONS:
		var cell: Vector2i = dest + direction
		var terrain := _game.map.terrain_at(cell)
		if terrain == null or not terrain.is_passable(passenger.type.move_class):
			continue
		var occupant := _game.unit_at(cell)
		if occupant != null and occupant != transport and can_see_unit(occupant):
			continue
		cells.append(cell)
	return cells
