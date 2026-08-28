extends GutTest
## The five faction hues, read the way a red-green colourblind player reads them.
##
## test_side_identity.gd proves no two sides ever draw in the same theme, and
## every hue is plainly distinct as raw RGB. Neither says the pair is still
## distinct once red and green have collapsed onto one axis, which is what the
## faction-identity plan's D5 leaves unproven — so this suite simulates
## deuteranopia (the common red-green form, ~1 in 16 men) and measures the five
## hues against each other again in that space.
##
## ## The simulation
##
## Viénot, Brettel & Mollon 1999, "Digital video colourmaps for checking the
## legibility of displays by dichromats" — the single-plane LMS projection every
## later tool (Vischeck, GIMP's display filter) took its matrices from. Linear
## RGB is taken to LMS by the Hunt-Pointer-Estevez transform, the M cone's
## response is replaced by the one a dichromat infers from the L and S cones it
## still has, and the result is taken back to sRGB. It is an approximation of a
## severe dichromat, deliberately: the worst case is the case a colour scheme has
## to survive.
##
## Distance is **full CIE76** over CIE Lab, through LegibilityMetric.lab so the
## repo has one statement of what Lab is. Full, unlike LegibilityMetric's own
## `hue_distance`, which drops the lightness term on purpose: dropping it is
## right when a value bar is already measuring it, and wrong here, because
## lightness is exactly the axis a dichromat still has and the one two collapsed
## hues are told apart on.
##
## ## THE FINDING: Meridian and Verdant nearly collide
##
## The ten pairs read (CIE76, normal sight -> simulated deuteranopia):
##
##   aurora   / gold      146.8 -> 156.6
##   meridian / aurora    108.4 -> 121.9
##   aurora   / verdant   119.6 -> 106.9
##   iron     / gold       93.4 ->  97.3
##   iron     / aurora     65.5 ->  69.9
##   meridian / iron       74.9 ->  57.7
##   verdant  / gold       65.9 ->  57.5
##   iron     / verdant    59.3 ->  40.9
##   meridian / gold       75.4 ->  40.7
##   meridian / verdant    99.6 ->  17.0   <-- red and green, both olive
##
## Meridian red and Verdant green simulate to two olive tones that differ mostly
## in lightness. 17 is far above the ~2.3 a trained eye can just tell apart, so
## it is not a true collision, but it is a quarter of what the other nine pairs
## keep and the two armies would read as shades of one colour on a busy board.
## Gold, the fifth hue, was chosen against this table: its worst pair is 40.7,
## a shade under the iron/verdant pair, and it left meridian/verdant the pair to
## watch.
##
## That is a design decision for a human, not a test's to force, so the gate here
## is MIN_DISTANCE — a floor that says "still two colours", which today's hues
## clear — and the table above is the record. The floor is set where it is
## because the design already refuses to let colour carry meaning alone
## (CommanderVisuals: "faction first, never colour alone" — the emblem and the
## faction name are always beside the hue), so a near-collision costs legibility
## rather than information. Raise MIN_DISTANCE the day a surface asks a hue to
## speak by itself.

## Well clear of the ~2.3 CIE76 two colours are just-noticeably different at, and
## below the 17.0 the worst shipped pair reads: a floor against a collision, not
## a bar for comfort. See the header's table.
const MIN_DISTANCE := 12.0

## Hunt-Pointer-Estevez, linear RGB -> LMS, as Viénot 1999 states it. Rows are
## L, M, S.
const RGB_TO_LMS: Array[Vector3] = [
	Vector3(17.8824, 43.5161, 4.11935),
	Vector3(3.45565, 27.1554, 3.86714),
	Vector3(0.0299566, 0.184309, 1.46709),
]
const LMS_TO_RGB: Array[Vector3] = [
	Vector3(0.080944, -0.130504, 0.116721),
	Vector3(-0.0102485, 0.0540194, -0.113615),
	Vector3(-0.000365294, -0.00412163, 0.693513),
]
## The deuteranope's plane: L and S pass through, and the missing M response is
## the one those two imply.
const DEUTERANOPE_M := Vector3(0.494207, 0.0, 1.24827)


## Every faction on the roster, asked of the single authority rather than listed
## here, so a fifth faction is measured the day it is seated.
func _faction_keys() -> Array[StringName]:
	var keys: Array[StringName] = []
	for theme: CommanderVisuals.FactionTheme in CommanderVisuals.faction_themes():
		keys.append(theme.key)
	return keys


## One faction's shipped field colour, asked of the same authority.
func _hue(key: StringName) -> Color:
	return CommanderVisuals.theme_for_key(key).color


static func _project(matrix: Array[Vector3], v: Vector3) -> Vector3:
	return Vector3(matrix[0].dot(v), matrix[1].dot(v), matrix[2].dot(v))


## What a deuteranope sees of a colour. Works in linear light, which is where the
## cone responses are defined; sRGB in, sRGB out.
static func deuteranope(colour: Color) -> Color:
	var linear := colour.srgb_to_linear()
	var lms := _project(RGB_TO_LMS, Vector3(linear.r, linear.g, linear.b))
	var seen := Vector3(lms.x, DEUTERANOPE_M.dot(lms), lms.z)
	var back := _project(LMS_TO_RGB, seen)
	var clamped := Color(
		clampf(back.x, 0.0, 1.0), clampf(back.y, 0.0, 1.0), clampf(back.z, 0.0, 1.0)
	)
	return clamped.linear_to_srgb()


## Full CIE76: how far apart two colours are, lightness included.
static func cie76(a: Color, b: Color) -> float:
	return (LegibilityMetric.lab(a) - LegibilityMetric.lab(b)).length()


func test_every_faction_pair_survives_deuteranopia() -> void:
	var keys := _faction_keys()
	for i in keys.size():
		for j in range(i + 1, keys.size()):
			var first := keys[i]
			var second := keys[j]
			var distance := cie76(deuteranope(_hue(first)), deuteranope(_hue(second)))
			assert_gt(
				distance,
				MIN_DISTANCE,
				(
					"%s and %s collapse to one colour under deuteranopia (CIE76 %.1f)"
					% [first, second, distance]
				)
			)


func test_meridian_and_verdant_are_the_pair_to_watch() -> void:
	# The header's finding, pinned: red and green are the pair the simulation
	# costs the most, so a retune that made another pair worse than this one has
	# moved the problem rather than fixed it.
	var keys := _faction_keys()
	var worst := INF
	var worst_pair := ""
	for i in keys.size():
		for j in range(i + 1, keys.size()):
			var distance := cie76(deuteranope(_hue(keys[i])), deuteranope(_hue(keys[j])))
			if distance < worst:
				worst = distance
				worst_pair = "%s/%s" % [keys[i], keys[j]]
	assert_eq(worst_pair, "meridian/verdant", "the closest simulated pair moved")


func test_simulation_leaves_a_blue_alone() -> void:
	# A deuteranope's blue axis is intact, so Aurora must simulate to something
	# still plainly blue — the check that the projection is the right one and not,
	# say, a greyscale.
	var seen := deuteranope(_hue(&"aurora"))
	assert_gt(seen.b, seen.r, "simulated Aurora lost its blue")
	assert_gt(seen.b, seen.g, "simulated Aurora lost its blue")


func test_simulation_collapses_red_and_green_together() -> void:
	# The property that makes the measurement above meaningful: red and green
	# both land on the yellow axis, where r and g agree.
	for key: StringName in [&"meridian", &"verdant"]:
		var seen := deuteranope(_hue(key))
		assert_almost_eq(seen.r, seen.g, 0.02, "%s did not collapse onto the red-green axis" % key)


func test_a_grey_is_unchanged_by_the_simulation() -> void:
	# A colour with nothing for the missing cone to carry must come back as
	# itself; this is the identity the projection is built to preserve.
	for level: float in [0.0, 0.25, 0.5, 1.0]:
		var grey := Color(level, level, level)
		assert_lt(cie76(deuteranope(grey), grey), 1.0, "grey %.2f moved under simulation" % level)
