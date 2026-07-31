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
var _viewing_team: int = 0
var _blacked_out := false
var _visible_cells: Dictionary = {}


func _init(p_game: GameState) -> void:
	_game = p_game
	_viewing_team = p_game.teams[0]  # until the first refresh names the real viewer


## Recomputes the read model after a committed action or turn change. A hot-seat
## handoff hides every cell and unit, including the incoming team's own pieces.
func refresh(viewing_team: int, blacked_out: bool) -> void:
	_viewing_team = viewing_team
	_blacked_out = blacked_out
	_visible_cells = {} if blacked_out else Vision.visible_cells(_game, viewing_team)


## Whose eyes the board is currently drawn through. Read by surfaces that have to
## say something *relative to the viewer* — the bar's allegiance word — rather
## than relative to whoever holds the turn.
func viewing_team() -> int:
	return _viewing_team


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
	if AttackRange.is_indirect(unit) and moved:
		return cells
	for other in _game.units:
		if _game.allied(other.team, unit.team) or other.carrier != null:
			continue
		if not can_see_unit(other):
			continue
		if not AttackRange.covers(_game, unit, dest, other.cell):
			continue
		if AttackRange.can_fire(_game, unit, other):
			cells.append(other.cell)
	cells.sort()
	return cells


## The cells to paint for `unit`'s reach — where it could move, and where it could
## bring fire — as the viewer is allowed to see them.
##
## One rule with two answers, and the axis is **whose side the unit is on**, not which
## flow is asking — a unit of the viewer's own that has already acted is previewed
## like an enemy, and is still shown whole. That is why the rule lives here rather
## than at either call site.
##
## A unit on the viewer's **own side** is shown its whole reach: that overlay has to
## agree cell for cell with what the commands will accept, and one that stopped at the
## fog would hide moves `MoveCommand` allows — the movement-overlay lesson this repo
## already paid for once, in the other direction.
##
## Another side's unit would tell two separate things. What it is drawn *over* is
## ground the viewer may never have scouted, which `_viewer_safe` masks away. What its
## outline *is* would be worse: a fill keyed to the mover's own sight is walled by the
## viewer's units that mover can see and planned through the ones it cannot, so the
## shape alone would report which of the viewer's pieces the enemy has spotted. A mask
## cannot close that — the cells carrying the signal are ones the viewer always sees —
## so both fills below are asked for the *viewer's* knowledge instead, and then depend
## on nothing the viewer does not already know (COM-57).
##
## Passed on every call, an own-side unit's included, where it names that unit's own
## team and the fill is the one the commands plan with, cell for cell.
func move_overlay_cells(unit: Unit) -> Array[Vector2i]:
	var reach := MovementResolver.reachable(_game, unit, 0, _viewing_team)
	return _viewer_safe(reach.cells(), unit)


func threat_overlay_cells(unit: Unit) -> Array[Vector2i]:
	return _viewer_safe(AttackRange.threat_cells(_game, unit, _viewing_team), unit)


## Every cell any side hostile to the viewer could bring under fire this turn —
## the survey lens, as against the one-unit reading above.
##
## A union over `threat_overlay_cells`, never a second walk: the per-unit answer
## already carries the sight rule the fill is keyed to and the mask that keeps
## another side's ring on scouted ground, and a lens that recomputed either would
## be the fourth opinion on firing geometry this repo has had to consolidate.
##
## A carried passenger is skipped for the same reason `attackable_cells` skips
## one — it is not on the board to shoot from — and a unit the viewer cannot see
## contributes nothing, so the lens never outlines a submarine or an ambush.
func all_threat_overlay_cells() -> Array[Vector2i]:
	var seen := {}
	for unit in _game.units:
		if _game.allied(unit.team, _viewing_team) or unit.carrier != null:
			continue
		if not can_see_unit(unit):
			continue
		for cell in threat_overlay_cells(unit):
			seen[cell] = true
	var cells: Array[Vector2i] = []
	for cell: Vector2i in seen:
		cells.append(cell)
	cells.sort()
	return cells


## Whole for a unit on the viewer's own side, scouted ground only for another side's.
func _viewer_safe(cells: Array[Vector2i], unit: Unit) -> Array[Vector2i]:
	if _game.allied(unit.team, _viewing_team):
		return cells
	var scouted: Array[Vector2i] = []
	for cell in cells:
		if can_see_cell(cell):
			scouted.append(cell)
	return scouted


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
