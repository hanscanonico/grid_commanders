extends GutTest
## The scrolling menu's arithmetic (mobile plan MB4): a build menu is taller than
## the band a touch build leaves it, so the rows become a window onto the list.
##
## Both answers are static and pure — the same shape PathArrow.segments is — so
## they are checked here rather than by photographing a menu.


func test_a_list_that_fits_opens_at_the_top() -> void:
	for selected in 6:
		assert_eq(ActionMenu.visible_window(selected, 6, 6), 0)
		assert_eq(ActionMenu.visible_window(selected, 6, 9), 0)


func test_the_window_follows_the_armed_row() -> void:
	for selected in 12:
		var top := ActionMenu.visible_window(selected, 12, 5)
		assert_between(selected, top, top + 4, "row %d is off screen" % selected)


func test_the_window_never_runs_off_either_end() -> void:
	assert_eq(ActionMenu.visible_window(0, 12, 5), 0, "the first row opens at the top")
	assert_eq(ActionMenu.visible_window(11, 12, 5), 7, "the last row opens at the bottom")


func test_a_degenerate_capacity_shows_the_top() -> void:
	assert_eq(ActionMenu.visible_window(9, 12, 0), 0)
	assert_eq(ActionMenu.visible_window(9, 12, -1), 0)


func test_rows_that_fit_counts_the_gaps_between_them() -> void:
	# Four 20px rows with 3px between them measure 89px, not 92.
	assert_eq(ActionMenu.rows_that_fit(89.0, 23.0, 3.0), 4)
	assert_eq(ActionMenu.rows_that_fit(88.0, 23.0, 3.0), 3)


func test_rows_that_fit_always_offers_one_row() -> void:
	assert_eq(ActionMenu.rows_that_fit(0.0, 23.0, 0.0), 1, "a band too short still shows a row")
	assert_eq(ActionMenu.rows_that_fit(100.0, 0.0, 0.0), 1, "and so does a row of no height")
