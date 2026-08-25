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
## The prop shadow: #000 at 0.25, offset +2,+2, no blur.
const CAST_GROUP := '<g transform="translate(2.0 2.0)" opacity="0.25">'
## The props drawn behind the bust, whose contact point is the strap in front.
const SHOULDERED: Array[StringName] = [&"sabre", &"wrench", &"anchor", &"axe", &"hammer"]

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


## Expressions are cast against doctrine, and every way that mapping can rot is
## silent: a name outside the vocabulary falls through to a default face, an eye
## outside the dial's range draws a child or a cyclops, and a column the whole
## roster shares is the "same template avatar" this table exists to break. Five
## brows over twenty-two generals cannot go below five apiece, which is why the
## mouth is the column held to three.
func test_no_expression_is_worn_by_the_whole_roster() -> void:
	var mouths := {}
	var brows := {}
	for id: StringName in FaceSvg.FACES:
		var row: Dictionary = FaceSvg.FACES[id]
		assert_has(FaceSvg.EYE_KINDS, row["eyes"], "%s wears an unknown eye" % id)
		assert_has(FaceSvg.BROW_KINDS, row["brow"], "%s wears an unknown brow" % id)
		assert_has(FaceSvg.MOUTH_KINDS, row["mouth"], "%s wears an unknown mouth" % id)
		assert_between(float(row.get("eye", FaceSvg.EYE_DEFAULT)), 0.82, 1.06, "%s: eye" % id)
		mouths[row["mouth"]] = int(mouths.get(row["mouth"], 0)) + 1
		brows[row["brow"]] = int(brows.get(row["brow"], 0)) + 1
	for mouth: StringName in mouths:
		assert_lte(int(mouths[mouth]), 3, "%s generals share the %s mouth" % [mouths[mouth], mouth])
	for brow: StringName in brows:
		assert_lte(int(brows[brow]), 5, "%s generals share the %s brow" % [brows[brow], brow])


## A nose outside the vocabulary falls through to the tick, so a typo would hand
## a general the face they were being given one of three glyphs to escape.
func test_every_general_names_a_nose_that_is_drawn() -> void:
	var noses: Array[StringName] = [FaceSvg.NOSE_TICK, FaceSvg.NOSE_HOOK, FaceSvg.NOSE_BROAD]
	var counts := {}
	for id: StringName in FaceSvg.FACES:
		var row: Dictionary = FaceSvg.FACES[id]
		var nose: StringName = row.get("nose", FaceSvg.NOSE_DEFAULT)
		assert_has(noses, nose, "%s wears an unknown nose" % id)
		counts[nose] = int(counts.get(nose, 0)) + 1
	assert_eq(counts.size(), noses.size(), "the sheet is not using all three noses")


## The tick is the nose every bust wore before the column existed, so a row that
## names none has to keep drawing it, on the skull's own x. Pinned by its path
## because nothing in `make verify` bakes a portrait, and Vance is where it is
## read: the one general on the sheet at width 1.0, where the skull applies
## nothing and the glyph is the handoff's literal.
func test_the_default_nose_is_the_one_every_bust_wore() -> void:
	var row: Dictionary = FaceSvg.FACES[&"iona_vance"]
	assert_eq(float(row["head"][0]), 1.0, "Vance is the unscaled skull this is read on")
	assert_eq(row.get("nose", FaceSvg.NOSE_DEFAULT), FaceSvg.NOSE_TICK, "Vance wears the default")
	var drawn := FaceSvg.new(CommanderVisuals.faction_themes()[0]).build(&"iona_vance")
	var tick := "M55.0,60 L53.5,65 Q55.0,66.5 57.0,65.2"
	assert_string_contains(drawn, tick, "the default nose is no longer the authored tick")


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
## while every general wears the same shoulders. The window is a patch of plain
## uniform, in from both the shoulder's outer edge and the chest: the silhouette
## owns that edge and it is the heaviest ink on the sheet, a tilted or zoomed
## pose swings it through a fixed window, and a shouldered prop's strap crosses
## the chest — on the five mirrored busts, the lit side of it. Every bust clears
## the floor by 0.045 here.
const LIT_PATCH := Rect2i(16, 226, 12, 12)
const SHADED_PATCH := Rect2i(184, 226, 12, 12)
## Well under the 0.045 the shipped shade measures at its worst, and well over
## the 0.0 a sheet with no shade on it at all would give.
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


## The collar column is data, and a name outside the vocabulary falls through to
## the chevron silently — which is exactly the repeat the column exists to
## break, so it is caught here rather than seen on the sheet.
func test_every_collar_is_one_the_file_can_cut() -> void:
	var collars: Array[StringName] = [
		FaceSvg.COLLAR_V, FaceSvg.COLLAR_MANDARIN, FaceSvg.COLLAR_DOUBLE
	]
	for id: StringName in FaceSvg.FACES:
		var row: Dictionary = FaceSvg.FACES[id]
		assert_has(collars, row.get("collar", FaceSvg.COLLAR_DEFAULT), "%s: unknown collar" % id)


## The chevron is what a row wearing no collar still draws, so the column is
## additive: the default is the V and the V is the handoff's own two paths,
## unchanged. The mandarin general beside it is what says the column is read at
## all — without that half, a `collar` nothing ever cut would pass.
func test_the_default_collar_is_the_handoff_chevron() -> void:
	assert_eq(FaceSvg.COLLAR_DEFAULT, FaceSvg.COLLAR_V, "the default collar is no longer the V")
	var chevron := "M40,90 L55,104 L70,90 L70,94 L55,108 L40,94 Z"
	var drawn := _bust_wearing(FaceSvg.COLLAR_V)
	assert_string_contains(drawn, chevron, "the V is no longer the authored chevron")
	assert_string_contains(drawn, "M44,90 L55,101 L66,90", "the V has lost its neckline")
	assert_false(
		_bust_wearing(FaceSvg.COLLAR_MANDARIN).contains(chevron),
		"the mandarin band still draws the chevron under it"
	)


## The first general on the table wearing this collar, drawn whole.
func _bust_wearing(collar: StringName) -> String:
	var artist := FaceSvg.new(CommanderVisuals.faction_themes()[0])
	for id: StringName in FaceSvg.FACES:
		var row: Dictionary = FaceSvg.FACES[id]
		if row.get("collar", FaceSvg.COLLAR_DEFAULT) == collar:
			return artist.build(id)
	fail_test("no general wears the %s collar" % collar)
	return ""


## Every prop drops the one shadow, at the one offset. The drawing itself is a
## picture and belongs in a capture, but "it casts" is a string fact that goes
## silent when a new prop forgets it, so it is pinned here rather than looked at.
## The group is spelled out rather than composed from the drawing's own
## constants, so a revert fails these tests instead of un-parsing them.
func test_every_prop_casts_its_shadow() -> void:
	for id: StringName in FaceSvg.FACES:
		assert_gt(_casts_in(_portrait(id)), 0, "%s's prop drops no shadow" % id)


## A shouldered prop is drawn behind the bust, so what makes it touch the figure
## is the strap in front of it: both layers draw, and both cast.
func test_a_shouldered_prop_is_carried_by_something_in_front() -> void:
	for id: StringName in FaceSvg.FACES:
		if not SHOULDERED.has(FaceSvg.FACES[id]["prop"]):
			continue
		assert_eq(_casts_in(_portrait(id)), 2, "%s wears no strap over its haft" % id)


## The strap was one diagonal band on every shouldered bust and read as the
## sheet's loudest shared mark, so each rig is its own now. Read off the strap's
## own cast, which is flattened to one tone: what is compared is the geometry
## rather than the faction colour over it.
func test_no_two_shouldered_busts_wear_the_same_strap() -> void:
	var worn := {}
	for id: StringName in FaceSvg.FACES:
		if not SHOULDERED.has(FaceSvg.FACES[id]["prop"]):
			continue
		var strap := _strap_cast(_portrait(id))
		assert_false(strap.is_empty(), "%s draws no strap to compare" % id)
		assert_false(worn.has(strap), "%s wears %s's strap" % [id, worn.get(strap, &"")])
		worn[strap] = id


func _portrait(id: StringName) -> String:
	return FaceSvg.new(CommanderVisuals.faction_themes()[0]).build(id)


func _casts_in(document: String) -> int:
	return document.count(CAST_GROUP)


## The second cast is the strap's: a shouldered prop draws its haft behind the
## bust first, then the rig that carries it.
func _strap_cast(document: String) -> String:
	var haft := document.find(CAST_GROUP)
	var strap := document.find(CAST_GROUP, haft + 1)
	if strap < 0:
		return ""
	var start := strap + CAST_GROUP.length()
	return document.substr(start, document.find("</g>", start) - start)
