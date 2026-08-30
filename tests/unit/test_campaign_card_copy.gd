extends GutTest
## How much of a war's premise the picker's card can hold. The count is derived
## from the room left under the lines above it, because a line the card cannot
## hold is painted over by the next card rather than trimmed by its own label.


func test_a_card_fits_as_many_whole_lines_as_it_has_room_for() -> void:
	assert_eq(CampaignPickerPanel.premise_lines(26.0, 13.0), 2, "two whole lines fit")


func test_a_part_line_is_not_offered() -> void:
	assert_eq(CampaignPickerPanel.premise_lines(25.0, 13.0), 1, "the second line would be sliced")


func test_a_card_with_no_room_left_still_says_something() -> void:
	assert_eq(CampaignPickerPanel.premise_lines(4.0, 13.0), 1, "a teaser of one line, clipped")


func test_a_font_that_measures_nothing_is_not_divided_by() -> void:
	assert_eq(CampaignPickerPanel.premise_lines(40.0, 0.0), 1)
