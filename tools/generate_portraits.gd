extends SceneTree
## Bakes the commander portraits and faction emblems: one heroic bust per
## general, a neutral silhouette for an empty seat, and four 64x64 emblems.
##
## The portraits are the "Heroic Commander Portraits" design handoff, drawn as
## SVG by tools/commander_face_svg.gd and rasterised here — each general with a
## pose of their own, a dramatic faction-coloured backdrop, a signature prop, and
## a chest-up crop that breaks the framed window they sit in. Project-original
## vector art, generated from data (CC0, no third-party pixels), so a balance or
## roster change never waits on an art pass.
##
## Faction colours are read from CommanderVisuals, the one authority on them, so
## the baked art and the UI that frames it can never disagree.  Run with:
##   make portraits          (headless, writes under assets/portraits/)
##   make portraits-check    (bakes in memory, byte-diffs what is committed)

## The rasterised size, as a multiple of the handoff's 110x134 drawing units.
## Twice the largest surface that shows a portrait (the power banner's 104x108
## field), so every screen scales the art down rather than up.
const PORTRAIT_SCALE := 2.0
const EMBLEM_PX := 64
const OUTLINE := Color(0.075, 0.094, 0.106)

const FaceSvg := preload("res://tools/commander_face_svg.gd")


func _init() -> void:
	var images := _bake()
	if images.is_empty():
		return
	if OS.get_cmdline_user_args().has("--check"):
		_check(images)
		return
	_write(images)


## Every file the bake owns, keyed by the path it belongs at — drawn in memory,
## so the same pass answers both writing and checking. Empty when a portrait
## could not be drawn: the run is already reported and quit by then.
func _bake() -> Dictionary[String, Image]:
	var images: Dictionary[String, Image] = {}
	var db := CommanderDB.load_default()
	for commander in db.all():
		var image := _draw_portrait(commander)
		if image == null:
			quit(1)
			return {}
		if image.get_size() != CommanderVisuals.PORTRAIT_SIZE:
			push_error(
				(
					"generate_portraits: %s rasterised at %s, but PORTRAIT_SIZE is %s"
					% [commander.id, image.get_size(), CommanderVisuals.PORTRAIT_SIZE]
				)
			)
			quit(1)
			return {}
		images["%s/%s.png" % [CommanderVisuals.PORTRAIT_DIR, commander.id]] = image
	for theme: CommanderVisuals.FactionTheme in CommanderVisuals.faction_themes():
		images["%s/%s.png" % [CommanderVisuals.FACTION_DIR, theme.key]] = _draw_emblem(theme)
	return images


func _write(images: Dictionary[String, Image]) -> void:
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(CommanderVisuals.PORTRAIT_DIR)
	)
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(CommanderVisuals.FACTION_DIR)
	)
	for path in images:
		var err := images[path].save_png(ProjectSettings.globalize_path(path))
		if err != OK:
			push_error("generate_portraits: cannot write %s: %s" % [path, error_string(err)])
			quit(1)
			return
	var emblems := CommanderVisuals.faction_themes().size()
	print(
		"generate_portraits: wrote %d portraits and %d emblems" % [images.size() - emblems, emblems]
	)
	quit()


## Compares a fresh bake against the committed bytes and writes nothing, so the
## question "does regenerating this art reproduce it?" has an answer that is run
## rather than argued.
func _check(images: Dictionary[String, Image]) -> void:
	var stale := PackedStringArray()
	for path in images:
		var committed := FileAccess.get_file_as_bytes(path)
		if committed.is_empty():
			stale.append("%s: nothing baked there" % path)
		elif images[path].save_png_to_buffer() != committed:
			stale.append("%s: differs from a fresh bake" % path)
	if not stale.is_empty():
		for line in stale:
			push_error("generate_portraits: %s" % line)
		quit(1)
		return
	print("generate_portraits: %d files match the committed bake" % images.size())
	quit()


# --- portraits ---------------------------------------------------------------


## One general's bust. The featureless silhouette is the empty seat's own
## portrait, so that id draws it quietly; anyone else reaching it is a general
## seated ahead of their art, who would ship reading as "No Commander" — the
## bake refuses rather than reporting it as a success.
func _draw_portrait(commander: CommanderType) -> Image:
	var svg := ""
	if FaceSvg.has_face(commander.id):
		svg = FaceSvg.new(CommanderVisuals.theme_for(commander)).build(commander.id)
	else:
		if commander.id != CommanderType.NEUTRAL_ID:
			push_error("generate_portraits: no face spec for %s" % commander.id)
			return null
		var neutral := CommanderVisuals.theme_for_key(CommanderVisuals.NEUTRAL_KEY)
		svg = FaceSvg.new(neutral).build_neutral()
	var image := Image.new()
	if image.load_svg_from_string(svg, PORTRAIT_SCALE) != OK:
		push_error("generate_portraits: could not rasterise %s" % commander.id)
		return null
	return image


# --- emblems -----------------------------------------------------------------


func _draw_emblem(theme: CommanderVisuals.FactionTheme) -> Image:
	var img := Image.create(EMBLEM_PX, EMBLEM_PX, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := 32
	match theme.key:
		&"meridian":  # hollow diamond
			_diamond(img, c, c, 26, OUTLINE)
			_diamond(img, c, c, 21, theme.color)
			_diamond(img, c, c, 11, OUTLINE)
		&"iron":  # solid diamond
			_diamond(img, c, c, 26, OUTLINE)
			_diamond(img, c, c, 21, theme.color)
		&"aurora":  # four-point star
			_diamond(img, c, c, 27, OUTLINE)
			_diamond(img, c, c, 22, theme.color)
			_band(img, c - 3, 6, 6, 52, theme.color)
			_band(img, 6, c - 3, 52, 6, theme.color)
		&"verdant":  # pennant
			_band(img, 18, 8, 6, 48, OUTLINE)
			for y in range(10, 40):
				for x in range(24, 54):
					if (x - 24) < (54 - 24) - absi(y - 22) * 1:
						img.set_pixel(x, y, theme.color)
	return img


# --- primitives --------------------------------------------------------------


func _band(img: Image, x: int, y: int, w: int, h: int, color: Color) -> void:
	var rect := Rect2i(x, y, w, h).intersection(Rect2i(0, 0, img.get_width(), img.get_height()))
	if rect.has_area():
		img.fill_rect(rect, color)


func _diamond(img: Image, cx: int, cy: int, r: int, color: Color) -> void:
	for y in range(maxi(0, cy - r), mini(img.get_height(), cy + r + 1)):
		for x in range(maxi(0, cx - r), mini(img.get_width(), cx + r + 1)):
			if absi(x - cx) + absi(y - cy) <= r:
				img.set_pixel(x, y, color)
