---
paths:
  - "core/campaign/**"
  - "data/campaigns/**"
  - "maps/campaign/**"
  - "docs/campaign_authoring.md"
  - "autoload/campaign_session.gd"
  - "scenes/battle/battle_campaign.gd"
  - "scenes/ui/mission_*"
  - "scenes/menu/*campaign*"
  - "tools/check_campaigns.gd"
---

# The campaign — designs of record

These are the `## Designs of record` entries of `CLAUDE.md` that own the six authored wars, the
mission vocabulary and the consequence ledger. Read the owning entry before an architectural
decision in its area; the plans themselves are under `.lavish/`, and the long forms named in the
root index are in `docs/design_record.md`.

- `campaign-depth-plan.html` — what the six shipped campaigns could not say: mission variety
  beyond capture-the-HQ, scripted mid-battle events, a consequence ledger carried between missions,
  the army a mission hands the next one, interludes and optional missions, across all six wars.
  CD1–CD8, **all shipped** (D9 is the content gate, whose refusals are
  `docs/campaign_authoring.md`'s). It is the design of record for the campaign's *depth*; the
  **Campaign mode** entry below stays the record of the campaign layer's own architecture, and the
  two are read together. It retired exactly one clause of that entry — "no evacuate/escort/convoy objective
  exists on purpose", which CD2 made sayable — and supersedes nothing else there. The diagnosis was
  the number: 86 of 108 authored objectives were `CaptureCell`, and `DayDeadline` the only failure
  condition in the game. D1: **an event effect is a `Command` issued at the one broker, never a
  direct board write** — reinforcements, a defecting garrison and a falling bridge all go through
  `BattleCommandPipeline.execute`, so an event lands in the log, the save and the replay with no
  special case. D2: **a trigger is a pure read of the committed board plus the mission's own saved
  tally**, so it can never depend on a half-applied command or on animation. D3: **events fire
  before the verdict, and a boundary settles whole** — fallen-army banner → due events →
  `CampaignSession.decide`, `MissionRuntime`'s own precedence untouched, events being a step in
  front of that class rather than a case inside it. D4: **`Unit.tag` is INERT DATA and the plan's one
  `core/` waiver** — a `StringName`, the optional fifth column of a `[units]` row, carried in save
  v9; nothing in `core/rules/`, `ai/` or the damage chart reads it, so a named unit fights, moves,
  is priced and is planned against identically to an unnamed one, and the balance byte bar stands in
  for the waiver. What a tag may *be* is `core/unit_tag.gd` and nowhere else, asked by `MapData` row
  by row and by `SaveCodec.validate` over a decoded list — a save being the second door onto the
  board. Identifying a unit by its starting cell is the rejected alternative: a unit that moves
  stops being identifiable, and a protect objective matters precisely when it is moving. D5: **a
  flag chooses authored content, never a number** — `CampaignState.flags` is a ledger of integers
  that reaches the board only by picking which authored thing is used, or a campaign becomes a
  second, invisible balance surface; nothing in `core/` or `ai/` reads one. It is **staged
  mid-mission and committed on the win**: `SetFlagEffect` changes no board, and
  **`CampaignState.complete` is the ledger's one writer**, so *a mission reads the war as it stood
  when it began, and writes to it when it is won* — which is what keeps a scripted opening
  deterministic and what stops a retry inheriting an abandoned attempt's writes. A replay of an
  already-cleared mission does not rewrite the ledger (found by test, not by reasoning), and
  `complete` returns whether the ledger took, which is the only thing the debrief's `RECORDED` lines
  print off. **`cleared:` and `stars:` are derived, never stored**, so there is no second copy to
  drift. `FlagCondition` carries **both** bounds, because a floor alone could only ever record that
  something went wrong. Variant `MissionLine`s are **independently included, not alternatives** —
  every line whose condition holds is said in authored order, an either/or being two adjacent lines
  with opposite conditions — and **a beat's own lines may not be gated**, a recording having to
  speak the same words. D6: **the carried army fills authored slots and never appends**, so every
  board still fields exactly the army it was balanced for; the short-roster fallback is the rule
  rather than the edge, which is why 99 missions are untouched by construction —
  `CampaignRoster.deploy` only writes `hp` and `tag` onto units `create` already built. A veteran is
  identified across the gap **by its type**, claiming the first unclaimed slot for it (an object
  reference dies with the board, a cell means nothing on another map, an index breaks the moment a
  unit in the middle dies); cargo banks as itself and arrives alone; a carried tag fills only a slot
  the board left unnamed. The carry mark is **`^`, the last column of a `[units]` row**, after the
  optional tag, and `core/map_data.gd`'s header comment is the authoritative statement of the map
  format. A failed mission banks nothing, `carry_out = false` **clears** the roster, a resumed
  mission does not redeploy, and deploy runs **after** `TurnRules.begin_turn` (so a carried unit on
  a friendly property misses day-one repair — recorded rather than hidden). D7:
  **`CampaignDefinition.missions` stays the only source of order** — branching is `unlock_requires`
  narrowing that list rather than forking it, which makes an unreachable mission structurally
  impossible to author. **`CampaignState.open_mission` is the ONE authority for what a war offers
  next** and `next_mission_id` is **deleted** for being a second answer to it. The route is derived
  **and latched**, and both halves are load-bearing: `unlock_requires` is **not monotone in the
  ledger** (`at_most 0` is the ordinary shape of an optional mission while flags only grow), so a
  freshly-asked gate would close a mission the player is standing on, while a naive latch alone
  cannot skip a closed mission. `route_error` keeps the route forward-only by failing
  `make campaigns` for a gate whose fact no **earlier** mission writes. **`is_complete` means the
  war has no mission left to offer**, `offered_count` is its denominator, and every surface counting
  progress reads those two — a picker counting the authored list read "17/18" forever. An interlude
  belongs to **the mission that closes the block** (`closes_block`, and only on a win), never to
  "the route left the block", with a gated block-closer refused by `block_error`. D8: the in-battle
  panel and speech overlay are presentation, and **D8's suppression clause is corrected rather than
  followed** — `MissionObjectivesPanel` is down unless `CampaignSession.active()`, which needs no
  Instant opt-out and does not hide the panel in the one scenario that exists to photograph it.
  **`O` lowers and raises the card** — a lens key like `T` and `R`, stated as a top-bar chip that is
  off the bar entirely outside a campaign, with the card's up/down state the **panel's own** rather
  than `Battle`'s; every mission opens with it up, deliberately not a device preference.
  **The card says what to do and the board says where**: all 317 objective strings were rewritten to
  one convention — the verb names the mechanic, a failure states the loss in the present, every
  number is read from the resource's own field — which `docs/campaign_authoring.md` owns, while the
  story keeps its voice (a `MissionLine` is where voice belongs). An objective that names ground is
  also **marked on the board**. `MissionObjective.marker_cells` is the authored `@export` cells read
  straight back — no board, no state, no tally, which is what separates it from the cell hooks CD8
  deleted — `BattleCampaign.objective_cells` is the single collector (live via `is_live`, unmet,
  primary and bonus alike), `ObjectiveMarks` is a dumb drawer like `CapturePips`, and the mark is
  deliberately **unfogged**, because what a mission is about is public. CD2's
  vocabulary settled that **only `HoldCell` and `LossLimit` need the tally**, which is why
  `MissionProgress` is counters, and why `is_met` / `readout` / `definition_error` take it
  **required, never defaulted** — a caller that forgot it would silently read a mission nobody can
  win. **Losses are a set difference over instance ids** between two boundaries, never "started
  with, minus have now", and the consequence is stated on the class: a `JoinCommand` merge reads as
  a loss, a board diff being unable to see which way a unit left. **The tally follows the board, not
  the mission**, so a resume inherits its losses and a retry starts clean. CD3: a `MissionEvent` is
  triggers (a **conjunction**, so a small vocabulary stays expressive) plus effects plus lines, one
  question or one deed a file under `core/campaign/triggers/` and `effects/`.
  `BattleCampaign.fire_due` is the seam and **cannot re-enter**. The opening board is the one
  boundary with no command behind it, which is what `DayReached { day: 1 }` is written against.
  **The campaign and mission ids ride in the replay *header*, never in the opening** — the opening
  stays `SaveCodec.encode` verbatim — so an event line names its beat by id; `ReplayCodec.FORMAT` is
  4, older recordings are refused outright, and a recording whose mission no longer resolves is
  refused **by name in `BattleSetup`** before a single command replays. Two rules were read off the
  shipped design rather than invented: a scripted removal **banks nothing to either charge meter**,
  and **a defection does not rout the army it empties**. `SpawnUnits` **skips an occupied cell**,
  Hammerfall staying the only thing in the game that removes a unit without a shot; a defecting unit
  takes its cargo, its capture progress and its turn with it. `MissionSpeechCard` **reads nothing** —
  its lines are handed over by the command — which is what makes a replay speak the same words. A
  hidden objective needs a stable save key, so `MissionObjective` gained `id` beside `hidden`, and
  **`MissionObjective.is_live` is the one answer to whether a condition is being judged yet**: the
  panel asks that same authority rather than printing the authored lists, so a held-back failure
  cannot name the trap. CD7 is the shape that vocabulary took across all 108 missions: 208 beats, 58
  of the 108 writing a ledger fact, ten route-gated missions, seven kinds of primary objective and
  three kinds of failure. **CD8 is the gate, and `docs/campaign_authoring.md` is the single owner of
  what the gate refuses** and of the traps left to a hand test — do not restate that list here, in
  the README or in the plan: it drifted in four surfaces inside one milestone. Three rules survive
  here: **a check is a `core/` authority the tool and `tests/unit/test_campaign_content.gd` both
  ask**, never a rule spelled in `tools/check_campaigns.gd`, so a new refusal is a new `..._error`;
  **a gate earns its authority by never being wrong**, so a case a machine cannot judge belongs in
  prose (a landing-zone check was written, proven unsound and **deleted** with the cell hooks it
  needed); and **the polarity of a fact is not in the file**, so the gate can only ever prove that a
  flag varies, never its sign. Two checks fired on shipped content and both were real (five
  missions' unjudgeable co-primaries became bonus objectives, two interlude lines lost conditions
  every route writes). **`tests/unit/test_campaign_soak.gd` asserts legality, never winnability** —
  every mission played to a verdict through `CampaignSession` itself, and every one of the 208 beats
  applied to the board its mission opens on, because a planner-against-planner game brings about
  half of them.
- **Campaign mode** (no committed plan artifact — the campaign-mode design handoff predates
  four-army play and this entry supersedes it where they disagree) — six authored wars against the
  Iron Dominion, eighteen missions each, the player rotating through the other three factions'
  commanders. The content is data end to end: a campaign is a directory under `data/campaigns/`
  (`campaign.tres` plus `missions/*.tres`, discovered by `CampaignDB` and never listed by hand),
  every mission owns a board under `maps/campaign/<campaign>/`, and `make campaigns`
  (`tools/check_campaigns.gd`) is the content gate — the board parses, the seating is one the
  board deals, every objective names ground that exists, the tier is one that ships
  (`MissionDefinition.difficulty_error`, because `DifficultyDB.by_id` falls back to Normal
  silently — right for a save naming a retired tier, invisible for a typo in a mission file),
  every story line's speaker is on the roster (`story_error`), the launch builds, every
  scripted effect is asked `MissionDefinition.events_board_error` against the board the mission
  **opens on** — an authority `tests/unit/test_campaign_content.gd` asks too, so `make verify` sees
  it as well — the one question `definition_error` cannot ask, a map dealing every seat it names
  while a mission may
  have closed some of them — and the campaign is asked `ledger_error` for the facts its content
  reads (CD4, above) and `carry_error` for a mission that carries an army in behind one that carries
  none out (CD5, above; the per-mission half — a refit floor no unit could reach, a carry slot on
  another army's row, a mission carrying an army in onto a board with no slot — is
  `MissionDefinition.definition_error`'s), plus CD8's authoring checks — whose inventory is
  `docs/campaign_authoring.md`'s, the author's side of all of it. The story is
  dialogue: a briefing or victory line is a `MissionLine` — `speaker` plus text, the speaker a
  **commander id** ("" = narration) because the roster already owns a general's name and colour
  and a name typed into 108 files is 108 places to drift; the defeat line stays one narrator's
  sentence. `MissionSpeech` is the one drawer of a spoken line, because four surfaces say them —
  the hub's briefing, `CampaignDebriefPanel` (the briefing's mirror, which plays the victory
  dialogue or the defeat line on the way back from a battle before the hub), since CD3
  `MissionSpeechCard` over the board, and since CD6 `CampaignInterludePanel` between two blocks, so
  a general sounds the same mid-battle as between missions.
  Five decisions:
  D1: **a mission states its match as `MatchRequest`'s own field list — seats and sides included —
  and `MissionDefinition.to_request()` is the one conversion.** The handoff's `player_team` /
  `ai_teams` pair cannot say "seats 1 and 3 play, and 1 stands with 3", which The Hollow Crown's
  Act II needs; a mission therefore boots through `MatchConfig.stage` and `BattleSetup` exactly as
  a menu launch does, and no campaign-only launch path exists.
  D2: **an objective is a pure read, by side, never by team.** Each `MissionObjective` subclass
  under `core/campaign/objectives/` reads only authorities that already exist (`owner_at`,
  `allied`, `is_eliminated`, `winners`) and counts ground and armies through `GameState.allied` —
  an ally's property is not a legal capture target, so a team-only count could be driven
  permanently below target by the player's own allied AI. `AllySurvivesObjective` exists because
  `winners()` lists survivors only, so "keep the marshal alive" is otherwise unsayable. Every
  objective's `definition_error` is checked when a mission loads, loud at the door.
  **`DefeatTeamObjective` is the one deliberate by-team read in the library** and its comment says
  so, because it looks exactly like the bug this rule warns about: a mission about one marshal is
  about that marshal's army, and read side-wide it would keep running with the marshal already
  gone. The clause that no evacuate/escort/convoy objective exists is retired — CD2 shipped the
  exit-zone, hold, named-unit and loss-limit verbs, and the CD entry above owns what they settled;
  the rest of this entry stands.
  D3: **`MissionRuntime`'s precedence is the class's whole point: losing outranks winning
  throughout** — tactical defeat, then failure conditions, then a scripted bad ending, then
  tactical victory, then a scripted good ending, then objectives — so a deadline that expires on
  the same board its objective completes is a failure. An `EndMission` effect is a **fact** taking
  its place in that order, never a second verdict authority (campaign-depth D3), and a hidden
  objective nobody has revealed is not judged at any step (`_live`).
  It is asked at the one seam the live scene already has — `Battle.conclude_command`, through
  `BattleCampaign`, the scene's whole campaign side (the mission capture's launch, the tally's
  opening board, the due beats, the verdict) — and it returns false for every skirmish, which is
  what leaves a
  match outside a campaign on the code it ran before campaigns existed: the sim gained no hook and
  every pre-existing test is untouched. `evaluate` takes the tally as a parameter and never writes
  it; **`CampaignSession` is `MissionProgress`' one writer** (campaign-depth D2) — `decide`
  advances the counters *before* the verdict, because a condition asking how long the ridge has
  been ours is about this board rather than the one before it, and `record_event` notes at that
  same boundary what fired and what it revealed.
  D4: **`CampaignSession` is a second autoload beside `MatchConfig`, navigation intent only** —
  `MatchConfig` deliberately carries exactly one typed request and nothing else, and a battle
  outside a campaign must not have to know a campaign exists. `clear()` empties it whole, runtime
  and verdict included, for the same reason `MatchConfig.take()` clears.
  D5: **progress is one file per campaign** under `user://campaigns/`, temp+backup like
  `SaveGame`, so six wars advance independently and finishing one cannot corrupt another's record.
  The mid-mission board is `SaveCodec.encode`'s envelope embedded whole (`CampaignSaveCodec`
  serialises no board of its own; its own format is **VERSION 4** — 2 arrived with CD2's mission
  tally, 3 with CD4's consequence ledger, 4 with CD5's carried army, and a profile below the current
  version loads with the parts it never had empty — the board save is deliberately untouched
  throughout, this being mission bookkeeping rather than
  board state, so a skirmish save is byte-unchanged) and the skirmish slot is never touched, so
  Continue keeps one unambiguous meaning; a damaged profile is read through a `JSON` instance
  rather than
  `JSON.parse_string`, whose static call logs an engine error for a condition `SaveGame` already
  treats as expected. The two file-line budgets the feature raised (`battle.gd`, `main_menu.gd`)
  are recorded with their reasons in `tools/check_scripts.sh`, extraction first —
  `MenuCampaignFlow` owns the menu's campaign walk.
