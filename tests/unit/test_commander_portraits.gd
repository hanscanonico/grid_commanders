extends GutTest
## The commander art the game loads: that it is all there, at the pinned size,
## imported with the mip chain, and lit from one side.
##
## Everything here reads a file under assets/portraits. The table the busts are
## drawn from lives in `generators/portraits` now and is linted by that
## package's own suites; what stays in the engine's suite is the contract the
## engine depends on — a general whose .tres lands with no bake behind it ships
## a flat faction rectangle, and PORTRAIT_SIZE is hand-written on one side of
## the pipeline and drawn from a viewBox on the other.

var db: CommanderDB


func before_all() -> void:
	db = Fixture.commander_db()


func test_every_commander_has_a_baked_portrait_at_the_pinned_size() -> void:
	for commander in db.all():
		_assert_baked(
			"%s/%s.png" % [CommanderVisuals.PORTRAIT_DIR, commander.id],
			Vector2(CommanderVisuals.PORTRAIT_SIZE)
		)


## Set equality rather than one-way coverage, so a failure names the side that
## drifted: a general with no bust, or a bust for a general since retired. The
## generator fails the same way from its own end, against what it emits.
func test_the_baked_sheet_and_the_roster_are_the_same_set() -> void:
	var baked := PackedStringArray()
	for file in DirAccess.get_files_at(CommanderVisuals.PORTRAIT_DIR):
		if file.ends_with(".png"):
			baked.append(file.get_basename())
	var roster := PackedStringArray()
	for commander in db.all():
		roster.append(String(commander.id))
	baked.sort()
	roster.sort()
	assert_eq(baked, roster, "the baked busts and the commander roster disagree")


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


## The shade is drawn in the bust's own coordinates, and the five mirrored poses
## are where that goes wrong invisibly: a shade that flips with the pose lights a
## quarter of the roster from the other side, and the sheet reads as two sheets.
## So every bust is measured — the lit shoulder against the shaded one, which
## must come out the same way round on all of them. Read off the uniform rather
## than the face because a full beard covers the shaded cheek, while every
## general wears the same shoulders. The two patches are exact mirror images
## about the bust's centre line, so what the difference reports is the shade and
## never the shoulder's own shape — and they sit in off that outer edge, because
## the silhouette owns it and is the heaviest ink on the sheet.
const LIT_PATCH := Rect2i(22, 242, 12, 12)
const SHADED_PATCH := Rect2i(186, 242, 12, 12)
## Well under what the shipped shade measures at its worst, and well over the 0.0
## a sheet with no shade on it at all would give.
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
