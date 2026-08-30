class_name PowerMeteor
extends Node2D
## Hammerfall's strike, drawn on the board: a body falling out of the top of the
## frame into the square the power named, and the flash, shock ring and dust it
## leaves behind.
##
## One clock and nothing else, exactly as a cut-in is (`CutscenePlayback`): every
## shape below is a pure function of `t`, so a skip is `t = 1` rather than a race
## between cancelled tweens, and a posed still is the same still every run.
##
## It decides nothing. The square it draws over is the doctrine's own footprint,
## handed in by `BattleAnimator`, and the bang and the board's flinch hang off
## `struck` so the animator keeps owning both.

## The clock crossed the impact beat. Silent on a skip, the way a fast-forwarded
## cut-in's cues are.
signal struck
## The clock reached its end. Once per playthrough, which is what makes the exit
## single however the run ended.
signal finished

const TILE := BattleView.TILE
## The footprint an aimed strike takes, in tiles.
const SPAN := 3
## Where on the 0..1 clock the body lands.
const IMPACT := 0.55
## Where the body falls from, relative to the square it lands on: off the top of
## the board and to one side, so it arrives on a slant rather than dropping
## straight down the frame.
const ENTRY := Vector2(-64.0, -132.0)
## The body's radius as it enters the frame and as it lands, the dark rule drawn
## round it so it reads over any terrain (the board's own outlined idiom), and how
## far its hot core sits toward the leading edge.
const BODY_MIN := 7.0
const BODY_MAX := 16.0
const BODY_OUTLINE := 2.0
const CORE_LEAD := 0.3
const CORE_RADIUS := 0.45
## How far behind the body its trail reaches, as a multiple of the body's radius,
## and how wide it is at the head.
const TRAIL_LENGTH := 3.4
const TRAIL_WIDTH := 0.8
## How often the fall sheds a puff of smoke, on the fall's own 0..1 phase.
const PUFF_EVERY := 0.1
const PUFF_MIN := 4.0
const PUFF_MAX := 11.0
## The impact flash's half-width as the body lands and as it dies away, measured
## against the square's own width, so it reads as a blast over the footprint
## rather than as the footprint painted white.
const FLASH_FROM := 0.55
const FLASH_TO := 0.2
## How dark the square the strike took stays under the flash.
const FOOTPRINT_ALPHA := 0.35
## The shock ring's half-width as it leaves the crater and where it ends up, in
## tiles.
const RING_FROM := 0.9
const RING_TO := 3.2
const RING_WIDTH := 4.0
## How many segments the falling body's outline is drawn with.
const OUTLINE_POINTS := 48
## The dust thrown up around the crater: how many puffs, how far out they drift
## in tiles, and how wide each one grows.
const DUST_PUFFS := 8
const DUST_FROM := 0.8
const DUST_TO := 2.0
const DUST_MIN := 3.0
const DUST_MAX := 9.0
## Above the cursor, which is the highest thing the board otherwise draws.
const Z := 20

## 0 as the body enters the frame, 1 once the dust has settled.
var t: float = 0.0:
	set(value):
		t = value
		queue_redraw()

var _seconds := 0.0
var _playing := false
var _skipped := false
var _struck := false


func _ready() -> void:
	z_index = Z
	hide()
	set_process(false)


## Plays the strike over `centre` and returns once the dust has settled.
## Awaitable, like every other beat the animator holds the flow on.
func strike(centre: Vector2i, seconds: float) -> void:
	_place(centre)
	_seconds = maxf(seconds, PUFF_EVERY)
	_playing = true
	_skipped = false
	_struck = false
	t = 0.0
	show()
	set_process(true)
	await finished


## Freezes the strike at one moment and leaves it there, for a screenshot: no
## clock runs, nothing sounds, and the same frame comes back every run.
func pose_at(centre: Vector2i, at: float) -> void:
	_place(centre)
	_playing = false
	set_process(false)
	show()
	t = clampf(at, 0.0, 1.0)


func _place(centre: Vector2i) -> void:
	position = BattleView.cell_center(centre)


func _process(delta: float) -> void:
	_advance(t + delta * FastForward.rate() / _seconds)


## The skip door the cut-ins use, asked of the one authority that owns it, so
## whatever retires a cut-in retires this too.
func _unhandled_input(event: InputEvent) -> void:
	if not _playing:
		return
	if not CutscenePlayback.is_skip_press(event):
		return
	get_viewport().set_input_as_handled()
	_skipped = true
	_advance(1.0)


## The one place the clock moves: the impact fires once, and reaching the end
## ends the run once. A skip sets the clock to 1 rather than cancelling anything,
## which is what makes a press at any beat land on the board a full playthrough
## would have left.
func _advance(to: float) -> void:
	t = minf(to, 1.0)
	if not _struck and t >= IMPACT:
		_struck = true
		if not _skipped:
			struck.emit()
	if t >= 1.0 and _playing:
		_playing = false
		set_process(false)
		hide()
		finished.emit()


func _draw() -> void:
	if t < IMPACT:
		_draw_fall(t / IMPACT)
	else:
		_draw_aftermath((t - IMPACT) / (1.0 - IMPACT))


## The body on its way down, accelerating along a straight line into the square.
func _draw_fall(phase: float) -> void:
	_draw_smoke(phase)
	var head := _body_at(phase)
	var radius := lerpf(BODY_MIN, BODY_MAX, phase)
	var heading := (-ENTRY).normalized()
	var side := Vector2(-heading.y, heading.x) * radius * TRAIL_WIDTH
	var tail := head - heading * radius * TRAIL_LENGTH
	draw_colored_polygon(
		PackedVector2Array([head + side, head - side, tail]), Color(UiTheme.DANGER, 0.45)
	)
	draw_circle(head, radius, UiTheme.DANGER)
	draw_arc(head, radius, 0.0, TAU, OUTLINE_POINTS, UiTheme.HARD_BORDER, BODY_OUTLINE)
	draw_circle(head + heading * radius * CORE_LEAD, radius * CORE_RADIUS, UiTheme.WHITE)


## Where the body is at a moment of the fall — a pure function of the phase, so
## the trail of smoke behind it is drawn by asking for its older positions rather
## than by remembering them.
func _body_at(phase: float) -> Vector2:
	return ENTRY.lerp(Vector2.ZERO, phase * phase)


func _draw_smoke(phase: float) -> void:
	var puff := 0.0
	while puff <= phase:
		var age := phase - puff
		draw_circle(
			_body_at(puff),
			lerpf(PUFF_MIN, PUFF_MAX, age),
			Color(UiTheme.NEUTRAL_DARK, maxf(0.55 - age * 0.7, 0.0))
		)
		puff += PUFF_EVERY


## The landing, drawn from the ground up: the square the strike took, the dust it
## threw, the ring running out of it, and the flash over all of it.
##
## The ring and the flash are square because the footprint is: the preview aims a
## SPAN x SPAN block, so a round blast over it would disagree with what the player
## was shown about which units were hit. The body falling is the only round thing.
func _draw_aftermath(phase: float) -> void:
	var square := float(SPAN * TILE)
	_draw_square(square * 0.5, Color(UiTheme.DANGER, (1.0 - phase) * FOOTPRINT_ALPHA), 0.0)
	for i in DUST_PUFFS:
		var out := Vector2.RIGHT.rotated(TAU * float(i) / float(DUST_PUFFS))
		draw_circle(
			out * lerpf(DUST_FROM, DUST_TO, phase) * TILE,
			lerpf(DUST_MIN, DUST_MAX, phase),
			Color(UiTheme.NEUTRAL_DARK, (1.0 - phase) * 0.55)
		)
	_draw_square(
		lerpf(RING_FROM, RING_TO, phase) * TILE,
		Color(UiTheme.DANGER, 1.0 - phase),
		maxf(RING_WIDTH * (1.0 - phase), 1.0)
	)
	_draw_square(
		lerpf(FLASH_FROM, FLASH_TO, phase) * square,
		Color(UiTheme.WHITE, pow(1.0 - phase, 2.0)),
		0.0
	)


## A square centred on the crater, filled at width 0 and an outline otherwise.
func _draw_square(half: float, colour: Color, width: float) -> void:
	var rect := Rect2(Vector2(-half, -half), Vector2(half, half) * 2.0)
	draw_rect(rect, colour, width <= 0.0, width)
