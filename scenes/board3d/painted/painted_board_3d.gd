class_name PaintedBoard3D
extends RefCounted
## The 3D board's ground in the painted-miniature look: the mesher's land and
## water in the flocked shader, the wood and mountain models stood on their
## cells, and low dressing scattered on the grass, never above a unit's ankles.

const TEXTURES := "res://assets/models/terrain/ground_%s.png"
const SHADER: Shader = preload("res://scenes/board3d/painted/painted_ground_3d.gdshader")
const DRESSING: Shader = preload("res://scenes/board3d/painted/painted_dressing_3d.gdshader")
## Which tile a sub-square wears.
const CLASS_GRASS := 0
const CLASS_FLOOR := 1
const CLASS_ROAD := 2
const CLASS_SAND := 3
const CLASS_EARTH := 4
const CLASS_MESH := 5
const TUFTS_PER_CELL := 22
const FLOWERS_PER_CELL := 5
const PEBBLES_PER_CELL := 9
## A phone draws a third of the dressing.
const TOUCH_DENSITY := 0.34
const TUFT_HEIGHT := 0.04


## The whole ground of `map` under `parent`.
static func dress(parent: Node3D, map: MapData, overlay: Texture2D, fog: Texture2D) -> void:
	var meshes := TerrainMesher3D.build(map, true)
	_add(parent, meshes[0], _on_board(ground_material(map, false), map, overlay, fog))
	if meshes[1] != null:
		_add(parent, meshes[1], _on_board(ground_material(map, true), map, overlay, fog))
	add_scenery(parent, map, overlay, fog)


static func ground_material(map: MapData, water: bool) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter(&"water", water)
	material.set_shader_parameter(&"map_cells", Vector2(map.size()))
	if water:
		material.set_shader_parameter(&"land_mask", _land_mask(map))
		return material
	material.set_shader_parameter(&"ground_classes", _class_lattice(map))
	material.set_shader_parameter(&"grass", load(TEXTURES % "grass"))
	material.set_shader_parameter(&"forest_floor", load(TEXTURES % "floor"))
	material.set_shader_parameter(&"road", load(TEXTURES % "road"))
	material.set_shader_parameter(&"sand", load(TEXTURES % "sand"))
	material.set_shader_parameter(&"earth", load(TEXTURES % "earth"))
	return material


## The woods, mountains and dressing on `map`. A cut-in's plot passes no marks.
static func add_scenery(parent: Node3D, map: MapData, overlay: Texture2D, fog: Texture2D) -> void:
	_add_props(parent, map, &"woods", overlay, fog)
	_add_props(parent, map, &"mountain", overlay, fog)
	_add_dressing(parent, map, fog)


static func _on_board(
	material: ShaderMaterial, map: MapData, overlay: Texture2D, fog: Texture2D
) -> ShaderMaterial:
	material.set_shader_parameter(&"on_board", true)
	material.set_shader_parameter(&"overlay", overlay)
	material.set_shader_parameter(&"fog_cells", fog)
	material.set_shader_parameter(&"map_cells", Vector2(map.size()))
	return material


static func _add(parent: Node3D, mesh: Mesh, material: Material) -> void:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	parent.add_child(instance)


static func _class_lattice(map: MapData) -> ImageTexture:
	var image := Image.create(map.width * 3, map.height * 3, false, Image.FORMAT_L8)
	for y in map.height:
		for x in map.width:
			var cell := Vector2i(x, y)
			var top := TerrainMesher3D.top_of(map, cell)
			var terrain := map.terrain_at(cell).id
			for k in 9:
				var which := CLASS_MESH if top.wet[k] else _class_of(top.colour[k], terrain)
				image.set_pixelv(cell * 3 + Vector2i(k % 3, k / 3), Color8(which, which, which))
	return ImageTexture.create_from_image(image)


static func _class_of(colour: Color, terrain: StringName) -> int:
	if terrain == &"woods":
		return CLASS_FLOOR
	if terrain == &"mountain":
		return CLASS_EARTH
	var bases: Dictionary[int, Color] = {
		CLASS_GRASS: TerrainMesher3D.GRASS,
		CLASS_ROAD: TerrainMesher3D.ROAD,
		CLASS_SAND: TerrainMesher3D.SAND,
		CLASS_EARTH: TerrainMesher3D.EARTH,
	}
	var best := CLASS_GRASS
	var nearest := INF
	for key: int in bases:
		var base: Color = bases[key]
		var gap := Vector3(colour.r - base.r, colour.g - base.g, colour.b - base.b).length()
		if gap < nearest:
			nearest = gap
			best = key
	return best


## Land as a soft field over the water: what its shallows and its foam read.
static func _land_mask(map: MapData) -> ImageTexture:
	var image := Image.create(map.width * 3, map.height * 3, false, Image.FORMAT_L8)
	for y in map.height:
		for x in map.width:
			var cell := Vector2i(x, y)
			var top := TerrainMesher3D.top_of(map, cell)
			for k in 9:
				var land := 0 if top.wet[k] else 255
				image.set_pixelv(cell * 3 + Vector2i(k % 3, k / 3), Color8(land, land, land))
	image.resize(map.width * 4, map.height * 4, Image.INTERPOLATE_BILINEAR)
	image.resize(map.width * 12, map.height * 12, Image.INTERPOLATE_CUBIC)
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)


static func _add_props(
	parent: Node3D, map: MapData, terrain: StringName, overlay: Texture2D, fog: Texture2D
) -> void:
	var spots: Array[Vector3] = []
	for y in map.height:
		for x in map.width:
			if map.terrain_at(Vector2i(x, y)).id == terrain:
				spots.append(Vector3(x + 0.5, BoardSpace3D.LAND_TOP, y + 0.5))
	if spots.is_empty():
		return
	var folder := PaintedModels3D.TERRAIN
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = PaintedModels3D.baked(folder, terrain).mesh
	multi.instance_count = spots.size()
	for i in spots.size():
		multi.set_instance_transform(i, _prop_place(terrain, spots[i]))
	var neutral := CommanderVisuals.theme_for_key(CommanderVisuals.NEUTRAL_KEY)
	var material := PaintedModels3D.material_for(folder, terrain, neutral)
	if fog != null:
		PaintedModels3D.on_board(material, overlay, fog, Vector2(map.size()))
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = multi
	instance.material_override = material
	parent.add_child(instance)


## A wood turns and sizes by its cell, so a forest is no grid of one copy. A
## mountain keeps its peaks at the back, where they hide nothing standing on it.
static func _prop_place(terrain: StringName, spot: Vector3) -> Transform3D:
	if terrain != &"woods":
		return Transform3D(Basis.IDENTITY, spot)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2(spot.x, spot.z))
	var turn := Basis(Vector3.UP, (rng.randi() % 4) * PI / 2.0)
	return Transform3D(turn.scaled(Vector3.ONE * rng.randf_range(0.9, 1.08)), spot)


static func _add_dressing(parent: Node3D, map: MapData, fog: Texture2D) -> void:
	var tufts: Array[Transform3D] = []
	var flowers: Array[Transform3D] = []
	var flower_colours: Array[Color] = []
	var pebbles: Array[Transform3D] = []
	var density := TOUCH_DENSITY if MobileProfile.active() else 1.0
	for y in map.height:
		for x in map.width:
			var cell := Vector2i(x, y)
			var id := map.terrain_at(cell).id
			if id == &"plains" or id == &"woods" or id == &"road":
				_scatter_cell(map, cell, id, density, tufts, flowers, flower_colours, pebbles)
	var cells := Vector2(map.size())
	_add_multi(parent, _tuft_mesh(), tufts, [], fog, cells)
	_add_multi(parent, _flower_mesh(), flowers, flower_colours, fog, cells)
	_add_multi(parent, _pebble_mesh(), pebbles, [], fog, cells)


static func _scatter_cell(
	map: MapData,
	cell: Vector2i,
	id: StringName,
	density: float,
	tufts: Array[Transform3D],
	flowers: Array[Transform3D],
	flower_colours: Array[Color],
	pebbles: Array[Transform3D],
) -> void:
	var top := TerrainMesher3D.top_of(map, cell)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(cell)
	var petals: Array[Color] = [Color("f4e04d"), Color("f7f3e8"), Color("e8619a"), Color("c55ee8")]
	for i in int(TUFTS_PER_CELL * density):
		var spot := Vector2(rng.randf(), rng.randf())
		if _on_grass(top, spot):
			tufts.append(_laid(cell, spot, rng, 0.75 + rng.randf() * 0.7))
	if id == &"plains":
		var bloom := rng.randf() < 0.5
		for i in int(FLOWERS_PER_CELL * density):
			var spot := Vector2(rng.randf(), rng.randf())
			if bloom and _on_grass(top, spot):
				flowers.append(_laid(cell, spot, rng, 0.8 + rng.randf() * 0.5))
				flower_colours.append(petals[rng.randi() % petals.size()])
	for i in int(PEBBLES_PER_CELL * density):
		var spot := Vector2(rng.randf(), rng.randf())
		if id == &"road" or rng.randf() < 0.18:
			pebbles.append(_laid(cell, spot, rng, 0.5 + rng.randf() * 1.1))


static func _on_grass(top: TerrainMesher3D.Top, spot: Vector2) -> bool:
	var sub_x := 0 if spot.x < 0.3 else (1 if spot.x < 0.7 else 2)
	var sub_y := 0 if spot.y < 0.3 else (1 if spot.y < 0.7 else 2)
	var k := sub_y * 3 + sub_x
	return not top.wet[k] and _class_of(top.colour[k], &"") != CLASS_ROAD


static func _laid(
	cell: Vector2i, spot: Vector2, rng: RandomNumberGenerator, size: float
) -> Transform3D:
	var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * size)
	return Transform3D(basis, Vector3(cell.x + spot.x, BoardSpace3D.LAND_TOP, cell.y + spot.y))


static func _add_multi(
	parent: Node3D,
	mesh: Mesh,
	places: Array[Transform3D],
	colours: Array[Color],
	fog: Texture2D,
	cells: Vector2
) -> void:
	if places.is_empty():
		return
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_colors = not colours.is_empty()
	multi.mesh = mesh
	multi.instance_count = places.size()
	for i in places.size():
		multi.set_instance_transform(i, places[i])
		if multi.use_colors:
			multi.set_instance_color(i, colours[i])
	var material := ShaderMaterial.new()
	material.shader = DRESSING
	if fog != null:
		material.set_shader_parameter(&"on_board", true)
		material.set_shader_parameter(&"fog_cells", fog)
		material.set_shader_parameter(&"map_cells", cells)
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = multi
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)


## Three crossed blades, lit straight from above like the ground under them.
static func _tuft_mesh() -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var low := Color("3f6a24")
	var high := Color("a8cf55")
	for i in 3:
		var angle := float(i) * PI / 3.0
		var across := Vector3(cos(angle), 0, sin(angle)) * 0.02
		var lean := Vector3(-sin(angle), 0, cos(angle)) * 0.008
		for tip_side: float in [-1.0, 0.0, 1.0]:
			var foot := across * tip_side
			_blade(st, foot - across * 0.34, foot + across * 0.34, foot * 1.5 + lean, low, high)
	return st.commit()


static func _blade(
	st: SurfaceTool, a: Vector3, b: Vector3, tip: Vector3, low: Color, high: Color
) -> void:
	st.set_normal(Vector3.UP)
	st.set_color(low)
	st.add_vertex(a)
	st.set_normal(Vector3.UP)
	st.set_color(low)
	st.add_vertex(b)
	st.set_normal(Vector3.UP)
	st.set_color(high)
	st.add_vertex(tip + Vector3.UP * TUFT_HEIGHT)


## A stem and a little flat bloom; the instance's colour tints it.
static func _flower_mesh() -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var y := TUFT_HEIGHT * 0.9
	var stem := Vector3(0, y - TUFT_HEIGHT, 0)
	_blade(st, Vector3(-0.003, 0, 0), Vector3(0.003, 0, 0), stem, Color.WHITE, Color.WHITE)
	var points := 5
	for i in points:
		var a := TAU * i / points
		var b := TAU * (i + 1) / points
		for v: Vector3 in [
			Vector3(0, y, 0),
			Vector3(cos(a), 0, sin(a)) * 0.012 + Vector3(0, y, 0),
			Vector3(cos(b), 0, sin(b)) * 0.012 + Vector3(0, y, 0),
		]:
			st.set_normal(Vector3.UP)
			st.set_color(Color.WHITE)
			st.add_vertex(v)
	return st.commit()


static func _pebble_mesh() -> Mesh:
	var st := MeshKit.begin()
	var squash := Transform3D(Basis.from_scale(Vector3(1.0, 0.55, 0.8)), Vector3.ZERO)
	MeshKit.ball(st, squash, 0.012, 2, 5, Color("9b917d"))
	return st.commit()
