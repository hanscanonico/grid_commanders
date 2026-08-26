extends GutTest
## What having a touch dock does to the board's framing. The mobile plan's D5 says
## a desktop build's pixels do not move, and these are that promise stated as
## arithmetic: on this build the dock is not constructed, so the chrome is the two
## bars and the lift is the constant it has always been. The dock's own behaviour
## is presentation and is driven by the `mobile_back` capture scenario instead.


func test_a_desktop_build_builds_no_dock() -> void:
	assert_false(MobileProfile.active(), "the suite runs as a desktop build")
	assert_eq(MobileDock.height(), 0)


func test_the_chrome_is_the_two_bars_on_a_desktop_build() -> void:
	assert_eq(MobileDock.chrome_h(), UiTheme.HUD_BARS_H)


## 12: the value BattleView.BOARD_LIFT_PX carried before the dock owned it.
func test_the_board_lift_is_unmoved() -> void:
	assert_eq(MobileDock.board_lift_px(), 12)


## The other half of the same promise, posed through the pin MB4 added: a touch
## build spends the dock's height out of the board and re-centres the band it
## leaves, and both answers come from here rather than from a second sum.
func test_a_touch_build_spends_the_docks_height_on_the_chrome() -> void:
	MobileProfile.pin(true)
	assert_eq(MobileDock.height(), UiTheme.HUD_DOCK_H)
	assert_eq(MobileDock.chrome_h(), UiTheme.HUD_BARS_H + UiTheme.HUD_DOCK_H)
	MobileProfile.unpin()


## The lift stays a whole screen pixel with the dock on the bar, and the nearest
## one to the band's new middle — the texel argument does not lapse on a phone.
func test_the_lift_follows_the_band_with_a_dock_on_it() -> void:
	MobileProfile.pin(true)
	var lift := MobileDock.board_lift_px()
	var exact := float(UiTheme.HUD_BOTTOM_H + UiTheme.HUD_DOCK_H - UiTheme.HUD_TOP_H) / 2.0
	assert_almost_eq(float(lift), exact, 0.5, "the lift is the nearest pixel to the middle")
	assert_gt(lift, 12, "the taller chrome pushes the board further up")
	MobileProfile.unpin()


func after_each() -> void:
	MobileProfile.unpin()  # a pin is a process fact; no sibling suite may inherit one
