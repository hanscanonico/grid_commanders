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
more than that board could ever give. Ground an objective names that no unit the
player can field — dealt on the board, or built by a property the player owns —
could reach over the terrain alone, so a target reachable only by transport (a
lander to an island) reads as unreachable until the coastal act teaches the
check `TerrainType.services` and transports. A difficulty tier that does not
ship. A story line whose speaker is not on the commander roster, or a seat cast
as a commander who is not. A briefing with nothing to say when it is won. A
mission with nothing to say when it is lost. A briefing, debrief or interlude
with no unconditional line — a page that can render empty. A `CaptureCell`
whose card does not open with `Capture` or `Recapture`, or a `HoldCell` that
does not open with `Hold` or `Keep`. A deadline
filed in `objectives` or `bonus_objectives` rather than in `failures`, and a
`par_day` falling past the mission's own deadline, or before the day a hold
objective says the mission cannot be won. A launch that does not build.

**The script.** A mission that scripts nothing — D9's own clause, a content bar
rather than a definition one. A beat that waits for nothing or does nothing. Two
beats under one name. A trigger or an effect naming ground, a unit or a seat the
board does not have. Two units landing under one name. An objective held back
that no beat ever reveals.

**The board it opens on**, which the map alone cannot answer, a map dealing every
seat it names while a mission may have closed some: a mission already over before
the first command, an objective standing beside one that ends the match
outright — traps 3 and 4 below — and a visible goal already satisfied at deploy,
which costs nothing without the mission being over. A hidden objective and an
`AllySurvives` are exempt: the first is not judged until a beat reveals it, the
second is met exactly while the war is going well.

**The whole war at once.** A campaign whose story is more narration than
dialogue — over half its briefing, victory and defeat lines with no speaker. A fact some
mission reads and no mission of that campaign writes, or a `cleared:` / `stars:`
name the campaign does not run. A
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
both ask rather than a rule spelled twice — `MissionDefinition.definition_error`,
`board_error`, `content_error`, `difficulty_error` and `story_error`,
`MissionBoardReach.error`, `MissionEffect.board_error`, and `CampaignDefinition`'s `ledger_error`,
`carry_error`, `route_error`, `constant_fact_error`, `block_error` and
`speech_error`. Add a check by adding one of those, not by adding a branch to the
tool.

## The shape of a mission

A campaign is a directory under `data/campaigns/` — `campaign.tres` plus
`missions/*.tres`, found by `CampaignDB` and never listed by hand — and every
mission owns a board under `maps/campaign/<campaign>/`.

A mission states its own match as `MatchRequest`'s field list (board, seats,
sides, commanders, fog, tier), what wins it, what loses it, what it says, and
what happens while it is fought. What it says is three pages of `MissionLine`s —
`briefing`, `victory` and `defeat` — each a list of speaker plus text, the
speaker a commander id or "" for narration.

**What is said on a loss.** A defeat is dialogue exactly like a victory, drawn by
the same `MissionSpeech` under the reason the mission ended. The foe's line comes
first and carries no condition — it is the words every player hears. The war's
own staff voice comes second, and it may carry `requires` / `unless`: the debrief
is read against the ledger after `CampaignSession.record`, so a loss can sound
different on a different route. Two or three lines, never a fourth — a player who
has just lost is not reading a page. `content_error` refuses a mission with no
defeat line at all, and `speech_error` counts the page with the briefing and the
victory: a loss is spoken, not narrated.

## The vocabulary

### Objectives — what wins it (`objectives`), what loses it (`failures`), what earns a star (`bonus_objectives`)

| Resource | Asks | Counts |
|---|---|---|
| `CaptureCell` | a named property is ours | board |
| `OwnProperties` | we hold N properties, optionally of one `terrain_id` | board |
| `ReachCell` | N of our units stand on named ground — or, with a `tag`, that one named unit does | board |
| `DestroyUnit` | a tagged unit is off the board | board |
| `ProtectUnit` | a tagged unit is still standing | board |
| `DefeatTeam` | one named army is gone | board |
| `AllySurvives` | a named ally is still in the war | board |
| `SurviveUntilDay` | the day has arrived | board |
| `DayDeadline` | the day has passed — **a failure, never a goal and never a bonus** | board |
| `HoldCell` | named ground has been ours for N whole days | tally |
| `LossLimit` | we have lost more than N units | tally |

Everything is counted across the player's **side** (`GameState.allied`), so an
ally's capture advances the objective and an ally's casualty is on the bill. The
one deliberate exception is `DefeatTeam`, which is about one army on purpose.

#### How an objective is worded

`text` is an instruction on a card a player reads mid-battle, not a line of the
story — the story is in `MissionLine`, which is where the voice belongs. Three
rules, and every shipped objective follows them:

**The verb names the mechanic.** `Capture` a `CaptureCell` — `Recapture` where
the ground was ours and was taken — `Hold … for N days` a `HoldCell`, or `Keep`
where the player already owns it; `Move N units to …` a `ReachCell`, `Destroy` a
`DestroyUnit`, `Survive until day N` a `SurviveUntilDay`. A `CaptureCell` written
"Hold the eastern relay" or "Reach the shrine" tells the player the wrong
mechanic, and those two really shipped. Two of them are gated, because each
already has its word: `MissionObjective.wording_error` holds a `CaptureCell`'s
first word to `Capture` or `Recapture` — the word the action menu says — and a
`HoldCell`'s to `Hold` or `Keep`, and `content_error` refuses the mission
otherwise.

**A failure states the loss, in the present.** "Time runs out at the end of day
10", not "Vale's garrison held the crossroads past day 10": a `failures` entry is
a thing the player must stop, and past tense reads as something already lost on
day 1.

**Every number comes from the resource's own field**, spelled in digits so it
matches the readout beside it (`DAY 1/10`, `2/3 DAYS`). Prose that counts by hand
drifts the first time a mission is retuned, and then the card lies about what the
runtime checks.

One condition, one sentence, no trailing aside: "why" belongs to the briefing.
Where the ground is, the board says — see below.

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
retrofit or the Five Flags rewrite at least one round.

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
- **There is no negation of `UnitDestroyed`** — but a `UnitReached` whose
  `cells` cover the whole region a unit can be in reads "this unit is alive and
  over there". Paired with `DayReached`, it is "if the cart is still on the road
  on day four", which is how Five Flags writes every escape and every spared
  commander.
- **`DayBefore` includes its own day.** `DayBefore { day: 2 }` holds on days 1
  and 2; a beat meant to stop the day an escape fires has to end the day before
  it.
- **A visible `DestroyUnit` bonus on a unit that can escape pays its star when it
  escapes**, a scripted removal being a kill to that reader too. Hold the bonus
  back (`hidden`) and let the beat that sees the kill reveal it, and say in the
  briefing that the unit is leaving and when.
- **An escort names its unit.** `ReachCell` with a `tag` counts only that one
  unit, so "move the delegates' car to Greywater" cannot be finished by a recon
  parked on the zone; keep a `ProtectUnit` failure beside it.
- **A spawn onto an occupied cell is skipped** (trap 6) — which is also a tool:
  an ambush that lands beside a bridge is defused by a player who holds the far
  bank first, and a briefing can teach exactly that.
- **A scripted `RemoveUnits` is indistinguishable from a kill** to every reader —
  the loss limit, the AI's board diff, the debrief. Say so in the line.
- **A `Join` merge counts as a loss** for `LossLimit`, because a board diff cannot
  see which way a unit left. Write the objective text as losses *from any cause*.
- **`DefeatTeam` as a primary in a duel is a synonym for tactical victory**, and
  so is `CaptureCell` on the enemy's home headquarters — see trap 4 below.
- **`DayReached` cannot be right on a mission that can finish before it.** Key the
  beat to the board instead.
- **The sea is the player's, never the enemy's.** A port opens on the player's
  side of the board and out of the enemy's reach, because the planner never
  ferries (naval plan R1) but does buy hulls: an Iron port is a money sink or a
  free fleet, and either reads as a broken mission. An enemy landing is
  `SpawnUnits` onto shoal cells; an enemy hull is pre-placed in `[units]`; a
  player transport is a real lander or t-copter the player drives.
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

## The ledger

Snapshot of *Five Flags* as it shipped. `CampaignDefinition.ledger_error` is what
keeps the names honest — a fact some mission reads and no mission writes fails
the gate — so this table can go stale in its detail and never in its names.
`docs/five_flags.md` says what each fact means in the story; this is where each
one is written and read. A fact's own mission reads it too, on its victory page.

| Fact | Written by | Read by |
|---|---|---|
| `ff_gold_found` | ff02 — the paymaster destroyed before he leaves | ff09, **ff10 (gate)**, ff22, interlude 0 |
| `ff_powder_lost` | ff03 — +1 per powder cart still on the road on day four | ff04 (the guns land, or a mech joins), interlude 0 |
| `ff_convoys` | ff09 — +1 per carrier that reaches Hollin | ff13 (Hollin's garrison marches), interlude 1 |
| `ff_mint_page` | ff10 — the counting house taken before the ledgers burn | ff22, ff27 |
| `ff_nia_fought` | ff11 — one of Nia's tagged rangers destroyed | **ff15 / ff16 (the fork)**, ff17, ff39, interludes 2 & 5 |
| `ff_capital_ring` | ff13 — the Old Town ours when the siege breaks | ff33, interlude 1 |
| `ff_concord_shells` | ff14 — Thorne's depot taken | ff17 |
| `ff_cipher_read` | ff19 — Orin's listening post taken | ff26, ff27, interlude 2 |
| `ff_draeg_spared` | ff20 — Draeg's column withdraws with its command tank alive | ff26 (defects, or surrenders), ff35, ff39, interludes 2, 3 & 5 |
| `ff_ferrow_bought` | ff22 — the counting house taken while Ferrow still has a company | ff28, ff36, ff39, interludes 3 & 5 |
| `ff_rhea_turned` | ff30 — the lower town taken by day five | ff31, ff32, **ff37 / ff38 (the fork)**, ff39, interludes 4 & 5 |
| `ff_refugees` | ff32 — +1 per refugee convoy across the causeway | ff39, interludes 4 & 5 |
| `ff_vance_joined` | ff34 — the Ostra bridgehead taken by day seven with Vance's tank alive | ff35, ff39, interlude 5 |
| `ff_vale_stood_down` | ff36 — the three foundries taken by day nine | ff39, interlude 5 |

Three gates shape the route: the optional ff10, and the two forks. Every other
fact chooses words, a beat, or who arrives at Hammer Hill.

## The run's own facts

A victory or defeat line can also read what the run that just ended says about
itself. `CampaignSession.record` writes nine facts onto the profile under a
reserved `run:` prefix — on a loss too — and a line reads them through the same
`requires` / `unless` a variant line already carries. They are never saved and
the next mission's `begin` drops them; nothing under `core/rules/` or `ai/`
reads one, so a run fact chooses words and never moves a number (campaign-depth
D5).

| Fact | What it holds | When it is 1 |
|---|---|---|
| `run:stars` | the stars this run earned; 0 on a loss | one star was earned |
| `run:full` | whether every star the mission offers was earned | stars equal the mission's most |
| `run:par` | whether it was won inside `par_day` | won on or before par (0 with no par, and on a loss) |
| `run:day` | the day the mission ended on, won or lost | it ended on day 1 |
| `run:losses` | units the player's side lost, as the tally counts them | exactly one was lost |
| `run:best` | whether this run beat the mission's record | a replay raised the stars or lowered the best day |
| `run:first` | whether the ledger took this run's facts | the mission's first clear |
| `run:cause` | how it was lost, as `MissionRuntime.Cause`: 0 not lost, 1 routed, 2 headquarters taken, 3 a failure condition, 4 a scripted ending | the army was routed |
| `run:failure` | which failure condition fired, 1-based into `failures`; 0 otherwise | the first one listed |

Two rules. **Only a `victory` or `defeat` line may read one.** `run_fact_error`,
asked inside `ledger_error`, refuses a run fact on an `unlock_requires`, a beat's
`Flag` trigger, a briefing line or an interlude, where it would read zero
forever and say nothing. And **a first clear is `run:first` 1 and `run:best`
0**: a record can only be beaten once there is one, so "a new best" is a
replay's line and "first clear" the first run's, never both at once.

A run fact holds a value, so a band reads it like any other: `run:day` with
`at_most: 3` is "finished by day three", `run:cause` at `2` to `2` is "your
headquarters fell", `run:losses` at `0` to `0` is "without losing a unit".

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
5. **Pick the failure.** `par_day` is the pressure — it pays the speed star on
   every mission and costs nobody the battle. A deadline is a *failure*, and a
   failure needs a reason, so it belongs only where a time-shaped primary
   (`SurviveUntilDay`, `HoldCell`, `AllySurvives`, `ProtectUnit`) makes the clock
   the mission's own subject; on an ordinary capture or rout it is a second
   statement of the same pressure that takes the match away. Where one is
   authored it goes in `failures` — never in `objectives`, and never in
   `bonus_objectives` either, since its truth is "the day has passed" and both
   goal lists read "satisfied = good", so as a bonus it would pay a star for
   being slow. `par_day` has to fall inside it — and, where the primary is a
   `SurviveUntilDay`, no earlier than its day, since nothing is won before it.
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
