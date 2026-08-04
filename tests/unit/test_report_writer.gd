extends GutTest
## Where an offline run is allowed to write.
##
## Worth its own suite because the same defect has now been found three times in
## two milestones, in three different tools: `path_join` concatenates rather than
## resolves, so a caller-supplied `--out=` re-roots inside the repo under a name
## nobody reads while the tool reports the path it was handed. The case table is
## `tools/balance_pool.py`'s `OUT_CASES`, run against the GDScript half of the
## one policy so the two cannot drift apart quietly.


func test_a_plain_relative_path_lands_under_reports() -> void:
	assert_eq(BalanceReportWriter.resolve_out("verify_equiv"), "reports/verify_equiv")
	assert_eq(BalanceReportWriter.resolve_out("./nested/run"), "reports/nested/run")


func test_a_path_already_under_reports_is_not_doubled() -> void:
	assert_eq(
		BalanceReportWriter.resolve_out("reports/balance_pool/run"), "reports/balance_pool/run"
	)
	assert_eq(BalanceReportWriter.resolve_out("reports"), "reports")


func test_a_res_spelled_path_is_the_same_directory_said_the_other_way() -> void:
	assert_eq(BalanceReportWriter.resolve_out("res://reports/ai_arena/run"), "reports/ai_arena/run")


func test_an_absolute_path_is_refused() -> void:
	assert_eq(BalanceReportWriter.resolve_out("/tmp/pooltest"), "")
	assert_eq(BalanceReportWriter.resolve_out("res:///tmp/pooltest"), "")


func test_a_path_that_climbs_out_is_refused() -> void:
	assert_eq(BalanceReportWriter.resolve_out("../escape"), "")
	assert_eq(BalanceReportWriter.resolve_out("reports/../../escape"), "")


func test_resolving_a_resolved_path_changes_nothing() -> void:
	for out in ["verify_equiv", "./nested/run", "reports", "res://reports/ai_arena/run"]:
		var once := BalanceReportWriter.resolve_out(out)
		assert_eq(BalanceReportWriter.resolve_out(once), once, "idempotent for '%s'" % out)


func test_the_arena_refuses_an_out_that_leaves_reports() -> void:
	var request := _seated("--out=/tmp/x")
	assert_ne(request.error, "", "an escaping --out is refused before a match is played")


func test_the_arena_reports_the_directory_it_resolved() -> void:
	var request := _seated("--out=res://reports/ai_arena/run")
	assert_eq(request.error, "")
	assert_eq(request.artifact_dir(), "reports/ai_arena/run")


func _seated(out_flag: String) -> ArenaRequest:
	var args := PackedStringArray(
		["--red-profile=data/ai/default.tres", "--blue-profile=data/ai/hard.tres", out_flag]
	)
	return ArenaRequest.parse(args)
