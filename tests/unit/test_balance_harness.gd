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


## The refusal every driver's numeric flags now share: the message names the
## tool and the flag that read it, so one wording answers for seven drivers.
func test_positive_flag_refuses_a_non_number_by_name() -> void:
	assert_eq(BalanceHarness.positive_flag("balance-sim", "--seeds", "12"), 12)
	assert_eq(BalanceHarness.positive_flag("balance-sim", "--seeds", "0"), -1)
	assert_push_error("balance-sim: --seeds must be a positive integer (got '0')")


## 0 is a legal count and only a negative or a non-number is not.
func test_count_flag_accepts_zero() -> void:
	assert_eq(BalanceHarness.count_flag("bulwark", "--seed-offset", "0"), 0)
	assert_eq(BalanceHarness.count_flag("bulwark", "--seed-offset", "-1"), -1)
	assert_push_error("bulwark: --seed-offset must be a non-negative integer (got '-1')")


## `--out=` keeps BalanceReportWriter.resolve_out as the authority on where a run
## may write; what the helper adds is the one refusal wording.
func test_out_flag_refuses_a_path_outside_reports() -> void:
	assert_eq(BalanceHarness.out_flag("balance", "reports/flag_test"), "reports/flag_test")
	assert_eq(BalanceHarness.out_flag("balance", "/tmp/elsewhere"), "")
	assert_push_error("balance: --out is a directory under reports/ (got '/tmp/elsewhere')")


## Padding around a value is the same value: the helpers strip, so a flag read
## out of a quoted shell variable is not a refusal on one driver and a run on
## another.
func test_flags_strip_padding() -> void:
	assert_eq(BalanceHarness.positive_flag("balance", "--days", " 20 "), 20)
	assert_eq(BalanceHarness.out_flag("balance", " reports/flag_test "), "reports/flag_test")


## A switch is the one flag shape where a typo has no shape of its own, so
## `--fog=of` refused by name rather than reading as off.
func test_bool_flag_refuses_a_word_it_does_not_know() -> void:
	assert_eq(BalanceHarness.bool_flag("mobile-soak", "--fog", "on"), 1)
	assert_eq(BalanceHarness.bool_flag("mobile-soak", "--fog", " TRUE "), 1, "stripped and cased")
	assert_eq(BalanceHarness.bool_flag("mobile-soak", "--fog", "0"), 0)
	assert_eq(BalanceHarness.bool_flag("mobile-soak", "--fog", "of"), -1)
	assert_push_error("mobile-soak: --fog is on/true/1 or off/false/0 (got 'of')")


## The loop arm six drivers used to spell: a flag the sample offers is consumed,
## anything else is handed back for the driver's own arms to answer.
func test_take_consumes_the_sample_flags_and_leaves_the_rest() -> void:
	var flags := BalanceHarness.sample(4, 20, BalanceHarness.SAMPLE_FLAGS)
	assert_eq(BalanceHarness.take(flags, "balance", "--seeds=12"), BalanceHarness.TAKEN)
	assert_eq(BalanceHarness.take(flags, "balance", "--seed-offset=8"), BalanceHarness.TAKEN)
	assert_eq(BalanceHarness.take(flags, "balance", "--days=40"), BalanceHarness.TAKEN)
	assert_eq(BalanceHarness.take(flags, "balance", "--out= reports/x "), BalanceHarness.TAKEN)
	assert_eq(BalanceHarness.take(flags, "balance", "--map=atoll"), BalanceHarness.NOT_MINE)
	assert_eq(flags.seeds, 12)
	assert_eq(flags.seed_offset, 8)
	assert_eq(flags.days_cap, 40)
	assert_eq(flags.out_dir, "reports/x", "the raw text, stripped and not yet resolved")


## A refusal stops the run, and it is the same wording the drivers pushed before
## they shared the arm.
func test_take_refuses_a_malformed_value_by_name() -> void:
	var flags := BalanceHarness.sample(4, 20, BalanceHarness.SAMPLE_FLAGS)
	assert_eq(BalanceHarness.take(flags, "board-measure", "--seeds=x"), BalanceHarness.REFUSED)
	assert_push_error("board-measure: --seeds must be a positive integer (got 'x')")
	assert_eq(BalanceHarness.take(flags, "board-measure", "--days=0"), BalanceHarness.REFUSED)
	assert_push_error("board-measure: --days must be a positive integer (got '0')")


## A driver's grammar is what it lists: `run_mobile_soak.gd` has no
## `--seed-offset=` and no `--out=`, so sharing the arm may not give it either —
## both fall through to its own unknown-flag refusal exactly as they did.
func test_take_offers_only_the_flags_the_driver_lists() -> void:
	var flags := BalanceHarness.sample(2, 20, ["--seeds", "--days"])
	assert_eq(BalanceHarness.take(flags, "mobile-soak", "--seed-offset=4"), BalanceHarness.NOT_MINE)
	assert_eq(BalanceHarness.take(flags, "mobile-soak", "--out=reports/x"), BalanceHarness.NOT_MINE)
	assert_eq(flags.seed_offset, 0)
	assert_eq(flags.out_dir, "")


## A flag name nothing reads is a typo in the driver, not a flag a run silently
## never takes.
func test_sample_refuses_a_flag_it_does_not_know() -> void:
	var flags := BalanceHarness.sample(4, 20, ["--seedz"])
	assert_push_error("balance: '--seedz' is not a sample flag")
	assert_eq(BalanceHarness.take(flags, "balance", "--seedz=9"), BalanceHarness.NOT_MINE)
