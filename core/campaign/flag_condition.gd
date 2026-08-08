class_name FlagCondition
extends Resource
## What the consequence ledger has to say for a piece of authored content to be
## used — a variant briefing line, a beat that only happens because an earlier
## mission went a particular way.
##
## One class because several things ask the same question: a `Flag` trigger, a
## variant `MissionLine`, and whatever CD6 hangs an optional mission on. A
## condition each of them spelled its own way is that many places for "at least"
## to drift into meaning something slightly different.
##
## **Both bounds, and that is the point.** With a floor alone the ledger can
## record that something went wrong and never that the player was quick or
## careful, so a war carried between missions could only ever get worse. `at_most`
## is the other half, and the two together say "between".

## The fact, as a `SetFlag` beat writes it or as the campaign's own record
## answers it (`CampaignState.flag`).
@export var flag: StringName = &""
## The least the ledger must hold. 0 is no floor, a fact never being negative.
@export var at_least: int = 1
## The most it may hold; -1 is no ceiling.
@export var at_most: int = -1


## Does the war read this way? A null ledger is a mission being played outside a
## campaign profile, where every fact reads zero.
func holds(ledger: CampaignState) -> bool:
	var value := ledger.flag(flag) if ledger != null else 0
	if value < at_least:
		return false
	return at_most < 0 or value <= at_most


## Why nothing could ever satisfy this, or "". Asked when a mission loads, so a
## band no ledger can hold is loud at the door rather than silent as content
## nobody ever sees.
func definition_error() -> String:
	var name_error := CampaignState.flag_name_error(flag)
	if name_error != "":
		return name_error
	if at_least < 0:
		return "flag '%s' asks for at least %d, and a fact is never negative" % [flag, at_least]
	if at_most >= 0 and at_most < at_least:
		return "flag '%s' asks for %d to %d, which nothing can hold" % [flag, at_least, at_most]
	return ""
