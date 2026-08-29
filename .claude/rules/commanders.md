---
paths:
  - "core/commanders/**"
  - "core/commander_type.gd"
  - "data/commanders/**"
  - "docs/commander_balance.md"
---

# Commanders and Command Powers — designs of record

These are the `## Designs of record` entries of `CLAUDE.md` that own the roster, the doctrines
and the powers. Read the owning entry before an architectural decision in its area; the plans
themselves are under `.lavish/`, and the long forms named in the root index are in
`docs/design_record.md`.

- `commanders-plan.html` — Commanders and Command Powers: milestones C1–C4, locked decisions D1–D4
  (subclassed `CommanderType`, asymmetric charge accrual, C1 scope, Sable Wren's reworked Vanish),
  risk register R1–R6.
- `new-commanders-plan.html` — six more generals, milestones NC1–NC7, **all shipped**: Ines Calder
  and Konrad Vale share the one `UnitPricing.cost_for` purchase authority while base cost remains
  charge/target/value currency; Perrin Ash and Halden Marr are domain-only and exactly neutral on
  land-only boards; Dane Ferrow's kill bounty is stolen through `ChargeLedger.bank_losses`,
  never minted; Iris Colt's `AFTER_ACTIONS` Second Wind refreshes non-attack actions. **That last
  clause is superseded by a user-directed retune: Second Wind refreshes an attack too**, so what
  `Unit.refreshable` now records is only whether the action was the unit's *own* — a fresh build
  and a unit somebody else set down or merged into stay exhausted, exactly as before — and
  `AttackCommand` no longer clears it. The flag therefore stays alive rather than becoming dead
  state: the plan's D4 “no new state/save” claim is still superseded by it, and save v8 still
  carries it, because `acted` alone cannot distinguish a unit's own action from one another unit
  spent on it. Older saves default it false, and one saved mid-turn under the old rule simply
  under-refreshes that turn's attackers. The doubled `power_cost` (44000) rides on the `.tres` with
  every other balance number; `docs/commander_balance.md` predates the retune and owes a regen.
  The roster is deliberately 5 / 5 / 4 / 4, and the full balance gate is
  18 × 18 × five scenarios × four seeds — both as that plan closed
  them; `more-commanders-plan.html` has since seated Sera Lark with the Aurora Compact (MC1),
  Iona Vance with the Meridian Coalition (MC2), Ivar Thorne with the Verdant League (MC3) and
  Radek Morn with the Iron Dominion (MC4), so they now read 6 / 6 / 5 / 5 over 22 × 22. Iona
  Vance and Mara Voss have since swapped factions — Vance is Iron Dominion, Voss is Meridian
  Coalition — and a fifth faction, the Gilded Concord, has since taken Rhea Sol, Lyra Quill and
  Sable Wren, one from each of the other three, for 6 / 5 / 4 / 4 / 3. Faction is
  presentation-only, so no count of matchups and no doctrine number is moved by either.
- `more-commanders-plan.html` — four more generals, MC1–MC5. Three of them (Lark, Vance, Thorne)
  touch no shared file at all, which is the commanders plan's D1 holding; the fourth is the whole
  cost of the plan and the one entry worth reading before touching a power. D2: **a power may name
  a cell, and `PowerCommand.target` is where it is named** — three hooks on `CommanderType`
  (`aims_power`, `power_blast_cells`, `power_target`) and `on_power_activated` growing a
  **defaulted** `target` rather than a sibling hook, because aimed and unaimed are one concept.
  The rejected alternative is an `AimedPowerCommand`: a power is deliberately just another command,
  which is what puts it in the log, the save, the replay and the AI with no special case, and a
  second class needs a second case in all five. D3: **`power_blast_cells` is the single authority
  for the footprint** — the overlay paints exactly what it returns, the AI scores exactly what it
  returns and `on_power_activated` destroys exactly what it returns, so nothing anywhere spells the
  shape a second time (the range-preview plan's D1, applied to a power). **Any cell on the board is
  a legal aim, fog or no fog**: `PowerCommand.validate` refuses an off-board target and nothing
  else, and the preview is deliberately unfogged — what fog costs the player is knowing what was
  standing there. D4: **Hammerfall is the only thing in the game that removes a unit without a
  shot**, through `GameState.remove_units`, so a match can now end without one; the doomed are
  collected before any is removed (`state.units` is being read and removal mutates it) and
  **nothing is banked to either meter**, charge being minted inside `ChargeLedger.bank_losses`
  and nowhere else — banking it to the victim would make the answer to the most expensive power in
  the game their own power. Units only: a headquarters, factory or city in the square keeps its
  owner. **The whole batch comes off the board before any army's rout is judged** (COM-179): a
  blast that empties two armies is then decided by the board rather than by the footprint's scan
  order, and one that empties *every* survivor is a deliberate deterministic no-winner — `winner`
  stays 0 with a loud `push_error`, and the victory screen has no presentation for it.
  D5: **the computer aims through the doctrine, never through the planner** —
  `RadekMorn._best_blast` answers both `wants_power` and `power_target`, so it cannot want to fire
  and then aim somewhere it did not want; `ai/` gained one branch in `_plan_power` and nothing else.
  The replay line for a power carries its target, which is what bumped `ReplayCodec.FORMAT` to 2;
  the constant has moved on since (COM-173 digested `Unit.refreshable`) and `core/replay_codec.gd`
  owns its current value. Older recordings are refused outright, which is the replay plan's D3.
  The save format did not move — the strike is one-shot and `power_active` was already saved.
  `docs/commander_balance.md` and the roster counts above are MC5's to close.
  One name in the plan's MC1 table is superseded: Sera Lark's passive export is
  **`move_bonus_points`**, not the `road_move_bonus` the table names — her bonus was never keyed to
  roads and the old name said it was, so COM-221 renamed it in `core/commanders/sera_lark.gd` and
  `data/commanders/sera_lark.tres` together. The number and the doctrine are unchanged.
- `power-quotes-plan.html` — Command Power quotes PQ1–PQ2, shipped. D1: a quote is presentation
  data — `power_quotes` is exported on `CommanderType`, the words live on each general's `.tres`,
  nothing in `core/` or `ai/` reads one. D2: rotation is by a per-team activation counter, never
  RNG, so a replayed match speaks the same words. A quote-less commander renders the banner
  pixel-identical to before. `tests/unit/test_commander_quotes.gd` enforces coverage and the
  60-character cap. Text only — no voice audio, no settings toggle.
