extends GutTest
## The commander art the game loads: that it is all there, at the pinned size,
## sampled the way the board is, drawn on whole texels, and lit from one side.
##
## Everything here reads a file under assets/portraits. The table the busts are
## drawn from lives in `generators/portraits` now and is linted by that
## package's own suites; what stays in the engine's suite is the contract the
## engine depends on — a general whose .tres lands with no bake behind it ships
## a flat faction rectangle, and PORTRAIT_SIZE is hand-written on one side of
## the pipeline and drawn from a grid on the other.

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


## The emblems keep their mip chain: they are the one piece of commander art
## still drawn at a fraction of its own size (a 64px badge at 22), so
## EMBLEM_FILTER samples them through it and an import without one shimmers.
func test_every_faction_has_an_emblem_at_the_pinned_size() -> void:
	var square := Vector2(CommanderVisuals.EMBLEM_PX, CommanderVisuals.EMBLEM_PX)
	for theme in CommanderVisuals.faction_themes():
		_assert_baked("%s/%s.png" % [CommanderVisuals.FACTION_DIR, theme.key], square, true)


## Every fallback's last stop: a commander whose art is missing borrows this one,
## so it is the file whose own absence would be invisible.
func test_the_neutral_portrait_path_names_a_file() -> void:
	_assert_baked(CommanderVisuals.NEUTRAL_PORTRAIT_PATH, Vector2(CommanderVisuals.PORTRAIT_SIZE))


## The busts are pixel art on their own grid, so they are sampled the way the
## board is: nearest, with no mip chain to fall between the rungs of the scale
## ladder. The emblems are the exception and keep the mipmapped filter — a 64px
## badge drawn at 22 has no whole rung under it.
func test_a_general_s_art_is_sampled_nearest() -> void:
	assert_eq(CommanderVisuals.ART_FILTER, CanvasItem.TEXTURE_FILTER_NEAREST)
	assert_eq(CommanderVisuals.EMBLEM_FILTER, CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS)


## The ladder itself: whole numbers, never under one, and the largest that fits.
## A pure function, so it is measured here rather than by looking at a field.
func test_the_scale_ladder_is_whole_numbers_that_fit() -> void:
	var bust := CommanderVisuals.PORTRAIT_SIZE
	assert_eq(CommanderVisuals.art_scale(Vector2(bust), bust), 1)
	assert_eq(CommanderVisuals.art_scale(Vector2(bust) * 2.0, bust), 2)
	assert_eq(CommanderVisuals.art_scale(Vector2(bust) * 2.9, bust), 2)
	assert_eq(
		CommanderVisuals.art_scale(Vector2(bust.x * 4, bust.y * 2), bust),
		2,
		"the ladder is the tighter of the two axes"
	)


## A field smaller than the art still draws it at 1:1 and clips. Half a pixel of
## a face is worse than a chest cut off, which is what the field's clipping and
## `UiKit._place_bust`'s top-hung placement are for.
func test_a_field_too_small_still_draws_whole_texels() -> void:
	var bust := CommanderVisuals.PORTRAIT_SIZE
	assert_eq(CommanderVisuals.art_scale(Vector2(96, 96), bust), 1)
	assert_eq(CommanderVisuals.art_scale(Vector2.ZERO, bust), 1)
	assert_eq(CommanderVisuals.art_scale(Vector2(64, 64), Vector2i.ZERO), 1)


## The field a whole bust needs is the art's own measurements and not a number
## anyone chose: the drawing's full width, and every row down to the jaw. Pinned
## here because a rebake on another grid moves both, and a stale copy of either
## is invisible — it ships as a general cropped at the ears.
func test_the_whole_bust_field_is_the_art_s_own_size() -> void:
	var field := CommanderVisuals.WHOLE_BUST_FIELD
	assert_eq(field.x, CommanderVisuals.PORTRAIT_SIZE.x, "a bust field is the drawing's width")
	assert_eq(field.y, CommanderVisuals.FACE_REGION.end.y, "a bust field reaches the jaw")
	assert_lt(field.y, CommanderVisuals.PORTRAIT_SIZE.y, "the chest is what a short field loses")


## Which fields may show one, exactly: the art's own shape and anything over it,
## and neither of the two ways to fall one pixel under. A field that fails this
## shows the baked chip instead (`UiKit._place_bust`), which is the whole reason
## the chip is baked.
func test_only_a_field_that_holds_the_art_shows_a_whole_bust() -> void:
	var field := Vector2(CommanderVisuals.WHOLE_BUST_FIELD)
	assert_true(CommanderVisuals.fits_whole_bust(field), "the art's own shape holds it")
	assert_true(CommanderVisuals.fits_whole_bust(Vector2(CommanderVisuals.PORTRAIT_SIZE)))
	assert_false(CommanderVisuals.fits_whole_bust(field - Vector2(1, 0)), "a pixel too narrow")
	assert_false(CommanderVisuals.fits_whole_bust(field - Vector2(0, 1)), "a pixel too short")
	assert_false(CommanderVisuals.fits_whole_bust(Vector2.ZERO), "an unplaced field")


## Every field the shell states out loud draws its art whole: the drawing it
## falls to — the bust where the field holds one, the baked chip otherwise — at
## a whole rung of the ladder, and that rung fits inside the field on both axes.
## A field is allowed slack (`CommanderCard.CHIP_BAND` is the chip's 93 plus
## three pixels of air), never a fraction of a texel and never a rung that
## overflows. The two private fields (the power banner and the roster tile) are
## read off the captured frames instead.
func test_every_named_bust_field_is_whole_texels() -> void:
	var fields := {
		"CommanderCard.WHOLE_BUST_BAND":
		Vector2(CommanderVisuals.WHOLE_BUST_FIELD.x, CommanderCard.WHOLE_BUST_BAND),
		"CommanderCard.CHIP_BAND": Vector2(CommanderCard.CHIP_BAND, CommanderCard.CHIP_BAND),
		"VictoryLockup.PORTRAIT": Vector2(VictoryLockup.PORTRAIT, VictoryLockup.PORTRAIT),
		"UiTheme.HUD_PORTRAIT": Vector2(UiTheme.HUD_PORTRAIT, UiTheme.HUD_PORTRAIT),
		"MissionSpeech.BUST": Vector2(MissionSpeech.BUST, MissionSpeech.BUST),
	}
	for label: String in fields:
		var field: Vector2 = fields[label]
		var drawing := (
			CommanderVisuals.PORTRAIT_SIZE
			if CommanderVisuals.fits_whole_bust(field)
			else CommanderVisuals.FACE_SIZE
		)
		var rung := CommanderVisuals.art_scale(field, drawing)
		assert_gte(rung, 1, "%s draws its art at no whole rung" % label)
		var drawn := Vector2(drawing) * rung
		assert_lte(drawn.x, field.x, "%s is narrower than the art it draws" % label)
		assert_lte(drawn.y, field.y, "%s is shorter than the art it draws" % label)


## The chip rung has one owner. Both surfaces that frame a chip take their square
## from `CHIP_FIELD` rather than writing the multiple down again, and the HUD
## chip is the art's own size — a drifted copy of either is invisible until the
## chip sits in its field with slack on two edges.
func test_the_chip_surfaces_take_their_field_from_the_authority() -> void:
	var chip := CommanderVisuals.CHIP_FIELD
	assert_eq(chip, CommanderVisuals.FACE_SIZE * CommanderVisuals.CHIP_ZOOM)
	assert_eq(
		CommanderVisuals.art_scale(Vector2(chip), CommanderVisuals.FACE_SIZE),
		CommanderVisuals.CHIP_ZOOM,
		"the chip field is exactly one rung of the ladder"
	)
	assert_eq(VictoryLockup.PORTRAIT, chip.x, "the lockup is the chip field")
	assert_eq(
		CommanderCard.CHIP_BAND - chip.y,
		CommanderVisuals.CHIP_ZOOM,
		"the card's band is the chip field plus one texel of air"
	)
	assert_eq(UiTheme.HUD_PORTRAIT, CommanderVisuals.FACE_SIZE.x, "the HUD draws a chip at 1x")


## Every general has a chip beside their bust, at the size the small surfaces
## draw it one texel to one pixel. A new file's `.import` is the trap this
## catches: Godot has never seen it, so a bake that skipped the reimport ships a
## texture the tree cannot load.
func test_every_commander_has_a_baked_face_chip() -> void:
	for commander in db.all():
		_assert_baked(
			"%s/%s.png" % [CommanderVisuals.FACE_DIR, commander.id],
			Vector2(CommanderVisuals.FACE_SIZE)
		)


## The chip is the face region repainted on its own grid, so the region's side is
## a whole number of chips across. A region that stopped dividing would put the
## chip half a pixel off the head it draws again. That every general gets a chip
## of that size back out of `face_for` is `test_commander_face.gd`'s roster loop,
## not a second one here.
func test_the_chip_is_the_face_region_on_its_own_grid() -> void:
	var region := CommanderVisuals.FACE_REGION
	assert_eq(region.size.x, region.size.y)
	assert_eq(region.size.x % CommanderVisuals.FACE_SIZE.x, 0)


## Both doors, because they answer differently: ResourceLoader reads the import
## cache, so it alone would still say yes over a source file that has been
## deleted, and FileAccess alone would say yes over one that never imported.
##
## The mip chain is read here rather than beside one caller because it is the
## import setting a rebake silently resets: a bust or a chip that came back with
## one is sampled between the rungs of the scale ladder and goes soft, and only
## the emblems are meant to have it.
func _assert_baked(path: String, size: Vector2, mipmapped: bool = false) -> void:
	assert_true(FileAccess.file_exists(path), "nothing baked at %s" % path)
	assert_true(ResourceLoader.exists(path), "%s has not been imported" % path)
	if not ResourceLoader.exists(path):
		return
	var texture: Texture2D = load(path)
	assert_eq(texture.get_size(), size, "%s is not the pinned size" % path)
	if mipmapped:
		assert_true(texture.get_image().has_mipmaps(), "%s imported without mipmaps" % path)
	else:
		assert_false(texture.get_image().has_mipmaps(), "%s imported with mipmaps" % path)


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
const LIT_PATCH := Rect2i(11, 121, 6, 6)
const SHADED_PATCH := Rect2i(93, 121, 6, 6)
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
		var delta := _patch_luminance(image, LIT_PATCH) - _patch_luminance(image, SHADED_PATCH)
		assert_gt(delta, SHADE_FLOOR, "%s is not lit from the sheet's side" % commander.id)


## The median rather than the mean, because a prop reaches into a corner of the
## lit patch on some busts — Lyra Quill's open book — and a mean lets that ink
## outvote the cloth the patch is there to read.
func _patch_luminance(image: Image, patch: Rect2i) -> float:
	var values: Array[float] = []
	for y: int in range(patch.position.y, patch.end.y):
		for x: int in range(patch.position.x, patch.end.x):
			values.append(image.get_pixel(x, y).get_luminance())
	values.sort()
	var half := values.size() / 2
	return 0.5 * (values[half - 1] + values[half])
