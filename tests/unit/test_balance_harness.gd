extends GutTest
## What every offline balance run opens with: the shared databases and the
## per-run map cache. `BalanceHarness` replaced two runners' worth of duplicated
## setup (plan D1), so this pins the one copy: `load_default()` hands back
## working databases, `map_of()` resolves and caches, and a name nothing
## answers to is reported with the ones that do.
##
## Node-free, like the class it covers.


func test_load_default_returns_working_databases() -> void:
	var harness := BalanceHarness.load_default()
	assert_not_null(harness.chart, "the damage chart resource")
	assert_gt(harness.terrain_db.size(), 0)
	assert_gt(harness.unit_db.size(), 0)
	assert_gt(harness.commander_db.size(), 0)
	assert_gt(harness.difficulty_db.size(), 0)
	assert_not_null(harness.terrain_db.by_id(&"city"), "a known terrain id resolves")
	assert_not_null(harness.unit_db.by_id(&"infantry"), "a known unit id resolves")
	assert_not_null(harness.commander_db.by_id(&"gideon_holt"), "a known commander id resolves")
	assert_not_null(harness.difficulty_db.by_id(&"hard"), "a known difficulty id resolves")


## The second ask for the same name hands back the identical MapData, not an
## equal-looking reload — a map is read once per run and shared across every
## match played on it (the class doc's "safe to share").
func test_map_of_caches_the_same_object_across_calls() -> void:
	var harness := BalanceHarness.load_default()
	var first := harness.map_of("first_steps")
	var second := harness.map_of("first_steps")
	assert_not_null(first)
	assert_true(
		is_same(first, second), "the second ask must return the cached object, not a reload"
	)


## A name nothing answers to is reported alongside every name that does, so a
## typo'd `--map=` names its own fix rather than failing somewhere further in.
func test_map_of_reports_an_unknown_name_with_the_known_ones() -> void:
	var harness := BalanceHarness.load_default()
	assert_null(harness.map_of("no_such_board_at_all"))
	assert_push_error("unknown map 'no_such_board_at_all'")
	# A second, identical miss pushes its own error, so it can be asserted
	# against separately for the part the first assert already consumed.
	assert_null(harness.map_of("no_such_board_at_all"))
	assert_push_error("first_steps")
