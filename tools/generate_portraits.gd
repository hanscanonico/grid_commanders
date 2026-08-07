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
##   make portraits    (headless, writes under assets/portraits/)

## The rasterised size, as a multiple of the handoff's 110x134 drawing units.
## Twice the largest surface that shows a portrait (the power banner's 104x108
## field), so every screen scales the art down rather than up.
const PORTRAIT_SCALE := 2.0
const EMBLEM_PX := 64
const OUTLINE := Color(0.075, 0.094, 0.106)

const FaceSvg := preload("res://tools/commander_face_svg.gd")


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(CommanderVisuals.PORTRAIT_DIR)
	)
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(CommanderVisuals.FACTION_DIR)
	)
	var db := CommanderDB.load_default()
	var count := 0
	for commander in db.all():
		var image := _draw_portrait(commander)
		if image == null:
			push_error("generate_portraits: could not rasterise %s" % commander.id)
			quit(1)
			return
		if image.get_size() != CommanderVisuals.PORTRAIT_SIZE:
			push_error(
				(
					"generate_portraits: %s rasterised at %s, but PORTRAIT_SIZE is %s"
					% [commander.id, image.get_size(), CommanderVisuals.PORTRAIT_SIZE]
				)
			)
			quit(1)
			return
		var path := "%s/%s.png" % [CommanderVisuals.PORTRAIT_DIR, commander.id]
		var err := image.save_png(ProjectSettings.globalize_path(path))
		if err != OK:
			push_error("generate_portraits: cannot write %s: %s" % [path, error_string(err)])
			quit(1)
			return
		count += 1
	for theme: CommanderVisuals.FactionTheme in CommanderVisuals.faction_themes():
		var emblem := _draw_emblem(theme)
		var emblem_path := "%s/%s.png" % [CommanderVisuals.FACTION_DIR, theme.key]
		var emblem_err := emblem.save_png(ProjectSettings.globalize_path(emblem_path))
		if emblem_err != OK:
			push_error(
				"generate_portraits: cannot write %s: %s" % [emblem_path, error_string(emblem_err)]
			)
			quit(1)
			return
	print("generate_portraits: wrote %d portraits and 4 emblems" % count)
	quit()


# --- portraits ---------------------------------------------------------------


## One general's bust. A commander the handoff has no face spec for falls back to
## the featureless silhouette rather than failing the bake. That is the empty
## seat's own portrait, so it passes quietly; for anyone else it means a general
## added ahead of their art would ship reading as "No Commander", which the bake
## says out loud rather than reporting as a success.
func _draw_portrait(commander: CommanderType) -> Image:
	var svg := ""
	if FaceSvg.has_face(commander.id):
		svg = FaceSvg.new(CommanderVisuals.theme_for(commander)).build(commander.id)
	else:
		if commander.id != CommanderType.NEUTRAL_ID:
			push_warning(
				(
					"generate_portraits: no face spec for %s — baking the neutral silhouette"
					% commander.id
				)
			)
		var neutral := CommanderVisuals.theme_for_key(CommanderVisuals.NEUTRAL_KEY)
		svg = FaceSvg.new(neutral).build_neutral()
	var image := Image.new()
	if image.load_svg_from_string(svg, PORTRAIT_SCALE) != OK:
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
