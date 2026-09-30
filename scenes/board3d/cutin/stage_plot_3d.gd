class_name StagePlot3D
extends Node3D
## One side's ground on the 3D cut-in stage: a small board of its own terrain,
## meshed by the board's own mesher and worn in the board's own materials, so a
## wood, a coast or a road here is the wood, coast or road the unit stood on.
##
## Laid out the way the flat cut-in paves its half: the squad stands on the
## cell's *ground* — the terrain itself, or the surface it names when its art
## is an object (`TerrainType.cutin_ground`) — and what stands (trees, peaks, a
## property in its owner's colours) rises behind it. Beyond the patch an apron
## of the same ground runs out to the horizon, so no shot finds the table edge.
##
## Stage frame: the seam between the two sides is x = 0, the squads' line is
## z = 0, a side's plot runs outward from the seam along its own x.

const COLUMNS := 16
const ROWS := 18
## The row whose middle is the squads' line, the rows behind it that what
## stands on the terrain is dressed on, and the column past which it flanks the
## squad too. Deep in front, so no lens stands past the patch's own rim.
const SQUAD_ROW := 6
const BACK_ROWS := 4
const FLANK_COLUMN := 8
## The gap a squad's front figure keeps from the seam, and where a property's
## main building stands out from it.
const FRONT_GAP := 1.3
const SQUAD_REACH := 3.5
## A property is blown up so it reads as the place being fought over, not a
## model on a table: the main building behind the squad, and for a city a
## smaller pair either side.
const BUILDING_SCALE := 3.4
const BUILDING_DEPTH := -3.3
const TOWN_SCALE := 2.2
const TOWN_REACH: Array[float] = [0.4, 7.6]
## How far the apron runs, and how far below the patch's own top it sits: just
## under, so the patch's rim walls are buried in it.
const APRON_FAR := 160.0
## The range behind a mountain: x outward from the seam, z on the stage, height.
const FAR_TREES := 70
const RANGE_ROCK := Color("#6d6a70")
const RANGE: Array[Vector3] = [
	Vector3(2.0, -15.0, 3.0), Vector3(7.0, -17.5, 3.9), Vector3(12.5, -14.0, 2.6)
]
const APRON_DROP := 0.003

## How far a formation may stagger in depth on this ground: 0 lines it up on a
## bridge deck.
var spread := 1.0
## The side this plot stands on: -1 left of the seam, +1 right.
var side := 1
## A property's buildings, the main one first — what a capture flips.
var buildings: Array[Node3D] = []

var _map: MapData


## Lays the plot out and builds it. `ground` is what the squad stands on;
## `owner` the theme a property is painted in (row 0's for nobody).
func setup(
	terrain: TerrainType,
	ground: TerrainType,
	owner: CommanderVisuals.FactionTheme,
	db: TerrainDB,
	p_side: int,
	materials: Array[Material]
) -> void:
	side = p_side
	spread = 0.0 if terrain.id == &"bridge" else 1.0
	var rows := layout(terrain, ground)
	if side < 0:
		for i in rows.size():
			rows[i] = rows[i].reverse()
	_map = MapData.parse("[terrain]\n" + "\n".join(rows), db)
	position = Vector3(-COLUMNS if side < 0 else 0, 0.0, -SQUAD_ROW - 0.5)
	var meshes := TerrainMesher3D.build(_map)
	_add(meshes[0], materials[0])
	if meshes[1] != null:
		_add(meshes[1], materials[1])
	_add_apron(rows[ROWS - 1].left(1), BACK_ROWS, APRON_FAR, materials)
	_add_apron(rows[0].left(1), -APRON_FAR, BACK_ROWS, materials)
	_add_far_trees(rows[0].left(1))
	if terrain.is_property:
		_add_buildings(terrain.id, owner)
	elif terrain.id == &"mountain":
		_add_range()


## The rows of symbols the plot is built from, back to front, each read outward
## from the seam. Pure, so which ground a squad is stood on is checked without a
## scene.
static func layout(terrain: TerrainType, ground: TerrainType) -> PackedStringArray:
	var paving := ground.symbol
	var stands := terrain.stands_in_cutin() and not terrain.is_property
	var backlot := terrain.symbol if stands else ("." if terrain.is_property else paving)
	var rows := PackedStringArray()
	for r in ROWS:
		if r < BACK_ROWS:
			rows.append(backlot.repeat(COLUMNS))
		elif stands:
			rows.append(paving.repeat(FLANK_COLUMN) + terrain.symbol.repeat(COLUMNS - FLANK_COLUMN))
		else:
			rows.append(paving.repeat(COLUMNS))
	_shape(rows, ground.id)
	return rows


## The grounds a whole field of would not read as themselves: a road is a road
## through a field, a river and a bridge a channel across one, a shoal a beach
## with the sea behind it.
static func _shape(rows: PackedStringArray, ground_id: StringName) -> void:
	var field := range(BACK_ROWS, ROWS)
	match ground_id:
		&"road":
			_fill(rows, ".", field)
			_fill(rows, "=", [SQUAD_ROW])
		&"river":
			_fill(rows, ".", field)
			_fill(rows, "~", [SQUAD_ROW - 1, SQUAD_ROW, SQUAD_ROW + 1])
		&"bridge":
			_fill(rows, ".", range(ROWS))
			_fill(rows, "~", [SQUAD_ROW - 1, SQUAD_ROW + 1])
			_fill(rows, "+", [SQUAD_ROW])
		&"shoal":
			_fill(rows, "S", range(BACK_ROWS))
		&"reef":
			for r in BACK_ROWS:
				rows[r] = "SS*SSS*SS*SSS*SS"


## The height a squad stands at on this plot at a stage point: the water's top
## on water, the deck on a bridge, the ground's top anywhere else.
func stand_at(point: Vector3) -> float:
	return BoardSpace3D.stand_at(_map, Vector2(point.x - position.x, point.z - position.z))


## Where this side's squad is anchored, on the stage, for a squad whose full
## five would reach `half_span` either side of it — so its front keeps the same
## gap from the seam whatever it is.
func squad_anchor(half_span: float) -> Vector3:
	var at := Vector3((FRONT_GAP + half_span) * side, 0.0, 0.0)
	at.y = stand_at(at)
	return at


static func _fill(rows: PackedStringArray, symbol: String, only: Array) -> void:
	for r: int in only:
		rows[r] = symbol.repeat(COLUMNS)


static func _is_water(symbol: String) -> bool:
	return symbol == "S" or symbol == "*"


func _add(mesh: ArrayMesh, material: Material) -> void:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	add_child(instance)


## A flat field of the patch's edge ground running out from the seam on this
## plot's side, between depths `z0` and `z1` of the plot's own frame.
func _add_apron(symbol: String, z0: float, z1: float, materials: Array[Material]) -> void:
	var water := _is_water(symbol)
	var top := BoardSpace3D.SEA_TOP if water else BoardSpace3D.LAND_TOP
	var colour := TerrainMesher3D.SEA if water else TerrainMesher3D.GRASS
	match symbol:
		"_":
			top = BoardSpace3D.SHOAL_TOP
			colour = TerrainMesher3D.SAND
		"F":
			colour = TerrainMesher3D.WOODS_FLOOR
		"M":
			colour = TerrainMesher3D.WOODS_FLOOR.lerp(TerrainMesher3D.ROCK, 0.35)
	var seam := -position.x
	var x0 := minf(seam, seam + APRON_FAR * side)
	var x1 := maxf(seam, seam + APRON_FAR * side)
	var y := top - APRON_DROP
	var st := MeshKit.begin()
	MeshKit.quad(
		st, Vector3(x0, y, z1), Vector3(x1, y, z1), Vector3(x1, y, z0), Vector3(x0, y, z0), colour
	)
	_add(st.commit(), materials[1] if water else materials[0])


## Clumps of trees far out on dry ground behind the patch, so the field has a
## far side rather than running flat into the haze. None on water.
func _add_far_trees(symbol: String) -> void:
	if _is_water(symbol) or symbol == "_":
		return
	var st := MeshKit.begin()
	for i in FAR_TREES:
		var out := 1.0 + 44.0 * SquadFormation3D.scatter(i, 91 + side)
		var deep := -22.0 - 26.0 * SquadFormation3D.scatter(i, 93 + side)
		var foot := Vector3(out * side, BoardSpace3D.LAND_TOP, deep) - position
		var tall := 0.9 + 1.1 * SquadFormation3D.scatter(i, 95 + side)
		var foliage := TerrainMesher3D.FOLIAGE[i % TerrainMesher3D.FOLIAGE.size()]
		MeshKit.column(st, MeshKit.at(foot), tall * 0.4, 0.0, tall, 6, foliage.darkened(0.15))
	var trees := MeshInstance3D.new()
	trees.mesh = st.commit()
	trees.material_override = MeshKit.vertex_material()
	trees.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(trees)


## Three big peaks behind the patch's own, so a mountain reads as a range
## rather than a field of hillocks.
func _add_range() -> void:
	var st := MeshKit.begin()
	for i in RANGE.size():
		var at := RANGE[i]
		var foot := Vector3(at.x * side, BoardSpace3D.LAND_TOP, at.y) - position
		var tall := at.z
		var turn := SquadFormation3D.scatter(i, 30) * 90.0
		MeshKit.column(st, MeshKit.at(foot, turn), tall * 0.62, tall * 0.08, tall, 7, RANGE_ROCK)
		var cap := 0.38
		MeshKit.column(
			st,
			MeshKit.at(foot + Vector3(0.0, tall * (1.0 - cap), 0.0), turn),
			tall * 0.62 * (cap + 0.16),
			0.0,
			tall * cap * 1.02,
			7,
			TerrainMesher3D.SNOW
		)
	var peaks := MeshInstance3D.new()
	peaks.mesh = st.commit()
	peaks.material_override = MeshKit.vertex_material()
	add_child(peaks)


func _add_buildings(terrain_id: StringName, owner: CommanderVisuals.FactionTheme) -> void:
	_stand_building(terrain_id, owner, SQUAD_REACH, BUILDING_SCALE)
	if terrain_id == &"city":
		for reach in TOWN_REACH:
			_stand_building(terrain_id, owner, reach, TOWN_SCALE)


func _stand_building(
	terrain_id: StringName, owner: CommanderVisuals.FactionTheme, reach: float, scale_by: float
) -> void:
	var building := PropertyModels3D.build(terrain_id, owner)
	var at := Vector3(
		reach * side, 0.0, BUILDING_DEPTH - (1.0 if scale_by < BUILDING_SCALE else 0.0)
	)
	building.position = at - position + Vector3(0.0, BoardSpace3D.LAND_TOP, 0.0)
	building.scale = Vector3.ONE * scale_by
	add_child(building)
	buildings.append(building)
