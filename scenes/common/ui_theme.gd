class_name UiTheme
extends RefCounted
## The presentation authority for the shell: the Grid Commander Design System,
## transcribed into Godot styleboxes and fonts. Where the handoff's look is drawn
## — the main menu, the commander select page, and the two docked battle HUD bars
## — the recipe comes from here, so a colour, a shadow or a bar height is defined
## once and every surface reads the same value (menu-revamp plan D1).
##
## The palette splits three ways. Faction colours are never re-declared: they stay
## CommanderVisuals.FactionTheme's, reached through `menu_identity()` so a future
## palette change lands here for free (plan D4). Cream and ink alias the shipped
## CommanderVisuals authorities (PAPER / PAPER_INK / HARD_BORDER). Only the shell
## tokens the game had no authority for — the slates, the neutrals, the capture
## green — are new constants below, transcribed from the handoff's colors.css.
##
## No .tres Theme resource: this repo builds its UI in code (CommanderSelectPanel,
## CommanderCard), and a hand-edited Theme is the one format that cannot be
## reviewed in a diff. No file under data/ either — data/ is for numbers the *sim*
## reads, and the sim must never read a menu colour.
##
## Sizes are canvas pixels: the game renders a 640x360 canvas stretched 2x into
## the default window, so every value here is half the handoff's and doubles on
## screen (plan section 2's div-2 rule). These are starting values, tuned by eye.
##
## No Node, no scene path — but this is scenes/, not core/, so loading a font and
## caching it is allowed here where it would not be there.

const FONT_DIR := "res://assets/fonts"
const DISPLAY_FONT_PATH := FONT_DIR + "/PixelifySans-Variable.ttf"
const STAT_FONT_PATH := FONT_DIR + "/Silkscreen-Regular.ttf"
const STAT_BOLD_FONT_PATH := FONT_DIR + "/Silkscreen-Bold.ttf"
## OpenType 'wght' axis tag ('w'<<24 | 'g'<<16 | 'h'<<8 | 't'), so the variable
## display face can be asked for its bold instance without a second file.
const _WGHT_TAG := 2003265652
## OpenType 'liga' feature tag, same encoding. Pixelify Sans ships fi/fl/ff
## ligatures whose merged glyphs are unreadable at pixel size ("first" rasterises
## as "Arst"), so the display face is always served with them switched off.
const _LIGA_TAG := 1818847073

# --- shell palette: new tokens (no shipped authority), from tokens/colors.css ---
const SLATE_900 := Color(0.13725, 0.15294, 0.16863)  # #23272b page backdrop
const SLATE_800 := Color(0.16863, 0.18431, 0.20392)  # #2b2f34 raised dark surface
const SLATE_700 := Color(0.22745, 0.24706, 0.27059)  # #3a3f45
const NEUTRAL := Color(0.54118, 0.56471, 0.60000)  # #8a9099 un-owned property grey
const NEUTRAL_DARK := Color(0.34902, 0.36471, 0.38824)  # #595d63
const NEUTRAL_LIGHT := Color(0.67843, 0.69412, 0.71765)  # #adb1b7
const PAPER_RAISED := Color(0.95686, 0.93725, 0.89020)  # #f4efe3 hovered/selected cream
const PAPER_2 := Color(0.81176, 0.81176, 0.81176)  # #cfcfcf secondary grey panel
const CAPTURE := Color(0.42353, 0.76078, 0.29020)  # #6cc24a capture green (toggle ON)
const WHITE := Color(0.93333, 0.93333, 0.93333)  # #eeeeee pure light
const INK_3 := Color(0.54118, 0.56471, 0.60000)  # #8a9099 faint text — HUD labels
## #e0a92e. The design system has no `--warn`: the amber that fills a charge
## meter, an ammo bar and a defense star is this one token, and the HUD handoff
## calls it out as the bug that left the commander meter unstyled.
const AMMO := Color(0.87843, 0.66275, 0.18039)
## #f4be32. The commander select page's own accent for "locked" — its focus
## rings and the tick on a confirmed seat — kept through the alignment pass
## because gold there means chosen, which no faction fill may say (plan D6). A
## lighter gold than AMMO and deliberately a second token rather than a second
## copy: it was an unnamed literal in two files before COM-89.
const SELECT_GOLD := Color(0.95686, 0.74510, 0.19608)
## #e8b33c. The funds readout's amber, and a token of its own rather than AMMO's
## even though the two read alike: money is not a supply level, so retuning the
## ammo bar must not move what a player's purse is printed in.
const FUNDS_INK := Color(0.90980, 0.70196, 0.23529)
const DANGER := Color(0.84706, 0.29020, 0.23529)  # #d84a3c critical HP
## The signature hard drop shadow: ink, 90% opaque, zero blur. rgba(35,39,43,.9).
const SHADOW_INK := Color(0.13725, 0.15294, 0.16863, 0.9)

# --- aliases: colours that already have a shipped authority (plan D1) ----------
## Cream panel surface and the two inks on it stay CommanderVisuals', so the menu
## and the battle screen can never disagree about what "paper" is.
const PAPER := CommanderVisuals.PAPER
const INK := CommanderVisuals.PAPER_INK  # body text / muted borders on cream
const HARD_BORDER := CommanderVisuals.HARD_BORDER  # the darkest outline

## A thin ink rule between two rows (handoff --border-soft): INK faded to 45%.
const BORDER_SOFT := Color(INK, 0.45)
## The wash a map cell takes on hover, unselected: PAPER_RAISED faded to 35%.
const HOVER_WASH := Color(PAPER_RAISED, 0.35)

# --- canvas-pixel metrics (plan section 2) -------------------------------------
const CONTENT_W := 370  # handoff 740 content column
const ACTION_W := 122  # handoff 244 action stack
const GAP := 8  # handoff 16 column gap
const BORDER := 1  # chrome outline; 2 physical px on the default window
const PANEL_BORDER := 2  # the panel's heavier outline
const SHADOW := 1  # hard-shadow size; shows 2*SHADOW canvas px past bottom-right
const RADIUS := 1  # a whisker of rounding, at most
## The clear space a button's stylebox keeps above and below its content, named
## because a row that reserves a slot of its own has to say how tall the row is.
const BUTTON_PAD_V := 3
## A full-screen page's outer margin, and the deeper one its bottom edge takes
## when the last row is a filled button. A button's ink runs to its own edge and
## its shadow a pixel past it, where a text row's stops short, so the same margin
## does not read the same: measured on the captured frames, a page ending in a
## line of copy clears 10 canvas px under it and the debrief's Continue button
## only 7, against a 12.5 px top on both. 13 reads as that top does.
const PAGE_MARGIN := GAP
const PAGE_BUTTON_MARGIN := 13

# --- the docked battle HUD (the handoff, .lavish/hud/SPEC.md) ------------------
## Both bars are fixed height, and the board's viewport is what is left over. The
## handoff's 46/92 px halve like every other metric here: the 640x360 canvas
## doubles into the window, so 23 + 46 canvas px show as 46 + 92 on screen.
##
## Fixed is the point, not an implementation detail. A bar that grows when a unit
## is selected would re-lay-out the board mid-turn and slide the map under the
## cursor, so HUD_TOP_H + HUD_BOTTOM_H is a constant the camera can be framed
## against once (SPEC "Fixed heights", "Empty is empty").
const HUD_TOP_H := 23
const HUD_BOTTOM_H := 46
const HUD_BARS_H := HUD_TOP_H + HUD_BOTTOM_H
## The touch dock's height, on a mobile build only — the third docked bar, under
## the bottom one (mobile plan MB3). Fixed like the two above it and for the same
## reason: it is part of the chrome the board's viewport is framed against, so a
## dock that grew with its labels would move the zoom ladder's floor mid-match.
## `MobileDock` is what answers whether it is on the screen at all; this is only
## how tall it is when it is.
const HUD_DOCK_H := 28
## The 3px ink edge the bars present to the board, halved like the rest.
const HUD_EDGE := 2
## The vertical rule that splits a bar's groups.
const HUD_RULE_W := 2
## One HP cell of the ten-pip strip (handoff 6x14).
const PIP := Vector2(3, 7)
const PIP_GAP := 1
## The inset at each end of a bar's row, and the separation between the groups
## inside it. One pad for both bars: they were declared 7 and 6, but the 6 never
## reached a pixel — `hud_spacer` floors a negative width at zero, so each bar was
## always inset by its own gap, which is 7 in both (COM-98).
const HUD_PAD := 7
## 7 until COM-254 set the bar's labels on the stat face's own pixel grid: the top
## bar is one row of fixed content across 640 canvas px, so a third more glyph
## width comes out of the space between the groups or out of the groups
## themselves, and a key legend cut mid-word is the worse of the two. The bar is
## full at 4: the campaign board measures it — four chips, the longest faction
## name and IDLE's legend at ControlHints.MAX_CHARS — so a fifth chip or a longer
## legend is a group that has to give, not another pixel here.
const HUD_GAP := 4
## The separations *inside* a bar's groups — a commander block's rows, a stat
## line's icons — as opposed to HUD_GAP, which is between the groups. Four
## sizes because the bottom bar's blocks disagreed on which of them to use
## with nothing saying which was which (COM-98's shape, found again in COM-192).
const HUD_GAP_HAIR := 2
const HUD_GAP_TIGHT := 3
const HUD_GAP_SNUG := 4
const HUD_GAP_WIDE := 5
## The faction colour square on the top bar (handoff 14px).
const HUD_CHIP := 7
## The clear space the top bar's doctrine line keeps to its right, on top of
## HUD_GAP. The line is the one label on either bar that clips rather than sizes
## to its text, so its right edge is a cut through a word rather than the end of
## one, and the ordinary group gap after a cut reads as no gap at all — the funds
## run straight on from a half glyph. A metric rather than a number in the bar,
## like every other size here.
const HUD_CLIP_GAP := 5
## A group divider's height, per bar: each keeps the inset it wants from its own
## fixed height, which is why there are two and not one.
const HUD_TOP_RULE_H := HUD_TOP_H - 10
const HUD_BOTTOM_RULE_H := HUD_BOTTOM_H - 18
## The bottom bar's three pictures: the commander's portrait field (handoff 62px),
## the unit icon (64) and the terrain chip's tile (40).
const HUD_PORTRAIT := 31
const HUD_UNIT_ICON := 32
const HUD_TILE_ICON := 20
## The charge meter's trough (handoff 132x12), and the floor width of the
## commander block around it — a floor, not a width: the block sizes to whichever
## of its two rows is wider, so every shipped power_name renders whole (they run
## to "Armoured Breakthrough"). The floor only bites on a commander-less side,
## where it keeps the empty left third from collapsing to the portrait.
const HUD_METER := Vector2(66, 6)
const HUD_CO_MIN_W := 105
## The square slot an illustrated menu row fits its artwork into — one world
## tile, since the art is authored at the atlas's own resolution (64px for the
## unit sprites) and would dwarf a 10px label — and the height such a row is
## held at, so a row's height is the slot's rather than its picture's shape.
const MENU_ICON := 16
const MENU_ICON_ROW := MENU_ICON + 2 * BUTTON_PAD_V

## What a finger has to be able to hit, in canvas pixels (mobile plan D8). On a
## 1080p phone held in landscape the 360-line canvas scales by exactly 3, so one
## canvas pixel is about one dp and about one pt — which puts Android's 48 dp and
## Apple's 44 pt both at roughly this many. It is a *hit* size and never a drawn
## one: every drawn height on the two docked bars feeds HUD_BARS_H and therefore
## the zoom ladder's floor, so the chrome keeps the size it was designed at and
## UiKit.touchable lays the tap over it.
const TOUCH_MIN := 44

const SIZE_WORDMARK := 24
const SIZE_TITLE := 8
## The title of every full-screen page.
const SIZE_PAGE_TITLE := 15
const SIZE_BUTTON := 10
## The one announcement size: the beat that stops the board (the day banner) and
## the lockup that ends it. Between the wordmark and a panel title, because both
## are read across the room rather than at reading distance — and one token, so
## the two surfaces that speak to the whole table cannot drift apart.
const SIZE_BANNER := 18
const SIZE_BODY := 8
const SIZE_SEGMENT := 7
## A tooltip's label line. The handoff sets it at --text-sm, which the div-2 rule
## puts at SIZE_SEGMENT's 7 — but a segment holds one word and a tip holds a
## sentence, and Pixelify's space advance rounds away at 7 with subpixel
## positioning off ("How fast moves" sets as "Howfast moves"). One step up is the
## smallest size that keeps the words apart.
const SIZE_TIP := 8
## Silkscreen is drawn on an 8-pixel grid, and a pixel face only rasterises whole
## at a whole multiple of the grid it was drawn on: below it the renderer drops
## rows out of every glyph, which is not a blur but a different letter — at 6 the
## shell printed "FUNDS 4200" as "FUHDG 42DD" and "MISSION" as "MIFFIDH", which is
## the whole of COM-254's "the font is hard to read".
const STAT_DESIGN_PX := 8
## The one size the shell sets the stat face at: its own grid, 16 physical px on
## the default window. One token rather than three sizes, because every label that
## reads as broken is a label somebody set off the grid.
const SIZE_STAT := STAT_DESIGN_PX
## The one exception, and it is not a label: the count a board badge carries
## (CapturePips, PowerMarks) is one or two digits drawn over a 16px tile with an
## outline, and a digit on the grid covers the building it is counting down. A
## number this short survives off the grid where a word does not.
const SIZE_MARK := 6

enum ButtonVariant { PRIMARY, SECONDARY, GHOST }

static var _display_file: FontFile
static var _stat: FontFile
static var _stat_bold: FontFile
static var _display: FontVariation
static var _display_bold: FontVariation
## Roster (as written by `str`) -> the identity that roster resolves to. See
## `menu_identity_of`, which is the only reader and writer.
static var _identity_by_roster: Dictionary[String, SideIdentity] = {}

# --- fonts -------------------------------------------------------------------


## Pixelify Sans — display & UI chrome. `bold` asks the variable face for its
## 700-weight instance (the wordmark and panel titles), no second file needed.
static func display(bold := false) -> Font:
	if bold:
		if _display_bold == null:
			_display_bold = _no_ligatures(_display_face())
			_display_bold.variation_opentype = {_WGHT_TAG: 700}
		return _display_bold
	if _display == null:
		_display = _no_ligatures(_display_face())
	return _display


## Silkscreen — micro-labels, numerals, badges. `bold` loads the static bold cut.
## Serve it at SIZE_STAT and nowhere else: it is a pixel face with a grid, and the
## sizes between its rungs are the ones that shatter (see STAT_DESIGN_PX).
static func stat(bold := false) -> Font:
	if bold:
		if _stat_bold == null:
			_stat_bold = _tuned(STAT_BOLD_FONT_PATH)
		return _stat_bold
	if _stat == null:
		_stat = _tuned(STAT_FONT_PATH)
	return _stat


static func _display_face() -> FontFile:
	if _display_file == null:
		_display_file = _tuned(DISPLAY_FONT_PATH)
	return _display_file


static func _no_ligatures(face: FontFile) -> FontVariation:
	var variation := FontVariation.new()
	variation.base_font = face
	variation.opentype_features = {_LIGA_TAG: 0}
	return variation


## Loads a face and switches off every source of blur: no antialiasing, no
## subpixel drift, no hinting — so the glyphs rasterise on the same pixel grid the
## tile and unit art already lives on (plan D2, and R1's mitigation).
static func _tuned(path: String) -> FontFile:
	var face: FontFile = load(path)
	face.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	face.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	face.hinting = TextServer.HINTING_NONE
	return face


# --- the faction hues, never re-declared (plan D4) ---------------------------


## The default side identities a commander-less match plays as: team 1 in the
## classic meridian red, team 2 in aurora blue. The menu's faction hues — the
## Start button fill, the seat strip's accent, the identity chip dots, the
## selected-map border — all read from this, so they stay CommanderVisuals'
## colours and never a fourth copy.
##
## `seats` is the board's roster, floored at a duel: a four-army board's third and
## fourth seats resolve to no theme under the two-seat default and would draw
## neutral grey wherever the menu previews them (the thumbnails, the footer chips).
static func menu_identity(seats: int = 2) -> SideIdentity:
	var roster: Array[int] = []
	for seat in range(1, maxi(2, seats) + 1):
		roster.append(seat)
	return menu_identity_of(roster)


## The same, for a match that fills only some of the board's seats: the identities
## are resolved over the seats that *play*, which is what the battle will do with
## the very same roster (`GameState.teams`). Asking about the whole board instead
## would preview a closed seat's livery beside armies that are not wearing it.
##
## Resolved once per roster and kept, because SideIdentity's own contract is
## "resolved once per match" and the menu was asking for one twice per map cell on
## every repaint of the picker. Safe to share: every pick here is null, so the
## answer is a pure function of the seat list and cannot go stale, and each
## identity is read-only to every caller — the themes inside it are already
## CommanderVisuals' shared instances, handed out the same way.
static func menu_identity_of(seats: Array[int]) -> SideIdentity:
	var roster := str(seats)
	if _identity_by_roster.has(roster):
		return _identity_by_roster[roster]
	var picks: Dictionary = {}
	for seat in seats:
		picks[seat] = null
	var identity := SideIdentity.resolve(picks)
	_identity_by_roster[roster] = identity
	return identity


# --- stylebox factories ------------------------------------------------------


## A flat fill with no border or shadow — the atom the header bands and chips are
## built from.
static func flat(color: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.anti_aliasing = false
	return box


## The recipe every bordered box on the shell reads: a flat fill, an outline of
## `width`, and — for the chrome that wants it — the signature hard shadow.
static func bordered(
	fill: Color, border: Color, width: int = BORDER, hard_shadow := false
) -> StyleBoxFlat:
	var box := flat(fill)
	box.border_color = border
	box.set_border_width_all(width)
	if hard_shadow:
		UiTheme.hard_shadow(box)
	return box


## The signature look, applied to any StyleBoxFlat: a hard offset shadow with zero
## blur. `shadow_size = n`, `shadow_offset = (n, n)` grows the shadow rect by n and
## shifts it, so it sits flush under the top-left edges and shows exactly 2n canvas
## pixels of ink past the bottom-right — CSS `2n 2n 0` (plan D3). Proven here first.
static func hard_shadow(box: StyleBoxFlat, size := SHADOW) -> StyleBoxFlat:
	box.shadow_color = SHADOW_INK
	box.shadow_size = size
	box.shadow_offset = Vector2(size, size)
	box.anti_aliasing = false
	return box


## The cream Match Setup panel: paper surface, ink outline, hard shadow. The
## game's universal container (handoff Panel.jsx, `tone: cream`).
static func panel_box() -> StyleBoxFlat:
	var box := flat(PAPER)
	box.border_color = HARD_BORDER
	box.set_border_width_all(PANEL_BORDER)
	box.set_corner_radius_all(RADIUS)
	return hard_shadow(box)


## The dark variant — slate surface for HUD-style overlays (the select page's
## backdrop panels). Same outline and shadow as the cream panel.
##
## `pad_x` / `pad_y` set the content margins when non-zero, which is what a card
## on the board — not a docked bar — asks for: it carries its own words inside
## its outline instead of being laid out around.
static func dark_panel_box(fill := SLATE_800, pad_x: int = 0, pad_y: int = 0) -> StyleBoxFlat:
	var box := flat(fill)
	box.border_color = HARD_BORDER
	box.set_border_width_all(PANEL_BORDER)
	box.set_corner_radius_all(RADIUS)
	if pad_x != 0:
		box.content_margin_left = pad_x
		box.content_margin_right = pad_x
	if pad_y != 0:
		box.content_margin_top = pad_y
		box.content_margin_bottom = pad_y
	return hard_shadow(box)


## One of the two docked HUD bars: an opaque slate slab with a single ink edge on
## the side that faces the board. Never translucent and never shadowed — it is
## chrome outside the map, not a card floating on it (SPEC "Opaque only").
static func hud_bar_box(edge_on_top: bool) -> StyleBoxFlat:
	var box := flat(SLATE_800)
	box.border_color = HARD_BORDER
	if edge_on_top:
		box.border_width_top = HUD_EDGE
	else:
		box.border_width_bottom = HUD_EDGE
	return box


## A vertical rule between two groups inside a docked bar. The height is the
## rule's own rather than the bar's, so each bar keeps the inset it wants from
## its own fixed height.
static func hud_divider(height: int) -> Control:
	var line := Panel.new()
	line.custom_minimum_size = Vector2(HUD_RULE_W, height)
	line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_theme_stylebox_override("panel", flat(SLATE_700))
	return line


## Fixed horizontal padding inside a bar's row. Never negative, so a caller may
## hand it the pad minus the row's separation without guarding the result.
static func hud_spacer(width: int) -> Control:
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(maxi(width, 0), 0)
	return pad


## One label on a docked bar: Silkscreen, vertically centred in a row whose
## height is fixed. `display_face` swaps in Pixelify for the two readouts the
## top bar sets as numerals rather than as micro-labels.
##
## Here rather than on either bar, for the same reason the colours are: a HUD
## label defined twice is a HUD label that drifts (menu-revamp plan D1).
static func hud_label(text: String, font_size: int, color: Color, display_face := false) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", display() if display_face else stat())
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label


## A key chip on a docked bar: `hud_label`'s dress on a Button, so the chip that
## advertises a key can also be pressed with the mouse. Every state's stylebox is
## empty and every state's ink is the one colour it was asked for — the bar's
## height is fixed and its row cannot move, so a chip that grew a frame under the
## pointer would shift the readouts beside it, and a hover shade would fight the
## lit/unlit colour that is the chip's whole readout.
static func hud_chip(text: String, font_size: int, color: Color) -> Button:
	var chip := Button.new()
	chip.text = text
	chip.focus_mode = Control.FOCUS_NONE
	chip.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	chip.add_theme_font_override("font", stat())
	chip.add_theme_font_size_override("font_size", font_size)
	for slot in ["normal", "hover", "pressed", "focus", "disabled"]:
		chip.add_theme_stylebox_override(slot, StyleBoxEmpty.new())
	hud_chip_ink(chip, color)
	return chip


## The one ink a chip wears, in every state it can be in. Its own function
## because lighting a chip is the same statement as dressing it.
static func hud_chip_ink(chip: Button, color: Color) -> void:
	for slot in ["font_color", "font_hover_color", "font_pressed_color"]:
		chip.add_theme_color_override(slot, color)


## The HP strip's colour rule, straight from the handoff: green above 6, amber
## through the middle, red at 3 or below. One place, so the pips in the bar and
## any later readout of the same number cannot disagree.
static func hp_color(hp: int) -> Color:
	if hp > 6:
		return CAPTURE
	if hp > 3:
		return AMMO
	return DANGER


## The wash a full-screen page or sheet lays over whatever it covers, at the
## opacity that page asks for — near-solid for a page that replaces the screen, a
## dim for one that only holds it. The backdrop slate, and only ever that: three
## surfaces mixed three darks between them, one of them a value defined nowhere
## else (COM-90). How opaque stays the page's own call.
static func veil(alpha: float) -> Color:
	return Color(SLATE_900, alpha)


## A panel's title band — the header bar that spans the top of a Panel. Ink by
## default, or a faction fill when the panel belongs to a side.
static func header_box(fill := HARD_BORDER) -> StyleBoxFlat:
	var box := flat(fill)
	box.border_color = HARD_BORDER
	box.border_width_bottom = BORDER
	box.content_margin_left = 6
	box.content_margin_right = 6
	box.content_margin_top = 3
	box.content_margin_bottom = 3
	return box


## One segment of a segmented control: the active segment carries the faction
## fill with white text, the rest are paper. Segments butt against each other and
## are split by the parent box's inner ink rules (drawn by the caller as thin
## dividers), so a segment itself is borderless.
static func segment_box(active: bool, accent: Color) -> StyleBoxFlat:
	var box := flat(accent if active else PAPER)
	box.content_margin_top = 2
	box.content_margin_bottom = 2
	box.content_margin_left = 2
	box.content_margin_right = 2
	return box


## The chunky focus ring — a bright border that reads at a glance for keyboard and
## controller users. Faction blue by default (handoff --focus-ring), swappable so
## a gold-selected surface can keep its own accent.
static func focus_box(accent := menu_identity().theme(2).color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0, 0, 0, 0)
	box.border_color = accent
	box.set_border_width_all(BORDER)
	box.set_corner_radius_all(RADIUS)
	box.anti_aliasing = false
	# Lift the ring a pixel off the control so it reads as a ring, not a repaint.
	box.expand_margin_left = 1
	box.expand_margin_right = 1
	box.expand_margin_top = 1
	box.expand_margin_bottom = 1
	return box


# --- the faction/cream/ghost button, all states (handoff Button.jsx) ----------


## Dresses a Button in the design system's recipe: chunky outline, hard offset
## shadow, snaps down on press (the shadow collapses and the label shifts into its
## place), hover brightens, disabled is `DisabledPalette`'s. One implementation, read
## by both the menu action stack and the select page (plan MN3), so the press
## feels identical wherever a button lives.
##
## `theme` tints a PRIMARY button to a faction; SECONDARY is cream, GHOST is
## chrome-less. Font colour is set per state so the label tracks the fill.
static func apply_button(
	button: Button,
	variant: ButtonVariant,
	theme: CommanderVisuals.FactionTheme = null,
	size := SIZE_BUTTON
) -> void:
	button.add_theme_font_override("font", display())
	button.add_theme_font_size_override("font_size", size)

	var fill := PAPER
	var border := HARD_BORDER
	var fg := INK
	match variant:
		ButtonVariant.PRIMARY:
			var t := theme if theme != null else menu_identity().theme(1)
			fill = t.color
			border = t.color_dark
			fg = t.ink
		ButtonVariant.SECONDARY:
			fill = PAPER
			border = HARD_BORDER
			fg = INK
		ButtonVariant.GHOST:
			fill = Color(0, 0, 0, 0)
			border = Color(0, 0, 0, 0)
			fg = WHITE

	var ghost := variant == ButtonVariant.GHOST
	var muted := DisabledPalette.plate(fill, border)
	button.add_theme_stylebox_override("normal", _button_box(fill, border, not ghost))
	button.add_theme_stylebox_override(
		"hover", _button_box(_brighten(fill, ghost), border, not ghost)
	)
	button.add_theme_stylebox_override("pressed", _pressed_box(fill, border))
	# Disabled keeps the border it was drawn with and loses only the shadow: a
	# button that cannot be pressed has nothing to drop off.
	button.add_theme_stylebox_override("disabled", _button_box(muted, border, false))
	button.add_theme_stylebox_override("focus", focus_box(WHITE))

	button.add_theme_color_override("font_color", fg)
	button.add_theme_color_override("font_hover_color", fg)
	button.add_theme_color_override("font_pressed_color", fg)
	button.add_theme_color_override("font_focus_color", fg)
	button.add_theme_color_override("font_disabled_color", DisabledPalette.label(fg, muted))


static func _button_box(fill: Color, border: Color, shadow: bool) -> StyleBoxFlat:
	var box := flat(fill)
	box.border_color = border
	box.set_border_width_all(BORDER)
	box.set_corner_radius_all(RADIUS)
	box.content_margin_left = 6
	box.content_margin_right = 6
	box.content_margin_top = BUTTON_PAD_V
	box.content_margin_bottom = BUTTON_PAD_V
	if shadow:
		hard_shadow(box)
	return box


## Pressed: the shadow is gone and the content shifts down-right by the shadow's
## size, so the button reads as having dropped onto the board (Button.jsx's
## `translate(2px,2px)` with the shadow removed). A state swap, no tween (plan D3).
static func _pressed_box(fill: Color, border: Color) -> StyleBoxFlat:
	var box := flat(fill)
	box.border_color = border
	box.set_border_width_all(BORDER)
	box.set_corner_radius_all(RADIUS)
	box.content_margin_left = 6 + SHADOW
	box.content_margin_top = BUTTON_PAD_V + SHADOW
	box.content_margin_right = 6 - SHADOW
	box.content_margin_bottom = BUTTON_PAD_V - SHADOW
	return box


# --- input plumbing ----------------------------------------------------------


## Marks a subtree as decoration: `root` and every Control under it stop
## hit-testing, so a card built by laying content over a Button leaves the Button
## itself as the one thing a click can land on.
##
## Control's default is MOUSE_FILTER_STOP and a parent's IGNORE does not exempt
## its children, so any Panel, PanelContainer or plain Control in the decoration
## silently eats the press and only keyboard focus still selects the card. This
## walks the whole subtree rather than naming the pieces, so it holds when one
## more label lands in a card later. Call it once the decoration is fully built.
##
## Walking everything has one consequence worth knowing: a piece of dress that
## *does* want the pointer — a `Tooltip` trigger label inside a toggle row — is
## silenced along with the rest, and a silenced Control emits no `mouse_entered`.
## Attach the tip after this call, not before; `Tooltip.attach` reopens its trigger
## to MOUSE_FILTER_PASS, which lets hover through while the press still falls to
## the Button underneath.
static func make_decoration(root: Control) -> void:
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in root.get_children():
		var control := child as Control
		if control != null:
			make_decoration(control)


# --- small colour maths ------------------------------------------------------


## Hover brightening. A PRIMARY/SECONDARY fill lifts toward white (Button.jsx's
## `brightness(1.07)`); a GHOST, which has no fill, takes a faint white wash.
static func _brighten(color: Color, ghost: bool) -> Color:
	if ghost:
		return Color(1, 1, 1, 0.10)
	return color.lightened(0.07)
