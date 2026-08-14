extends GutTest
## Every general that has a Command Power ships the spoken lines the activation
## banner reads (power-quotes plan PQ1), and every line fits the card.
##
## In scope for the same reason test_battle_styles.gd is: power_quotes is
## presentation data in the battle_style tradition — a display field on a
## Node-free Resource that no rule reads — and what is under test is data
## integrity, not how anything looks. The failure is quiet: the banner
## deliberately degrades to the quote-less card, which is the right behaviour
## in play and exactly the wrong behaviour to discover in play.

## The editorial ruler, not a rendering fact: the banner wraps at a fixed width,
## so what the cap really guards is each line staying a spoken beat rather than
## a paragraph. Raising it is a writing decision, not a fix.
const MAX_QUOTE_CHARS := 60

## The other editorial ruler. Rotation is a per-team activation counter rather
## than a roll (power-quotes plan D2), so a short list does not merely risk a
## repeat — it repeats on a fixed beat, and a two-line general says the same
## words every other power of every match. Three is where a general can be
## fired as often as the charge allows and still sound like a person.
const MIN_QUOTES := 3

var commanders: CommanderDB


func before_each() -> void:
	commanders = Fixture.commander_db()


func test_every_powered_general_has_quotes() -> void:
	var powered := 0
	for commander in commanders.all():
		if not commander.has_power():
			continue
		powered += 1
		assert_gte(
			commander.power_quotes.size(),
			MIN_QUOTES,
			(
				"%s has a Command Power but only %d power_quotes, under the %d floor"
				% [commander.id, commander.power_quotes.size(), MIN_QUOTES]
			)
		)
	assert_gt(powered, 0, "no powered commanders loaded, so this would pass vacuously")


func test_quotes_are_spoken_beats_not_paragraphs() -> void:
	for commander in commanders.all():
		for quote in commander.power_quotes:
			assert_false(
				quote.strip_edges().is_empty(), "%s ships an empty quote line" % commander.id
			)
			assert_true(
				quote.length() <= MAX_QUOTE_CHARS,
				(
					'%s quote is %d chars, over the %d cap: "%s"'
					% [commander.id, quote.length(), MAX_QUOTE_CHARS, quote]
				)
			)


## The neutral commander has no power to announce, so it must stay wordless —
## part of the guarantee that a no-CO match plays identically to before.
func test_neutral_commander_stays_silent() -> void:
	assert_true(CommanderType.neutral().power_quotes.is_empty())
