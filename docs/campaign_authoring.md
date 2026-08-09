# Authoring a campaign mission

What a mission may say, what it may not, and how to add one. The design of
record is `.lavish/campaign-depth-plan.html`; this is the working document for
the person writing the 109th mission.

The gate is **`make campaigns`** (`tools/check_campaigns.gd`). Every rule below
that a machine can check is checked there and in `tests/unit/test_campaign_content.gd`,
so a shipped campaign cannot drift past it. The rules a machine *cannot* check
are in [What the gate cannot see](#what-the-gate-cannot-see), and they are the
ones that cost the retrofit the most rounds.

## The shape of a mission

A campaign is a directory under `data/campaigns/` — `campaign.tres` plus
`missions/*.tres`, found by `CampaignDB` and never listed by hand — and every
mission owns a board under `maps/campaign/<campaign>/`.

A mission states its own match as `MatchRequest`'s field list (board, seats,
sides, commanders, fog, tier), what wins it, what loses it, what it says, and
what happens while it is fought.

## The vocabulary

### Objectives — what wins it (`objectives`), what loses it (`failures`), what earns a star (`bonus_objectives`)

| Resource | Asks | Counts |
|---|---|---|
| `CaptureCell` | a named property is ours | board |
| `OwnProperties` | we hold N properties, optionally of one `terrain_id` | board |
| `ReachCell` | N of our units stand on named ground | board |
| `DestroyUnit` | a tagged unit is off the board | board |
| `ProtectUnit` | a tagged unit is still standing | board |
| `DefeatTeam` | one named army is gone | board |
| `AllySurvives` | a named ally is still in the war | board |
| `SurviveUntilDay` | the day has arrived | board |
| `DayDeadline` | the day has passed — **a failure, never a goal** | board |
| `HoldCell` | named ground has been ours for N whole days | tally |
| `LossLimit` | we have lost more than N units | tally |

Everything is counted across the player's **side** (`GameState.allied`), so an
ally's capture advances the objective and an ally's casualty is on the bill. The
one deliberate exception is `DefeatTeam`, which is about one army on purpose.

### Triggers — what a beat waits for

`DayReached`, `DayBefore`, `CellOwned`, `UnitDestroyed`, `UnitReached`,
`ForceStrength`, `ObjectiveMet`, `Flag`.

A beat's triggers are a **conjunction**: every one has to hold, which is what
makes "took the depot, and took it by day four" one beat.

### Effects — what a beat does

`SpawnUnits`, `RemoveUnits`, `Defect`, `SetOwner`, `GrantFunds`, `GrantCharge`,
`RevealObjective`, `SetFlag`, `EndMission`.

Every one lands as a `MissionEventCommand` at a command boundary, so a beat is in
the log, the save and the recording like anything else.

## The authoring rule

**A mission's event should be the thing its briefing already promised.** The
dialogue says what the fight is about; an event that *performs* that sentence is
the mission finally doing what it said, and one that contradicts it is a gimmick.
Most beats should be small — a line spoken at the moment it becomes true, plus
one board fact. The act openers, the block finales and the turning points carry
the big ones.

## Limits of the vocabulary

These are not bugs; they are the shape of the language, and each cost the
retrofit at least one round.

- **An event must carry at least one effect.** A beat that only speaks is
  unsayable. Give it the smallest true board fact instead.
- **A beat's own lines may not carry `Flag` conditions.** A recording re-issues
  the beat and has to speak the same words, so flag-varied dialogue is two events
  with opposite `Flag` triggers applying the same effect.
- **`DestroyUnit` cannot name a unit the mission spawns.** The objective is
  checked against the board the mission opens on, so the tag has to be on the map.
- **`ObjectiveMet` on a tally-backed objective never fires in time.** `HoldCell`
  and `LossLimit` are counted by `MissionProgress`, which is advanced inside
  `decide` — after the beats of that boundary have already been offered — so a
  beat watching one reads a boundary-old count. Key such a beat to the board.
- **`CaptureCell` and `CellOwned` are side-wide.** "Our team took it" is
  unsayable; an ally taking it reads the same way.
- **There is no negation of `UnitDestroyed`.** "This unit is still alive" is a
  `ProtectUnit` failure or nothing.
- **A scripted `RemoveUnits` is indistinguishable from a kill** to every reader —
  the loss limit, the AI's board diff, the debrief. Say so in the line.
- **A `Join` merge counts as a loss** for `LossLimit`, because a board diff cannot
  see which way a unit left. Write the objective text as losses *from any cause*.
- **`DefeatTeam` as a primary in a duel is a synonym for tactical victory**, and
  so is `CaptureCell` on the enemy's home headquarters — see trap 4 below.
- **`DayReached` cannot be right on a mission that can finish before it.** Key the
  beat to the board instead.
- **Adding `terrain_id` to an `OwnProperties` almost always has to move the
  count with it.** The same edit made four missions correctly winnable rather
  than won-at-deploy, and made one mandatory mission unclearable.

## The six traps

Every one of these was found in the retrofit, in several campaigns, by
independent authors, and every one passed the gate as it then stood. Five are now
refused by `make campaigns`; the sixth is the one a machine cannot see.

### 1 · A fact nothing can vary

A flag whose only writer fires for everyone who wins the mission is not a
consequence. The branch it gates is dead content: the "it went badly" reading
never happens.

*Refused by* `CampaignDefinition.constant_fact_error`, which fails a fact whose
every writing beat waits only on the calendar at a day the mission's own
`par_day` allows — and which some condition then reads. A beat on a route-gated
mission is left alone: a road the player may decline is the ordinary shape of a
fact that sometimes goes unwritten.

### 2 · Polarity inversion

A flag written by *good* play gating content the player *wants* — a star, a
commander's only appearance, an optional mission, a block's closing scene. Play
well, see less.

*Not refused by anything*, because what a player wants is not a property of the
file. It is the trap in [What the gate cannot see](#what-the-gate-cannot-see).

### 3 · An objective already satisfied on the opening board

`tc18`, a campaign finale, was won by the player's first command; `tc08` was
satisfied at deploy, because `OwnProperties` counts the headquarters and the base
the board already deals.

*Refused by* `MissionDefinition.board_error`, which asks the mission's own
`MissionRuntime` for a verdict on the board it opens on: anything but RUNNING is
a broken mission.

### 4 · A co-primary beside a match-ending primary

`MissionRuntime` reaches tactical victory *before* it walks the objective list,
so taking the last enemy's home headquarters wins the mission with every other
primary still unticked on the card.

*Refused by* `MissionDefinition.board_error`. A mission whose point is the enemy
headquarters has exactly **one** primary; anything else you want the player to do
is a bonus objective, where it is judged and earns its star.

### 5 · An optional mission that closes a block

`CampaignDefinition.closes_block` names a block's last mission structurally, so
its interlude is shown by winning that one mission and by nothing else. Gate it
and every player the route sends past it loses the page.

*Refused by* `CampaignDefinition.block_error`.

### 6 · A landing zone the beat's own triggers hold a unit on

`SpawnUnits` skips an occupied cell rather than clearing it, and a `once` beat is
spent either way — so the column speaks its line, lands nothing, and never comes
due again.

*Refused by* `MissionDefinition.definition_error`, but only where the void is
**certain**: a beat's triggers are a conjunction read at one boundary, so a
`UnitReached` naming a single cell, or an `ObjectiveMet` watching a `ReachCell`
zone with no slack in it, holds a unit on that square at the instant the beat
fires. Landing there is a beat that can never do anything.

Ownership is not occupancy, so `CaptureCell`, `HoldCell` and `CellOwned` pin
nothing: ground stays ours long after the unit that took it walked off. Dropping
a reserve onto the depot the player is being sent to take is a good beat and the
gate lets it through — it lands whenever the player has not got there yet.

*The caution the gate cannot give you:* if the beat is timed so the player is
**likely** to be standing there, you have written the same dud with a better
chance of firing. Ask when the trigger comes due and where the player is then.

## What the gate cannot see

**Trap 2, and the judgement half of trap 1.** A flag's *sign* and its
*variability* are independent: a fact can vary perfectly and still be wired
backwards, and the gate only measures the second.

The hand test, applied to every flag before it ships:

> **Describe a player who sets this flag and a player who does not, both doing
> something ordinary.**

If you cannot describe the second player, the flag is trap 1 and the gate should
have caught it — check it is not hiding behind a route gate. If you can describe
both but the one who played *better* is the one who gets less content, it is
trap 2, and the fix is to invert the condition rather than the beat: gate the
reward on the good run.

## The ledger, campaign by campaign

Snapshot of the shipped content at CD8. `CampaignDefinition.ledger_error` is what
keeps the names honest — a fact some mission reads and no mission writes fails
the gate — so this table can go stale in its detail and never in its names.

**The Six Marshals** — one fact per marshal, each written by the mission that
meets them, read by the missions that follow and by the act's own page.

| Fact | Written by | Read by |
|---|---|---|
| `ferrow_paid` | sm01, sm03 | sm02, sm18, interludes 0 & 5 |
| `vale_factory` | sm04 | sm05, sm18, interludes 1 & 5 |
| `orlov_trophy` | sm07 | sm08, sm09, sm18, interludes 2 & 5 |
| `vance_dug_in` | sm10 | sm11, sm12, sm18, interludes 3 & 5 |
| `draeg_column_intact` | sm13 | sm14, sm18, interludes 4 & 5 |
| `morn_charged` | sm16 | sm17, sm18, interlude 5 |

**The Collection** — the audit's own books; two of them gate a mission.

| Fact | Written by | Read by |
|---|---|---|
| `ferrow_bounty` | tc01, tc02 | tc02, tc03, tc18, interlude 0 |
| `province_held` | tc04 | tc06, interlude 0 |
| `forgery_proven` | tc05, tc12 | tc13, **tc14 (gate)**, tc18, interludes 1 & 2 |
| `vale_funded` | tc07 | tc10, tc11, tc16, interlude 1 |
| `witnesses_alive` | tc08 | **tc09 (gate)**, tc12, interlude 1 |
| `draeg_veterans_spared` | tc14 | interlude 2 |
| `morn_charged` | tc15 | tc17, interlude 2 |

**The Furnace Winter** — the fuel road is a counter six missions add to.

| Fact | Written by | Read by |
|---|---|---|
| `fw_granary_saved` | fw02 | **fw05 (gate)**, fw18, interludes 0 & 2 |
| `fw_ice_road_open` | fw04 | fw07, interlude 0 |
| `fw_kestrel_held` | fw06 | fw17, interlude 0 |
| `fw_depots_open` | fw07, fw08, fw09, fw10, fw11, fw12 | fw15, fw18, interludes 1 & 2 |
| `fw_bounty_paid` | fw09, fw11, fw14, fw16 | **fw16 (gate)**, fw18, interludes 1 & 2 |
| `fw_vale_withdrew` | fw12 | fw13, interlude 1 |
| `fw_road_half` | fw18 | — (the debrief's note) |

**The Hollow Crown** — the one campaign with a branch in it.

| Fact | Written by | Read by |
|---|---|---|
| `morn_bloodied` | hc01 | **hc05 (gate)**, interlude 0 |
| `ferrow_unpaid` | hc03 | hc14, hc17 |
| `vance_ledger_seized` | hc04 | hc15 |
| `directorate_fallen` | hc06 | — (the debrief's note) |
| `draeg_column_broken` | hc08 | **hc10 (gate)**, hc13, interlude 1 |
| `marshal_kept` | hc08, hc10, hc12, hc16 | hc18, interlude 2 |
| `alliance_debt` | hc12 | — (the debrief's note) |
| `crown_hollow` | hc18 | interlude 2 |

`marshal_kept` varies only because one of its four writers, hc10, is itself
gated — which is the shape trap 1's check is written to allow.

**The Long Front** — what was saved in the retreat, read at the end.

| Fact | Written by | Read by |
|---|---|---|
| `column_saved` | lf01 | lf02, lf07, lf18, interludes 0 & 2 |
| `coast_watch_saved` | lf03 | lf04, lf07, lf18, interludes 0 & 2 |
| `shrine_saved` | lf06 | lf07, lf18, interludes 0 & 2 |
| `averyn_held` | lf08 | lf16, lf18, interludes 1 & 2 |
| `carrow_early` | lf09 | **lf11 (gate)**, interludes 1 & 2 |
| `cities_burned` | lf10 | lf13, **lf15 (gate)** |
| `battery_silenced` | lf16 | lf17, lf18, interlude 2 |

**The Quiet War** — the file the whole war is about.

| Fact | Written by | Read by |
|---|---|---|
| `qw_evidence` | qw01, qw04, qw06, qw08, qw10, qw12 | — (the debrief's note) |
| `qw_towns_saved` | qw03, qw11, qw14 | qw18, interludes 1 & 2 |
| `qw_thornfield_held` | qw05 | qw16, interlude 0 |
| `qw_handler_taken` | qw06 | **qw09 (gate)**, interlude 0 |
| `qw_columns_broken` | qw07, qw08, qw09 | **qw11 (gate)**, qw13, interlude 1 |
| `qw_network_blind` | qw10 | qw12, qw17, interlude 1 |
| `qw_draeg_bloodied` | qw14 | qw18, interlude 2 |
| `qw_draeg_wall` | qw18 | — (the debrief's note) |

## Adding a mission

1. **Draw the board** under `maps/campaign/<campaign>/`. Every seat the mission
   plays needs a headquarters; tag (fifth column of a `[units]` row) whatever the
   objectives or the story name, and mark carry slots with a trailing `^` only if
   the mission before it carries its army out.
2. **Write the briefing first.** The fight it describes is the mission's real
   objective and the beat's real content.
3. **State the match** — `map_path`, `player_team`, `ai_teams`, `seats`, `sides`,
   `commanders`, `fog_enabled`, `difficulty` (a tier that ships).
4. **Pick the primary.** If it is the enemy's home headquarters, it is the *only*
   primary. Everything else the briefing asks for is a bonus.
5. **Pick the failure.** A deadline goes in `failures`, never in `objectives`, and
   `par_day` has to fall inside it.
6. **Author the beat.** One beat minimum, per D9. Its trigger is something the
   board can answer; its line is the sentence the briefing already promised; its
   effect is the smallest true board fact.
7. **Wire the ledger.** If the beat writes a fact, run the hand test above on it
   before anything reads it.
8. **Add it to `campaign.tres`** — the missions array is the play order, and
   `block_lengths` has to still cover the list.
9. **Run the gate**: `make campaigns`, then `make test`. The soak
   (`tests/unit/test_campaign_soak.gd`) plays the new mission with its script live
   and applies every one of its beats to the board it opens on.
