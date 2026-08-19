class_name CutscenePlayback
extends RefCounted
## The shell a cut-in plays inside: one clock, one letterbox, one exit.
##
## Both directors — `CombatCutscene` and `CaptureCutscene` — used to carry their
## own copy of this, and the copies were byte-identical: `_process`, `skip`,
## `_finish`, `_unhandled_input`, `_frame_bars`, `_new_bar`, `_restore_zoom`,
## `_window`, `_decay`, `_cue` and `_accent_of` matched to the character across
## the two files (architecture finding A5). What each cut-in actually owns is its
## beat sheet and what it paints in the band; everything around that was the same
## machinery written twice, and the divergence the finding predicted had already
## started — see `shake` below.
##
## Composed rather than inherited, which is what keeps the directors free to be
## what they are: they hold one of these, hand it their total and their board,
## and ask it for the clock. It owns no beat and paints nothing inside the band.
##
## **The two guarantees it exists to keep identical for every cut-in:**
##
## * *One clock.* Every visual is a pure function of `t`, so skipping is
##   `t = total` rather than a race between cancelled tweens, and a posed still is
##   the same still every run (cutscene plan R2/R4).
## * *One exit.* `advance` reports the end exactly once and `end` tears down
##   exactly once, so the director's `finished` cannot be emitted twice or
##   skipped — whatever the player presses, and whenever they press it.

## The letterbox's share of the screen height, top and bottom each.
const BAR_RATIO := 0.13
## How dark the board goes behind the band.
const DIM_ALPHA := 0.62
## How much the band pushes toward the viewer as it opens.
const PUSH_SCALE := 0.03
## The band shake's amplitude at full jolt.
const SHAKE_PX := 5.0
## The faction line on the letterbox's inner edge.
const ACCENT_PX := 2.0

## The full-screen node everything is parented to. The director shows and hides
## it; it starts hidden.
var root: Control
## Where the cut-in paints. The director adds its own children here and sizes
## them in its layout callback — this class never draws inside it.
var band: Control
## The faction colour the letterbox edge wears. Set by the director from
## `SideIdentity`, which is the only thing that knows about the mirror borrow.
var accent := Color.WHITE
## The clock every visual is a function of, and the end it runs to.
var t := 0.0
var total := 0.0
## How fast that clock runs against real time, taken from the speed tier when the
## playthrough begins. The shell is the one place a tier reaches a cut-in: the
## directors own beat sheets and know nothing about the setting, so scaling here
## keeps both of them obeying it and neither of them deciding it.
##
## Read once at `begin` rather than every frame because a cut-in blocks the flow
## it could be changed from — a run holds the rate it opened at, so `t` advances
## monotonically at one pace.
var rate := 1.0
## True between `begin` and `end`. A posed still never sets it, which is what
## keeps `pose_at` from ever emitting `finished`.
var playing := false
## True once the player has cut the cut-in short. Sounds are suppressed from that
## moment — a skip is silent rather than a pile-up of every cue it fast-forwarded
## through.
var skipping := false
## The viewport as last measured, and the letterbox height derived from it.
var view_size := Vector2(640.0, 360.0)
var bar_h := 46.0

var _dim: ColorRect
var _top_bar: ColorRect
var _bottom_bar: ColorRect
var _top_edge: ColorRect
var _bottom_edge: ColorRect
## The board the entry flinch punched, and how far in. Null for a posed still,
## which never punched anything and must leave the board's zoom alone.
var _board: BattleView
var _punch_from := 1.0
## Cue name -> true once its sound has played, so a beat crossed twice by a frame
## boundary is heard once.
var _cues: Dictionary = {}
## Called with the band's size whenever the viewport changes, so the director can
## re-place what it painted there.
var _on_layout := Callable()


## Builds the shell into the director's own CanvasLayer and remembers how to tell
## it the band moved. `on_layout` is called with the band size, immediately and on
## every later resize.
func build(layer: CanvasLayer, on_layout: Callable) -> void:
	_on_layout = on_layout
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)
	_dim = ColorRect.new()
	_dim.color = Color(CutscenePalette.DIM, 0.0)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_dim)
	band = Control.new()
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(band)


## The letterbox bars, added *after* the director has put its own children in the
## band so they draw over it. Split from `build` for exactly that ordering.
func build_bars() -> void:
	_top_bar = _new_bar()
	_bottom_bar = _new_bar()
	_top_edge = _new_bar()
	_bottom_edge = _new_bar()
	root.resized.connect(layout)


func _new_bar() -> ColorRect:
	var bar := ColorRect.new()
	bar.color = CutscenePalette.BAR
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bar)
	return bar


## Sizes the band off the viewport rather than off constants, so a cut-in still
## frames correctly if the base resolution ever changes, then lets the director
## re-place what it painted inside.
func layout() -> void:
	view_size = root.get_viewport_rect().size
	bar_h = roundf(view_size.y * BAR_RATIO)
	var size := Vector2(view_size.x, view_size.y - bar_h * 2.0)
	_dim.position = Vector2.ZERO
	_dim.size = view_size
	band.position = Vector2(0.0, bar_h)
	band.size = size
	band.pivot_offset = size * 0.5
	_top_bar.position = Vector2.ZERO
	_bottom_bar.position = Vector2(0.0, view_size.y - bar_h)
	if _on_layout.is_valid():
		_on_layout.call(size)


# --- the clock ----------------------------------------------------------------


## Starts a playthrough over the board the animator has just punched into, whose
## flinch this then eases back out.
func begin(total_in: float, board: BattleView) -> void:
	total = total_in
	rate = Settings.speed.cutscene_rate()
	_board = board
	_punch_from = board.punch_zoom
	t = 0.0
	playing = true
	skipping = false
	_cues.clear()


## Freezes the clock at one moment and leaves it there, for a screenshot. No
## clock runs and no sound plays, which is what makes a posed frame byte-stable.
func pose(total_in: float, at: float) -> void:
	total = total_in
	rate = 1.0
	_board = null
	t = clampf(at, 0.0, total)


## Advances the clock at the tier's rate and reports whether this frame reached
## the end. True exactly once per playthrough, which is what makes the exit
## single. Skipping still sets `t = total` outright, so any press at any tier
## lands on the final tableau.
func advance(delta: float) -> bool:
	t = minf(t + delta * rate, total)
	return t >= total


## Fast-forwards every remaining beat to its end state. Never aborts: the clock
## is set to the end, so the final tableau is applied and the same exit runs —
## which is what makes a skip at any beat land on the right board.
func skip() -> void:
	if not playing:
		return
	skipping = true
	t = total


## The skip press, decided in one place for both cut-ins so the two can never
## disagree about what cuts one short. Returns whether the event was consumed;
## the director marks it handled, which needs a Node.
func consume_skip(event: InputEvent) -> bool:
	if not playing:
		return false
	var pressed := (
		event.is_action_pressed(&"confirm")
		or event.is_action_pressed(&"cancel")
		or (event is InputEventMouseButton and (event as InputEventMouseButton).pressed)
	)
	if not pressed:
		return false
	skip()
	return true


## Tears the shell down. The director emits `finished` after calling this, and
## the `playing` guard above it is what keeps that emission single.
func end() -> void:
	playing = false
	root.hide()


# --- the frame ----------------------------------------------------------------


## Everything the shell itself draws, as a pure function of the clock: the dim
## behind the band, the board's flinch easing out, and the letterbox with its
## faction line. `present` is the director's own wipe curve — the shell does not
## decide when a cut-in is on screen, only what it looks like while it is.
func frame(present: float, wipe_out: Vector2) -> void:
	_dim.color.a = DIM_ALPHA * present
	_restore_zoom(wipe_out)
	var bar := bar_h * present
	_top_bar.size = Vector2(view_size.x, bar)
	_bottom_bar.position = Vector2(0.0, view_size.y - bar)
	_bottom_bar.size = Vector2(view_size.x, bar)
	# Brightest while the halves are still sliding, settling to a quiet rule once
	# they are home — the wipe is the acting side arriving, in their colour.
	var glow := lerpf(1.0, 0.55, present)
	var edge := Color(accent, present * glow)
	_top_edge.color = edge
	_top_edge.position = Vector2(0.0, bar)
	_top_edge.size = Vector2(view_size.x, ACCENT_PX)
	_bottom_edge.color = edge
	_bottom_edge.position = Vector2(0.0, view_size.y - bar - ACCENT_PX)
	_bottom_edge.size = Vector2(view_size.x, ACCENT_PX)


## Eases the board's entry punch back out over the closing wipe, in lockstep with
## `present` falling to zero — so the map is already at rest on the frame the wipe
## uncovers it, and a skip (which pins the reveal at 1) lands it exactly at rest
## with everything else. What is eased is a still of the board rather than the
## camera, which never leaves its rung (see BoardPunch); this asks the view for it
## so the shell keeps one route to the board and no second opinion about the
## flinch.
func _restore_zoom(wipe_out: Vector2) -> void:
	if _board == null:
		return
	var reveal := window(wipe_out)
	_board.punch_zoom = 1.0 if reveal >= 1.0 else lerpf(_punch_from, 1.0, reveal)


## The band's push and shake, the one piece of shell framing a director still
## parameterises. `freq` is the shake's two frequencies.
##
## Those frequencies are the finding's own evidence, carried forward deliberately:
## the combat cut-in shakes at 91/77 and the capture at 90/76 — the same effect,
## copied and drifted by 1 Hz before either was extracted. Unifying them would
## move shipped pixels, and a refactor that also changes what the screen shows is
## a refactor nothing can verify, so they are passed in and left alone. Settling
## on one pair is a one-line follow-up with its own before/after frames.
func frame_band(present: float, jolt: float, freq: Vector2, push_from: float) -> void:
	var push := 1.0 + PUSH_SCALE * push_from * present
	band.scale = Vector2(push, push)
	band.position = Vector2(
		sin(t * freq.x) * jolt * SHAKE_PX, bar_h + cos(t * freq.y) * jolt * SHAKE_PX
	)


# --- curves -------------------------------------------------------------------


## Where the clock sits inside a beat window, 0 -> 1. A zero-length window — a
## beat this cut-in does not have — is always 0, switching its branch of the frame
## off.
func window(span: Vector2) -> float:
	if span.y <= span.x:
		return 0.0
	return clampf((t - span.x) / (span.y - span.x), 0.0, 1.0)


## A jolt strongest as its window opens and gone a third of the way in.
static func decay(progress: float) -> float:
	if progress <= 0.0 or progress >= 1.0:
		return 0.0
	return maxf(0.0, 1.0 - progress / 0.35)


## Plays a cue's sound the first time the clock crosses it. Silent during a skip,
## so fast-forwarding through five beats does not fire five sounds at once.
func cue(key: StringName, at: float, sfx: StringName) -> void:
	if at <= 0.0 or _cues.has(key) or t < at:
		return
	_cues[key] = true
	if not skipping:
		Sfx.play(sfx)
