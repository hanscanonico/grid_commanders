class_name CaptureCutscene
extends CanvasLayer
## The capture cut-in: when an infantry squad takes a property, the board gives
## way to a single-panel frame — the squad marches up, mashes the building down
## over one to three hops as a points meter drains, and on completion the
## property flashes white and flips to the capturing faction's colours under a
## CAPTURED! banner — then the map returns.
##
## The sibling of CombatCutscene, and it replays; it never decides (plan D1).
## Every beat is driven by the CaptureCommand.CaptureResult it is handed — the
## two point totals and whether ownership flipped. The chips the mashes knock off
## are a presentation split of that committed delta (`points_before -
## points_after`), never a call back into `capture_strength`, so a press
## mid-mash lands on the same number the terrain panel reports.
##
## One clock, one exit — both `CutscenePlayback`'s, held rather than repeated.
## Every visual below is a pure function of `_play.t`, so skipping is the clock
## jumping to its end rather than a race between cancelled tweens, and the
## awaitable `play()` resolves exactly once whatever the player presses (plan R2).
## This file owns the beat sheet and what goes in the band; the shell around it —
## letterbox, dim, camera punch, cue ledger — is shared with CombatCutscene.
##
## Owned by Battle, which assigns `view` and hands it to the animator — the same
## assignment-not-constructor shape the rest use.

## Emitted once per cut-in, when the wipe has cleared and control belongs to the
## caller again. Every branch funnels through `_finish`, the only place it emits.
signal finished

## Beat budgets, in seconds. A completing capture runs ~2.4 s and a partial ~2.0
## — the tempo the plan's beat sheet asks for, and deliberately faster than the
## design handoff's 4.6 s reference, because captures are the most frequent
## ceremony in the game (plan R1). Fixed constants scaled by the streak pacing the
## animator sets, exactly as CombatCutscene's are — the two cut-ins keep one clock
## shape, and neither reads GameSpeed for its beat lengths.
const WIPE_IN := 0.22
const PLATES := 0.22
const MARCH := 0.34
const HOP_DUR := 0.24
const HOP_GAP := 0.03
const HOP_HEIGHT := 46.0
const FLIP := 0.30
const BANNER := 0.55
const HOLD := 0.20
const WIPE_OUT := 0.20
const MIN_WIPE_SCALE := 0.4
## At most three mashes, however many points came off — a strength-12 doctrine
## turn still reads as three hops, not twelve.
const MAX_HOPS := 3

## The band shake's two frequencies. Deliberately not the combat cut-in's 91/77 —
## see CutscenePlayback.frame_band for why the drift is carried rather than fixed.
const SHAKE_FREQ := Vector2(90.0, 76.0)


## The beat windows this capture has, laid out on the clock. A completing capture
## has a flip; a partial does not, and its banner opens where the flip would have.
class Beats:
	var plates := Vector2.ZERO
	var march := Vector2.ZERO
	var hops: Array[Vector2] = []
	var lands := PackedFloat32Array()
	var flip := Vector2.ZERO
	var banner := Vector2.ZERO
	var wipe_out := Vector2.ZERO
	var total := 0.0


## The board the capture is taken on. Assigned by Battle before first use. The
## cut-in reads the property's terrain and the two atlas rows off it — the owner's
## and the capturer's — which is what dresses the panel and drives the flip.
var view: BattleView
## Playback rate and how much of the closing hold/wipe is kept — the AI-pacing
## levers (plan CP3), set by the animator's shared streak state so a turn mixing
## attacks and captures tightens as one run.
var speed := 1.0
var tail_scale := 1.0

## The clock, the letterbox and the single exit, shared with CombatCutscene.
var _play := CutscenePlayback.new()
var _stage: CaptureStage
var _hud: CaptureHud

var _beats := Beats.new()
var _result: CaptureCommand.CaptureResult
## The point chips each mash knocks off, largest first, summing to the meter's
## drop. Computed once in `_pose`.
var _chips := PackedInt32Array()


func _ready() -> void:
	_build()
	_play.root.hide()
	set_process(false)


# --- playing -----------------------------------------------------------------


## Plays one already-applied capture and returns when the map is back. Awaitable:
## both call sites hold the interaction flow on it. The animator punches the board
## in on its way here; the cut-in eases that flinch back out over the closing wipe,
## through the view (see CutscenePlayback).
func play(result: CaptureCommand.CaptureResult, unit: Unit, cell: Vector2i) -> void:
	_pose(result, unit, cell)
	_play.begin(_beats.total, view)
	_play.layout()
	_apply()
	_play.root.show()
	set_process(true)
	set_process_unhandled_input(true)
	await finished


## Freezes the cut-in at one moment of its own clock and leaves it there, for a
## screenshot (plan D3). No clock runs, no sound plays, and `finished` is never
## emitted — a still, not a playthrough, which is what makes it byte-stable.
## Dev-only; play never poses.
func pose_at(result: CaptureCommand.CaptureResult, unit: Unit, cell: Vector2i, at: float) -> void:
	_pose(result, unit, cell)
	_play.pose(_beats.total, at)
	_play.layout()
	_apply()
	_play.root.show()


## The diorama, so a posed still can be read back. Dev-only, like `pose_at` and
## for the same caller: the scenario driver checks that the squad and the property
## it is taking are painted in the faction rows SideIdentity gives them (COM-10).
func stage() -> CaptureStage:
	return _stage


## Fast-forwards every remaining beat to its end state. Never aborts: the clock is
## set to the end, the final tableau is applied, and the same exit runs — which is
## what makes a skip at any beat land on the right board.
func skip() -> void:
	_play.skip()


func _process(delta: float) -> void:
	if not _play.playing:
		return
	var done := _play.advance(delta * speed)
	_apply()
	if done:
		_finish()


func _unhandled_input(event: InputEvent) -> void:
	if _play.consume_skip(event):
		get_viewport().set_input_as_handled()


## The single exit. Every branch reaches it, and it emits once.
func _finish() -> void:
	if not _play.playing:
		return
	_play.end()
	set_process(false)
	set_process_unhandled_input(false)
	finished.emit()


# --- staging -----------------------------------------------------------------


## Poses the stage and hud and works out the beat windows this capture has.
func _pose(result: CaptureCommand.CaptureResult, unit: Unit, cell: Vector2i) -> void:
	_result = result
	var terrain := view.map.terrain_at(cell)
	_play.accent = _accent_of(unit.team)
	# The two faction rows the flip crosses between, both SideIdentity's answer —
	# and the second of them is the marching squad's row as well, since the squad
	# *is* the capturer (see CaptureStage.bind).
	var owner_row := view.identity.atlas_row(result.owner_before)
	var capturer_row := view.identity.atlas_row(unit.team)
	_stage.bind(unit, terrain, terrain.atlas_col, owner_row, capturer_row)
	var removed := maxi(result.points_before - result.points_after, 0)
	var hops := clampi(removed, 1, MAX_HOPS)
	_chips = _split(removed, hops)
	_beats = _plan(result.captured, hops, clampf(tail_scale, 0.0, 1.0))


## A side's faction accent, asked of the identity that resolved the match rather
## than of the commander directly — the sibling of CombatCutscene._accent_of, and
## for the same reason. SideIdentity gives a commanded side its own faction's
## colour and a commander-less one the classic its slot falls back to, and it is
## the only one that knows about the mirror borrow: the plate must wear whatever
## the marching squad beside it is drawn in, borrowed classic included.
func _accent_of(team: int) -> Color:
	return view.identity.theme(team).color_light


## Splits the points removed across the mashes, largest first, so the chips sum
## to the meter's committed drop: 10 over 3 hops is 4/3/3, a doctrine's 12 is
## 4/4/4, a finishing 1 is a single hop of 1.
static func _split(removed: int, hops: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	var base := removed / hops
	var extra := removed % hops
	for i in hops:
		out.append(base + (1 if i < extra else 0))
	return out


## The beat sheet, laid out on the clock. `tail` trims the closing hold and wipe,
## the only part the pacing is allowed to take — the mashes and the flip keep
## their length, because those carry what the cut-in is for.
static func _plan(captured: bool, hops: int, tail: float) -> Beats:
	var beats := Beats.new()
	beats.plates = Vector2(WIPE_IN * 0.5, WIPE_IN * 0.5 + PLATES)
	beats.march = Vector2(WIPE_IN, WIPE_IN + MARCH)
	var t := beats.march.y
	for i in hops:
		var start := t + i * (HOP_DUR + HOP_GAP)
		beats.hops.append(Vector2(start, start + HOP_DUR))
		beats.lands.append(start + HOP_DUR)
	var settled: float = beats.lands[beats.lands.size() - 1]
	var banner_start := settled + 0.05
	if captured:
		beats.flip = Vector2(settled + 0.05, settled + 0.05 + FLIP)
		banner_start = beats.flip.x + FLIP * 0.4
	beats.banner = Vector2(banner_start, banner_start + BANNER)
	var hold := beats.banner.y + HOLD * tail
	beats.wipe_out = Vector2(hold, hold + WIPE_OUT * maxf(tail, MIN_WIPE_SCALE))
	beats.total = beats.wipe_out.y
	return beats


# --- the frame ---------------------------------------------------------------


## Everything the cut-in shows, as a pure function of the clock. Called once per
## frame while playing and once by `skip`, so it may never do anything that only
## makes sense the first time — sounds go through `_play.cue`.
func _apply() -> void:
	var present := clampf(
		_play.window(Vector2(0.0, WIPE_IN)) - _play.window(_beats.wipe_out), 0.0, 1.0
	)
	var plates := _play.window(_beats.plates) * present
	_play.frame(present, _beats.wipe_out)
	_frame_band(present)

	# The meter reading and the chips: a split of the committed delta, applied as
	# each mash lands.
	var shown := _result.points_before
	var flip_p := _play.window(_beats.flip) if _result.captured else 0.0
	var flash := sin(flip_p * PI) if (flip_p > 0.0 and flip_p < 1.0) else 0.0
	var squash := 0.0
	var hop_advance := 0.0
	var chip_p := PackedFloat32Array()
	for i in _beats.hops.size():
		var hp := _play.window(_beats.hops[i])
		if hp > 0.0:
			hop_advance = (i + minf(hp * 2.0, 1.0)) / float(_beats.hops.size())
		var land: float = _beats.lands[i]
		if _play.t >= land:
			shown -= _chips[i]
		squash = maxf(squash, sin(clampf((_play.t - land) / 0.22, 0.0, 1.0) * PI) * 0.12)
		chip_p.append(_play.window(Vector2(land, land + 0.6)))

	_stage.plate_p = plates
	_stage.march_p = _play.window(_beats.march)
	_stage.hop_advance = hop_advance
	_stage.squad_y = -sin(_active_hop() * PI) * HOP_HEIGHT
	_stage.squash = squash
	_stage.brightness = flash * 2.0
	_stage.flipped = _result.captured and flip_p >= 0.5
	_stage.dust = _dust_windows()
	_stage.clock = _play.t
	_stage.modulate.a = present
	_stage.queue_redraw()

	_hud.points_shown = shown
	_hud.meter_p = plates
	_hud.chip_values = _chips
	_hud.chip_p = chip_p
	_hud.chip_at = _prop_head()
	_hud.flash = flash * 0.55
	_hud.specks_p = (
		_play.window(Vector2(_beats.flip.y - 0.05, _beats.flip.y + 0.8))
		if _result.captured
		else 0.0
	)
	_hud.specks_at = _prop_head() + Vector2(0.0, 20.0)
	_hud.specks_accent = _play.accent
	_frame_banner()
	_hud.modulate.a = present
	_hud.queue_redraw()

	_sound()


## Where along its arc the one hop in flight sits, 0 while none is.
func _active_hop() -> float:
	for span in _beats.hops:
		var hp := _play.window(span)
		if hp > 0.0 and hp < 1.0:
			return hp
	return 0.0


## One dust window per hop, opening as it lands.
func _dust_windows() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for land in _beats.lands:
		out.append(_play.window(Vector2(land, land + 0.5)))
	return out


## The property's head in the band's coordinates — where the chips rise from and
## the specks fan out. Fixed for the whole cut-in so nothing anchored here drifts.
func _prop_head() -> Vector2:
	return Vector2(_play.band.size.x * CaptureStage.PROP_CENTER, _play.band.size.y * 0.34)


func _frame_banner() -> void:
	_hud.banner_p = _play.window(Vector2(_beats.banner.x, _beats.banner.x + 0.3))
	_hud.banner_complete = _result.captured
	if _result.captured:
		_hud.banner_text = "CAPTURED!"
		_hud.banner_sub = ""
	else:
		_hud.banner_text = "OCCUPYING"
		var left := maxi(_result.points_after, 0)
		_hud.banner_sub = "%d/%d LEFT" % [left, GameState.CAPTURE_POINTS]
	if _play.t < _beats.banner.x or _play.t >= _beats.banner.y:
		_hud.banner_p = 0.0


## The single panel pushes in slightly, with a decaying shake on every landing and
## the flip flash. The push and the shake are the shell's; which beats jolt it is
## this cut-in's alone.
func _frame_band(present: float) -> void:
	var jolt := 0.0
	for land in _beats.lands:
		jolt += CutscenePlayback.decay(_play.window(Vector2(land, land + 0.3)))
	if _result.captured:
		var flip_p := _play.window(_beats.flip)
		jolt += (sin(flip_p * PI) if (flip_p > 0.0 and flip_p < 1.0) else 0.0) * 0.6
	_play.frame_band(present, jolt, SHAKE_FREQ, _play.window(Vector2(WIPE_IN, WIPE_IN + 0.3)))


func _sound() -> void:
	if not _play.playing:
		return
	for i in _beats.lands.size():
		_play.cue(StringName("mash_%d" % i), _beats.lands[i], &"capture")
	if _result.captured:
		_play.cue(&"flip", _beats.banner.x, &"fanfare")


# --- nodes -------------------------------------------------------------------


## The shell, then this cut-in's own two draw layers inside its band, then the
## letterbox over both — the ordering the bars depend on to sit on top.
func _build() -> void:
	_play.build(self, _place_layers)
	_stage = CaptureStage.new()
	_hud = CaptureHud.new()
	_play.band.add_child(_stage)
	_play.band.add_child(_hud)
	_play.build_bars()


## Re-places the two draw layers whenever the shell re-measures the viewport.
func _place_layers(band: Vector2) -> void:
	_stage.position = Vector2.ZERO
	_stage.size = band
	_hud.position = Vector2.ZERO
	_hud.size = band
