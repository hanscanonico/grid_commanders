class_name CutinWarmup3D
extends RefCounted
## The 3D cut-ins, drawn unseen through stand-in plays over the board's first
## second up. A browser builds a shader the first time a frame needs it and
## stalls that frame to do it — over four seconds across a first combat cut-in —
## so the build is paid while the view is switching, never on the frames of the
## first real exchange.
##
## The stand-ins are picked for what they make the stage draw, not for being a
## legal exchange: two tanks trading shots in the open, so a counter, casualties
## and plain ground are drawn; a tank on a property routing a foe afloat when the
## board has sea, so the buildings, the blast, the fade and the water are; and the
## same property taken, so the capture's rig is.

const NO_CELL := Vector2i(-1, -1)
## How far apart the drawn moments are, in seconds of a cut-in's clock.
const STEP := 0.25
## What each side keeps of the traded shots: casualties on both, neither routed.
const TRADED_HP := 50


static func run(board: Board3D, view: BattleView) -> void:
	var properties := view.map.property_cells()
	if properties.is_empty():
		return
	var units := UnitDB.load_default()
	var tank := units.by_id(&"tank")
	var ship := units.by_id(&"battleship")
	var home := properties[0]
	var ours := Unit.create(tank, GameState.TEAMS[0], home)
	var combat := board.combat_cut_in()
	var field := _open_cell(view.map, tank)
	if field != NO_CELL:
		var near := Unit.create(tank, GameState.TEAMS[0], field)
		var far := Unit.create(tank, GameState.TEAMS[1], field)
		if not await _draw(board, combat, combat.pose_at.bind(_trade(), near, far, 0.0)):
			return
	var sea := _open_cell(view.map, ship)
	var foe := Unit.create(tank, GameState.TEAMS[1], home)
	if sea != NO_CELL:
		foe = Unit.create(ship, GameState.TEAMS[1], sea)
	if not await _draw(board, combat, combat.pose_at.bind(_rout(), ours, foe, 0.0)):
		return
	var capture := board.capture_cut_in()
	if await _draw(board, capture, capture.pose_at.bind(_taken(ours), ours, home, 0.0)):
		board.cutin_stage().clear()


## Poses a stand-in with `pose`, then draws it at every STEP of its clock into
## frames never shown, each a frame after it was held there — a material takes a
## new look only as a frame ends, so a figure drawn the frame it faded would be
## drawn solid — keeping it off the screen between. False when the stage stopped
## being the warm-up's.
static func _draw(board: Board3D, director: CutsceneDirector, pose: Callable) -> bool:
	var stage := board.cutin_stage()
	if not await _still_ours(board):
		return false
	pose.call()
	var at := 0.0
	while at < director.length():
		director.hold(at)
		_put_away(stage, director)
		if not await _still_ours(board):
			return false
		director.hold(at)
		RenderingServer.force_draw(false)
		_put_away(stage, director)
		at += STEP
	return true


## Waits out a frame, and any story scene — its frames are the ones the shader
## builds would stall — then answers whether the stage is still the warm-up's: the
## board not flipped back to 2D and no real cut-in playing on it.
static func _still_ours(board: Board3D) -> bool:
	await board.get_tree().process_frame
	while board.cinema().rolling:
		await board.get_tree().process_frame
	return board.active and not board.cutin_stage().rolling


static func _put_away(stage: CutinStage3D, director: CutsceneDirector) -> void:
	stage.leave()
	director.put_away()


static func _trade() -> CombatSnapshot.CombatResult:
	var result := CombatSnapshot.CombatResult.new()
	result.attacker_weapon_slot = DamageChart.PRIMARY
	result.counter_weapon_slot = DamageChart.PRIMARY
	result.countered = true
	result.attacker_hp_before = Unit.MAX_HP
	result.defender_hp_before = Unit.MAX_HP
	result.attacker_hp_after = TRADED_HP
	result.defender_hp_after = TRADED_HP
	result.attack_damage = Unit.MAX_HP - TRADED_HP
	result.counter_damage = Unit.MAX_HP - TRADED_HP
	return result


static func _rout() -> CombatSnapshot.CombatResult:
	var result := CombatSnapshot.CombatResult.new()
	result.attacker_weapon_slot = DamageChart.PRIMARY
	result.attacker_hp_before = Unit.MAX_HP
	result.attacker_hp_after = Unit.MAX_HP
	result.defender_hp_before = Unit.MAX_HP
	result.attack_damage = Unit.MAX_HP
	result.defender_died = true
	return result


static func _taken(unit: Unit) -> CaptureCommand.CaptureResult:
	var result := CaptureCommand.CaptureResult.new()
	result.owner_before = MapData.NEUTRAL
	result.points_before = unit.displayed_hp()
	result.captured = true
	return result


## The first cell that is no property and that `type` may stand on.
static func _open_cell(map: MapData, type: UnitType) -> Vector2i:
	for y in map.height:
		for x in map.width:
			var terrain := map.terrain_at(Vector2i(x, y))
			if not terrain.is_property and terrain.is_passable(type.move_class):
				return Vector2i(x, y)
	return NO_CELL
