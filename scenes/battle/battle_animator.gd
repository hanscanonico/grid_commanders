class_name BattleAnimator
extends RefCounted
## Plays the battle scene's animations: unit movement, the combat exchange,
## the turn banner, camera shake, and the cursor pulse, with the sound effects
## that go with them.
##
## Every method here animates something that has *already* been decided. The
## animator never chooses a gameplay outcome, applies a command, or reads a
## rule — it is handed a result and shows it. Its awaitable methods let Battle
## hold the interaction flow still until an animation finishes.
##
## Depends on BattleView to find sprites; never on Battle. Tweens need a Node
## to live on, so the scene root is passed in as a plain Node.
##
## Every duration it waits is a GameSpeed tier's, asked of `Settings` at the
## moment the animation starts rather than cached at scene load, so a speed
## changed mid-match lands on the very next move. The sprite it hands durations
## to derives nothing, and BattleAiRunner paces its turn off the same answer. No
## literal seconds below: a tween timed by a number written here would ignore the
## player's setting forever.

signal banner_finished
signal power_banner_finished
signal speech_finished

## The two durations that deliberately do *not* follow the setting: the shake is
## impact feedback and the pulse is idle UI, and neither is gameplay theatre.
## Named rather than written inline so the exception is visibly meant, and so
## "no bare seconds in a battle tween" stays a grep anyone can run.
const SHAKE_STEP_SECONDS := 0.04
const CURSOR_PULSE_SECONDS := 0.4
## Two cut-ins closer together than this are treated as one run of fighting, and
## each one after the first is tightened (plan BA4, risk R1). Comfortably longer
## than BattleAiRunner.COMMAND_DELAY, which is what makes a computer's turn
## qualify; a human picks a unit, moves it and opens a menu between attacks, so
## an ordinary player's turn never does.
const CUT_IN_STREAK_GAP_MS := 1600
## How far the tightening goes: full ceremony at the start of a run, and by the
## fourth attack in a row a cut-in that plays a third faster with most of its
## closing hold gone. The volley and the impact keep their length throughout.
const CUT_IN_MAX_STREAK := 4
const CUT_IN_STREAK_SPEED := 0.11
const CUT_IN_STREAK_TAIL := 0.22
## The board's flinch as the frame is taken over: a short zoom toward the cell
## that is about to be struck. The cursor is already parked there by both call
## sites, and the camera follows the cursor, so there is nothing to pan. Its
## length is the cut-in's first beat in all but name, so it runs on the cut-in's
## clock rate — the seconds below are the default tier's, like the beat sheets'.
const PUNCH_ZOOM := 1.14
const PUNCH_SECONDS := 0.11

## Assigned by Battle before first use, like BattleView's nodes.
var node: Node
var view: BattleView
var perspective: BattlePerspective
var cursor: Sprite2D
var turn_banner: TurnBanner
var power_banner: CommanderPowerBanner
## What a scripted mission beat says, held like the power card and retired by the
## same press; down for every skirmish, because nothing else ever fills it.
var mission_speech: MissionSpeechCard
## The full-screen battle cut-in. Every resolved attack goes through it when the
## player has it on and both sides are visible; see `animate_combat`.
var cutscene: CombatCutscene
## The full-screen capture cut-in, combat's sibling. Every completed capture
## action goes through it under the same gate; see `animate_capture`.
var capture_cutscene: CaptureCutscene
## True for a run that exists to be photographed. Suppresses the two open-ended
## animations — see `shake_camera` and `start_cursor_pulse` — and the cut-in.
var capturing := false

var _banner_tween: Tween
var _power_banner_tween: Tween
var _speech_tween: Tween
## When the last cut-in ended, and how many have run back to back since the
## fighting started. Held as elapsed time rather than as a per-turn counter
## somebody has to remember to reset: there is no lifecycle to get wrong, and a
## fast pace cannot leak out of a computer's turn into the player's next one.
var _last_cut_in_ms := -CUT_IN_STREAK_GAP_MS
var _cut_in_streak := 0

# --- movement ----------------------------------------------------------------


## Tweens a sprite along a path without touching the sim. Awaitable.
##
## Instant sets the destination and returns in the same frame — a path the flow
## already walks, since a one-cell "move" has always returned without a tween.
func animate_path(sprite: UnitSprite, path: Array[Vector2i]) -> void:
	if path.size() < 2:
		return
	Sfx.play(&"move", -6.0)
	var tier := Settings.speed
	if tier.instant:
		sprite.position = BattleView.cell_center(path[path.size() - 1])
		return
	var tween := node.create_tween()
	for i in range(1, path.size()):
		var step := BattleView.cell_center(path[i])
		tween.tween_property(sprite, "position", step, tier.move_step_seconds())
	await tween.finished


# --- combat ------------------------------------------------------------------


## Plays out one already-resolved exchange: the hit, the shake, whichever side
## died, and the counter. Awaitable, so the flow resumes once the dust settles.
##
## A null result means the move was ambushed short of the firing cell — the shot
## never happened — so there is nothing to play but the trap cue.
##
## Two bodies, one contract. With battle animations on, the exchange plays as the
## full-screen cut-in and the map is brought back into step underneath; with them
## off — or while capturing, when the viewer cannot see both combatants, or at the
## Instant tier where there is nothing to watch — the on-map version below runs,
## byte-for-byte as it always did. Either way this returns exactly once, which is
## what both call sites hold their flow on.
##
## Under Instant that on-map flash, fade and shake all fall away but the sounds
## stay: an attack the player triggered has to register even when there is
## nothing to see.
func animate_combat(result: CombatSnapshot.CombatResult, attacker: Unit, defender: Unit) -> void:
	if result == null:
		await show_ambush(attacker)
		return
	var defender_sprite := view.sprite_for(defender)
	var attacker_sprite := view.sprite_for(attacker)
	view.refresh_sprite(attacker)  # snap to the committed destination
	if _cut_in_applies(attacker, defender):
		_pace_cut_in()
		await _punch_board()
		await cutscene.play(result, attacker, defender)
		view.punch_zoom = 1.0  # safety net: the cut-in already eased it out on the wipe
		_last_cut_in_ms = Time.get_ticks_msec()
		_sync_aftermath()
		return
	Sfx.play(&"shot")
	await flash_hit(defender_sprite)
	shake_camera()
	if result.defender_died:
		Sfx.play(&"explosion")
		view.release_sprite(defender)
		await fade_out(defender_sprite)
	else:
		view.refresh_sprite(defender)
	if result.countered:
		Sfx.play(&"shot")
		await flash_hit(attacker_sprite)
	if result.attacker_died:
		view.release_sprite(attacker)
		await fade_out(attacker_sprite)
	else:
		view.refresh_sprite(attacker)
	view.sync_sprites()


## The white hit flash, at the active tier's pace. Awaitable.
func flash_hit(sprite: UnitSprite) -> void:
	var tier := Settings.speed
	await sprite.flash_hit(tier.flash_in_seconds(), tier.flash_out_seconds())


## Fades a sprite out and frees it, at the active tier's pace. Awaitable, and
## the single place a death fade's length is decided — Battle's Join merge fades
## a sprite outside combat entirely and comes through here for that reason.
func fade_out(sprite: UnitSprite) -> void:
	await sprite.die(Settings.speed.death_fade_seconds())


## Whether this exchange gets the cut-in.
##
## The visibility half is the point of the gate: under fog an exchange the
## viewer cannot see would otherwise parade two hidden units across the screen,
## so it stays on the map path, which already draws fogged units correctly. The
## question goes to BattlePerspective, which asks `Vision` — no second opinion
## on who can see what lives here (plan R6).
##
## Instant is out too: that tier exists to skip the theatre, so a full-screen
## cut-in playing on its own clock would defeat it — the exchange stays on the
## map path, which under Instant collapses to just the sounds.
func _cut_in_applies(attacker: Unit, defender: Unit) -> bool:
	if cutscene == null or capturing or not Settings.battle_animations:
		return false
	if Settings.speed.instant:
		return false
	return perspective.can_see_unit(attacker) and perspective.can_see_unit(defender)


## Sets how much ceremony whichever cut-in is about to play gets, from how long
## it has been since the last one (plan BA4). Two seconds a battle is charming for
## ten battles and a chore for two hundred — R1, the plan's own named risk — and a
## computer turn that opens fire or captures five times is exactly where that
## bites. So a run of cut-ins tightens as it goes: faster overall, and most of the
## closing hold cut away. Combat and capture share the one streak counter, so a
## turn mixing attacks and captures tightens as a single run; the pacing is routed
## to both cutscenes and whichever one is about to play reads it.
##
## What is *not* touched is the volley, the impact and the HP tick. Those carry
## the information; trimming them would make the cut-in shorter and worse, which
## is the wrong trade at any speed.
func _pace_cut_in() -> void:
	var gap := Time.get_ticks_msec() - _last_cut_in_ms
	_cut_in_streak = (
		mini(_cut_in_streak + 1, CUT_IN_MAX_STREAK) if gap < CUT_IN_STREAK_GAP_MS else 0
	)
	var streak_speed := 1.0 + _cut_in_streak * CUT_IN_STREAK_SPEED
	var streak_tail := maxf(0.0, 1.0 - _cut_in_streak * CUT_IN_STREAK_TAIL)
	if cutscene != null:
		cutscene.speed = streak_speed
		cutscene.tail_scale = streak_tail
	if capture_cutscene != null:
		capture_cutscene.speed = streak_speed
		capture_cutscene.tail_scale = streak_tail


## A short zoom onto the cell about to be struck, so the board flinches before
## the frame is taken away from it. Awaited, then left punched in: the cut-in
## covers the map for its whole run and eases the punch back out over the closing
## wipe, so the board is already at rest the moment it is uncovered — see
## CutscenePlayback._restore_zoom.
##
## Asked of `BattleView.punch_zoom`, never written to the camera, for the same
## reason `shake_camera` goes through `shake_offset`: the view derives the board's
## docking inset and the camera limits from the zoom, and a punch it never hears
## about leaves both at the resting level for as long as the flinch lasts.
func _punch_board() -> void:
	var tween := node.create_tween()
	var seconds := PUNCH_SECONDS / Settings.speed.cutscene_rate()
	(
		tween
		. tween_property(view, "punch_zoom", PUNCH_ZOOM, seconds)
		. set_trans(Tween.TRANS_CUBIC)
		. set_ease(Tween.EASE_OUT)
	)
	await tween.finished


## The map beats the cut-in stands in for. Both sides have already been shown
## dying on screen, so there is no fade left to play: this only brings the board
## back into step with a sim that has moved on — dropping the sprites of units
## the exchange removed (cargo that went down with a transport included) and
## redrawing the survivors.
func _sync_aftermath() -> void:
	view.sync_sprites()


# --- capture -----------------------------------------------------------------


## Plays out one already-applied capture: the march, the mashes, and — on a
## completing capture — the flip to the capturer's colours. Awaitable, so the
## flow resumes once the banner has cleared. The sibling of `animate_combat`, and
## it obeys the same gate, the same streak pacing, and the same camera contract.
##
## A null result means the move was ambushed short of the property — nothing was
## captured, and the `settle_move` both call sites run afterwards plays the trap
## cue — so there is nothing here to replay.
##
## With the cut-in gated out — animations off, while capturing, at the Instant
## tier, or when the viewer cannot see the capturer — the map path is a single
## `capture` thump if the cell is visible, and nothing else: the board repaint
## the caller runs after this is what shows the result, byte-for-byte as it did
## before the cut-in existed. Either way this returns exactly once.
func animate_capture(result: CaptureCommand.CaptureResult, unit: Unit, cell: Vector2i) -> void:
	if result == null:
		return
	if _capture_cut_in_applies(unit):
		_pace_cut_in()
		await _punch_board()
		await capture_cutscene.play(result, unit, cell)
		view.punch_zoom = 1.0  # safety net: the cut-in already eased it out on the wipe
		_last_cut_in_ms = Time.get_ticks_msec()
		return
	if perspective.can_see_unit(unit):
		Sfx.play(&"capture")


## Whether this capture gets the cut-in. The same four questions as the combat
## gate, with one unit instead of two: the capturer stands on the very cell it
## takes, so a single visibility check answers for the whole scene (plan R6). No
## second opinion on who can see what lives here — the perspective asks `Vision`.
func _capture_cut_in_applies(unit: Unit) -> bool:
	if capture_cutscene == null or capturing or not Settings.battle_animations:
		return false
	if Settings.speed.instant:
		return false
	return perspective.can_see_unit(unit)


# --- ambush ------------------------------------------------------------------


## The cue when a committed move runs into a hidden enemy and stops short: put the
## mover's sprite back where the sim actually left it — the preview walked it
## further — and name the trap. Shared by every move-family action, combat too,
## where the shot simply never fires.
func show_ambush(unit: Unit) -> void:
	view.refresh_sprite(unit)
	await show_banner("Ambush!")


## Brings a moved unit's sprite back in step with the sim after an ordinary
## (non-combat) action, springing the ambush cue in place of a plain refresh when
## the move was cut short. Every such action funnels its sprite update here so the
## trap reads the same however the move was going to end.
func settle_move(command: Command, unit: Unit) -> void:
	if command.ambushed:
		await show_ambush(unit)
	else:
		view.refresh_sprite(unit)


## The sprite side of a Join: the moving unit's twin fades away and the survivor
## redraws where they merged — unless a hidden enemy stopped the move short, in
## which case nobody merged and the mover is simply back on its own cell.
func animate_join(command: Command, mover: Unit, survivor: Unit) -> void:
	if command.ambushed:
		await show_ambush(mover)
		return
	fade_out(view.release_sprite(mover))  # merged-away twin; fire and forget
	view.refresh_sprite(survivor)


# --- banner ------------------------------------------------------------------


## Shows the banner immediately and cancels any pending auto-hide.
func _set_banner(text: String) -> void:
	if _banner_tween != null and _banner_tween.is_valid():
		_banner_tween.kill()
	turn_banner.announce(text)
	turn_banner.show()
	turn_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER)


## Shows one blocking beat and returns once time or a press retires it.
func show_banner(text: String) -> void:
	_set_banner(text)
	_banner_tween = node.create_tween()
	_banner_tween.tween_interval(Settings.speed.banner_seconds())
	_banner_tween.tween_callback(_finish_banner)
	await banner_finished


## Dismisses the banner now, cancelling any pending auto-hide.
func hide_banner() -> void:
	if _banner_tween != null and _banner_tween.is_valid():
		_banner_tween.kill()
	_finish_banner()


func _finish_banner() -> void:
	_banner_tween = null
	if not turn_banner.visible:
		return
	turn_banner.hide()
	banner_finished.emit()


## The Command Power activation card: portrait, the general's spoken line, power
## name, and exact effect text, faction-tinted. Shown when a power fires (player
## or AI, both through BattleCommandPipeline._present_power) and auto-hidden
## after a beat.
## `team` keys the card's quote rotation, so the two sides speak independently.
## While capturing it holds, so a screenshot of the same activation is the same
## frame — the whole reason the two open-ended animations above are suppressed
## for captures.
func show_power_banner(commander: CommanderType, team: int) -> void:
	if _power_banner_tween != null and _power_banner_tween.is_valid():
		_power_banner_tween.kill()
	power_banner.bind(commander, team)
	power_banner.show()
	power_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	if capturing:
		return
	_power_banner_tween = node.create_tween()
	_power_banner_tween.tween_interval(Settings.speed.power_banner_seconds())
	_power_banner_tween.tween_callback(_finish_power_banner)
	await power_banner_finished


func hide_power_banner() -> void:
	if _power_banner_tween != null and _power_banner_tween.is_valid():
		_power_banner_tween.kill()
	_finish_power_banner()


func _finish_power_banner() -> void:
	_power_banner_tween = null
	if not power_banner.visible:
		return
	power_banner.hide()
	power_banner_finished.emit()


## One beat of scripted mission dialogue, on the board the beat landed on. The
## power card's shape throughout, because it is the same kind of thing: a blocking
## card carrying a general's spoken line, which is also why it holds for the power
## card's beat rather than the day banner's shorter one — a sentence needs more
## time than a title. Silent for an event nobody comments on.
##
## While capturing it holds, exactly as the power card does, so a posed frame
## still has the card in it.
func speak_lines(lines: Array[MissionLine], commanders: CommanderDB) -> void:
	if lines.is_empty():
		return
	if _speech_tween != null and _speech_tween.is_valid():
		_speech_tween.kill()
	mission_speech.announce(lines, commanders)
	mission_speech.show()
	# Measured before it is centred: the card is as tall as the words it was just
	# given, and a PanelContainer's size is a layout pass behind them.
	mission_speech.reset_size()
	mission_speech.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	if capturing:
		return
	_speech_tween = node.create_tween()
	_speech_tween.tween_interval(Settings.speed.power_banner_seconds())
	_speech_tween.tween_callback(_finish_speech)
	await speech_finished


func hide_speech() -> void:
	if _speech_tween != null and _speech_tween.is_valid():
		_speech_tween.kill()
	_finish_speech()


func _finish_speech() -> void:
	_speech_tween = null
	if not mission_speech.visible:
		return
	mission_speech.hide()
	speech_finished.emit()


## Any keyboard, mouse or controller press retires the visible blocking card.
## Returns whether it claimed the event so Battle can stop it over-landing on
## the board or a newly revealed action.
func consume_banner_skip(event: InputEvent) -> bool:
	if not TransitionInput.is_press(event):
		return false
	if turn_banner.visible:
		hide_banner()
		return true
	if power_banner.visible and not capturing:
		hide_power_banner()
		return true
	if mission_speech.visible and not capturing:
		hide_speech()
		return true
	return false


# --- camera and cursor -------------------------------------------------------


## Brief camera jitter on combat hits. Presentation-only randomness: this
## must never touch game.rng, which is reserved for deterministic sim luck.
##
## Skipped while capturing: the shake is still mid-tween when a frame is taken,
## so it offsets the whole board by a few pixels and makes two otherwise
## identical captures differ everywhere — noise that would hide a real
## rendering regression.
##
## Skipped under Instant too, which is the one tier where it is theatre rather
## than feedback: there is no hit animation left for it to punctuate.
##
## Tweened through `BattleView.shake_offset`, never `camera.offset` directly. The
## view uses that property to dock the board in the band between the two HUD
## bars, so a shake written straight to the camera would settle at Vector2.ZERO
## and leave the board half a bar low for the rest of the match. The view
## composes the two; the shake only ever says how far it is jittering.
func shake_camera(strength: float = 3.0) -> void:
	if capturing or Settings.speed.instant:
		return
	var tween := node.create_tween()
	for i in 4:
		var offset := Vector2(randf_range(-strength, strength), randf_range(-strength, strength))
		tween.tween_property(view, "shake_offset", offset, SHAKE_STEP_SECONDS)
	tween.tween_property(view, "shake_offset", Vector2.ZERO, SHAKE_STEP_SECONDS)


## Skipped while capturing, for the same reason as `shake_camera`: a loop has
## no settled state, so every frame catches it at a different phase.
func start_cursor_pulse() -> void:
	if capturing:
		return
	var tween := node.create_tween().set_loops()
	(
		tween
		. tween_property(cursor, "scale", Vector2(1.15, 1.15), CURSOR_PULSE_SECONDS)
		. set_trans(Tween.TRANS_SINE)
		. set_ease(Tween.EASE_IN_OUT)
	)
	(
		tween
		. tween_property(cursor, "scale", Vector2.ONE, CURSOR_PULSE_SECONDS)
		. set_trans(Tween.TRANS_SINE)
		. set_ease(Tween.EASE_IN_OUT)
	)
