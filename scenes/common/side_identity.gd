class_name SideIdentity
extends RefCounted
## Resolves each side's presentation identity — theme colour, display name, and
## units/terrain atlas row — from the match's commander picks. One resolver,
## resolved once per match, read by every surface that used to say "Red"/"Blue"
## (Faction Identity plan D1/D2).
##
## Presentation only: the sim keeps its team ints everywhere, nothing here ever
## enters core/, and the identity is derived at scene setup and never stored — a
## resumed save re-resolves to the same answer because the commander picks are
## the same. The sim cannot disagree with the theatre about who is who because it
## never hears the question.
##
## No Node, no scene path: this sits in scenes/common/ beside CommanderVisuals,
## whose four faction themes it reads and never re-derives.

## Theme key -> the row the art pipeline draws that faction's units and property
## buildings at. MUST match sprite_generator's FACTIONS row order:
## 0 neutral, 1 meridian(red), 2 aurora(blue), 3 iron, 4 verdant.
const _ROW_FOR_KEY := {
	&"neutral": 0,
	&"meridian": 1,
	&"aurora": 2,
	&"iron": 3,
	&"verdant": 4,
}
## Team 0 (a neutral property owner) and any side that never resolved.
const NEUTRAL_ROW := 0
## The team-tinted rows, 1..FACTION_ROWS — one per faction, above the neutral
## row 0. The runtime property TileSet registers exactly these (BattleView).
const FACTION_ROWS := 4

## Every theme a side may fall back to, in the order it is offered. Both lists
## hold all four keys and both start with the two original classics — Meridian
## red and Aurora blue — so every resolution a two-army board ever produced is
## unchanged, and iron and verdant only ever come up on a board that seats a
## third or fourth army (four-players plan D5).
##
## Four keys against at most four armies is what makes "no two sides share a
## colour" **provable** rather than merely true so far: each fallback takes the
## first key nobody has, and there can never be fewer free keys than sides left
## to place. `_fallback`'s neutral escape hatch became unreachable with this.
##
## Generic (commander-less) sides claim classics in this order, meridian then
## aurora, so a match with no commanders at all renders exactly as it did before
## factions: side 1 red, side 2 blue (plan D4).
const _GENERIC_ORDER: Array[StringName] = [&"meridian", &"aurora", &"iron", &"verdant"]
## A mirror side — one whose faction an earlier slot already wears — borrows in
## this order instead, aurora then meridian, taking the first that is hue-distinct
## from what is already on the board (plan D3). Iron v Iron -> slate + blue;
## Aurora v Aurora -> blue + red.
const _MIRROR_ORDER: Array[StringName] = [&"aurora", &"meridian", &"iron", &"verdant"]

var _theme_by_team: Dictionary[int, CommanderVisuals.FactionTheme] = {}
var _name_by_team: Dictionary[int, String] = {}


## The identity for a running match, read straight from its commander picks.
static func for_game(game: GameState) -> SideIdentity:
	var commanders := {}
	for team in game.teams:
		commanders[team] = game.commander_of(team)
	return resolve(commanders)


## The identity for a hypothetical set of picks (team -> CommanderType). The
## selection page previews live from this before a match exists; for_game is the
## match's own route. Public and side-effect free so it can be unit-tested with
## no scene tree.
static func resolve(commanders_by_team: Dictionary) -> SideIdentity:
	var identity := SideIdentity.new()
	identity._resolve(commanders_by_team)
	return identity


## The theme a side wears — its faction's, or a borrowed classic in a mirror.
## Never null; an unresolved team answers neutral.
func theme(team: int) -> CommanderVisuals.FactionTheme:
	return _theme_by_team.get(team, CommanderVisuals.theme_for_key(CommanderVisuals.NEUTRAL_KEY))


## What a side is called — its faction name (kept even when the colour is a
## borrowed classic), or "First Army"/"Second Army" for a commander-less side.
## Team 0 is the neutral property owner, the one non-side this is asked about
## (the terrain panel labels who owns a tile).
func display_name(team: int) -> String:
	if team == MapData.NEUTRAL:
		return "Neutral"
	return _name_by_team.get(team, "Team %d" % team)


## The units/terrain atlas row a side draws in. Team 0 (a neutral property
## owner) and any unresolved team fall to the neutral row, which is what an
## unowned property and a side-less query both want.
func atlas_row(team: int) -> int:
	if not _theme_by_team.has(team):
		return NEUTRAL_ROW
	return _ROW_FOR_KEY.get(_theme_by_team[team].key, NEUTRAL_ROW)


# --- resolution --------------------------------------------------------------


## Two passes, both in slot order, so the answer is deterministic and total:
## faction sides claim their colours first, then commander-less sides take what
## is left. Every collision falls to the first free theme, so no two sides can
## resolve to the same colour and the same picks always resolve the same.
func _resolve(commanders: Dictionary) -> void:
	var used: Dictionary[StringName, bool] = {}  # theme key -> true, for every side already placed
	var roster := _seat_order(commanders)
	for slot in roster.size():
		var team: int = roster[slot]
		var faction := CommanderVisuals.theme_for(commanders.get(team))
		if faction.key == CommanderVisuals.NEUTRAL_KEY:
			continue  # commander-less; placed in the second pass
		var worn := faction if not used.has(faction.key) else _fallback(_MIRROR_ORDER, used)
		used[worn.key] = true
		_theme_by_team[team] = worn
		# The faction's own name, even when the colour it wears is a borrowed
		# classic — a mirror keeps both sides named for the faction and leans on
		# the slot numeral and commander to tell them apart.
		_name_by_team[team] = faction.display
	for slot in roster.size():
		var team: int = roster[slot]
		if _theme_by_team.has(team):
			continue
		var worn := _fallback(_GENERIC_ORDER, used)
		used[worn.key] = true
		_theme_by_team[team] = worn
		_name_by_team[team] = _ordinal_army_name(slot)


## The seats to place, in seat order: whichever sides the caller asked about.
## The roster is the match's (`GameState.teams`) or the selection page's pair, and
## either way it arrives as the keys of the picks — so this resolver never holds a
## second opinion on how many armies are playing.
func _seat_order(commanders: Dictionary) -> Array[int]:
	var seats: Array[int] = []
	for team: int in commanders:
		seats.append(team)
	seats.sort()
	return seats


## The first theme in `order` whose key is not already on the board.
## Distinctness is by theme key, which for the four faction themes is
## distinctness by hue — each theme is its own hue — so this is the "fall back by
## hue, never by shade" of plan D3, and the "first classic not in use" of D4,
## the two differing only in which order they try the four keys.
func _fallback(
	order: Array[StringName], used: Dictionary[StringName, bool]
) -> CommanderVisuals.FactionTheme:
	for key in order:
		if not used.has(key):
			return CommanderVisuals.theme_for_key(key)
	# Unreachable: both orders hold all four keys and a board seats at most four
	# armies, so a side reaching a fallback always finds one nobody has taken.
	# Answering neutral rather than crashing keeps the resolver total, but a
	# neutral side would be indistinguishable from unowned ground — and
	# `BattleView._last_seen_owner` maps an atlas row back to a team, so two sides
	# sharing row 0 would make it name the wrong owner.
	return CommanderVisuals.theme_for_key(CommanderVisuals.NEUTRAL_KEY)


func _ordinal_army_name(slot: int) -> String:
	const ORDINALS: Array[String] = ["First", "Second", "Third", "Fourth"]
	var word := ORDINALS[slot] if slot < ORDINALS.size() else "%d-th" % (slot + 1)
	return "%s Army" % word
