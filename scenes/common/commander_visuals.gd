class_name CommanderVisuals
extends RefCounted
## Presentation adapter for commanders: turns the sim-side CommanderType (id,
## faction, text, numbers) into the things a scene needs to draw one — a portrait
## texture, a faction colour theme, an emblem — without any of that ever entering
## core/.
##
## This is the single authority on commander styling. The card, the battle HUD
## chip, and the power banner all ask here rather than each keeping their own
## copy of the four faction colours, exactly as the resolvers each own one rule.
## The offline portrait generator asks here too, so the art it bakes and the art
## the UI expects can never disagree about which colour a faction is.
##
## No Node, no scene path — but this is scenes/, not core/, so loading a
## Texture2D and caching it is allowed here where it would not be there.


## A faction's colour identity. Colour is always reinforced by the emblem and the
## faction name (see the plan's "faction first, never colour alone" principle),
## so nothing here is asked to carry meaning on hue alone.
class FactionTheme:
	extends RefCounted

	var key: StringName
	var display: String
	## The field colour behind the portrait and the name band.
	var color: Color
	## A darker shade for borders and the pressed/inactive state.
	var color_dark: Color
	## A lighter shade for the diagonal field's second stripe.
	var color_light: Color
	## Text drawn on top of `color`.
	var ink: Color

	func _init(
		p_key: StringName,
		p_display: String,
		p_color: Color,
		p_dark: Color,
		p_light: Color,
		p_ink: Color
	) -> void:
		key = p_key
		display = p_display
		color = p_color
		color_dark = p_dark
		color_light = p_light
		ink = p_ink


## Warm rules-panel paper and the ink on it, shared by every card regardless of
## faction — the doctrine and power copy always sits on the same neutral field.
const PAPER := Color(0.933, 0.906, 0.839)
const PAPER_INK := Color(0.145, 0.169, 0.188)
const HARD_BORDER := Color(0.067, 0.086, 0.098)

const PORTRAIT_DIR := "res://assets/portraits/commanders"
const FACTION_DIR := "res://assets/portraits/factions"
const NEUTRAL_PORTRAIT_PATH := "res://assets/portraits/commanders/none.png"
## Master portrait size the generator writes and the fallbacks match. Taller than
## it is wide: a portrait is a framed window with the bust breaking out of its
## top, so it composes onto a faction-coloured field rather than filling one.
## The bake checks each rasterised image against this and fails loudly on a
## mismatch, so changing the drawing's viewBox or scale cannot silently pass it by.
const PORTRAIT_SIZE := Vector2i(220, 268)
const EMBLEM_PX := 64
## The square of a portrait that holds the head — hair, headwear, both ears and
## the jaw — for all twenty-two generals. A portrait is a framed window with the
## bust breaking out of its top, so the head's centre sits well above the
## image's: a square covering the whole portrait spends a third of itself on
## chest, and one fitting the portrait whole leaves the head at half the field.
##
## Measured over the twenty-two shipped busts rather than eyeballed, because the
## poses are per-general (tilt, zoom and mirror) and the skulls are not one
## width. Their ear-to-ear span runs x 22.3 (Draeg) to 199.7 (Morn), centred on
## 111.0; the deepest chin ends at y 202 (Quill), while the highest skull starts
## at y 30.8 (Morn). One square holds every one of them: the head centres spread
## only 15.5px, which a 190 square absorbs with at least 6px of margin on either
## side and 12px under that deepest chin — the clearance
## tests/unit/test_commander_face.gd pins, 12 to 21 across the roster. So the
## crop is a fixed rect and no per-pose anchor is needed — re-measure it if the
## bake's viewBox, scale, skull widths or pose range move.
##
## Hair breaking over the top edge is deliberate and is the portrait's own
## composition: what may never be cut is the jaw, which
## tests/unit/test_commander_face.gd measures on every shipped bust.
const FACE_REGION := Rect2i(16, 25, 190, 190)
## How commander art is sampled, everywhere it is drawn — the busts and the
## faction emblems alike. Linear, alone in a game whose art is otherwise
## nearest-neighbour: both are baked larger than any field that shows them, and
## every surface lands on its own fractional scale (a 31px HUD chip, a 96px card
## band, a 104px banner, a 22px emblem badge off a 64px source). Nearest at those
## ratios drops whole rows and frays the ink outlines the style rests on.
## Every surface that draws a bust asks for this by name rather than setting a
## filter of its own, so none of them can drift from the others.
## With mipmaps, because the two smallest fields minify hardest — 220x268 into a
## 31px chip and into a 28px speech bust — and plain linear samples four texels
## out of the sixty each output pixel covers there, so the ink outlines shimmer
## and thin features drop in and out. Every portrait and emblem import therefore
## carries `mipmaps/generate=true`; a texture built in code without them (the
## flat-colour fallback) is simply drawn at its one level.
const ART_FILTER := CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

## The neutral commander has no faction; it renders in this iron-grey so "No
## Commander" still reads as a deliberate, styled choice rather than a blank.
const NEUTRAL_KEY := &"neutral"

## Faction display string -> short theme key. Kept here so a .tres that names a
## faction and this adapter can never drift; an unknown faction falls back to the
## neutral theme rather than crashing.
const _FACTION_KEYS := {
	"Meridian Coalition": &"meridian",
	"Iron Dominion": &"iron",
	"Aurora Compact": &"aurora",
	"Verdant League": &"verdant",
}

static var _themes: Dictionary = {}
static var _texture_cache: Dictionary = {}
static var _warned_portraits: Dictionary = {}


static func _build_themes() -> void:
	if not _themes.is_empty():
		return
	_themes = {
		&"meridian":
		FactionTheme.new(
			&"meridian",
			"Meridian Coalition",
			Color(0.859, 0.290, 0.231),
			Color(0.663, 0.212, 0.192),
			Color(0.937, 0.447, 0.373),
			Color(0.973, 0.957, 0.925)
		),
		&"iron":
		FactionTheme.new(
			&"iron",
			"Iron Dominion",
			Color(0.290, 0.322, 0.345),
			Color(0.184, 0.212, 0.231),
			Color(0.420, 0.455, 0.482),
			Color(0.949, 0.957, 0.961)
		),
		&"aurora":
		FactionTheme.new(
			&"aurora",
			"Aurora Compact",
			Color(0.220, 0.396, 0.847),
			Color(0.169, 0.306, 0.659),
			Color(0.427, 0.549, 0.910),
			Color(0.957, 0.965, 0.988)
		),
		&"verdant":
		FactionTheme.new(
			&"verdant",
			"Verdant League",
			Color(0.173, 0.525, 0.212),
			Color(0.114, 0.380, 0.153),
			Color(0.310, 0.659, 0.353),
			Color(0.949, 0.965, 0.945)
		),
		NEUTRAL_KEY:
		FactionTheme.new(
			NEUTRAL_KEY,
			"No Commander",
			Color(0.376, 0.416, 0.443),
			Color(0.235, 0.267, 0.290),
			Color(0.510, 0.549, 0.573),
			Color(0.925, 0.933, 0.937)
		),
	}


## The short theme key for a faction string. Empty/unknown -> neutral.
static func key_for_faction(faction: String) -> StringName:
	return _FACTION_KEYS.get(faction, NEUTRAL_KEY)


static func theme_for_key(key: StringName) -> FactionTheme:
	_build_themes()
	return _themes.get(key, _themes[NEUTRAL_KEY])


## The theme a commander renders in. Neutral commanders — and any general whose
## .tres names a faction this adapter has not been taught — resolve to the
## neutral grey rather than crashing.
static func theme_for(commander: CommanderType) -> FactionTheme:
	if commander == null or commander.faction.is_empty():
		return theme_for_key(NEUTRAL_KEY)
	return theme_for_key(key_for_faction(commander.faction))


## Every faction theme except neutral, in the plan's tab order. The selection
## page groups the roster under these.
static func faction_themes() -> Array[FactionTheme]:
	_build_themes()
	var ordered: Array[FactionTheme] = []
	for key: StringName in [&"meridian", &"iron", &"aurora", &"verdant"]:
		ordered.append(_themes[key])
	return ordered


# --- textures ----------------------------------------------------------------


## The portrait for a commander. Resolves by id; a commander whose art has not
## been produced yet falls back to the neutral silhouette, and if even that is
## missing (a truly fresh tree before `make portraits`) returns a generated
## flat-colour placeholder so no caller ever gets null and no scene crashes.
static func portrait_for(commander: CommanderType) -> Texture2D:
	var id := commander.id if commander != null else CommanderType.NEUTRAL_ID
	var path := "%s/%s.png" % [PORTRAIT_DIR, id]
	return _cached(
		path,
		func() -> Texture2D:
			_warn_missing_portrait(path)
			if ResourceLoader.exists(NEUTRAL_PORTRAIT_PATH):
				return load(NEUTRAL_PORTRAIT_PATH)
			return _fallback_portrait()
	)


## The same portrait cropped to `FACE_REGION` — what a surface too small to show
## a bust asks for. The atlas shares the portrait's own texture, so a face costs
## no second load, and it is cached under a key of its own beside the portraits.
##
## The empty seat is the one exception and gets its bust back whole: the neutral
## art is a featureless silhouette, so cropped to the head it is a dark blob on
## near-black, and "no commander" reads as an empty seat only head-and-shoulders.
static func face_for(commander: CommanderType) -> Texture2D:
	var id := commander.id if commander != null else CommanderType.NEUTRAL_ID
	if id == CommanderType.NEUTRAL_ID:
		return portrait_for(commander)
	var key := "face:%s" % id
	if _texture_cache.has(key):
		return _texture_cache[key]
	var portrait := portrait_for(commander)
	var face := AtlasTexture.new()
	face.atlas = portrait
	face.region = Rect2(FACE_REGION).intersection(Rect2(Vector2.ZERO, portrait.get_size()))
	_texture_cache[key] = face
	return face


## A faction's emblem. Neutral has none, so callers gate on the theme key; asked
## anyway it falls back like a portrait does.
static func emblem_for_key(key: StringName) -> Texture2D:
	return _cached("%s/%s.png" % [FACTION_DIR, key], func() -> Texture2D: return _fallback_emblem())


static func emblem_for(commander: CommanderType) -> Texture2D:
	return emblem_for_key(theme_for(commander).key)


## Loads `path` through a small cache, calling `on_missing` for the fallback when
## the file is not there. Each caller owns its own fallback: portraits borrow the
## neutral bust, emblems fall to a transparent square. Textures are shared immutable
## resources, so caching them across scene loads is safe and keeps the select page
## from reloading twenty-three portraits every time a tab changes.
static func _cached(path: String, on_missing: Callable) -> Texture2D:
	if _texture_cache.has(path):
		return _texture_cache[path]
	var texture: Texture2D
	if ResourceLoader.exists(path):
		texture = load(path)
	if texture == null:
		texture = on_missing.call()
	_texture_cache[path] = texture
	return texture


## Names a bust the tree does not hold, once. Without it a fresh clone draws every
## general as the same neutral silhouette and says nothing anywhere about why. It
## warns rather than errors because this is presentation and the fallback is the
## point — the loud gate on missing art belongs to the offline bake and the suite.
## The emblems deliberately do not get one: neutral has no emblem by design, so a
## miss there is the shape rather than a defect.
static func _warn_missing_portrait(path: String) -> void:
	if _warned_portraits.has(path):
		return
	_warned_portraits[path] = true
	push_warning("Missing commander portrait %s - run `make portraits` to bake it." % path)


static func _fallback_portrait() -> Texture2D:
	var image := Image.create(PORTRAIT_SIZE.x, PORTRAIT_SIZE.y, false, Image.FORMAT_RGBA8)
	image.fill(theme_for_key(NEUTRAL_KEY).color)
	return ImageTexture.create_from_image(image)


static func _fallback_emblem() -> Texture2D:
	var image := Image.create(EMBLEM_PX, EMBLEM_PX, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	return ImageTexture.create_from_image(image)
