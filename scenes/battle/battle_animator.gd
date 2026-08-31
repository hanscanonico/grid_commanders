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
## The board's flinch as the frame is taken over: a short push toward the cell
## that is about to be struck. The cursor is already parked there by both call
## sites, and the camera follows the cursor, so there is nothing to pan. Its
## length is the cut-in's first beat in all but name, so it runs on the cut-in's
## clock rate — the seconds below are the default tier's, like the beat sheets'.
const PUNCH_ZOOM := 1.14
const PUNCH_SECONDS := 0.11
## The strike runs longer than the marks that follow it, being the power itself
## rather than a caption on one, and it flinches the board harder than a shot.
const METEOR_SCALE := 2.5
const METEOR_SHAKE := 5.0
## How many times a touched unit blinks over its mark's lift, and the flash
## itself: a colourless overdrive, so a blinking unit keeps the faction hue
## `BattleView.refresh_sprite` wrote and stays its owner's. Which kind of mark
## it took is said by the mark over it, not by recolouring the unit.
const BLINK_PULSES := 3
const BLINK_GAIN := 2.5
const BLINK_FLASH := Color(BLINK_GAIN, BLINK_GAIN, BLINK_GAIN)
## Where each blocking card sits in `_cards`.
const _TURN_CARD := 0
const _POWER_CARD := 1
const _SPEECH_CARD := 2

## Assigned by Battle before first use, like BattleView's nodes.
var node: Node
var view: BattleView
var perspective: BattlePerspective
var cursor: Sprite2D
var turn_banner: TurnBanner
var power_banner: CommanderPowerBanner
## The board marks a fired power leaves behind, played once the card clears.
var power_marks: PowerMarks
## Hammerfall's strike. Built on first use by `meteor()`, and down otherwise.
var power_meteor: PowerMeteor
## The star at a firing unit's muzzle on the map path — see `_flash_muzzle`.
var muzzle_flash: MuzzleFlash
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

## The three cards a press retires, in the order it retires them.
var _cards: Array[BlockingCard] = []
## When the last cut-in ended, and how many have run back to back since the
## fighting started. Held as elapsed time rather than as a per-turn counter
## somebody has to remember to reset: there is no lifecycle to get wrong, and a
## fast pace cannot leak out of a computer's turn into the player's next one.
var _last_cut_in_ms := -CUT_IN_STREAK_GAP_MS
var _cut_in_streak := 0

# --- movement ----------------------------------------------------------------


## Tweens a sprite along a path without touching the sim. Awaitable.
##
## The travel is this tween and the gait is the sprite's move clip: the sprite is
## put on that clip for exactly the tween's lifetime, and turned to face each leg
## at the corner it turns rather than once for the whole path.
##
## Instant sets the destination and returns in the same frame — a path the flow
## already walks, since a one-cell "move" has always returned without a tween —
## so a still board plays no clip at all.
func animate_path(sprite: UnitSprite, path: Array[Vector2i]) -> void:
	if path.size() < 2:
		return
	Sfx.play(&"move", -6.0)
	var tier := Settings.speed
	if tier.instant:
		sprite.position = BattleView.cell_center(path[path.size() - 1])
		return
	var tween := node.create_tween()
	sprite.moving = true
	for i in range(1, path.size()):
		var leg: Vector2i = path[i] - path[i - 1]
		tween.tween_callback(sprite.face_step.bind(leg))
		tween.tween_property(
			sprite, "position", BattleView.cell_center(path[i]), tier.move_step_seconds()
		)
	await tween.finished
	# Parked again whether the walk finished or the tween died with the scene:
	# a sprite left on the clip strides on the spot. Leaving the clip is also
	# what faces it forward again — the mirror is the clip's, and `moving` owns
	# both ends of it.
	if is_instance_valid(sprite):
		sprite.moving = false


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
		await _show_ambush(attacker)
		return
	var defender_sprite := view.sprite_for(defender)
	var attacker_sprite := view.sprite_for(attacker)
	view.refresh_sprite(attacker)  # snap to the committed destination
	if _cut_in_applies(attacker, defender):
		_pace_cut_in()
		await _punch_board()
		await cutscene.play(result, attacker, defender)
		_drop_punch()
		_last_cut_in_ms = Time.get_ticks_msec()
		_sync_aftermath()
		return
	Sfx.play(&"shot")
	await _flash_muzzle(attacker, defender, result.attacker_weapon_slot)
	await flash_hit(defender_sprite)
	shake_camera()
	if result.defender_died:
		Sfx.play(&"explosion")
		view.release_sprite(defender)
		await _fade_out(defender_sprite)
	else:
		view.refresh_sprite(defender)
	if result.countered:
		Sfx.play(&"shot")
		await _flash_muzzle(defender, attacker, result.counter_weapon_slot)
		await flash_hit(attacker_sprite)
	if result.attacker_died:
		view.release_sprite(attacker)
		await _fade_out(attacker_sprite)
	else:
		view.refresh_sprite(attacker)
	view.sync_sprites()


## The shot leaving, on the map path the cut-in stands in for: a star at the
## firing unit's muzzle, thrown at what it is shooting at, one beat ahead of the
## hit flash. Awaitable. Without it the map path drew the shooter nothing at all,
## so an exchange read as the target flinching at nothing — the cut-in has flashed
## a muzzle since BA1 and this is the same flash at the board's scale.
##
## Which weapon fired is a snapshot fact — the result's own slot — mapped to its
## BattleStyle through the registry the cut-in reads, so the two can never
## disagree about what a weapon looks like. Nothing is recomputed here, and a
## style with no muzzle (a bomber's, an unarmed unit's) flashes none.
##
## Silent under Instant, which shows results rather than playing them out — the
## tier answers no beat to run on — and silent unless the viewer can see both
## sides, which is `_cut_in_applies`' own fog rule: the star is aimed, so a
## shooter alone would point at ground the board is hiding.
func _flash_muzzle(shooter: Unit, target: Unit, slot: StringName) -> void:
	if muzzle_flash == null:
		return
	if not perspective.can_see_unit(shooter) or not perspective.can_see_unit(target):
		return
	var seconds := Settings.speed.flash_in_seconds()
	if seconds <= 0.0:
		return
	var style := BattleStyleDB.shared().for_weapon(shooter.type, slot)
	if style.muzzle <= 0.0:
		return
	muzzle_flash.show_shot(shooter.cell, target.cell, style)
	var tween := node.create_tween()
	tween.tween_property(muzzle_flash, "spark", 0.0, seconds)
	await tween.finished
	muzzle_flash.clear_shot()


## The white hit flash, at the active tier's pace. Awaitable.
func flash_hit(sprite: UnitSprite) -> void:
	var tier := Settings.speed
	await sprite.flash_hit(tier.flash_in_seconds(), tier.flash_out_seconds())


## Fades a sprite out and frees it, at the active tier's pace. Awaitable, and
## the single place a death fade's length is decided — Battle's Join merge fades
## a sprite outside combat entirely and comes through here for that reason.
func _fade_out(sprite: UnitSprite) -> void:
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


## A short push onto the cell about to be struck, so the board flinches before
## the frame is taken away from it. Awaited, then left punched in: the cut-in
## covers the map for its whole run and eases the punch back out over the closing
## wipe, so the board is already at rest the moment it is uncovered — see
## CutscenePlayback._restore_zoom.
##
## What is pushed is a still of the board rather than the camera: the zoom ladder
## is whole rungs, and a camera walked continuously from 1.00 to 1.14 drops and
## doubles a different set of rows on every frame. `BoardPunch` grabs the frame
## first — awaited, because the still has to carry the attacker on the cell it
## has just been snapped to.
func _punch_board() -> void:
	await view.punch.open()
	var tween := node.create_tween()
	var seconds := PUNCH_SECONDS / Settings.speed.cutscene_rate()
	(
		tween
		. tween_property(view, "punch_zoom", PUNCH_ZOOM, seconds)
		. set_trans(Tween.TRANS_CUBIC)
		. set_ease(Tween.EASE_OUT)
	)
	await tween.finished


## Hands the frame back to the live board. The cut-in has already eased the still
## to rest over its closing wipe, so this only tears it down — and it runs however
## the cut-in ended, which is what keeps a skip landing on the board rather than
## under a frozen picture of it.
func _drop_punch() -> void:
	view.punch_zoom = 1.0
	view.punch.close()


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
		_drop_punch()
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
func _show_ambush(unit: Unit) -> void:
	view.refresh_sprite(unit)
	await show_banner("Ambush!")


## Brings a moved unit's sprite back in step with the sim after an ordinary
## (non-combat) action, springing the ambush cue in place of a plain refresh when
## the move was cut short. Every such action funnels its sprite update here so the
## trap reads the same however the move was going to end.
func settle_move(command: Command, unit: Unit) -> void:
	if command.ambushed:
		await _show_ambush(unit)
	else:
		view.refresh_sprite(unit)


## The sprite side of a Join: the moving unit's twin fades away and the survivor
## redraws where they merged — unless a hidden enemy stopped the move short, in
## which case nobody merged and the mover is simply back on its own cell.
func animate_join(command: Command, mover: Unit, survivor: Unit) -> void:
	if command.ambushed:
		await _show_ambush(mover)
		return
	_fade_out(view.release_sprite(mover))  # merged-away twin; fire and forget
	view.refresh_sprite(survivor)


# --- blocking cards ----------------------------------------------------------


## The three cards, built on first use: Battle assigns `node` and the controls
## field by field after construction, so there is no moment at which a
## constructor could have them all. The signals stay here as relays, because
## Battle and the scenarios know the animator rather than its cards.
##
## Only the turn banner is put down by name (`hide_banner`). The power card and
## the speech card come down when their own hold runs out — and the pause menu's
## re-read has no hold at all — so `consume_banner_skip` is the only other way
## either is retired.
func _blocking_cards() -> Array[BlockingCard]:
	if _cards.is_empty():
		_cards = [
			BlockingCard.new(turn_banner, node, false),
			BlockingCard.new(power_banner, node, true),
			BlockingCard.new(mission_speech, node, true),
		]
	return _cards


## Raises one card and holds it for as long as the tier says. A card that holds
## while capturing is raised and left standing: there it is the frame's subject.
func _present(which: int, seconds: float, after: Callable) -> void:
	var card := _blocking_cards()[which]
	card.raise(after)
	if _frozen(card):
		return
	await card.hold(seconds)


func _frozen(card: BlockingCard) -> bool:
	return capturing and card.holds_while_capturing


## Shows one blocking beat and returns once time or a press retires it.
func show_banner(text: String) -> void:
	await _present(_TURN_CARD, Settings.speed.banner_seconds(), turn_banner.announce.bind(text))


## Dismisses the banner now, cancelling any pending auto-hide.
func hide_banner() -> void:
	_blocking_cards()[_TURN_CARD].dismiss()


## The Command Power activation card: portrait, the general's spoken line, power
## name, and exact effect text, faction-tinted. Shown when a power fires (player
## or AI, both through BattleCommandPipeline._present_power) and auto-hidden
## after a beat.
## `team` keys the card's quote rotation, so the two sides speak independently.
## While capturing it holds, so a screenshot of the same activation is the same
## frame — the whole reason the two open-ended animations above are suppressed
## for captures.
func show_power_banner(commander: CommanderType, team: int) -> void:
	await _present(
		_POWER_CARD,
		Settings.speed.power_banner_seconds(),
		func() -> void: power_banner.bind(commander, team)
	)


## Who the power just touched, said on the board rather than only on the card: a
## mark over every affected unit, lifting off its tile and fading. Awaitable like
## the card, so the flow resumes with the board at rest.
##
## Handed the marks already worked out and already through the fog gate — this
## decides nothing about who was affected. An empty list is the ordinary quiet
## case: a power fired where the viewer can see none of it.
##
## Every unit a mark names blinks colourless while its mark lifts, so the power is
## read off the pieces it touched rather than off the tiles they happen to stand
## on, and the piece stays its owner's while it flashes. An aimed square that took
## what was standing in it gets the meteor first — the strike itself, before the
## receipt.
##
## While capturing the marks pose at rest, exactly as the card holds, because
## there they are the frame's subject, and the blink poses at its brightest for
## the same reason. Instant skips them outright — that tier shows results rather
## than playing them out.
func show_power_effects(marks: Array[PowerEffects.Mark], blast: Array[Vector2i] = []) -> void:
	if marks.is_empty():
		return
	if capturing:
		power_marks.set_marks(marks)
		_pose_blink(marks)
		return
	var tier := Settings.speed
	if tier.instant:
		return
	var seconds := tier.power_mark_seconds()
	if _strikes(marks, blast):
		await meteor().strike(_blast_centre(blast), seconds * METEOR_SCALE)
	power_marks.set_marks(marks)
	_blink_marked(marks, seconds / BLINK_PULSES)
	var tween := node.create_tween().set_parallel()
	tween.tween_property(power_marks, "rise", 1.0, seconds).set_trans(Tween.TRANS_CUBIC).set_ease(
		Tween.EASE_OUT
	)
	tween.tween_property(power_marks, "modulate:a", 0.0, seconds).set_delay(seconds)
	await tween.finished
	power_marks.clear_marks()


## The meteor, built here rather than in `battle.tscn` because the scene root is
## already at its line budget and this is the collaborator that owns the strike.
## Its bang and its flinch are the animator's own, hung off `struck`, so the
## meteor keeps drawing and deciding nothing.
func meteor() -> PowerMeteor:
	if power_meteor == null:
		power_meteor = PowerMeteor.new()
		power_meteor.name = "PowerMeteor"
		power_meteor.struck.connect(_on_meteor_struck)
		node.add_child(power_meteor)
	return power_meteor


func _on_meteor_struck() -> void:
	Sfx.play(&"explosion")
	shake_camera(METEOR_SHAKE)


## True for the one power the meteor belongs to: an aimed footprint that took
## what was standing in it. Every other power — aimed or not — blinks and no more.
static func _strikes(marks: Array[PowerEffects.Mark], blast: Array[Vector2i]) -> bool:
	if blast.is_empty():
		return false
	for mark in marks:
		if mark.kind == PowerEffects.Kind.DESTROYED:
			return true
	return false


static func _blast_centre(blast: Array[Vector2i]) -> Vector2i:
	var sum := Vector2i.ZERO
	for cell in blast:
		sum += cell
	return sum / blast.size()


func _blink_marked(marks: Array[PowerEffects.Mark], step: float) -> void:
	for mark in marks:
		var sprite := view.sprite_for(mark.unit) if mark.unit != null else null
		if sprite == null:
			continue
		var tween := node.create_tween()
		for _pulse in BLINK_PULSES:
			tween.tween_property(sprite, "self_modulate", BLINK_FLASH, step)
			tween.tween_property(sprite, "self_modulate", Color.WHITE, step)


func _pose_blink(marks: Array[PowerEffects.Mark]) -> void:
	for mark in marks:
		var sprite := view.sprite_for(mark.unit) if mark.unit != null else null
		if sprite != null:
			sprite.self_modulate = BLINK_FLASH


## One beat of scripted mission dialogue, on the board the beat landed on. The
## power card's shape throughout, because it is the same kind of thing: a blocking
## card carrying a general's spoken line. It is never briefer than either banner
## and it holds for a length of its own — the tier is asked how long *these
## words* take to read (COM-255), a beat being anything from a five-word order
## to two generals arguing. Any press still retires it early, so the longer hold costs an
## impatient player nothing. Silent for an event nobody comments on.
##
## While capturing it holds, exactly as the power card does, so a posed frame
## still has the card in it.
func speak_lines(lines: Array[MissionLine], commanders: CommanderDB) -> void:
	if lines.is_empty():
		return
	await _present(
		_SPEECH_CARD,
		Settings.speed.speech_seconds(_spoken_characters(lines)),
		_fill_speech.bind(lines, commanders)
	)


## The same card, held until the player puts it down: the briefing re-read from
## the pause menu. Untimed because it was asked for rather than delivered —
## a beat's card interrupts a turn and has to give it back, while this one is the
## thing the player stopped to look at, and orders are read at reading speed.
func speak_until_dismissed(lines: Array[MissionLine], commanders: CommanderDB) -> void:
	if lines.is_empty():
		return
	var card := _blocking_cards()[_SPEECH_CARD]
	card.raise(_fill_speech.bind(lines, commanders))
	if _frozen(card):
		return
	await card.finished


## How much there is to read on the card: the words themselves, the speakers'
## names being a label rather than a sentence.
static func _spoken_characters(lines: Array[MissionLine]) -> int:
	var said := 0
	for line: MissionLine in lines:
		if line != null:
			said += line.text.length()
	return said


## Filled and then measured, before the card is centred: it is as tall as the
## words it was just given, and a PanelContainer's size is a layout pass behind
## them.
func _fill_speech(lines: Array[MissionLine], commanders: CommanderDB) -> void:
	mission_speech.announce(lines, commanders)
	mission_speech.reset_size()


## Any keyboard, mouse or controller press retires the visible blocking card.
## Returns whether it claimed the event so Battle can stop it over-landing on
## the board or a newly revealed action.
func consume_banner_skip(event: InputEvent) -> bool:
	if not TransitionInput.is_press(event):
		return false
	for card: BlockingCard in _blocking_cards():
		if card.is_up() and not _frozen(card):
			card.dismiss()
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
## Tweened through `BoardCamera.shake_offset`, never `camera.offset` directly:
## `BoardCamera._apply_board_offset` composes the jitter with the board's
## docking shift and is that property's only writer.
func shake_camera(strength: float = 3.0) -> void:
	if capturing or Settings.speed.instant:
		return
	var tween := node.create_tween()
	for i in 4:
		var offset := Vector2(randf_range(-strength, strength), randf_range(-strength, strength))
		tween.tween_property(view.board_camera, "shake_offset", offset, SHAKE_STEP_SECONDS)
	tween.tween_property(view.board_camera, "shake_offset", Vector2.ZERO, SHAKE_STEP_SECONDS)


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
