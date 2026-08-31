class_name BattleCutsceneScenario
extends BattleScenario
## The battle and capture cut-in staging family, split out so
## BattleScenarioDriver stays under its linted size cap — COM-94, the split its
## own gdlintrc history had named as due since COM-13's raise.
##
## Poses a real CombatResult/CaptureResult at one moment of the cut-in's own
## clock rather than driving it through the targeting flow, which suppresses
## the cut-in while capturing (BattleAnimator._cut_in_applies /
## _capture_cut_in_applies) — a mid-tween frame is exactly what makes two
## otherwise identical captures differ. Then checks the frame it posed: the
## atlas rows (COM-10), and the skip-spam risk R2.
##
## Reports through the base's `_fail`, and `run` hands the flag back rather than
## the driver reaching in for it.

## Where on the cut-in's clock the `cutin` capture is posed: about 70% into the
## defender's impact for a cannon exchange, so the plates are up, the HP has
## ticked and the callout and the topple are both running. Any moment would be
## byte-stable — the cut-in is a pure function of its clock — but this is the one
## that shows the most.
##
## One clock cannot sit inside seven impacts once a per-weapon wind-up has pulled
## the firing times 0.22 s apart (small arms at 0.40, the howitzer at 0.62), and
## this number picks the five that leave a mark: `cannon`, `artillery`, `rocket`
## and `bomb` are all mid-burst here and `torpedo` mid-foam — the howitzer's only
## just, its shell being the last to land — while `small_arms` and `autocannon`,
## the two whose `impact_radius` is 0 so their hit is a spark stitch rather than a
## burst, have settled past theirs and show the ticked HP, the callout and the
## figures going down instead.
const CUT_IN_POSE := 1.05
## `cutin_ko` sits on the blast at its brightest, a third of the way into the
## death beat with the K.O. tag already up. Only the cannon matchup poses here.
const KO_POSE := 1.22
## `cutin_volley` freezes a round in the air — which is what makes it the frame
## the weapon *signatures* are checkable in, where the impact pose shows only
## what a hit looks like and nothing of what threw it.
##
## The howitzer split off the cannon closed the old fit and this is the
## re-measurement it forced. Every window, at the default tier: a style fires at
## `ARRIVE_END + aim_seconds` and its volley is in the air for
## `TRAVEL * travel_scale` after that, so artillery (aim 0.28) fires at **0.62**
## and small arms' stream is gone by **0.6465** (0.40 + 0.29 x 0.85). Those two
## are the fences, they leave 26 ms between them, and 0.633 is the middle of it.
##
## What gives way is the *cannon's flash*, not its round: `FLASH_HOLD` puts that
## out at 0.62, one frame before the howitzer's own barrel lights, and no value
## can hold both. There is none to hold, because a round in flight is what this
## frame is for — at 0.633 the cannon has five shells strung across the band, the
## howitzer's barrel is lit with its shell leaving it, and the rocket, the bomb,
## the torpedo, the tracer stream and the flak are all in the air.
const VOLLEY_POSE := 0.633
## Cut-in modes are `cutin[_ko][:<attacker>:<defender>]`, so they are recognised
## by prefix and parsed rather than matched name-for-name.
const CUT_IN_MODE := "cutin"
const KO_SUFFIX := "_ko"
const VOLLEY_SUFFIX := "_volley"
## The capture cut-in's poses. `capture_cutin` freezes a completing capture late
## in its banner — the property already flipped, the meter at zero, the specks
## out; `capture_cutin_partial` freezes an occupying one over its OCCUPYING tag.
const CAPTURE_CUT_IN_MODE := "capture_cutin"
const CAPTURE_CUT_IN_POSE := 1.75
const CAPTURE_PARTIAL_POSE := 1.65
const PARTIAL_SUFFIX := "_partial"
## `cutin_iron_commander` and `capture_cutin_iron_commander` stage their cut-in in
## a *commander* match rather than the commander-less default. That is the whole
## point of them: a commander-less side deliberately draws in the row its slot
## number names (SideIdentity plan D4), so every other cut-in capture is blind to
## a surface that reads a team int where an atlas row belongs.
const FACTION_SUFFIX := "_iron_commander"
## The pairing those variants stage, in slot order: Iron on side one, Verdant on
## side two. Neither faction's atlas row (3 and 4) equals its team int, so
## *both* halves of the frame are a live comparison — a side whose row happened
## to match its slot could not tell the two apart.
const FACTION_CO_IDS: Array[StringName] = [&"viktor_draeg", &"nia_rowan"]
## The ground `cutin_iron_commander` is fought over: the south-east base and HQ,
## adjacent, both team-tinted, and re-owned one side each. The frontline cells the
## other cut-in modes use are plains, where an untinted tile makes the owner row
## moot — so the third surface COM-10 named, the ground strip under each half, was
## the one no scenario put a faction row through. Owning the pair apart puts a
## *different* faction row under each half, so a swapped one is as loud as a
## wrong one.
const FACTION_ATTACKER_CELL := Vector2i(16, 11)  # base
const FACTION_DEFENDER_CELL := Vector2i(17, 11)  # HQ
## And the side `capture_cutin_iron_commander` takes its property *from*, so the
## flip crosses between two faction rows rather than out of neutral row 0.
const FACTION_CAPTURE_FROM := 2
## `cutin_scenery` fights over the woods and the mountain that sit one above the
## other in the west of the default board. A terrain either paves the cut-in's
## ground plane or stands on it, and three shapes stand: `_iron_commander` already
## sweeps the buildings, and every other cut-in mode fights on plains, road or open
## water, all of which pave — so trees and peaks had no frame in the sweep at all,
## which is how both went unphotographed while being reachable from any woods or
## mountain in ordinary play.
const SCENERY_SUFFIX := "_scenery"
const SCENERY_ATTACKER_CELL := Vector2i(4, 5)  # woods
const SCENERY_DEFENDER_CELL := Vector2i(4, 6)  # mountain
## `cutin_skip` walks a skip across the whole cut-in — see _spam_skip. One entry
## per beat boundary and a couple past the end, which is where a double-finish
## would show up.
const SKIP_SUFFIX := "_skip"
const SKIP_FRAMES: Array[int] = [0, 1, 2, 4, 8, 16, 32, 64, 128, 240]
## Every variant each cut-in family implements, as the suffix left once its
## prefix is taken off. Not decoration: each suffix below is read off the name
## with `ends_with`/`begins_with`, and an unrecognised one answers false to all
## of them rather than erroring — so `cutin_iron_commandr` quietly poses the
## commander-less frame under the acceptance mode's name, and
## `capture_cutin_partail` poses a completing capture where an occupying one was
## asked for. That is the one failure the row checks cannot catch, because the
## frame they check *is* correct; it is simply not the frame that was asked for.
##
## Combat takes at most one suffix, since all four are `ends_with` and only the
## last would be honoured — `cutin_ko_skip` would drop its `_ko` in silence.
## Capture reads `_partial` off the front, so it composes with one of the other
## two and must lead.
const CUT_IN_SUFFIXES: Array[String] = [
	"", KO_SUFFIX, VOLLEY_SUFFIX, SKIP_SUFFIX, FACTION_SUFFIX, SCENERY_SUFFIX
]
const CAPTURE_CUT_IN_SUFFIXES: Array[String] = [
	"",
	PARTIAL_SUFFIX,
	SKIP_SUFFIX,
	FACTION_SUFFIX,
	PARTIAL_SUFFIX + SKIP_SUFFIX,
	PARTIAL_SUFFIX + FACTION_SUFFIX,
]


## Dispatches on the mode's prefix — the cut-in families carry a matchup in the
## name, so they are parsed rather than matched name-for-name — and answers
## whether anything staged or checked here failed.
func run(mode: String) -> bool:
	if mode.begins_with(CAPTURE_CUT_IN_MODE):
		await _stage_capture_cut_in(mode)
	elif mode.begins_with(CUT_IN_MODE):
		await _stage_cut_in(mode)
	return _failed


## The battle cut-in, held still for the shutter. Any matchup, on any board:
##
##   --demo=cutin                    the two frontline tanks, defender survives
##   --demo=cutin_ko                 the same pair, defender routed
##   --demo=cutin_volley             the same pair, frozen with the round in the air
##   --demo=cutin:bomber:fighter     that matchup, staged wherever it fits
##   --demo=cutin_ko:artillery:mech  and the same with a kill
##   --demo=cutin_iron_commander     the same tanks, Iron v Verdant, and fought
##                                   over a property apiece so the ground under
##                                   each half carries a faction row too
##   --demo=cutin_scenery:mech:mech  fought across the woods and the mountain, so
##                                   one half stands trees and the other peaks
##
## One suffix off CUT_IN_SUFFIXES, then an optional `:<attacker>:<defender>`;
## anything else fails the run rather than falling back to the plain variant.
##
## The exchange is resolved directly rather than driven through the targeting
## flow, because the flow deliberately suppresses the cut-in while capturing
## (BattleAnimator._cut_in_applies) — a mid-tween frame is exactly what makes two
## otherwise identical captures differ, which is the war this repo already fought
## with the camera shake. So the still is posed instead: a real result off the
## real resolver, frozen at one moment of the cut-in's own clock.
##
## Named matchups are what makes "all eighteen units stage correctly" checkable
## without eighteen hand-placed scenarios. The pair is stood on the first cells
## the board offers that both can legally occupy, so an air or naval matchup
## works on whatever map the capture was launched with.
func _stage_cut_in(spec: String) -> void:
	var parts := spec.split(":")
	if parts.size() != 1 and parts.size() != 3:
		_fail("cutin demo: a matchup reads ':<attacker>:<defender>' (%s)" % spec)
		return
	if not _known_variant(parts[0], CUT_IN_MODE, CUT_IN_SUFFIXES):
		return
	var lethal := parts[0].ends_with(KO_SUFFIX)
	var game := _battle.game
	var factions := parts[0].ends_with(FACTION_SUFFIX)
	if factions:
		_stage_faction_commanders()
	var attacker := game.unit_at(Vector2i(8, 8))  # red tank
	var defender := game.unit_at(Vector2i(9, 8))  # blue tank
	if parts.size() >= 3:
		var pair := _stand_pair(parts[1], parts[2])
		if pair.is_empty():
			return
		attacker = pair[0]
		defender = pair[1]
	if attacker == null or defender == null:
		_fail("cutin demo: no pair to stage (%s)" % spec)
		return
	if factions:
		_stage_owned_ground(attacker, defender)
	if parts[0].ends_with(SCENERY_SUFFIX) and not _stage_wild_ground(attacker, defender):
		return
	defender.hp = 10 if lethal else 74
	var result := CombatResolver.resolve(game, attacker, defender)
	_battle.view.sync_sprites()
	if parts[0].ends_with(SKIP_SUFFIX):
		await _spam_skip(result, attacker, defender)
	var pose := KO_POSE if lethal else CUT_IN_POSE
	if parts[0].ends_with(VOLLEY_SUFFIX):
		pose = VOLLEY_POSE
	_battle.animator.cutscene.pose_at(result, attacker, defender, pose)
	_check_cut_in_rows(attacker, defender)


## The capture cut-in, held still for the shutter — the sibling of `_stage_cut_in`.
##
##   --demo=capture_cutin           a completing capture, late in its banner
##   --demo=capture_cutin_partial   an occupying capture over its OCCUPYING tag
##   --demo=capture_cutin_skip      walks a skip across the whole clock (a test)
##   --demo=capture_cutin_iron_commander  the same city, taken by Iron off Verdant
##
## One suffix off CAPTURE_CUT_IN_SUFFIXES, `_partial` leading where it composes;
## anything else fails the run rather than falling back to the plain variant.
##
## Like the combat still it is posed rather than driven through the menu, because
## the capture flow suppresses the cut-in while capturing for exactly the same
## byte-stability reason (BattleAnimator._capture_cut_in_applies). A real
## CaptureResult, frozen at one moment of the cut-in's own clock, on the default
## board's neutral city at (3,4) — the same property the `capture` demo takes.
func _stage_capture_cut_in(mode: String) -> void:
	if not _known_variant(mode, CAPTURE_CUT_IN_MODE, CAPTURE_CUT_IN_SUFFIXES):
		return
	var game := _battle.game
	var cell := Vector2i(3, 4)  # the neutral city
	var unit := game.unit_at(Vector2i(4, 3))  # the red infantry
	if unit == null:
		_fail("capture_cutin demo: no infantry at (4,3)")
		return
	var factions := mode.ends_with(FACTION_SUFFIX)
	if factions:
		_stage_faction_commanders()
	var partial := mode.begins_with(CAPTURE_CUT_IN_MODE + PARTIAL_SUFFIX)
	var result := CaptureCommand.CaptureResult.new()
	# Taken off the rival side rather than off neutral in the faction variant, so
	# the row the property *starts* in is a faction row too — row 0 either way is
	# how the owner path stayed unexercised. The sim's property is re-owned with
	# it, so the board behind the cut-in agrees about who is being taken from.
	result.owner_before = FACTION_CAPTURE_FROM if factions else MapData.NEUTRAL
	if factions:
		game.set_owner(cell, result.owner_before)
		_battle.view.repaint_property(cell)
	result.points_before = 20 if partial else 8
	result.points_after = 10 if partial else 0
	result.captured = not partial
	_battle.view.sync_sprites()
	if mode.ends_with(SKIP_SUFFIX):
		await _spam_capture_skip(result, unit, cell)
	_battle.animator.capture_cutscene.pose_at(
		result, unit, cell, CAPTURE_PARTIAL_POSE if partial else CAPTURE_CUT_IN_POSE
	)
	_check_capture_cut_in_rows(unit, cell)


## The capture cut-in's half of risk R2, made checkable exactly as `_spam_skip`
## makes combat's: the same capture is played and skipped again and again, one
## frame later each time, so the skip walks every beat — the wipe, the march, the
## three mashes, the flip and the banner. Each run must emit `finished` exactly
## once and land the punched-in camera back at its resting zoom.
func _spam_capture_skip(result: CaptureCommand.CaptureResult, unit: Unit, cell: Vector2i) -> void:
	var cutscene := _battle.animator.capture_cutscene
	var camera := _battle.camera
	var tree := _battle.get_tree()
	var resting := camera.zoom
	for delay in SKIP_FRAMES:
		var finishes := [0]
		var tally := func() -> void: finishes[0] += 1
		cutscene.finished.connect(tally)
		_punch_board()
		cutscene.play(result, unit, cell)  # deliberately not awaited
		for frame in delay:
			await tree.process_frame
		for spam in 3:
			cutscene.skip()
			await tree.process_frame
		await tree.process_frame  # the exit lands on the frame after the skip
		cutscene.finished.disconnect(tally)
		if finishes[0] != 1:
			_fail(
				"capture cut-in skipped after %d frame(s) finished %d times" % [delay, finishes[0]]
			)
			return
		if not camera.zoom.is_equal_approx(resting):
			_fail(
				(
					"capture cut-in skipped after %d frame(s) left camera zoom at %s, not resting %s"
					% [delay, camera.zoom, resting]
				)
			)
			return
	_battle.view.punch_zoom = 1.0
	print(
		(
			"capture_cutin_skip: %d skips, each resolved exactly once and camera home"
			% SKIP_FRAMES.size()
		)
	)


## Risk R2, made checkable: both call sites hold the whole interaction flow on
## `animate_combat`, so a cut-in that ever fails to finish freezes input for the
## rest of the session. Here the same exchange is played and skipped again and
## again, one frame later each time, which walks the skip across every beat the
## cut-in has — the wipe, the volley, the impact, the counter, the death and the
## hold. Each run has to emit `finished` exactly once and land the punched-in
## camera back at its resting zoom, since the cut-in now eases that off its own
## clock too (plan R2/R4).
##
## A run that never finishes hangs the scenario and the smoke sweep reports the
## timeout; one that finishes twice, or not at all, or leaves the camera zoomed,
## quits non-zero here.
func _spam_skip(result: CombatSnapshot.CombatResult, attacker: Unit, defender: Unit) -> void:
	var cutscene := _battle.animator.cutscene
	var camera := _battle.camera
	var tree := _battle.get_tree()
	var resting := camera.zoom
	for delay in SKIP_FRAMES:
		var finishes := [0]
		# Deliberately not CONNECT_ONE_SHOT: a one-shot connection drops itself
		# after the first emission, so the very failure this is looking for — an
		# exit that fires twice — would be the one it could not see.
		var tally := func() -> void: finishes[0] += 1
		cutscene.finished.connect(tally)
		# Punch the board the way the animator would, so the skip has a flinch to
		# land: the cut-in owns easing it back out off its own clock, and a skip
		# must pin it home like every other value it drives.
		_punch_board()
		cutscene.play(result, attacker, defender)  # deliberately not awaited
		for frame in delay:
			await tree.process_frame
		# Spammed, not pressed once: a second skip after the exit has run must be
		# a no-op rather than a second `finished`.
		for spam in 3:
			cutscene.skip()
			await tree.process_frame
		await tree.process_frame  # the exit lands on the frame after the skip
		cutscene.finished.disconnect(tally)
		if finishes[0] != 1:
			_fail("cut-in skipped after %d frame(s) finished %d times" % [delay, finishes[0]])
			return
		if not camera.zoom.is_equal_approx(resting):
			_fail(
				(
					"cut-in skipped after %d frame(s) left camera zoom at %s, not resting %s"
					% [delay, camera.zoom, resting]
				)
			)
			return
	_battle.view.punch_zoom = 1.0
	print("cutin_skip: %d skips, each resolved exactly once and camera home" % SKIP_FRAMES.size())


## The entry flinch, staged the way BattleAnimator stages it — and checked while it
## is held. The board is docked in the band between the two HUD bars by a camera
## offset in *world* units, so the same screen inset is a different offset at each
## zoom level: a punch written straight to the camera keeps the resting level's
## inset and drops the board out of the band for as long as the flinch lasts
## (COM-84). Measured in the screen pixels that must not move, so the check does
## not restate the view's arithmetic.
func _punch_board() -> void:
	var camera := _battle.camera
	var docked := camera.offset.y * camera.zoom.y
	_battle.view.punch_zoom = BattleAnimator.PUNCH_ZOOM
	var punched := camera.offset.y * camera.zoom.y
	if not is_equal_approx(punched, docked):
		_fail("the zoom punch slid the board %.1fpx out of the band" % (punched - docked))


## Puts one unit of each named type onto the first pair of cells the board has
## that both can stand on, clearing whatever was there. Returns
## [attacker, defender], or empty when the ids or the board do not work out —
## which fails the run rather than passing quietly. A matchup that was asked for
## and never staged photographs a plain board, and the caller has nothing to pose
## and nothing to check; a naval pair belongs on a board with water on it, which
## is why tools/smoke_scenarios.sh hands those modes `--map=the_straits`.
##
## The two are stood the attacker's own minimum range apart, not simply side by
## side, so an indirect weapon is staged from a cell it could actually have
## fired from — which is also the only way to see the no-counter framing an
## indirect attack gets.
func _stand_pair(attacker_id: String, defender_id: String) -> Array[Unit]:
	var none: Array[Unit] = []
	var attacker_type := _battle.unit_db.by_id(StringName(attacker_id))
	var defender_type := _battle.unit_db.by_id(StringName(defender_id))
	if attacker_type == null or defender_type == null:
		_fail("cutin demo: unknown unit id in '%s vs %s'" % [attacker_id, defender_id])
		return none
	if not _battle.game.damage_chart.can_attack(attacker_type.id, defender_type.id):
		_fail("cutin demo: %s has no weapon that reaches %s" % [attacker_id, defender_id])
		return none
	var map := _battle.map
	var reach: int = maxi(attacker_type.min_range, 1)
	for y in map.height:
		for x in map.width:
			var here := Vector2i(x, y)
			if not map.terrain_at(here).is_passable(attacker_type.move_class):
				continue
			for dir in MovementResolver.DIRECTIONS:
				var there: Vector2i = here + dir * reach
				var terrain := map.terrain_at(there)
				if terrain == null or not terrain.is_passable(defender_type.move_class):
					continue
				var pair: Array[Unit] = [
					_stand(attacker_type, 1, here), _stand(defender_type, 2, there)
				]
				_battle.view.sync_sprites()
				return pair
	_fail("cutin demo: no cell pair on this board fits %s vs %s" % [attacker_id, defender_id])
	return none


## Clears a cell and stands a fresh unit on it.
func _stand(type: UnitType, team: int, cell: Vector2i) -> Unit:
	var game := _battle.game
	var sitting := game.unit_at(cell)
	if sitting != null:
		game.remove_unit(sitting)
	var unit := Unit.create(type, team, cell)
	game.units.append(unit)
	_battle.view.spawn_sprite_for(unit)
	return unit


## Gives both sides a general whose faction row differs from its slot number, then
## restages identity so the board's units, properties and HUD all wear those
## factions. What that buys the cut-in variants is a straight comparison inside one
## frame: whatever colour the board paints a side, the cut-in over it has to paint
## the same one, and no team-int-as-row shortcut can survive it.
func _stage_faction_commanders() -> void:
	for slot in FACTION_CO_IDS.size():
		var team: int = _battle.game.teams[slot]
		_battle.game.set_commander(team, _battle.commander_db.by_id(FACTION_CO_IDS[slot]))
	_battle.view.restage_identity()


## Stands the pair on the two adjacent properties in the south-east and gives one
## to each side, so the ground strip under each half of the cut-in is a tinted
## tile with a *faction* owner. Called for the `_iron_commander` combat variant
## only: the frontline cells the other modes fight over are plains, where the
## owner row is never read at all.
func _stage_owned_ground(attacker: Unit, defender: Unit) -> void:
	var cells: Array[Vector2i] = [FACTION_ATTACKER_CELL, FACTION_DEFENDER_CELL]
	_stand_pair_on(attacker, defender, cells)
	_battle.game.set_owner(FACTION_ATTACKER_CELL, attacker.team)
	_battle.game.set_owner(FACTION_DEFENDER_CELL, defender.team)
	for cell in cells:
		_battle.view.repaint_property(cell)


## Stands the pair on the woods and the mountain in the west, one shape of drawn
## scenery per half of the frame. The sibling of `_stage_owned_ground`, and there
## for the same kind of reason: the cells the other cut-in modes fight over all
## *pave* the ground plane, so the two scenery shapes that are not a building were
## drawn by nothing the sweep photographed.
##
## A mountain takes foot and boot only, which is why the mode is spelled with its
## matchup (`cutin_scenery:mech:mech`) — a pair that could not legally be standing
## on the ground the frame is about is refused out loud rather than posed on it.
## False fails the run; the caller stages nothing further.
func _stage_wild_ground(attacker: Unit, defender: Unit) -> bool:
	var cells: Array[Vector2i] = [SCENERY_ATTACKER_CELL, SCENERY_DEFENDER_CELL]
	var pair: Array[Unit] = [attacker, defender]
	for slot in cells.size():
		var terrain := _battle.map.terrain_at(cells[slot])
		if terrain.is_passable(pair[slot].type.move_class):
			continue
		_fail(
			(
				"cutin demo: a %s cannot stand on the %s at %s"
				% [pair[slot].type.display_name, terrain.display_name, cells[slot]]
			)
		)
		return false
	_stand_pair_on(attacker, defender, cells)
	return true


## Clears two cells of everything but the pair and stands the pair on them, in
## order. The half the two ground-staging variants above share.
func _stand_pair_on(attacker: Unit, defender: Unit, cells: Array[Vector2i]) -> void:
	var game := _battle.game
	for cell in cells:
		var sitting := game.unit_at(cell)
		if sitting != null and sitting != attacker and sitting != defender:
			game.remove_unit(sitting)
	attacker.cell = cells[0]
	defender.cell = cells[1]
	_battle.view.sync_sprites()


## Every atlas row the posed combat cut-in baked into its art is the one
## SideIdentity gives the side it belongs to — each army's, and each ground
## strip's owner's.
##
## Checked rather than eyeballed, in the spirit of `_fog_hides_unseen`: a half
## painted in the wrong faction's colours still renders a perfectly good frame, so
## a scenario that only proves one was written passes straight through COM-10.
## Run for every cut-in mode, not just the commander ones — on a commander-less
## board it is a live check that the no-CO fallback still lands where its slot
## names, which is the case the bug hid behind.
func _check_cut_in_rows(attacker: Unit, defender: Unit) -> void:
	var cutscene := _battle.animator.cutscene
	var atk := cutscene.attacker_side()
	var def := cutscene.defender_side()
	_check_row("cut-in attacker", atk.drawn_unit_row(), _army_row(attacker.team))
	_check_row("cut-in defender", def.drawn_unit_row(), _army_row(defender.team))
	_check_row("cut-in attacker ground", atk.drawn_ground_row(), _ground_row(attacker.cell))
	_check_row("cut-in defender ground", def.drawn_ground_row(), _ground_row(defender.cell))


## The same check over the capture cut-in: the marching squad wears the
## capturer's row, and the property flips from the row its owner on the board
## wears to that same capturer's.
func _check_capture_cut_in_rows(unit: Unit, cell: Vector2i) -> void:
	var stage := _battle.animator.capture_cutscene.stage()
	var capturer := _army_row(unit.team)
	_check_row("capture squad", stage.drawn_squad_row(), capturer)
	_check_row("capture property before", stage.row_before, _ground_row(cell))
	_check_row("capture property after", stage.row_after, capturer)


## The atlas row a side's army is drawn in on the board — SideIdentity's answer,
## which is the one every surface owes.
func _army_row(team: int) -> int:
	return _battle.view.identity.atlas_row(team)


## And the row a cell's ground is drawn in — SideIdentity's answer again, asked
## of the *board* here so the cut-in is compared against what the player sees
## under it rather than against a rule this check spelled for itself.
func _ground_row(cell: Vector2i) -> int:
	return SideIdentity.terrain_row(
		_battle.map.terrain_at(cell), _army_row(_battle.game.owner_at(cell))
	)


func _check_row(what: String, drawn: int, wanted: int) -> void:
	if drawn == wanted:
		return
	_fail("%s is drawn in atlas row %d, but the board wears row %d" % [what, drawn, wanted])


## True when a cut-in mode names a variant the family actually implements — the
## part left after its prefix is one of `known`. Fails the run otherwise, naming
## every mode the family does take, since the whole hazard is a name that reads
## like a variant and quietly stages a different one.
func _known_variant(name_part: String, prefix: String, known: Array[String]) -> bool:
	if known.has(name_part.substr(prefix.length())):
		return true
	var legal := PackedStringArray()
	for suffix in known:
		legal.append(prefix + suffix)
	_fail("%s demo: unknown variant '%s'; it takes %s" % [prefix, name_part, ", ".join(legal)])
	return false
