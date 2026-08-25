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


## The head column is the only thing separating one bust from another before the
## hair goes on, and every way it can go wrong is silent: a row that forgot it
## draws the shared skull, a jaw outside the vocabulary falls through to the
## round one, and a row copied off a neighbour hands two generals one face. All
## three come from a data edit, so this is where they are caught.
func test_every_general_is_drawn_on_a_skull_of_their_own() -> void:
	var jaws: Array[StringName] = [FaceSvg.JAW_ROUND, FaceSvg.JAW_SQUARE, FaceSvg.JAW_TAPERED]
	var seen := {}
	for id: StringName in FaceSvg.FACES:
		var row: Dictionary = FaceSvg.FACES[id]
		assert_true(row.has("head"), "%s is drawn on the shared skull" % id)
		var head: Array = row.get("head", FaceSvg.HEAD_DEFAULT)
		assert_eq(
			head.size(), FaceSvg.HEAD_DEFAULT.size(), "%s: head is [width, jaw, crown, spread]" % id
		)
		assert_between(float(head[0]), 0.86, 1.14, "%s: head width" % id)
		assert_has(jaws, head[1], "%s stands an unknown jaw" % id)
		assert_between(float(head[2]), -3.0, 3.0, "%s: crown" % id)
		assert_between(float(head[3]), 0.9, 1.1, "%s: eye spread" % id)
		var key := str(head)
		assert_false(seen.has(key), "%s and %s share a skull" % [id, seen.get(key, &"")])
		seen[key] = id


## The default is the one head the handoff authored, so a row that names none
## still draws the bust every general shared before this table grew a column —
## which is what the neutral silhouette has always been and must stay. The
## numbers are the handoff's, printed as the floats they are now composed from;
## the raster is unchanged, which is what `make portraits` shows.
func test_the_default_skull_is_the_handoff_head() -> void:
	var drawn := FaceSvg.new(CommanderVisuals.faction_themes()[0]).build_neutral()
	var crown := "M32.0,52 Q32.0,27.0 55.0,27.0 Q78.0,27.0 78.0,52"
	var handoff := crown + " L78.0,60 Q78.0,84 55.0,89 Q32.0,84 32.0,60 Z"
	assert_string_contains(drawn, handoff, "the neutral bust is no longer the authored head")


## The shade is drawn in the bust's own coordinates, and the five mirrored poses
## are where that goes wrong invisibly: a shade path that flips with the pose
## lights a quarter of the roster from the other side, and the sheet reads as
## two sheets. So every bust is measured — the lit shoulder against the shaded
## one, which must come out the same way round on all of them. Read off the
## uniform rather than the face because a full beard covers the shaded cheek,
## while every general wears the same shoulders.
const LIT_PATCH := Rect2i(16, 232, 32, 24)
const SHADED_PATCH := Rect2i(172, 232, 32, 24)
## Well under the ~0.077 the shipped shade measures, and well over the 0.0 a
## sheet with no shade on it at all would give.
const SHADE_FLOOR := 0.01


func test_every_bust_is_lit_from_the_same_side() -> void:
	for commander in db.playable():
		var path := "%s/%s.png" % [CommanderVisuals.PORTRAIT_DIR, commander.id]
		var texture: Texture2D = load(path)
		assert_not_null(texture, "%s has no portrait to read" % commander.id)
		if texture == null:
			continue
		var image := texture.get_image()
		var delta := _mean_luminance(image, LIT_PATCH) - _mean_luminance(image, SHADED_PATCH)
		assert_gt(delta, SHADE_FLOOR, "%s is not lit from the sheet's side" % commander.id)


func _mean_luminance(image: Image, patch: Rect2i) -> float:
	var total := 0.0
	for y: int in range(patch.position.y, patch.end.y):
		for x: int in range(patch.position.x, patch.end.x):
			total += image.get_pixel(x, y).get_luminance()
	return total / float(patch.size.x * patch.size.y)
