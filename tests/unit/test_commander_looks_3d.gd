extends GutTest
## CommanderLooks3D and CommanderFigure3D: every general has a look the 3D
## figure knows how to draw, and the figure it builds stands on the ground at
## the height a general is meant to have. `rest_mesh` is a Resource built with
## no Node, so the model contract is checked without a scene.

const TOLERANCE := 0.005
const FOOTPRINT := 0.42


func _generals() -> Array[CommanderType]:
	var generals: Array[CommanderType] = []
	for commander in Fixture.commander_db().all():
		if commander.id != CommanderType.NEUTRAL_ID:
			generals.append(commander)
	return generals


func test_every_general_has_a_look() -> void:
	var generals := _generals()
	assert_eq(generals.size(), CommanderLooks3D.LOOKS.size())
	for commander in generals:
		assert_true(CommanderLooks3D.has_look(commander.id), String(commander.id))


func test_every_look_is_in_the_figures_vocabulary() -> void:
	for id: StringName in CommanderLooks3D.LOOKS:
		var look := CommanderLooks3D.look_of(id)
		var what := String(id)
		assert_typeof(look[&"skin_color"], TYPE_COLOR, what)
		assert_typeof(look[&"hair_color"], TYPE_COLOR, what)
		assert_has(CommanderFigure3D.STYLES, look[&"style"], what + " style")
		assert_has(CommanderFigure3D.ACCESSORIES, look[&"acc"], what + " acc")
		assert_has(CommanderFigure3D.ACCESSORIES, look[&"acc2"], what + " acc2")
		assert_has(CommanderFigure3D.FACIALS, look[&"facial"], what + " facial")
		assert_has(CommanderFigure3D.COLLARS, look[&"collar"], what + " collar")
		assert_has(CommanderFigure3D.CHESTS, look[&"chest"], what + " chest")
		assert_has(CommanderProps3D.PROPS, look[&"prop"], what + " prop")


func test_an_unknown_general_is_the_neutral_officer() -> void:
	assert_false(CommanderLooks3D.has_look(&"nobody"))
	assert_false(CommanderLooks3D.has_look(CommanderType.NEUTRAL_ID))
	var neutral := CommanderLooks3D.look_of(CommanderType.NEUTRAL_ID)
	assert_eq(CommanderLooks3D.look_of(&"nobody"), neutral)
	assert_has(CommanderFigure3D.STYLES, neutral[&"style"])
	assert_eq(neutral[&"prop"], &"none")


func test_every_figure_stands_on_the_ground_inside_its_cell() -> void:
	for commander in _generals():
		var look := CommanderLooks3D.look_of(commander.id)
		var mesh := CommanderFigure3D.rest_mesh(look, CommanderVisuals.theme_for(commander))
		var box := mesh.get_aabb()
		var what := String(commander.id)
		assert_between(box.position.y, -TOLERANCE, TOLERANCE, what + " feet on the ground")
		var top := CommanderFigure3D.HEIGHT
		assert_between(box.end.y, top - 0.04, top + 0.02, what + " height")
		assert_gte(box.position.x, -FOOTPRINT, what + " reaches past -X")
		assert_lte(box.end.x, FOOTPRINT, what + " reaches past +X")
		assert_gte(box.position.z, -FOOTPRINT, what + " reaches past -Z")
		assert_lte(box.end.z, FOOTPRINT, what + " reaches past +Z")


func test_a_general_is_taller_than_an_infantry_squad() -> void:
	var infantry := UnitModels3D.mesh_for(&"infantry", CommanderVisuals.theme_for(null))
	assert_gt(CommanderFigure3D.HEIGHT, infantry.get_aabb().end.y)


func test_the_head_is_about_two_fifths_of_the_figure() -> void:
	var share := CommanderFigure3D.HEAD_TOP / CommanderFigure3D.HEIGHT
	assert_between(share, 0.35, 0.45)


func test_every_part_has_a_pivot_on_a_known_parent() -> void:
	for part in CommanderFigure3D.PARTS:
		assert_true(CommanderFigure3D.PIVOTS.has(part), String(part))
		var parent: StringName = CommanderFigure3D.PARENTS[part]
		assert_true(parent.is_empty() or CommanderFigure3D.PARTS.has(parent), String(part))
