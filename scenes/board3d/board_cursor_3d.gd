class_name BoardCursor3D
extends MeshInstance3D
## The cursor on the 3D board: four corner brackets standing just off the cell's
## surface, gliding after the 2D cursor it mirrors and breathing slowly so it can
## be found on a busy board. Unshaded, so neither the sun nor the fog dims it.
## Two-tone: each cream bar sits inside a dark one, so it reads on a cream dock
## as well as on grass or sea.

const COLOUR := Color("#fff6d8")
const OUTLINE := Color("#1b1f29")
const RIM := 0.022
const ARM := 0.26
const BAR := 0.055
const LIFT := 0.02
const GLIDE_RATE := 18.0
const PULSE := 0.05


func _init() -> void:
	var st := MeshKit.begin()
	# Every dark shell goes in before any cream: with no depth test the later
	# triangles draw over the earlier, so the cream bars read as one unbroken
	# L inside a dark rim rather than two boxes with a seam where they meet.
	for pass_rim: float in [RIM, 0.0]:
		for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			var tip := Vector3(corner.x * 0.5, 0, corner.y * 0.5)
			var along_x := Vector3(
				tip.x - corner.x * ARM / 2.0, BAR / 2.0, tip.z - corner.y * BAR / 2.0
			)
			var along_z := Vector3(
				tip.x - corner.x * BAR / 2.0, BAR / 2.0, tip.z - corner.y * ARM / 2.0
			)
			_bar(st, along_x, Vector3(ARM, BAR, BAR), pass_rim)
			_bar(st, along_z, Vector3(BAR, BAR, ARM), pass_rim)
	mesh = st.commit()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.no_depth_test = true
	material.render_priority = 1
	material_override = material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## One bar: grown by `rim` on every side in the dark, or bare in the cream.
static func _bar(st: SurfaceTool, centre: Vector3, size: Vector3, rim: float) -> void:
	var colour := OUTLINE if rim > 0.0 else COLOUR
	MeshKit.box(st, MeshKit.at(centre), size + Vector3.ONE * rim * 2.0, colour)


## Jumps to `goal` with no glide — the first frame after a flip.
func snap(goal: Vector3) -> void:
	position = goal + Vector3.UP * LIFT


func follow(delta: float, goal: Vector3, clock: float) -> void:
	position = position.lerp(goal + Vector3.UP * LIFT, 1.0 - exp(-delta * GLIDE_RATE))
	scale = Vector3.ONE * (1.0 + PULSE * sin(clock * 4.0))
