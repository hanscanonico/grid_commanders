class_name CutinPlates3D
extends Control
## The flat cut-in's chrome over the 3D stage: the two name plates with their
## weapon chips and HP pips, the two terrain rows with their cover stars, and
## the damage numbers pinned over each squad. Drawn with the flat cut-in's own
## measures (`CutscenePlates`, `CutsceneSide`'s plate constants, `CutsceneFx`'s
## callout), so the two cut-ins read as one film — only the band between the
## plates is 3D.
##
## Dumb: the director hands it every value off its clock and it draws them.


## One side's plate.
class Plate:
	var title := ""
	var accent := Color.WHITE
	var weapon := ""
	var hp := 10
	var terrain := ""
	var stars := 0
	var note := ""


## A damage number over a squad: where on this control, how much, its K.O. tag
## and how far through its rise.
class Callout:
	var at := Vector2.ZERO
	var amount := 0
	var tag := ""
	var progress := 0.0


var left := Plate.new()
var right := Plate.new()
var plate_p := 0.0
var callouts: Array[Callout] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var font := get_theme_font(&"font", &"Label")
	for callout in callouts:
		_draw_callout(font, callout)
	if plate_p <= 0.0:
		return
	CutscenePlates.draw_frames(self, size, plate_p)
	_draw_name_row(font, left, false)
	_draw_name_row(font, right, true)
	var bottom := size.y - CutscenePlates.BOT_H
	_draw_terrain_row(font, left, false, bottom)
	_draw_terrain_row(font, right, true, bottom)


## An x measured from a side's outer edge.
func _outward(from_edge: float, mirror: bool) -> float:
	return size.x - from_edge if mirror else from_edge


func _draw_name_row(font: Font, plate: Plate, mirror: bool) -> void:
	var title := plate.title
	var width := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	var bar_x := _outward(CutsceneSide.PLATE_MARGIN - 10.0, mirror) - (4.0 if mirror else 0.0)
	draw_rect(Rect2(bar_x, 6.0, 4.0, 13.0), Color(plate.accent, plate_p))
	var text_x := _outward(CutsceneSide.PLATE_MARGIN, mirror) - (width if mirror else 0.0)
	draw_string(
		font,
		Vector2(text_x, 18.0),
		title,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		12,
		Color(Color.WHITE, plate_p)
	)
	_draw_chip(font, plate, mirror, CutsceneSide.PLATE_MARGIN + width + CutsceneSide.CHIP_GAP)
	_draw_pips(plate, mirror)


func _draw_chip(font: Font, plate: Plate, mirror: bool, from_edge: float) -> void:
	if plate.weapon == "":
		return
	var px := CutsceneSide.CHIP_FONT_PX
	var pad := CutsceneSide.CHIP_PAD
	var text := font.get_string_size(plate.weapon, HORIZONTAL_ALIGNMENT_LEFT, -1, px)
	var box := Vector2(text.x + pad.x * 2.0, px + pad.y * 2.0)
	var x := _outward(from_edge, mirror) - (box.x if mirror else 0.0)
	var y := (CutscenePlates.TOP_H - box.y) * 0.5 - 1.0
	var frame := Rect2(x, y, box.x, box.y)
	draw_rect(frame, Color(CutscenePalette.STROKE, 0.35 * plate_p))
	var border := CutsceneSide.CHIP_BORDER
	draw_rect(frame, Color(border, border.a * plate_p), false, 1.0)
	var ink := CutsceneSide.CHIP_TEXT
	draw_string(
		font,
		Vector2(x + pad.x, y + box.y - pad.y - 1.0),
		plate.weapon,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		px,
		Color(ink, ink.a * plate_p)
	)


## Ten pips anchored at the seam and depleting toward it, so the two bars read
## as one gauge — the flat cut-in's rule.
func _draw_pips(plate: Plate, mirror: bool) -> void:
	var band := UiTheme.hp_color(plate.hp)
	var seam := size.x * 0.5 + (CutsceneSide.SEAM_MARGIN if mirror else -CutsceneSide.SEAM_MARGIN)
	var pip := CutsceneSide.PIP_SIZE
	for i in CutsceneSide.PIP_COUNT:
		var step := (pip.x + CutsceneSide.PIP_GAP) * (CutsceneSide.PIP_COUNT - 1 - i)
		var x := seam + step if mirror else seam - step - pip.x
		var tint := band if i < plate.hp else CutsceneSide.HP_EMPTY
		draw_rect(Rect2(x, 9.0, pip.x, pip.y), Color(tint, tint.a * plate_p))


func _draw_terrain_row(font: Font, plate: Plate, mirror: bool, y: float) -> void:
	CutscenePlates.draw_terrain_row(
		self,
		font,
		y,
		plate.terrain,
		_outward(CutsceneSide.PLATE_MARGIN, mirror),
		-1.0 if mirror else 1.0,
		CutsceneSide.TERRAIN_STAR_GAP,
		plate.stars,
		plate_p,
		plate.note
	)


## The flat cut-in's damage number: it punches in, rises and fades.
func _draw_callout(font: Font, callout: Callout) -> void:
	var p := callout.progress
	if p <= 0.0 or p >= 1.0:
		return
	var rise := CutsceneFx.ramp(p, [0.0, 0.3, 1.0], [10.0, -8.0, -26.0])
	var punch := CutsceneFx.ramp(p, [0.0, 0.25, 1.0], [0.4, 1.2, 1.0])
	var alpha := CutsceneFx.ramp(p, [0.0, 0.15, 0.7, 1.0], [0.0, 1.0, 1.0, 0.0])
	draw_set_transform(callout.at + Vector2(0.0, rise), 0.0, Vector2(punch, punch))
	if callout.tag != "":
		var tag_tint := (
			CutsceneFx.KO_RED if callout.tag == CutsceneFx.KO_TAG else CutsceneFx.FLASH_GOLD
		)
		CutsceneFx.stroked_centered(
			self, font, Vector2(0.0, -18.0), callout.tag, 15, Color(tag_tint, alpha)
		)
	if callout.amount > 0:
		CutsceneFx.stroked_centered(
			self, font, Vector2(0.0, 8.0), "-%d" % callout.amount, 26, Color(Color.WHITE, alpha)
		)
	draw_set_transform(Vector2.ZERO)
