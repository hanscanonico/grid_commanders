extends GutTest
## AR1's merge bar, played out: the planner that keeps its plans between commands
## answers exactly what the planner that scores every unit from scratch answers,
## over whole seeded matches.
##
## A missed invalidation is not a crash. It is a *different AI* that passes every
## other test in the tree and quietly re-prices the difficulty ladder, the Atlas
## and every commander number in one commit — the AI Arena plan's R3. So these
## runs stay in the tree afterwards, and **a milestone that adds a dial to the
## planner adds a run here**: a cache that is exact only while a dial is zero is
## exactly the silent divergence this file exists to refuse.
##
## This is the broad net — three boards, and the profiles that reach paths no
## shipped tier does. Its sibling `test_ai_plan_cache.gd` holds the other
## instrument: one fixture per invalidation rule, each a board where that rule is
## the only thing standing between the two answers. Both drive the same machinery
## from `tests/helpers/plan_cache_diff.gd`, and neither keeps a copy of it.

const PlanCacheDiff := preload("res://tests/helpers/plan_cache_diff.gd")

## The one shipped tier two of these runs want: the threat-weighing run plays it
## as it ships, the shelf run plays a copy with the arena's dials turned up. Held
## once because a loaded resource is one shared instance per path — so anything
## that means to change it duplicates it first.
const HARD_TIER := preload("res://data/ai/hard.tres")

var diff: PlanCacheDiff


func before_each() -> void:
	diff = PlanCacheDiff.new()


func test_the_shipped_profile_plays_every_board_command_for_command() -> void:
	for board: Array in PlanCacheDiff.boards():
		_assert_agrees_over_a_match(board[1], AIProfile.load_default(), board[0])


## The claim path no shipped tier reaches: `capture_claim_depth` is 0 everywhere,
## and it is the one dial that makes a capturer's goal a function of where every
## *other* capturer stands. AR5 turns it on, and a cache that is exact only while
## a dial is zero is exactly the silent divergence this file exists to refuse.
func test_a_live_capture_claim_plays_command_for_command() -> void:
	for depth in [1, 2]:
		var profile := AIProfile.new()
		profile.capture_claim_depth = depth
		for board: Array in PlanCacheDiff.boards():
			_assert_agrees_over_a_match(board[1], profile, "%s at depth %d" % [board[0], depth])


## Every profile that weighs a threat map: the two shipped tiers that carry one,
## and the withdrawal dial no tier carries. Their plans are read off a map built
## once per turn against the board at the moment of first need, so these are the
## runs that prove the cache never moved that moment. The withdrawal profile is
## here for a second reason as well — AR6d gave its refuge a key read off the
## unit's *advance goal*, which is a fact about the whole board rather than about
## the ground around the unit, and a threat map is the only thing holding it.
func test_threat_weighing_profiles_play_command_for_command() -> void:
	var withdrawing := AIProfile.new()
	withdrawing.withdraw_weight = 0.5
	var profiles := {
		&"easy": load("res://data/ai/easy.tres"),
		&"hard": HARD_TIER,
		&"withdrawing": withdrawing,
	}
	for tier: StringName in profiles:
		var profile: AIProfile = profiles[tier]
		assert_not_null(profile, "the %s profile must load" % tier)
		for board: Array in PlanCacheDiff.boards():
			_assert_agrees_over_a_match(board[1], profile, "%s on %s" % [board[0], tier])


## Brutal, the arena's searched champion, seated verbatim as a tier a player can
## pick from the difficulty picker and switch to mid-match from the pause menu's
## Auto submenu. It is here for a reason none of the runs above cover: it carries
## sixteen dials off Normal *at once* — a live capture claim, cover and
## condition off the AR6 shelf, both threat readings, cohesion, a priced
## production property and the whole build block — where every run above turns
## one or two on at a time, and the plan's D2 says a milestone that
## adds a dial to the planner adds a run here. A cache exact only for the
## combinations somebody remembered to diff is what that rule refuses.
func test_the_searched_champion_plays_command_for_command() -> void:
	var profile: AIProfile = load("res://data/ai/brutal.tres")
	assert_not_null(profile, "the brutal profile must load")
	for board: Array in PlanCacheDiff.boards():
		_assert_agrees_over_a_match(board[1], profile, "%s on brutal" % board[0])


## The AI Arena's AR6 shelf, which no shipped tier carries either, so nothing
## above ever reaches the code these three gate. Each alone and then all three at
## once over a tier that also weighs a threat map, which is the profile AR5 will
## actually search with.
func test_the_arena_shelf_dials_play_command_for_command() -> void:
	var cover := AIProfile.new()
	cover.cover_tiles = 1.0
	var condition := AIProfile.new()
	condition.condition_weight = 1.0
	var joining := AIProfile.new()
	joining.join_weight = 0.5
	var whole_shelf: AIProfile = HARD_TIER.duplicate()
	whole_shelf.cover_tiles = 1.0
	whole_shelf.condition_weight = 0.6
	whole_shelf.join_weight = 0.5
	var profiles := {
		&"cover": cover,
		&"condition": condition,
		&"joining": joining,
		&"the whole shelf on hard": whole_shelf,
	}
	for dial: StringName in profiles:
		for board: Array in PlanCacheDiff.boards():
			_assert_agrees_over_a_match(board[1], profiles[dial], "%s, %s" % [board[0], dial])


## The AI Economy block, which shipped inert on every tier and so is reached by
## nothing above: two pricing dials that make ground worth more for what it
## produces — on the capture itself and, through the goal, from as far away as a
## unit can want one — and two roster dials read off how much of the board is
## still unowned and what the enemy has built, neither of them a fact any
## envelope around a unit bounds. All four on a profile that carries nothing
## else, then all four over a tier that also weighs a threat map, which is how a
## tier would carry them.
##
## The roster pair is what makes both profiles play a different game from the
## runs above: the pricing pair was measured to move no command on these three
## fixtures at any value tried, so what these runs hold for it is that it is live
## rather than a match of its own.
func test_the_economy_dials_play_command_for_command() -> void:
	var economy := AIProfile.new()
	var whole_block: AIProfile = HARD_TIER.duplicate()
	for profile: AIProfile in [economy, whole_block]:
		profile.production_capture_multiplier = 2.0
		profile.capture_goal_value_tiles = 2.0
		profile.capture_units_per_property = 0.5
		profile.build_reactivity = 0.5
	var profiles := {&"the economy alone": economy, &"the whole economy on hard": whole_block}
	for dial: StringName in profiles:
		for board: Array in PlanCacheDiff.boards():
			_assert_agrees_over_a_match(board[1], profiles[dial], "%s, %s" % [board[0], dial])


## A shipped board, at the width the Balance Lab plays on. The three fixtures
## above are small enough to keep the suite quick and they all agreed while the
## diff was still dropping half its invalidations on the floor: an army only
## marches into everybody else's envelope when there is a board wide enough to
## march across, and armies only reach that size some days in.
func test_a_shipped_board_plays_command_for_command() -> void:
	var map := MapData.load_from_file(PlanCacheDiff.SHIPPED_BOARD, diff.terrain_db)
	assert_not_null(map, "the shipped board must load")
	_assert_agrees(
		diff.over(
			map, AIProfile.load_default(), PlanCacheDiff.SHIPPED_SEEDS, PlanCacheDiff.SHIPPED_DAYS
		),
		"ironworks"
	)


## The withdrawal dial, which no shipped tier carries either. AR6d gave the
## refuge a key read off the unit's *advance goal* — a fact about the whole
## board rather than the ground around the unit — so the plan a withdrawal is
## cached as now depends on something no envelope bounds. Every profile that
## lives this dial also weighs a threat map, which is what makes the cache keep
## nothing while it is on; this run is what holds that together.
func test_a_live_withdrawal_plays_command_for_command() -> void:
	var profile := AIProfile.new()
	profile.withdraw_weight = 0.5
	for board: Array in PlanCacheDiff.boards():
		_assert_agrees_over_a_match(board[1], profile, "%s withdrawing" % board[0])


## Focus fire prices a shot by what every other ready friendly could still add to
## the same target, which no envelope around one unit bounds.
func test_live_focus_fire_plays_command_for_command() -> void:
	var profile := AIProfile.new()
	profile.focus_fire_bonus = 1.0
	_assert_agrees_over_a_match(PlanCacheDiff.SKIRMISH, profile, "focus fire")


## Commanders seated, so the meter moves under the planner all match: charge is
## banked on every exchange, powers fire mid-turn, and Sable Wren prices ground
## off the meter itself.
func test_commanders_play_command_for_command() -> void:
	var db := CommanderDB.load_default()
	for pairing: Array in [[&"sable_wren", &"gideon_holt"], [&"iris_colt", &"mara_voss"]]:
		var seated := {1: db.by_id(pairing[0]), 2: db.by_id(pairing[1])}
		assert_not_null(seated[1], "commander %s must load" % pairing[0])
		assert_not_null(seated[2], "commander %s must load" % pairing[1])
		_assert_agrees_over_a_match(
			PlanCacheDiff.SKIRMISH, AIProfile.load_default(), "%s vs %s" % pairing, seated
		)


## COM-177's own run: three armies allied against a fourth, at the tier that
## weighs a threat map (the one dial `_note_change`'s allegiance question
## gates). `BalanceMatchEngine.play()` plays exactly two sides (asymmetric-board
## plan R4), so this is played by hand through `over_grouped_match`, the way
## `test_alliance_soak.gd` plays a grouping — and it is a milestone that could
## have changed which commands survive a resync, so it earns its own run rather
## than riding on the boards above, which are all still 1v1.
func test_an_allied_grouping_plays_command_for_command() -> void:
	var map := MapData.load_from_file("res://maps/fixtures/quartet.txt", diff.terrain_db)
	assert_not_null(map, "the quartet fixture must load")
	var sides: Dictionary[int, int] = {1: 0, 2: 0, 3: 0, 4: 1}
	var result := diff.over_grouped_match(map, sides, HARD_TIER, 7, 12)
	assert_gt(result.commands, 10, "the fixture should play a real match")
	assert_eq(result.divergence, "", "the cache must not change a command under an alliance")


func _assert_agrees_over_a_match(
	board: String, profile: AIProfile, hint: String, commanders: Dictionary = {}
) -> void:
	_assert_agrees(diff.over_a_match(board, profile, commanders), hint)


## The two claims every run above makes: the planners agreed, and they agreed
## over a match long enough for the disagreement to have somewhere to happen.
func _assert_agrees(result: PlanCacheDiff.Diff, hint: String) -> void:
	assert_gt(result.commands, 10, "%s: the fixture should play a real match" % hint)
	assert_eq(result.divergence, "", "%s: the cache must not change a command" % hint)
