---
paths:
  - "maps/**"
  - "core/map_data.gd"
  - "core/seating.gd"
  - "core/game_state.gd"
  - "tests/helpers/map_parity.gd"
  - "docs/bulwark_balance.md"
---

# Boards and armies — designs of record

These are the `## Designs of record` entries of `CLAUDE.md` that own the map format, the
movement domains, four-army play and board fairness. Read the owning entry before an
architectural decision in its area; the plans themselves are under `.lavish/`, and the long
forms named in the root index are in `docs/design_record.md`.

- `naval-air-units-plan.html` — air and naval domains N1–N4. Standing risk R1: the AI cannot plan
  a ferry, so it never builds transports — a naval map has to let fleets reach each other without
  one. Its one-weapon simplification is superseded: Tank, Md Tank and Mech carry an infinite-ammo
  secondary the damage chart selects; every other unit stays single-weapon.
- `map-retrofit-plan.html` — which shipped boards carry a port or airfield and which stay
  land-only on purpose. Its byte-identical clause is superseded by the rule that replaced it: a
  map edit **converts** cells, never carves — land stays passable to every land class, no cell
  becomes sea, no coastline is redrawn — because a save stores its board by `map_path` and reloads
  the edited file from `res://`.
- `production-maps-plan.html` — the `forge`/`arsenal`/`steelworks` boards. D1: zero starting units
  is an omitted `[units]` section, not a flag and not a parser change. D3 keeps them land-only
  (naval R1).
- `four-players-plan.html` — up to four armies, FP1–FP6, **all shipped**. D1: **the map is the
  roster authority** — `MapData.teams()` / `player_count()` are read off the seats a board's
  `[owners]` and `[units]` name, `GameState.create` copies that into `GameState.teams`, and how many
  armies play is never a menu setting. Ask `state.teams`; `GameState.TEAMS` survives only as the
  legal maximum, re-exported from `MapData.PLAYER_TEAMS` so the `1..4` bound has one owner. The
  plan's "contiguous from 1" as a *validated* rule is superseded: a roster is a **range** — seat 1
  up to the highest seat the board names, floored at a duel — so contiguity is structural rather
  than breakable, and the many single-team fixtures keep playing the duel they always did. The save
  format is version 10 and **`core/save_codec.gd`'s header is the ledger of what arrived when**;
  `SaveCodec._teams_error` / `_sides_error` / `_eliminated_error` / `_home_hq_error` refuse a
  roster, grouping, casualty list or home-HQ list no seating could have produced *before* any
  per-side check is derived from it. `tests/unit/test_maps.gd`'s HQ and base lints hold each board
  to its **own** roster, never a global constant. D2: **`GameState.allied(a, b)` is the single
  hostility authority** — ask it, never re-derive `team != mine`; `sides` (empty = free-for-all) is
  the grouping, `enemies_of` and `side_of` its two readings, and every targeting, movement, vision,
  AI and doctrine site goes through it. Allies share sight (composed as the union over a side's
  armies) and purpose, **never infrastructure**: funds, production, repair, resupply, join and
  transports all stay `owner == unit.team`. The grouping is the *match's* choice, so it rides on
  `MatchRequest.sides` and `BattleSetup.build` writes it onto the state. D3: **elimination is a
  modelled state and victory belongs to a side** — `eliminated` / `is_eliminated` / `active_teams()`
  say who is still in; never infer a fallen army from an empty unit list. An army falls when its
  last unit dies or its **home** HQ is captured (`GameState.home_hq`; any other HQ is a high-value
  property captured like a city), and `eliminate()` is the one way out: units removed, properties to
  **neutral** rather than to the conqueror, capture progress cleared. `winner` stays **scalar, the
  winning side's lead army**, so every `winner != 0` gate is untouched; `winners()` is the
  presentation reading and lists that side's **survivors only**. `next_team()` skips the fallen and
  income never runs for one. **Duel parity is the merge bar** — first elimination, same day, same
  winner — and FP3 is the one accepted departure from the balance byte bar (`commander-balance`'s
  `matches.csv` moves only in the loser's `blue_props` / `red_props` / `blue_units`, always to 0).
  `BalanceMatchEngine.termination` is **told** an HQ fell rather than inferring it. D5: **four
  armies get four faces, and every face is presentation** — both `SideIdentity` fallback orders
  hold every theme key (four then, five since the Gilded Concord) with their first two entries
  untouched, which is what makes "no two sides share a colour" *provable* and `_fallback`'s neutral escape unreachable (`BattleView`'s
  `_last_seen_owner` maps a row back to a team). A fallen army is announced through the ordinary
  turn banner, awaited **before** the turn hands over so it lands on the board that produced it and
  suppressed while `animator.capturing`; elimination is public information, fog or no fog. The
  victory lockup reads `winners()` and the standings line reads `eliminated` in **match order**.
  D7: **`Battle.last_human_team` is the one key for both the viewer and the handoff**, read by
  `scenes/battle/battle_handoff.gd` (`BattleHandoff`), which owns the blackout — while a
  computer plays, the board renders through the fog of the human who played last, and a human turn
  blacks out whenever the previous *human* seat was someone else, so one human is never asked to
  hand the device to themselves. D6: **`scenes/menu/seat_strip.gd` (`SeatStrip`) is the menu's one
  answer to who sits at the table, who plays each army and who stands with whom** — `seats()`,
  `ai_teams()`, `sides()`, and no menu state mirrors any of it. A seat's third state is **Empty**
  (open-seats D4), offered only while closing it leaves at least two seats filled — so no seat of a
  duel board ever closes and neither do the last two filled seats of any board. **That rule's
  presentation clause is superseded** (COM-224): the refusal is unchanged, but every board now
  builds the same panel — all three seat states, all four side letters and the TABLE presets row —
  and greys what the board refuses, rather than a duel board building fewer controls and reading as
  a different screen. A closed seat wears no *lit* side badge, bringing no army and so standing on
  no side, and the sides re-pack over the filled seats (`normalised_sides` / `reopened_seats`, both
  static and pure so the shrink path is checked without a scene). The presets are tables, each
  setting a seating *and* a grouping (Duel fills the opposite pair 1+3, the fair one under the
  four-seat boards' authoring convention). A free-for-all is the **empty**
  dictionary, from the strip and from `MatchRequest.parse_sides_flag` alike, because that is what
  `GameState.allied` reads as "every army its own side". `--sides=1+3v2+4` is the flag's grammar,
  `--red`/`--blue` stay developer vocabulary, and an unreadable grouping is refused **out loud** and
  dropped to the free-for-all rather than half-applied — while the computer's seats are narrowed to
  the filled table *silently*, nothing a player types being able to reach `ai_teams`. Whether a
  grouping leaves anybody hostile is the *board's* answer, asked of `GameState.enemies_of` once a
  roster is loaded. **"Difficulty stays match-wide" is superseded (COM-225): a tier is per seat, and
  the strip is where it is said** — a chip on every row, live only while the computer plays that seat,
  which is the same rule ("asked of the seats, never of a mode") read one seat at a time; the panel's
  one Difficulty segment is gone, two controls writing one fact being the drift a single authority
  exists to prevent. `MatchRequest.seat_difficulty` (team -> tier id) carries it through the three
  adapters that state a live match — `from_replay` states none of it, a recording's opening envelope
  being the whole request — with the scalar `difficulty` as the fallback for a seat it does not name,
  so `--difficulty=hard` still means every computer seat (dropping the strip's picks, the way a flag
  overrides the menu everywhere else) and `--difficulty=2:hard` names one;
  `BattleSetup` resolves a profile per seat into `per_team_difficulty` and hands back the planners
  themselves, and save v11's `seat_tiers` is what a resume and a rematch replay. **The difficulty
  lock does not bend**: a tier is still only an `AIProfile` and a label, so per-seat difficulty is
  per-seat profile selection and nothing else, and `DIFFICULTY_PAIRINGS` and both balance reports are
  untouched.
  `SeatStrip.layout_error` and `CommanderInfoSheet.layout_error` exist for the same reason: unsorted
  rows stack at the container's origin, so enclosure alone photographed the strip as bare panel.
  The boards seating more than a duel are `compass`, `foursquare`, `heartland`, `pinwheel`, `atoll`,
  `trident`, `marchlands`, `windrose`, `causeway`, `confluence`, `coal_and_crown` (24×16, the second
  board to declare a `# grouping` and the first 2v2 authored *not* level seat by seat — three bases
  and two cities to each northern seat against one base and four cities to each southern one, equal
  side totals, the gap paid for in terrain and one extra mech rather than in property) and `bulwark`
  (whose facts are the asymmetric-board entry's, and which is the named exception to this entry's
  kind-for-kind parity and to D5). Three authoring rules govern them and only some have lints. **Every army has to be
  able to march on every other** — the AI cannot plan a ferry (naval R1) — which is why most carry
  no water at all; the three that do keep the sea **one body every port opens onto** by shape
  (Atoll's closed ring, Causeway's loopless tree off the board edge, Confluence's arms stopped short
  of it), so keep those shapes if you edit one. Their ferry-only prizes are ground the AI
  deliberately leaves alone. None carries the `# symmetric` tag — that lint is a *duel* instrument —
  so fairness on these is design review plus `test_maps.gd`'s property-parity lint plus the soak's
  win spread across seats, which is load-bearing: Compass passed every lint while giving two armies
  cities 2–3 tiles out and two 5–6, so its cities are now a ring closed under a half turn with every
  army's nearest two at exactly 4 and 5 tiles — **keep that, because no lint holds it**. 3v1 is
  deliberately asymmetric — a challenge grouping, compensated by commander pick and tier, never by
  the board. `tests/unit/test_alliance_soak.gd` plays the shipped boards in the groupings their seat
  strips offer, not only the fixture. `maps/fixtures/quartet.txt` stays a fixture, sized to fit the
  viewport whole, and is the board `make smoke`'s `side_victory` and `mixed_seat_handoff+fog`
  scenarios run on. The plan artifact's decisions stay as authored — every supersession is here.
- `four-player-maps-plan.html` — a seat may stay empty, and eight more four-seat boards: OS1 (the
  sim), OS2 (the table), OS3 and OS4 (the shelf). Builds on four-players and never duplicates it.
  D1: **the map's roster authority bends downward only** — the board still owns how many seats
  exist and where they sit, the match owns which of them are filled, any two or more.
  `GameState.create` gains a defaulted `p_seats` (empty = every seat, today's behaviour verbatim)
  and a closed seat **never enters the state**: no purse, no commander, no turn, no banner, its
  `[units]` rows skipped and its `[owners]` rows opened to neutral, so its HQ and base become ground
  anyone may take. Modelling it as a day-0 *elimination* is the rejected alternative and stays
  rejected — a ghost in the standings, the liveries, the banner and every save is a ghost that
  leaks. So is a menu-side preprocessor handing the sim a doctored `MapData`: that is a second
  opinion about the roster between the file and the state, which is the drift four-players D1
  exists to prevent. The invariant to hold onto, and why nothing downstream needed changing: **a
  reduced match on a big board produces exactly the state a small board would have produced.**
  Seats keep their own numbers — closing seat 2 of four leaves `[1, 3, 4]`, never a renumber,
  because `[owners]`, `[units]`, the liveries and the commander picks are all keyed by the seat's
  team id — and `create` is the one authority that refuses a seating, out loud and with no guessing:
  a seat the board never dealt, a seat named twice, or fewer than `MIN_SEATS` armies left.
  D3: **`GameState.home_hq` is the single authority for what an army can be beheaded through** —
  ask it, never `terrain_at(cell).id == "hq"`. "Capturing an HQ eliminates its owner" is exact only
  while every HQ has a living owner and no army holds two, and this milestone breaks the first while
  a conqueror already broke the second: a vacant seat's HQ has nobody to fell, and a survivor
  holding a conquered HQ must not be beheadable through it. Recorded by `create` from the map's
  starting ownership (`Seating.home_hqs` is the one derivation, read off the *map* because
  mid-match "the HQ this team owns" has two answers exactly when it matters, and stored as
  `GameState.home_hq`), and carried in save v7 — the map derives the same answer, so what
  persisting it buys is the **pin**: a save whose
  board has since moved an HQ is refused rather than silently re-homed, which
  `SaveBoardCheck._home_hq_board_error` enforces cell by cell. Every other HQ is a high-value
  property with HQ terrain stars, captured like a city.
  D2: **seats are the match's fourth setup fact** — `MatchRequest.seats` (empty = all) through all
  three adapters: `from_menu` reads the strip, `from_match` copies the live `state.teams` so a
  rematch of a reduced match is that match again, `apply_cmdline` reads `--seats=1,3,4` and reads it
  **before `--co=`**, because a commander list is positional over the seats that *play*. The request
  parses and does not vet; the board is where a seating is refused.
  D4 is the seat strip's third state and lives in the four-players D6 entry above, beside the rest
  of the strip. D5: **boards are authored full and reduced fairness is a convention, not a parser
  feature** — every four-seat board lints as a four-army map, and the authoring convention is that
  **opposite seats (1&3, 2&4) make the fair duel**, which the Duel preset encodes and a
  90°-rotational layout makes true by construction. No map-file metadata for seatings, no
  recommended-pairs syntax: the convention lives in the boards' header comments and in the preset.
- `asymmetric-board-plan.html` — Bulwark, the board that is not fair on purpose: one entrenched
  army holding a rampart against three allies, AB1–AB4, **all shipped**. It is the named exception
  to four-players D5, which stays the rule for every other board: **a board may compensate a
  grouping when it is authored for that grouping and declares it.** D1: **the handicap is board
  state and nothing else** — no handicap multiplier, no starting-funds field, no per-seat
  difficulty, no boss flag; the lone army's advantage is entirely `[owners]`, `[units]` and terrain.
  D2: **`# grouping 1+2+3v4` is a claim the lint checks, never an instruction the match follows** —
  read beside `SYMMETRIC_TAG` and exposed as `MapData.grouping`, the **raw declared text and nothing
  more**; `core/` interprets none of it and a board carrying it plays whatever grouping the launch
  says. Its only reader is `tests/helpers/map_parity.gd`, which turns the string into sides through
  **`MatchRequest.parse_sides_flag`** rather than re-reading the grammar in `core/` — which is also
  why the tag is a String, `core/` not being allowed to reach `scenes/`. D3: **parity moves from the
  seat to the side and is not switched off** — `MapParity.error` is the one answer to what "level"
  means, untagged boards get the seat-by-seat kind-for-kind check verbatim, and a tagged board gets
  two checks instead: allied seats identical **kind for kind**, and no side out-owning the sum of
  its opponents by **plain total count** — a ceiling rather than a judgement. AB1 settled that
  ceiling as **one-directional**: a side is held to it only while it fields no more armies than its
  opponents combined, because the defect is one army out-owning three, never three out-owning one.
  On an equally seated grouping neither side is exempt, so there the ceiling *is* equal totals. The
  rejected alternatives are an `# asymmetric` opt-out and a filename exemption list; R5 is what
  keeps the tag from becoming the former and it is **enforced** — a tagged board whose seats already
  open level fails, as does a tag that reads as a free-for-all. D4: seat 4 is the lone army, so
  `SeatStrip`'s shipped 3v1 preset fits without a line of UI. D6: **the lone army's edge is interior
  lines** (a lateral road behind the rampart), never a bigger pile — the failure mode a retune is
  most likely to drift back into. D7: land only (naval R1). `maps/bulwark.txt` is 49×32, twice the
  largest before it: **terrain and property ownership mirror exactly about column 24** (not the half
  turn `# symmetric` checks, and **nothing lints that mirror** — keep it), while each seat's four
  starting units are laid out **seat-identically** (translations by 16, not reflections, which is
  what opens the three allies on the same match). Seats 1/2/3 hold 12 properties each against seat
  4's 30. Its rampart is rows 16–18 whose middle row is mountain wall to wall except **four two-cell
  passes**, and the rule that makes it a battle rather than a siege was read out of the terrain data:
  mountain moves `foot`, `boot` and `air` only, so armour must come through 8 cells of frontage
  across 49 while infantry and mech climb anywhere. **Do not narrow the four passes** — halving them
  gave the alliance 20 of 20 — and **the belt is not a dial that helps the bulwark in either
  direction** (poorer cost it 11 points, richer took it to zero), which refutes R1's own framing. As
  the largest board in `MapCatalog.ordered()`, Bulwark is what the menu's animated backdrop bakes.
  R4: `BalanceMatchEngine` plays two sides, so the board is invisible to both balance reports and
  their staying byte-identical is the merge bar; the fairness number comes from AB3's own
  instruments — `tests/unit/test_alliance_soak.gd` for **legality** (no rejected command, no stall)
  and **`tools/run_bulwark_measure.gd` (`make bulwark-measure`) for the win spread**, which seats no
  commander because it measures the board. **`docs/bulwark_balance.md` is the committed record**, and
  **AB4's finding is that the board did not need a retune**: the unchanged board reads 64.1%
  alliance over 40 seeds (not AB3's n=20 headline of 73.7%, so an edit justified by that figure
  would have been an edit justified by noise), and all four candidates lost to leaving it alone.
