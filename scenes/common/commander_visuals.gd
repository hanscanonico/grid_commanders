class_name CommanderVisuals
extends RefCounted
## Presentation adapter for commanders: turns the sim-side CommanderType (id,
## faction, text, numbers) into the things a scene needs to draw one — a portrait
## texture, a faction colour theme, an emblem — without any of that ever entering
## core/.
##
## This is the single authority on commander styling. The card, the battle HUD
## chip, and the power banner all ask here rather than each keeping their own
## copy of the five faction colours, exactly as the resolvers each own one rule.
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
const FACE_DIR := "res://assets/portraits/faces"
const FACTION_DIR := "res://assets/portraits/factions"
const NEUTRAL_PORTRAIT_PATH := "res://assets/portraits/commanders/none.png"
## Master portrait size the generator writes and the fallbacks match — the grid
## the busts are pixelled on, not a canvas they are drawn large on and shrunk
## into. Taller than it is wide: a portrait is a framed window with the bust
## breaking out of its top, so it composes onto a faction-coloured field rather
## than filling one. The bake checks each rasterised image against this and fails
## loudly on a mismatch, so changing the drawing's grid cannot silently pass by.
const PORTRAIT_SIZE := Vector2i(110, 134)
## The face chip: `FACE_REGION` of that same drawing, repainted by the generator
## on the chip's own coarser grid rather than cut out of the bust (`face_for`).
const FACE_SIZE := Vector2i(31, 31)
const EMBLEM_PX := 64
## The square of a portrait that holds the head — hair, headwear, both ears and
## the jaw — for all twenty-two generals. Because the bust breaks out of the
## frame's top, the head's centre sits well above the image's: a square covering
## the whole portrait spends a third of itself on chest, and one fitting the
## portrait whole leaves the head at half the field.
##
## The rectangle moved once, when the busts came onto `PORTRAIT_SIZE`'s grid. It
## is not the old square rescaled: origin and side were chosen fresh so that both
## the bust grid and the coarser chip grid divide it exactly — the generator
## rasterises this rectangle coarsely to bake `FACE_DIR`, and a rectangle that
## did not divide would put the chip half a pixel off the bust's own head.
## `generators/portraits` reads this constant out of this file and measures every
## general's chin against it.
##
## From here the rule is what it always was — geometry moves, the rectangle does
## not: a bust whose jaw crosses the bottom edge is redrawn, because the HUD chip,
## the speech bust and the campaign brief all read the same square. Hair breaking
## over the top edge is deliberate and is the portrait's own composition.
const FACE_REGION := Rect2i(9, 15, 93, 93)
## The smallest field that can show a whole bust, in screen pixels, now that the
## art is drawn at whole texels or not at all: the drawing's full width, and
## every row down to the jaw. Both halves are read off the art itself rather
## than guessed, so a rebake on another grid moves this with it.
##
## The width is exact — a narrower field clips the ears, and a bust is centred,
## so it clips them on both sides. The height is the face region's bottom edge
## rather than the drawing's, because a short field hangs the art from its top
## and what it loses is chest; a field under this loses the chin instead, which
## is the line between a cropped portrait and a decapitated one.
const WHOLE_BUST_FIELD := Vector2i(PORTRAIT_SIZE.x, FACE_REGION.position.y + FACE_REGION.size.y)
## How a general's own art is sampled, everywhere it is drawn — the busts and the
## face chips. Nearest, the way the board and the units are: this art is pixelled
## on its own grid now, and a linear filter over pixel art is a blur whatever the
## ratio. Every surface that draws a bust asks for this by name rather than
## setting a filter of its own, so none of them can drift from the others.
##
## Nearest is only crisp on a WHOLE-number scale, so no surface fits a bust
## freely any more: it asks `art_scale` for a rung of the ladder and draws the
## art at exactly that multiple. The imports carry no mip chain — there is no
## level between the rungs to sample.
const ART_FILTER := CanvasItem.TEXTURE_FILTER_NEAREST
## The scale ladder every bust surface draws on. Whole numbers only, and never
## under one: half a pixel of a face is worse than a face that overflows the
## field it is centred in, which is what the field's own clipping is for.
const MIN_ART_SCALE := 1
## The rung a surface that frames a face chip draws it at, and the field that
## comes out — stated here so the two surfaces that do (the card's chip band and
## the victory lockup) cannot drift apart, and pinned against both by
## `test_commander_portraits.gd`. A chip at 1x is a HUD glyph; where the eye is
## meant to rest on the general it is zoomed, and only a whole rung will do.
const CHIP_ZOOM := 3
const CHIP_FIELD := FACE_SIZE * CHIP_ZOOM
## The emblems are the one piece of commander art not on that ladder, and they
## keep the mipmapped linear filter. They are a 64px badge drawn at 22 in the one
## corner that shows them — a ratio with no whole rung under it — and unlike a
## bust they are geometry rather than pixels: a disc and a chevron, authored at
## the size they are baked. Their imports therefore keep `mipmaps/generate=true`.
const EMBLEM_FILTER := CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

## The neutral commander has no faction; it renders in this iron-grey so "No
## Commander" still reads as a deliberate, styled choice rather than a blank.
const NEUTRAL_KEY := &"neutral"

## The order every surface lists the factions in — the select page's tab row
## first among them. The Iron Dominion, the campaigns' antagonist, closes the
## row. Listing order only: the atlas row a faction is baked into
## (`SideIdentity._ROW_FOR_KEY`) is pinned by the sprite sheets and differs.
const FACTION_ORDER: Array[StringName] = [&"meridian", &"aurora", &"verdant", &"gold", &"iron"]

## Faction display string -> short theme key. Kept here so a .tres that names a
## faction and this adapter can never drift; an unknown faction falls back to the
## neutral theme rather than crashing.
const _FACTION_KEYS := {
	"Meridian Coalition": &"meridian",
	"Iron Dominion": &"iron",
	"Aurora Compact": &"aurora",
	"Verdant League": &"verdant",
	"Gilded Concord": &"gold",
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
		# The shell already spends a gold on "chosen" (`UiTheme.SELECT_GOLD`), and a
		# fifth army wearing one cannot avoid it: this hue reads 11.5 CIE76 from that
		# token, so the select page's pick mark is faint on a Gilded Concord tile. The
		# hue is 50 rather than the amber 43 SELECT_GOLD sits at because warmer is
		# both nearer that token AND nearer neutral's khaki (hue 39) — this is the far
		# end of the room the row has, not a colour picked past the collision.
		&"gold":
		FactionTheme.new(
			&"gold",
			"Gilded Concord",
			Color(0.914, 0.788, 0.157),
			Color(0.694, 0.600, 0.118),
			Color(0.953, 0.863, 0.400),
			Color(0.114, 0.094, 0.024)
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


## Every faction theme except neutral, in `FACTION_ORDER`. The selection page
## groups the roster under these.
static func faction_themes() -> Array[FactionTheme]:
	_build_themes()
	var ordered: Array[FactionTheme] = []
	for key: StringName in FACTION_ORDER:
		ordered.append(_themes[key])
	return ordered


# --- textures ----------------------------------------------------------------


## The largest whole scale `art` fits into `field` at, and the one statement of
## the ladder. A field shorter than the art it shows still draws it at 1:1 and
## clips — the alternative is a fractional scale, which is the softness this art
## was rebaked to be rid of.
static func art_scale(field: Vector2, art: Vector2i) -> int:
	if art.x <= 0 or art.y <= 0:
		return MIN_ART_SCALE
	var rungs := mini(int(field.x) / art.x, int(field.y) / art.y)
	return maxi(MIN_ART_SCALE, rungs)


## Whether a field of this shape can show a whole bust at one texel to one
## pixel — the one statement of it, so the six surfaces that draw a general all
## ask the art the same question. `false` is a chip field: `face_for`'s baked
## drawing, which says who a general is in a square no bust survives.
static func fits_whole_bust(field: Vector2) -> bool:
	return int(field.x) >= WHOLE_BUST_FIELD.x and int(field.y) >= WHOLE_BUST_FIELD.y


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


## The face chip a surface too small to show a bust asks for, straight off the
## bake — the empty seat's included.
##
## One degradation, named because it is the one case that hands back a bust: a
## general the tree holds no chip for falls through to their whole drawing,
## which a chip field then draws at 1:1 and clips. That is a broken bake rather
## than a state to run in, so it errors where a missing bust only warns.
static func face_for(commander: CommanderType) -> Texture2D:
	var id := commander.id if commander != null else CommanderType.NEUTRAL_ID
	var path := "%s/%s.png" % [FACE_DIR, id]
	return _cached(
		path,
		func() -> Texture2D:
			var missing := "Missing commander face chip %s - run `make portraits`." % path
			push_error(missing + " The whole bust is standing in, and a chip field clips it.")
			return portrait_for(commander)
	)


## A faction's emblem. Neutral has none, so callers gate on the theme key; asked
## anyway it falls back like a portrait does.
static func _emblem_for_key(key: StringName) -> Texture2D:
	return _cached("%s/%s.png" % [FACTION_DIR, key], func() -> Texture2D: return _fallback_emblem())


static func emblem_for(commander: CommanderType) -> Texture2D:
	return _emblem_for_key(theme_for(commander).key)


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
