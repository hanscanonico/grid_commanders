class_name ThreatMap
extends RefCounted
## Where the enemy could hit next turn, and how hard. For every enemy that can
## reach a firing position and shoot a given board cell, this records that the
## cell is threatened by that unit; a caller then asks "if my unit stood here,
## what damage answers it?" and gets a luck-free forecast summed over those
## enemies. What it buys the planner is a unit that can refuse to end its move in
## a kill zone. It is not a Difficult-only smart: the four dials that read it
## (threat_aversion, advance_threat_tiles, withdraw_weight,
## capture_threat_aversion) are as usable to make a tier timid as to make it
## careful, and any tier weighing one of them above zero builds this map —
## AIProfile.builds_threat_map is the one statement of which they are. Which tier
## carries which value is the tier files' (data/ai/*.tres) and
## docs/difficulty_check.md's — not this comment's.
##
## Node-free like the rest of ai/. Reuses the single authorities and re-derives
## no rules: MovementResolver for each enemy's reach, AttackRange for its firing
## ring and for whether an enemy can fire at the defender (can_fire, so a dived
## sub is charged nothing by a hunter that cannot reach under the water),
## CombatResolver.forecast_at for the damage. Forecast is luck-free and draws no
## RNG, so a Difficult match stays as deterministic and replayable as any other
## tier.
##
## The expensive half — one flood fill per enemy — depends only on where the
## enemies are, which does not change during the side's own turn (a unit only
## leaves the board by dying to a counter). So AIPlanningContext builds one of
## these once per turn and reuses it across every command planned that turn,
## keyed on the day and the enemy set so a new day always rebuilds it — the day
## marks the turn boundary because a controller plans for one team for the whole
## match and its team id never changes.
##
## One approximation comes with that, and it is deliberate: an enemy's reach is
## flood-filled against the board as it stood when the map was built, so our own
## units moving during the turn does not re-open or re-block the lanes they were
## standing in. Refreshing per command would cost a fill per enemy per command
## for a second-order correction. The map is a scoring heuristic and never a
## legality check, so the cost of being slightly stale is a slightly wrong
## preference, never an illegal move.

## cell -> Array[Unit]: the enemies that can bring `cell` under fire. An enemy
## appears at most once per cell however many firing positions reach it. The
## value stays a plain Array — GDScript cannot nest typed containers, so the
## Unit typing lives only in the doc comment and at each read.
var _by_cell: Dictionary[Vector2i, Array] = {}


## Builds the map for `team` from the enemies it can see. The caller passes the
## visible-enemy list (already filtered through Vision) so this stays ignorant of
## the fog rules — it never widens what the AI is allowed to know.
##
## Each enemy's reach is filled with that enemy's own sight (MOVER_SIGHT, the
## default `firing_cells` passes down), never with the planning team's, because
## the question is "what will this enemy attempt" and it will attempt it with
## the knowledge it has. Keyed to the planner's team the fill would be walled by
## our own units the enemy has not spotted, and the map would under-report the
## reach the enemy actually plans through — where over-reporting is the safe
## direction for a heuristic that only ever makes a unit more careful. Mostly a
## fog question: with fog off `MovementResolver.reachable` computes no visible
## set at all, and what the key still decides there is the doctrine-hidden — a
## dived submarine or a vanished unit hides on a clear day too, so the enemy
## plans through one of ours it cannot see either way round.
static func build(state: GameState, enemies: Array[Unit]) -> ThreatMap:
	var map := ThreatMap.new()
	for enemy in enemies:
		if enemy.type.max_range <= 0 or not AttackRange.has_ready_weapon(state, enemy):
			continue  # no ready weapon: no threat to map
		var band := AttackRange.band(state, enemy)
		var seen: Dictionary[Vector2i, bool] = {}
		for from in AttackRange.firing_cells(state, enemy):
			map._mark_ring(state, enemy, from, band, seen)
	return map


## Flags every in-bounds cell in the [low, high] firing ring around `from` as
## threatened by `enemy`. The ring geometry — which cells, in what order — is
## AttackRange's, the same walk threat_cells and the range overlay use; this only
## records who threatens each one, the attribution the union throws away.
##
## `seen` is this enemy's own set of cells already attributed to it, carried
## across its firing positions by `build` so the once-per-cell rule costs a
## lookup rather than a scan of the cell's list. It must stay a first-wins set:
## the append order it preserves is the per-cell enemy order `_by_cell` holds,
## and therefore the order `incoming_damage` sums its forecasts in.
func _mark_ring(
	state: GameState, enemy: Unit, from: Vector2i, band: Vector2i, seen: Dictionary[Vector2i, bool]
) -> void:
	for cell in AttackRange.ring_cells(state, from, band.x, band.y):
		if seen.has(cell):
			continue
		seen[cell] = true
		if _by_cell.has(cell):
			_by_cell[cell].append(enemy)
		else:
			_by_cell[cell] = [enemy]


## Expected luck-free damage `defender` would take standing on `cell`, summed
## over every enemy that threatens it and capped at the defender's HP — two
## attackers cannot cost more than the unit is worth.
##
## Evaluates the shot with the defender *at* `cell`, which is the whole point:
## the terrain it would move onto changes how hard it is hit. `forecast_at`
## takes that position as an effective value, so scoring a hypothetical move
## asks a question without ever standing the unit somewhere to ask it.
##
## The price is taken from the enemy's *current* cell (`enemy.cell` below),
## never from whichever firing position in `_mark_ring` actually reached this
## cell — the stored per-cell list only says who threatens it, not from where.
## For every shipped doctrine but one that is exact: only the defender's
## terrain enters the formula, so any in-range origin gives the same number.
## Alina Ward is the exception — her combined_arms_pct reads the firing cell
## (core/commanders/alina_ward.gd) — so against her the map can be off by that
## bonus in either direction. Accepted: this is a scoring heuristic, never a
## legality check, and per-origin forecasting would cost a second fill's worth
## of bookkeeping to correct one commander's percentage points. Pinned by
## tests/unit/test_ai_smarts.gd's
## test_ward_combined_arms_makes_the_firing_cell_matter_to_the_map.
func incoming_damage(state: GameState, defender: Unit, cell: Vector2i) -> int:
	if not _by_cell.has(cell):
		return 0
	var enemies: Array = _by_cell[cell]
	var total := 0
	for enemy: Unit in enemies:
		if not AttackRange.can_fire(state, enemy, defender):
			continue  # no chart entry, or the defender is dived beyond this hunter
		var forecast := CombatResolver.forecast_at(state, enemy, enemy.cell, defender, cell)
		if forecast.can_attack:
			total += forecast.attack_damage
	return mini(total, defender.hp)
