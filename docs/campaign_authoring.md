# Authoring a campaign mission

What a mission may say, what it may not, and how to add one. The design of
record is `.lavish/campaign-depth-plan.html`; this is the working document for
the person writing the 109th mission.

The gate is **`make campaigns`** (`tools/check_campaigns.gd`). Every rule below
that a machine can check is checked there and in `tests/unit/test_campaign_content.gd`,
so a shipped campaign cannot drift past it. The rules a machine *cannot* check
are in [What the gate cannot see](#what-the-gate-cannot-see), and they are the
ones that cost the retrofit the most rounds.

## What `make campaigns` refuses

This is the inventory, and it is the only one: README and `CLAUDE.md` point here
rather than keeping copies, because a list written in four places is re-measured
in none.

**The mission itself.** No such board, or a board that does not parse. A seating
naming a seat the board does not deal, or giving one seat to both sides. A
mission that can be neither won nor lost by objective, an empty objective slot,
or an objective naming ground or a unit the board does not have — or asking for
more than that board could ever give. A difficulty tier that does not ship. A story
line whose speaker is not on the commander roster, or a seat cast as a commander
who is not. A briefing with nothing to say when it is won. A briefing, debrief or
interlude with no unconditional line — a page that can render empty. A launch that
does not build.

**The script.** A mission that scripts nothing — D9's own clause, a content bar
rather than a definition one. A beat that waits for nothing or does nothing. Two
beats under one name. A trigger or an effect naming ground, a unit or a seat the
board does not have. Two units landing under one name. An objective held back
that no beat ever reveals.

**The board it opens on**, which the map alone cannot answer, a map dealing every
seat it names while a mission may have closed some: a mission already over before
the first command, and an objective standing beside one that ends the match
outright — traps 3 and 4 below.

**The whole war at once.** A fact some mission reads and no mission of that
campaign writes, or a `cleared:` / `stars:` name the campaign does not run. A
mission opening only once some fact is written when no mission *ahead of it*
writes it. A fact every route writes the same way, read as though it could have
gone otherwise — trap 1. A gated mission that closes a block — trap 5. An
interlude with nothing to say, one after a block the war does not have, and two
after the same block.

**The carried army**, every slip in it being an army that quietly never arrives:
a mission carrying one in behind a mission that carries none out, or onto a board
with no slot to stand it in; a carry slot marked on another army's row; a refit
minimum no unit could ever be refit to.

Each question is a `core/` authority the tool and `tests/unit/test_campaign_content.gd`
both ask rather than a rule spelled twice — `MissionDefinition.definition_error`
and `board_error`, `MissionEffect.board_error`, and `CampaignDefinition`'s
`ledger_error`, `carry_error`, `route_error`, `constant_fact_error` and
`block_error`. Add a check by adding one of those, not by adding a branch to the
tool.

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

#### What the board marks

An objective that names ground is **marked on the board** as well as printed on
the card: `MissionObjective.marker_cells` reads the cells you authored straight
back — `CaptureCell` and `HoldCell` their `cell`, `ReachCell` every cell of its
zone — and nothing else you write is involved. An objective about a count, a day
or an army names no ground and is marked nowhere. So the words never have to
carry a location the player would otherwise hunt for, and there is nothing extra
to author: place the cell correctly and the mark follows.

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
independent authors, and every one passed the gate as it then stood. Four are now
refused by `make campaigns`; two are the ones a machine cannot see.

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

### 6 · A landing zone the mission also points at

`SpawnUnits` **skips an occupied cell** rather than clearing it, and a `once`
beat is spent whether or not anything landed — while its dialogue plays either
way. So a column authored onto a square somebody happens to be standing on
speaks its line, puts nothing on the board, and never comes due again.

*Not refused by anything*, and the reason is in
[What the gate cannot see](#what-the-gate-cannot-see). **Prefer a cell adjacent
to the ground the mission points at, unless the beat's own effects guarantee the
square is clear.**

## What the gate cannot see

Two judgements live here rather than in `make campaigns`, for the same reason:
the file does not contain the fact the check would need.

### Polarity (trap 2, and the judgement half of trap 1)

A flag's *sign* and its *variability* are independent: a fact can vary perfectly
and still be wired backwards, and the gate only measures the second.

The hand test, applied to every flag before it ships:

> **Describe a player who sets this flag and a player who does not, both doing
> something ordinary.**

If you cannot describe the second player, the flag is trap 1 and the gate should
have caught it — check it is not hiding behind a route gate. If you can describe
both but the one who played *better* is the one who gets less content, it is
trap 2, and the fix is to invert the condition rather than the beat: gate the
reward on the good run.

### Whether a landing zone is clear (trap 6)

Occupancy at fire time is not statically knowable, and no narrowing of the check
rescues it:

- **A beat's effects run in authored order**, so a `RemoveUnits` earlier in the
  same beat frees the square before the `SpawnUnits` reaches it. *The courier is
  extracted and the relief column takes his square* is a good beat.
- **`due_events` reads the board once per boundary**, so an earlier due beat can
  free the square too.
- **Ownership is not occupancy.** `CaptureCell`, `HoldCell` and `CellOwned` say
  nothing about who is standing anywhere — ground stays ours long after the unit
  that took it walked off — so a reserve dropping onto the depot the player is
  being *sent* to take lands correctly whenever they have not got there yet.

Any check tight enough to refuse the real failure also refuses those, and a gate
that forbids good content teaches authors to route around the checks that are
right. The four above are worth more than a fifth that is sometimes wrong.

The hand test:

> **Say when the trigger comes due, and say where the player is then.** If the
> answer is "on that square", move the spawn one cell.

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

**The Furnace Winter** — the fuel road is a counter six missions add to, summing
to 13 so the interludes' "thirteen depots, end to end" is the counter's own truth.

| Fact | Written by | Read by |
|---|---|---|
| `fw_granary_saved` | fw02 (early capture, or the torch squad hunted down) | **fw05 (gate)**, fw18, interludes 0 & 2 |
| `fw_ice_road_open` | fw04 (the fuel sledge reaches the east landing) | fw07, interlude 0 |
| `fw_kestrel_held` | fw06 | fw17, interlude 0 |
| `fw_depots_open` | fw07 +2, fw08 +2, fw09 +2, fw10 +3, fw11 +2, fw12 +2 | fw15, fw18, interludes 1 & 2 |
| `fw_bounty_paid` | fw09, fw11, fw14, fw16 | fw14 (both branch beats), **fw16 (gate)**, fw18, interludes 1 & 2 |
| `fw_vale_withdrew` | fw12 | fw13, interlude 1 |
| `fw_siege_broken` | fw15 (the siege gun silenced) | fw17, interlude 2 |
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
