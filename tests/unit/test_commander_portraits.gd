extends GutTest
## The commander portrait pipeline: the roster, the face table it is drawn from,
## and the art it bakes to.
##
## In scope for the reason test_figure_sheet.gd is, and CommanderVisuals already
## earns: nothing here builds a Node, and what is under test is an art contract
## that goes quiet when it breaks. A general seated without a FACES row is
## caught here, ahead of the bake that now refuses them rather than drawing the
## neutral silhouette; a general whose .tres lands with no bake run behind it
## ships a flat faction rectangle; and PORTRAIT_SIZE is hand-written on one side
## of the pipeline and derived from the drawing's viewBox on the other, with
## only the offline bake ever comparing them.

const FaceSvg := preload("res://tools/commander_face_svg.gd")

var db: CommanderDB


func before_all() -> void:
	db = CommanderDB.load_default()


## Set equality rather than one-way coverage, so a failure names the side that
## drifted: a general with no face, or a face for a general since retired.
func test_the_face_table_and_the_roster_are_the_same_set() -> void:
	var roster := PackedStringArray()
	for commander in db.playable():
		roster.append(String(commander.id))
	var drawn := PackedStringArray()
	for id: StringName in FaceSvg.FACES:
		drawn.append(String(id))
	roster.sort()
	drawn.sort()
	assert_eq(drawn, roster, "FACES and the commander roster disagree")


func test_the_face_table_answers_for_every_general() -> void:
	for commander in db.playable():
		assert_true(FaceSvg.has_face(commander.id), "%s has no FACES row" % commander.id)


func test_every_commander_has_a_baked_portrait_at_the_pinned_size() -> void:
	for commander in db.all():
		_assert_baked(
			"%s/%s.png" % [CommanderVisuals.PORTRAIT_DIR, commander.id],
			Vector2(CommanderVisuals.PORTRAIT_SIZE)
		)


func test_every_faction_has_an_emblem_at_the_pinned_size() -> void:
	var square := Vector2(CommanderVisuals.EMBLEM_PX, CommanderVisuals.EMBLEM_PX)
	for theme in CommanderVisuals.faction_themes():
		_assert_baked("%s/%s.png" % [CommanderVisuals.FACTION_DIR, theme.key], square)


## Every fallback's last stop: a commander whose art is missing borrows this one,
## so it is the file whose own absence would be invisible.
func test_the_neutral_portrait_path_names_a_file() -> void:
	_assert_baked(CommanderVisuals.NEUTRAL_PORTRAIT_PATH, Vector2(CommanderVisuals.PORTRAIT_SIZE))


## Every bust and emblem is minified — hardest into the 31px HUD chip and the
## 28px speech bust — so ART_FILTER samples them through their mip chain. A
## texture imported without one is sampled at level 0 and shimmers, and a fresh
## bake writes a default .import with mipmaps off, so the flag would go quiet on
## the twenty-third general rather than fail.
func test_the_art_filter_is_the_mipmapped_one() -> void:
	assert_eq(CommanderVisuals.ART_FILTER, CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS)


## Both doors, because they answer differently: ResourceLoader reads the import
## cache, so it alone would still say yes over a source file that has been
## deleted, and FileAccess alone would say yes over one that never imported.
func _assert_baked(path: String, size: Vector2) -> void:
	assert_true(FileAccess.file_exists(path), "nothing baked at %s" % path)
	assert_true(ResourceLoader.exists(path), "%s has not been imported" % path)
	if not ResourceLoader.exists(path):
		return
	var texture: Texture2D = load(path)
	assert_eq(texture.get_size(), size, "%s is not the pinned size" % path)
	assert_true(texture.get_image().has_mipmaps(), "%s imported without mipmaps" % path)
