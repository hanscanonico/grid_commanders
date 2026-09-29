class_name PropertyModels3D
extends RefCounted
## The five property buildings for the 3D board — city, base, airport, port, HQ —
## one merged mesh each per owner, cached. The origin is the middle of the cell
## on the ground's top face.
##
## A unit stands on the same cell, so the tall masses sit toward the back (-Z)
## and the sides and the middle stays low. The owner reads off the roofs, flags
## and trim; the walls stay pale for everybody, which is what lets a neutral
## building's grey roofs say "nobody's" rather than "the grey army's".

const WALL := Color("e6e0d2")
const WALL_SHADE := Color("c7bfae")
const PAVE := Color("9d9a92")
const ASPHALT := Color("45484d")
const STRIPE := Color("ecebe4")
const WINDOW := Color("2f4152")
const METAL := Color("5b6068")
const DARK := Color("2e3136")

static var _meshes: Dictionary[String, ArrayMesh] = {}
static var _warned: Dictionary[StringName, bool] = {}


static func mesh_for(terrain_id: StringName, theme: CommanderVisuals.FactionTheme) -> ArrayMesh:
	var key := "%s|%s" % [terrain_id, theme.key]
	if not _meshes.has(key):
		var st := MeshKit.begin()
		_body(st, terrain_id, theme)
		_meshes[key] = st.commit()
	return _meshes[key]


## A fresh model: one `Body`, with a material made for this call alone because
## the board tints it in place.
static func build(terrain_id: StringName, theme: CommanderVisuals.FactionTheme) -> Node3D:
	var root := Node3D.new()
	root.name = String(terrain_id)
	var body := MeshInstance3D.new()
	body.name = "Body"
	body.mesh = mesh_for(terrain_id, theme)
	body.material_override = MeshKit.vertex_material()
	root.add_child(body)
	return root


static func _body(
	st: SurfaceTool, terrain_id: StringName, t: CommanderVisuals.FactionTheme
) -> void:
	match terrain_id:
		&"city":
			_city(st, t)
		&"base":
			_base(st, t)
		&"airport":
			_airport(st, t)
		&"port":
			_port(st, t)
		&"hq":
			_hq(st, t)
		_:
			if not _warned.has(terrain_id):
				_warned[terrain_id] = true
				push_warning("PropertyModels3D: no model for terrain '%s'" % terrain_id)
			MeshKit.block(st, MeshKit.at(Vector3.ZERO), Vector3(0.5, 0.3, 0.5), t.color)


static func _pad(st: SurfaceTool, color: Color) -> void:
	MeshKit.block(st, MeshKit.at(Vector3.ZERO), Vector3(0.92, 0.03, 0.92), color)


## A walled house standing on `pos`, a roof in the owner's colour and a row of
## windows on the two faces the camera sees (+Z and +X).
static func _house(
	st: SurfaceTool, pos: Vector3, size: Vector3, gabled: bool, t: CommanderVisuals.FactionTheme
) -> void:
	MeshKit.block(st, MeshKit.at(pos), size, WALL)
	var top := pos + Vector3(0, size.y, 0)
	if gabled:
		MeshKit.roof(st, MeshKit.at(top), Vector3(size.x + 0.03, 0.1, size.z + 0.04), t.color)
	else:
		MeshKit.block(st, MeshKit.at(top), Vector3(size.x + 0.02, 0.035, size.z + 0.02), t.color)
		MeshKit.block(st, MeshKit.at(top), Vector3(size.x * 0.4, 0.06, size.z * 0.4), t.color_dark)
	MeshKit.block(st, MeshKit.at(pos), Vector3(size.x + 0.01, 0.03, size.z + 0.01), t.color_dark)
	var floors := maxi(1, int(size.y / 0.1))
	for f in floors:
		var y := pos.y + 0.06 + f * 0.1
		for i in 2:
			var x := pos.x + (float(i) - 0.5) * size.x * 0.5
			MeshKit.block(
				st,
				MeshKit.at(Vector3(x, y, pos.z + size.z / 2.0)),
				Vector3(0.05, 0.045, 0.01),
				WINDOW
			)
			var z := pos.z + (float(i) - 0.5) * size.z * 0.5
			MeshKit.block(
				st,
				MeshKit.at(Vector3(pos.x + size.x / 2.0, y, z)),
				Vector3(0.01, 0.045, 0.05),
				WINDOW
			)


static func _city(st: SurfaceTool, t: CommanderVisuals.FactionTheme) -> void:
	_pad(st, PAVE)
	_house(st, Vector3(-0.23, 0.03, -0.26), Vector3(0.26, 0.37, 0.24), false, t)
	_house(st, Vector3(0.18, 0.03, -0.28), Vector3(0.3, 0.22, 0.2), true, t)
	_house(st, Vector3(-0.32, 0.03, 0.22), Vector3(0.16, 0.16, 0.2), true, t)
	_house(st, Vector3(0.33, 0.03, 0.2), Vector3(0.16, 0.12, 0.2), false, t)
	var awning := MeshKit.at(Vector3(0.33, 0.12, 0.31)) * Transform3D(Basis(Vector3.RIGHT, 0.4))
	MeshKit.box(st, awning, Vector3(0.16, 0.012, 0.06), t.color_light)


static func _base(st: SurfaceTool, t: CommanderVisuals.FactionTheme) -> void:
	_pad(st, PAVE)
	MeshKit.block(st, MeshKit.at(Vector3(0, 0.03, -0.23)), Vector3(0.82, 0.2, 0.36), WALL)
	for i in 3:
		var x := -0.27 + 0.27 * i
		var tooth := MeshKit.at(Vector3(x, 0.23, -0.23))
		MeshKit.wedge(st, tooth, Vector3(0.27, 0.1, 0.36), t.color)
		MeshKit.box(
			st, tooth * MeshKit.at(Vector3(-0.13, 0.05, 0)), Vector3(0.012, 0.07, 0.3), WINDOW
		)
	MeshKit.block(st, MeshKit.at(Vector3(0, 0.03, -0.05)), Vector3(0.3, 0.15, 0.012), DARK)
	for i in 5:
		var stripe := MeshKit.at(Vector3(-0.12 + 0.06 * i, 0.19, -0.048))
		MeshKit.block(st, stripe, Vector3(0.03, 0.02, 0.012), t.color_light if i % 2 == 0 else DARK)
	MeshKit.block(st, MeshKit.at(Vector3(0, 0.03, -0.23)), Vector3(0.83, 0.03, 0.37), t.color_dark)
	MeshKit.column(st, MeshKit.at(Vector3(0.33, 0.03, -0.36)), 0.045, 0.04, 0.37, 8, METAL)
	MeshKit.column(st, MeshKit.at(Vector3(0.33, 0.3, -0.36)), 0.047, 0.047, 0.04, 8, t.color)
	MeshKit.block(st, MeshKit.at(Vector3(0.36, 0.03, 0.3)), Vector3(0.1, 0.08, 0.1), t.color_dark)
	MeshKit.block(
		st, MeshKit.at(Vector3(0.36, 0.11, 0.3)), Vector3(0.07, 0.06, 0.07), t.color_light
	)


static func _airport(st: SurfaceTool, t: CommanderVisuals.FactionTheme) -> void:
	_pad(st, PAVE)
	MeshKit.block(st, MeshKit.at(Vector3(0, 0.03, 0.18)), Vector3(0.92, 0.012, 0.3), ASPHALT)
	for i in 4:
		var dash := MeshKit.at(Vector3(-0.33 + 0.22 * i, 0.042, 0.18))
		MeshKit.block(st, dash, Vector3(0.1, 0.004, 0.025), STRIPE)
	for z in [0.05, 0.31]:
		MeshKit.block(st, MeshKit.at(Vector3(0, 0.042, z)), Vector3(0.9, 0.004, 0.012), t.color)
	MeshKit.column(st, MeshKit.at(Vector3(-0.3, 0.03, -0.3)), 0.075, 0.065, 0.28, 6, WALL)
	MeshKit.column(st, MeshKit.at(Vector3(-0.3, 0.3, -0.3)), 0.1, 0.115, 0.07, 8, WINDOW)
	MeshKit.column(st, MeshKit.at(Vector3(-0.3, 0.37, -0.3)), 0.125, 0.04, 0.05, 8, t.color)
	MeshKit.column(st, MeshKit.at(Vector3(-0.3, 0.42, -0.3)), 0.008, 0.006, 0.03, 4, METAL)
	MeshKit.block(
		st, MeshKit.at(Vector3(-0.3, 0.2, -0.3)), Vector3(0.16, 0.025, 0.16), t.color_dark
	)
	MeshKit.block(st, MeshKit.at(Vector3(0.17, 0.03, -0.24)), Vector3(0.48, 0.13, 0.34), WALL)
	MeshKit.roof(st, MeshKit.at(Vector3(0.17, 0.16, -0.24)), Vector3(0.5, 0.12, 0.38), t.color)
	MeshKit.block(st, MeshKit.at(Vector3(0.17, 0.03, -0.068)), Vector3(0.3, 0.11, 0.01), DARK)


static func _port(st: SurfaceTool, t: CommanderVisuals.FactionTheme) -> void:
	MeshKit.block(st, MeshKit.at(Vector3.ZERO), Vector3(0.92, 0.05, 0.92), WALL_SHADE)
	MeshKit.block(st, MeshKit.at(Vector3(0, 0.0, 0.44)), Vector3(0.92, 0.055, 0.04), t.color_dark)
	for x in [-0.3, 0.0, 0.3]:
		MeshKit.column(st, MeshKit.at(Vector3(x, 0.05, 0.38)), 0.025, 0.03, 0.04, 6, DARK)
	for x in [-0.36, -0.2]:
		for z in [-0.36, -0.2]:
			MeshKit.block(st, MeshKit.at(Vector3(x, 0.05, z)), Vector3(0.035, 0.34, 0.035), t.color)
	MeshKit.block(
		st, MeshKit.at(Vector3(-0.28, 0.39, -0.28)), Vector3(0.22, 0.03, 0.22), t.color_dark
	)
	MeshKit.block(st, MeshKit.at(Vector3(-0.28, 0.42, -0.28)), Vector3(0.12, 0.08, 0.12), t.color)
	MeshKit.box(st, MeshKit.at(Vector3(-0.2, 0.47, -0.21)), Vector3(0.01, 0.03, 0.06), WINDOW)
	var jib := MeshKit.at(Vector3(-0.1, 0.52, -0.28))
	MeshKit.box(st, jib, Vector3(0.62, 0.035, 0.045), t.color_light)
	MeshKit.block(st, MeshKit.at(Vector3(-0.42, 0.47, -0.28)), Vector3(0.06, 0.06, 0.08), DARK)
	MeshKit.block(st, MeshKit.at(Vector3(0.14, 0.34, -0.28)), Vector3(0.005, 0.17, 0.005), DARK)
	MeshKit.block(st, MeshKit.at(Vector3(0.14, 0.31, -0.28)), Vector3(0.035, 0.035, 0.035), METAL)
	MeshKit.block(st, MeshKit.at(Vector3(0.24, 0.05, -0.28)), Vector3(0.36, 0.17, 0.26), WALL)
	MeshKit.roof(st, MeshKit.at(Vector3(0.24, 0.22, -0.28)), Vector3(0.38, 0.09, 0.3), t.color)
	MeshKit.block(st, MeshKit.at(Vector3(0.24, 0.05, -0.148)), Vector3(0.14, 0.11, 0.01), DARK)
	MeshKit.block(st, MeshKit.at(Vector3(0.34, 0.05, 0.12)), Vector3(0.1, 0.08, 0.1), t.color_dark)
	MeshKit.block(st, MeshKit.at(Vector3(0.34, 0.05, 0.23)), Vector3(0.1, 0.08, 0.1), t.color_light)
	MeshKit.block(st, MeshKit.at(Vector3(0.34, 0.13, 0.17)), Vector3(0.1, 0.07, 0.1), t.color)


static func _hq(st: SurfaceTool, t: CommanderVisuals.FactionTheme) -> void:
	_pad(st, PAVE)
	MeshKit.block(st, MeshKit.at(Vector3(0, 0.03, -0.27)), Vector3(0.44, 0.3, 0.3), WALL)
	MeshKit.block(st, MeshKit.at(Vector3(0, 0.33, -0.27)), Vector3(0.46, 0.035, 0.32), t.color)
	MeshKit.block(st, MeshKit.at(Vector3(0, 0.03, -0.27)), Vector3(0.45, 0.04, 0.31), t.color_dark)
	MeshKit.block(st, MeshKit.at(Vector3(0, 0.365, -0.28)), Vector3(0.18, 0.24, 0.18), WALL)
	MeshKit.block(st, MeshKit.at(Vector3(0, 0.56, -0.28)), Vector3(0.19, 0.03, 0.19), t.color_dark)
	var spire := MeshKit.at(Vector3(0, 0.59, -0.28), 45)
	MeshKit.column(st, spire, 0.14, 0.0, 0.1, 4, t.color)
	MeshKit.column(st, MeshKit.at(Vector3(0, 0.66, -0.28)), 0.008, 0.007, 0.14, 4, METAL)
	MeshKit.box(st, MeshKit.at(Vector3(0.07, 0.755, -0.28)), Vector3(0.13, 0.075, 0.01), t.color)
	MeshKit.box(
		st, MeshKit.at(Vector3(0.1, 0.755, -0.275)), Vector3(0.04, 0.03, 0.012), t.color_light
	)
	MeshKit.block(st, MeshKit.at(Vector3(0, 0.45, -0.187)), Vector3(0.07, 0.06, 0.01), WINDOW)
	MeshKit.block(st, MeshKit.at(Vector3(0, 0.03, -0.117)), Vector3(0.1, 0.14, 0.01), DARK)
	for x in [-0.17, -0.1, 0.1, 0.17]:
		MeshKit.column(st, MeshKit.at(Vector3(x, 0.03, -0.1)), 0.018, 0.018, 0.27, 6, WALL_SHADE)
	MeshKit.block(st, MeshKit.at(Vector3(0, 0.3, -0.1)), Vector3(0.42, 0.03, 0.05), t.color)
	for x in [-0.14, 0.14]:
		MeshKit.block(st, MeshKit.at(Vector3(x, 0.14, -0.114)), Vector3(0.05, 0.13, 0.008), t.color)
	for side: float in [-1.0, 1.0]:
		var wing := Vector3(side * 0.34, 0.03, -0.14)
		MeshKit.block(st, MeshKit.at(wing), Vector3(0.2, 0.2, 0.42), WALL)
		MeshKit.roof(
			st, MeshKit.at(wing + Vector3(0, 0.2, 0), 90), Vector3(0.44, 0.1, 0.22), t.color
		)
		MeshKit.block(st, MeshKit.at(wing), Vector3(0.21, 0.03, 0.43), t.color_dark)
		for z in [-0.05, 0.08]:
			var pane := Vector3(side * 0.34 - side * 0.1, 0.12, -0.14 + z)
			MeshKit.block(st, MeshKit.at(pane), Vector3(0.012, 0.05, 0.05), WINDOW)
		MeshKit.block(
			st, MeshKit.at(Vector3(side * 0.34, 0.1, 0.071)), Vector3(0.06, 0.05, 0.01), WINDOW
		)
	MeshKit.block(st, MeshKit.at(Vector3(0, 0.03, -0.05)), Vector3(0.24, 0.015, 0.06), WALL_SHADE)
