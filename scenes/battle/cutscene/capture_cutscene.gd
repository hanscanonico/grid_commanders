class_name CaptureCutscene
extends CutsceneDirector
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
## One clock, one exit — both `CutsceneDirector`'s, held rather than repeated.
## Every visual below is a pure function of `_play.t`, so skipping is the clock
## jumping to its end rather than a race between cancelled tweens, and the
## awaitable `play()` resolves exactly once whatever the player presses (plan R2).
## This file owns what goes in the band and CaptureBeats the beat sheet; the
## lifecycle and the shell around it — letterbox, dim, camera punch, cue ledger —
## are shared with CombatCutscene.

## How high a mash hops the squad, in band pixels. The beat sheet — when each
## window opens and the chips each mash knocks off — is CaptureBeats'.
const HOP_HEIGHT := 46.0

## The band shake's two frequencies. Deliberately not the combat cut-in's 91/77 —
## see CutscenePlayback.frame_band for why the drift is carried rather than fixed.
const SHAKE_FREQ := Vector2(90.0, 76.0)

var _stage: CaptureStage
var _hud: CaptureHud

var _beats := CaptureBeats.new()
var _result: CaptureCommand.CaptureResult


func _ready() -> void:
	_build()
	_play.root.hide()


# --- playing -----------------------------------------------------------------


## Plays one already-applied capture and returns when the map is back. Awaitable:
## both call sites hold the interaction flow on it. The animator punches the board
## in on its way here; the cut-in eases that flinch back out over the closing wipe,
## through the view (see CutscenePlayback).
func play(result: CaptureCommand.CaptureResult, unit: Unit, cell: Vector2i) -> void:
	_pose(result, unit, cell)
	run()
	await finished


## Freezes the cut-in at one moment of its own clock and leaves it there, for a
## screenshot (plan D3). No clock runs, no sound plays, and `finished` is never
## emitted — a still, not a playthrough, which is what makes it byte-stable.
## Dev-only; play never poses.
func pose_at(result: CaptureCommand.CaptureResult, unit: Unit, cell: Vector2i, at: float) -> void:
	_pose(result, unit, cell)
	hold(at)


## The diorama, so a posed still can be read back. Dev-only, like `pose_at` and
## for the same caller: the scenario driver checks that the squad and the property
## it is taking are painted in the faction rows SideIdentity gives them (COM-10).
func stage() -> CaptureStage:
	return _stage


# --- staging -----------------------------------------------------------------


## Poses the stage and hud and works out the beat windows this capture has.
func _pose(result: CaptureCommand.CaptureResult, unit: Unit, cell: Vector2i) -> void:
	_result = result
	var terrain := view.map.terrain_at(cell)
	_play.accent = accent_of(unit.team)
	# The two faction rows the flip crosses between, both SideIdentity's answer —
	# and the second of them is the marching squad's row as well, since the squad
	# *is* the capturer (see CaptureStage.bind).
	var owner_row := view.identity.atlas_row(result.owner_before)
	var capturer_row := view.identity.atlas_row(unit.team)
	_stage.bind(unit, terrain, terrain.atlas_col, owner_row, capturer_row)
	_beats = CaptureBeats.plan(result, clampf(tail_scale, 0.0, 1.0))


## How long this capture runs: the beat sheet's own end.
func _total() -> float:
	return _beats.total


# --- the frame ---------------------------------------------------------------


## Everything the cut-in shows — sounds go through `_play.cue`, which is what
## keeps a beat crossed twice heard once.
func _apply() -> void:
	var present := clampf(
		_play.window(Vector2(0.0, CaptureBeats.WIPE_IN)) - _play.window(_beats.wipe_out), 0.0, 1.0
	)
	var plates := _play.window(_beats.plates) * present
	_play.frame(present, _beats.wipe_out)
	_frame_band(present)

	# The meter reading and the chips: a split of the committed delta, applied as
	# each mash lands.
	var shown := _beats.points_at(_result.points_before, _play.t)
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
	_hud.chip_values = _beats.chips
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
	_play.frame_band(
		present,
		jolt,
		SHAKE_FREQ,
		_play.window(Vector2(CaptureBeats.WIPE_IN, CaptureBeats.WIPE_IN + 0.3))
	)


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
