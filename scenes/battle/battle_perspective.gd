class_name BattlePerspective
extends RefCounted
## Viewer-safe battle queries.
##
## This is presentation policy, not simulation: it combines the viewing team
## and hot-seat blackout with the existing rule authorities, then exposes only
## what that viewer may act on or watch. `Vision` still owns sight geometry and
## `AttackRange` still owns firing geometry.

## Why the viewer's unit cannot shoot from where it is standing. An empty target
## list used to say all four of these the same way, and the only thing a menu can
## do with one fact it cannot name is drop the row.
enum FireBlock {
	NONE,  ## something is in reach and the shot is offered
	UNARMED,  ## no weapon at all, so there is no shot to explain
	MOVED,  ## indirect, and it has already left the cell it would fire from
	NO_AMMO,  ## every weapon that could reach a target is dry
	NO_TARGET,  ## nothing the viewer can see stands inside the ring
}


## What a unit may fire at from a cell, and — when that is nothing — the fact that
## made it nothing. Paired for the same reason DropOption is: the menu prints a
## refusal it got no cells for, and asking twice would walk the board twice.
class FireTargets:
	var cells: Array[Vector2i]
	var block: BattlePerspective.FireBlock

	func _init(p_cells: Array[Vector2i], p_block: BattlePerspective.FireBlock) -> void:
		cells = p_cells
		block = p_block


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
var _visible_cells: Dictionary[Vector2i, bool] = {}
## Set for a replay: the match is over, so there is nobody left to hide it from
## (replay plan D5). It is a *viewer* policy and nothing else — `fog_enabled` on
## the state stays exactly as the match was played, because the sim has to resolve
## the recorded moves the way it did, ambushes and all.
##
## Two short-circuits cover the whole surface: every other query here composes off
## `can_see_cell` and `can_see_unit`, so nothing can be omniscient in one answer
## and fogged in another.
var _omniscient := false


func _init(p_game: GameState, p_omniscient: bool = false) -> void:
	_game = p_game
	_omniscient = p_omniscient
	_viewing_team = p_game.teams[0]  # until the first refresh names the real viewer


## Recomputes the read model after a committed action or turn change. A hot-seat
## handoff hides every cell and unit, including the incoming team's own pieces.
func refresh(viewing_team: int, blacked_out: bool) -> void:
	_viewing_team = viewing_team
	_blacked_out = blacked_out and not _omniscient
	# Not a ternary: GDScript does not carry a typed dictionary's element types
	# through one, so the `{}` branch would build a plain Dictionary and the
	# assignment below would refuse it.
	if _blacked_out or _omniscient:
		_visible_cells = {}
	else:
		_visible_cells = Vision.visible_cells(_game, viewing_team)


## Whose eyes the board is currently drawn through. Read by surfaces that have to
## say something *relative to the viewer* — the bar's allegiance word — rather
## than relative to whoever holds the turn.
func viewing_team() -> int:
	return _viewing_team


## Whether the viewer may see activity on `cell`. Cell and unit visibility stay
## separate because a doctrine or a dive can hide a unit on visible ground.
func can_see_cell(cell: Vector2i) -> bool:
	if _omniscient:
		return true
	return not _blacked_out and (not _game.fog_enabled or _visible_cells.has(cell))


## Whether the viewer may read `team`'s bank — its own seat's, and no other's,
## an ally's included. Funds are infrastructure, which a side shares sight and
## purpose but never any of (maps plan D2), so the army fighting beside you is
## still not owed your treasury.
func can_see_funds(team: int) -> bool:
	if _omniscient:
		return true
	return not _blacked_out and team == _viewing_team


## Whether the viewer may be told what `team` holds — the properties it owns and
## the income they pay.
##
## With fog off every flag on the board is drawn for everyone, so the count says
## nothing the board is not already saying. Under fog it would: a property
## captured inside the viewer's fog keeps its last-seen colour until they scout
## it, which is exactly the enemy expansion and income `BattleView.repaint_property`
## refuses to paint through, and a live count would announce the same capture in
## numerals. So under fog only the viewer's own side is counted — sight is unioned
## over a side, so an ally's flags are already drawn for them.
func can_see_holdings(team: int) -> bool:
	if _omniscient:
		return true
	if _blacked_out:
		return false
	return not _game.fog_enabled or _game.allied(team, _viewing_team)


## Whether the viewer may see `unit`, including doctrine and dive hiding.
func can_see_unit(unit: Unit) -> bool:
	if _omniscient:
		return true
	if _blacked_out:
		return false
	return Vision.can_see_unit(_game, _viewing_team, unit, _visible_cells)


## Which of these losses this viewer may be told about.
##
## A loss on the viewer's own side is always told: a lone plane that runs its tank
## dry away from the rest of the army lights no cell once it is gone, and its owner
## still has to learn it is down. Another side's loss is told only where the viewer
## can see the ground it fell on.
##
## Asked after the sim has already removed them, which changes no answer here:
## `Vision` unions over the armies standing with the viewer, so a unit leaving from
## any other side cannot narrow what this viewer sees — and the one side whose
## leaving could is the side that is answered without asking.
func reportable_losses(lost: Array[Unit]) -> Array[Unit]:
	var told: Array[Unit] = []
	for unit in lost:
		if _game.allied(unit.team, _viewing_team) or can_see_cell(unit.cell):
			told.append(unit)
	return told


## The unit the viewer can actually see on `cell`, or null when the tile reads
## empty to them. A hidden occupant therefore cannot turn a click into a fog
## probe; command validation still owns whether anything may land there.
func visible_unit_at(cell: Vector2i) -> Unit:
	var unit := _game.unit_at(cell)
	if unit != null and not can_see_unit(unit):
		return null
	return unit


## Enemy cells `unit` may fire at from `dest`, and why there are none when there
## are none. `AttackRange` remains the authority on reach, on readiness and on
## targetability: the three refusals below are its own answers named, never a
## second reading of a unit's ammo or its weapon.
func fire_targets(unit: Unit, dest: Vector2i, moved: bool) -> FireTargets:
	var cells: Array[Vector2i] = []
	if AttackRange.maximum(_game, unit) <= 0:
		return FireTargets.new(cells, FireBlock.UNARMED)
	if AttackRange.is_indirect(unit) and moved:
		return FireTargets.new(cells, FireBlock.MOVED)
	if not AttackRange.has_ready_weapon(_game, unit):
		return FireTargets.new(cells, FireBlock.NO_AMMO)
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
	return FireTargets.new(cells, FireBlock.NO_TARGET if cells.is_empty() else FireBlock.NONE)


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
## A carried passenger is skipped for the same reason `fire_targets` skips
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
