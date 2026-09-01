extends GutTest
## Every unit names a weapon signature that exists, and the ones that cannot
## shoot name one that fires nothing.
##
## In scope despite living beside the cut-in: BattleStyle is a Resource and
## BattleStyleDB is a RefCounted, both Node-free, and what is under test is data
## integrity — a `.tres` naming a style that is not there — not how anything
## looks. The same reason tests/unit/test_maps.gd parses every shipped board.
##
## Worth pinning because the failure is quiet. A misspelled key does not crash:
## BattleStyleDB deliberately degrades to unarmed, so the unit simply stops
## firing anything in the cut-in and the exchange still resolves correctly. That
## is the right behaviour in play and exactly the wrong behaviour to discover in
## play.

var styles: BattleStyleDB
var units: UnitDB
var chart: DamageChart


func before_each() -> void:
	styles = BattleStyleDB.load_default()
	units = Fixture.unit_db()
	chart = Fixture.chart()


## How far a lobbed round may rise above the firing line, in pixels. The number
## the howitzer's `arc` is really about is `arc x INDIRECT_LOB`, artillery being
## always indirect, so what the file authors is never the height drawn: at 90 the
## product is 135 and the shell spends ~150 ms clipped outside a 313 px half-band
## with nothing to say where it went; at 62 it is 93 and stays in frame. An arc
## that genuinely leaves the band needs an exit cue — a puff at the top edge and
## a re-entry streak — and that is a decision rather than a side effect.
const MAX_LOB_PX := 100.0


func test_every_unit_names_a_style_that_exists() -> void:
	assert_gt(units.size(), 0, "no units loaded, so this would pass vacuously")
	for type in units.all():
		assert_true(
			styles.has(type.battle_style),
			(
				"%s names battle_style '%s', which is not in %s"
				% [type.id, type.battle_style, BattleStyleDB.STYLE_DIR]
			)
		)
		assert_true(
			styles.has(type.secondary_battle_style),
			(
				"%s names secondary_battle_style '%s', which is not in %s"
				% [type.id, type.secondary_battle_style, BattleStyleDB.STYLE_DIR]
			)
		)


## The howitzer, split off the tank's cannon: a shell that visibly elevates,
## hangs and lands, rather than a tank round fired from a gun with three times
## the range. `battle_style` is a presentation key like `atlas_col`, so the split
## moved no rule and no stat — which is exactly why the two units it re-dresses
## are pinned here by name.
func test_the_howitzer_is_registered_and_dresses_the_two_units_that_lob() -> void:
	assert_true(styles.has(&"artillery"), "the howitzer style is on the shelf")
	var howitzer := styles.by_id(&"artillery")
	assert_has(BattleStyle.PROJECTILES, howitzer.projectile)
	assert_eq(howitzer.projectile, BattleStyle.SHELL)
	for id: StringName in [&"artillery", &"battleship"]:
		assert_eq(units.by_id(id).battle_style, &"artillery", "%s should fire the howitzer" % id)


func test_a_lobbed_shell_stays_inside_the_band() -> void:
	var howitzer := styles.by_id(&"artillery")
	assert_lt(
		howitzer.arc * CombatCutscene.INDIRECT_LOB,
		MAX_LOB_PX,
		"an indirect howitzer round lobs arc x INDIRECT_LOB above the firing line"
	)


## The four look scalars the weapon-fx slice added. A `.tres` is not held to an
## `@export_range` — the range guides the inspector and nothing checks a file
## written by hand — so a stagger authored in the wrong unit, or a hit throwing
## twenty chips, would ship as a frame full of noise with nothing said.
func test_every_style_declares_the_look_scalars_in_range() -> void:
	assert_gt(styles.size(), 0, "no styles loaded, so this would pass vacuously")
	for id: StringName in styles.ids():
		var style := styles.by_id(id)
		assert_between(style.fire_stagger, 0.0, 0.2, "%s fire_stagger" % id)
		assert_between(style.arrive_scale, 0.5, 1.5, "%s arrive_scale" % id)
		assert_between(style.dust, 0.0, 1.0, "%s dust" % id)
		assert_between(style.impact_debris, 0, 5, "%s impact_debris" % id)


## The built fallback and `unarmed.tres` are one answer, which is the whole of
## BattleStyleDB's contract: a style it cannot honour stages as the silent one,
## and a silent one that differed from the file would make the fallback its own
## third weapon.
func test_the_built_fallback_and_the_silent_style_agree() -> void:
	var built := BattleStyleDB.unarmed()
	var shipped := styles.by_id(&"unarmed")
	assert_eq(built.fire_stagger, shipped.fire_stagger)
	assert_eq(built.arrive_scale, shipped.arrive_scale)
	assert_eq(built.dust, shipped.dust)
	assert_eq(built.impact_debris, shipped.impact_debris)
	assert_eq(built.fire_stagger, 0.0, "nothing that never fires staggers its barrels")
	assert_eq(built.impact_debris, 0, "nothing that never fires throws chips")


func test_secondary_units_name_the_small_arms_style() -> void:
	for id: StringName in [&"tank", &"md_tank", &"mech"]:
		var type := units.by_id(id)
		assert_eq(type.secondary_battle_style, &"small_arms")
		assert_true(styles.has(type.secondary_battle_style))
		assert_eq(
			styles.for_weapon(type, DamageChart.SECONDARY),
			styles.by_id(&"small_arms"),
			"%s should replay its snapshotted secondary as small arms" % id,
		)


## The two tables that describe a secondary have to name the same units: the
## chart row the weapon is selected from, and the signature it replays with.
## Either one alone reads like the whole answer and they drift silently — a
## chart row with no style fires an invisible machine gun, a style with no row
## dresses a weapon nothing can ever select.
func test_secondary_styles_and_secondary_chart_rows_agree() -> void:
	for type in units.all():
		assert_eq(
			type.secondary_battle_style != &"unarmed",
			chart.has_secondary(type.id),
			(
				"%s names secondary_battle_style '%s' but %s a secondary chart row"
				% [
					type.id,
					type.secondary_battle_style,
					"has" if chart.has_secondary(type.id) else "has no"
				]
			)
		)


## The roster's three transports are the only units the damage chart gives no
## attack at all. They are staged as defenders and never fire, so their style
## must be the one that puts nothing on screen — a transport with a cannon
## signature would look armed the first time a doctrine let it counter.
func test_unarmed_units_have_a_style_that_fires_nothing() -> void:
	for type in units.all():
		var armed := false
		for other in units.all():
			if chart.can_attack(type.id, other.id):
				armed = true
				break
		assert_eq(
			styles.for_weapon(type, DamageChart.PRIMARY).fires(),
			armed,
			(
				"%s is %s but its style %s"
				% [
					type.id,
					"armed" if armed else "unarmed",
					"fires nothing" if armed else "fires something"
				]
			)
		)


## The whole point of two weapons: the *same* attacker reads differently depending
## on what it is shooting at. A tank strafes a foot squad with its machine gun and
## slams a vehicle with its cannon, and the cut-in has to announce and draw the one
## the rules actually picked.
##
## Pinned as a table of named matchups because this is the one place the two halves
## meet — DamageChart.select_shot decides the slot, BattleStyleDB.for_weapon dresses
## it — and either half can be right on its own while the pair says the wrong thing.
## Nothing here touches the cut-in; both collaborators are Node-free (see above).
const MATCHUPS: Array[Array] = [
	[&"tank", &"mech", &"small_arms"],
	[&"tank", &"infantry", &"small_arms"],
	[&"tank", &"tank", &"cannon"],
	[&"md_tank", &"infantry", &"small_arms"],
	[&"md_tank", &"md_tank", &"cannon"],
	[&"mech", &"tank", &"bazooka"],
	[&"mech", &"infantry", &"small_arms"],
	[&"rockets", &"infantry", &"rocket"],
	[&"rockets", &"tank", &"rocket"],
	[&"bomber", &"tank", &"bomb"],
	[&"sub", &"battleship", &"torpedo"],
	[&"artillery", &"mech", &"artillery"],
	[&"battleship", &"tank", &"artillery"],
]
## And the three that never fire at anything. A transport is only ever a defender,
## so what matters is that it stays silent rather than which weapon it would pick.
const SILENT: Array[StringName] = [&"apc", &"t_copter", &"lander"]


func test_the_selected_weapon_is_dressed_by_the_matchup() -> void:
	for row in MATCHUPS:
		var attacker: UnitType = units.by_id(row[0])
		var shot := chart.select_shot(row[0], row[1], attacker.max_ammo, attacker.max_ammo)
		assert_not_null(shot, "%s should have a shot at %s" % [row[0], row[1]])
		if shot == null:
			continue
		assert_eq(
			styles.for_weapon(attacker, shot.slot),
			styles.by_id(row[2]),
			"%s vs %s should replay as '%s'" % [row[0], row[1], row[2]]
		)


## The chip beside the unit's name is the label off the style the rules selected, so
## a signature that fires has to say what it is — an unlabelled one leaves the plate
## announcing nothing while the frame is full of tracer.
func test_every_firing_style_names_itself_and_a_silent_one_does_not() -> void:
	for id in styles.ids():
		var style := styles.by_id(id)
		assert_eq(
			style.label != &"",
			style.fires(),
			(
				"style '%s' %s but its chip label is '%s'"
				% [id, "fires" if style.fires() else "is silent", style.label]
			)
		)


func test_a_transport_selects_no_weapon_against_anything() -> void:
	for id in SILENT:
		var type := units.by_id(id)
		for other in units.all():
			assert_null(
				chart.select_shot(id, other.id, type.max_ammo, type.max_ammo),
				"%s should have no shot at %s" % [id, other.id]
			)
		assert_eq(
			styles.for_weapon(type, DamageChart.PRIMARY).label,
			&"",
			"%s should announce no weapon" % id
		)


## The fallback is the safety net BattleStyleDB's whole contract rests on, so it
## has to hold even with no files on disk at all.
func test_an_unknown_style_falls_back_to_unarmed_rather_than_null() -> void:
	var empty := BattleStyleDB.new()
	var style := empty.by_id(&"no_such_style")
	assert_not_null(style)
	assert_false(style.fires())
	assert_eq(style.muzzle, 0.0)


## Every shipped style names a projectile the cut-in can actually draw. The
## vocabulary is a match in CutsceneFx, so a typo used to fall through to the
## tracer arm and dress an artillery shell as machine-gun fire — a change nobody
## made, in a frame that photographs perfectly well.
func test_every_shipped_style_names_a_projectile_the_cut_in_draws() -> void:
	assert_gt(styles.size(), 0, "no styles loaded, so this would pass vacuously")
	for id: StringName in styles.ids():
		var style := styles.by_id(id)
		assert_has(
			BattleStyle.PROJECTILES,
			style.projectile,
			"style '%s' fires '%s'" % [id, style.projectile]
		)


## The same shape one layer down: a style names a sound, and `Sfx.NAMES` is the
## hand-kept list of the ones the autoload loads. A name that is not on it is
## never loaded and `play` skips it in silence, so the volley is permanently mute
## with nothing in the log.
##
## Sfx is an autoload rather than a Node-free class, which is normally outside
## what tests/ targets; it earns the exception exactly as Music does — see the
## docstring on tests/unit/test_music.gd.
func test_every_style_names_a_sound_sfx_loads() -> void:
	assert_gt(styles.size(), 0, "no styles loaded, so this would pass vacuously")
	for id: StringName in styles.ids():
		assert_has(
			Sfx.NAMES,
			styles.by_id(id).sfx,
			"style '%s' names sound '%s'" % [id, styles.by_id(id).sfx]
		)


## And from the other side: a wav the audio pipeline installed that nobody added
## to the list is dead weight, loaded by nothing and reachable from nothing.
##
## Deliberately not the reverse — a name with no wav is the tolerance Sfx
## documents, which is what lets a style ship ahead of its render.
func test_every_shipped_sound_is_one_sfx_loads() -> void:
	var dir := DirAccess.open(Sfx.SFX_DIR)
	assert_not_null(dir, "cannot open %s" % Sfx.SFX_DIR)
	if dir == null:
		return
	var found := 0
	for file in dir.get_files():
		# Each wav sits beside its .import sidecar, which is not a sound.
		if not file.ends_with(".wav"):
			continue
		found += 1
		assert_has(Sfx.NAMES, StringName(file.trim_suffix(".wav")), "%s is on disk" % file)
	assert_gt(found, 0, "no sounds on disk, so this would pass vacuously")


## And a typo'd one is refused out loud rather than registered: an unregistered
## style stages unarmed, which is the DB's standing answer to a style it cannot
## honour.
func test_a_style_with_an_unknown_projectile_is_refused() -> void:
	var typo := BattleStyle.new()
	typo.id = &"typo"
	typo.projectile = &"trcaer"
	var db := BattleStyleDB.new()
	db.register(typo)
	assert_push_error("is not a projectile kind")
	assert_false(db.has(&"typo"), "a style the cut-in cannot draw is not on the shelf")
