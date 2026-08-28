---
paths:
  - "tools/**"
  - "docs/**"
  - "core/replay_codec.gd"
  - "core/save_codec.gd"
  - "Makefile"
---

# The offline instruments — designs of record

These are the `## Designs of record` entries of `CLAUDE.md` that own the base game's own plan,
the Balance Lab, replays and the smoke sweep. Read the owning entry before an architectural
decision in its area; the plans themselves are under `.lavish/`, and the long forms named in the
root index are in `docs/design_record.md`.

- `grid-commanders-plan.html` — the base game: milestones M0–M7 (all done), mechanics reference,
  damage formula.
- `balance-simulator-plan.html` — offline balance instruments BS1–BS4, all shipped. D2: **the
  telemetry observes, it never instruments the sim** — nothing under `core/` or `ai/` gained a
  hook for it. D1: `tools/balance/match_engine.gd` is the one match loop; `make commander-balance`
  and `make difficulty-check` are byte-stable presets over it, and the merge bar for touching it
  is a fixed-seed byte-diff of both reports. Its one exception is a board that engine structurally
  cannot play — it plays two sides — and the asymmetric-board entry below owns it
  (`tools/run_bulwark_measure.gd`, which reuses `BalanceHarness`, `tools/balance/four_army_loop.gd`
  (`FourArmyLoop`) and the generic `command_ceiling`, but not the two-side match engine).
  `docs/balance_sim.md` is how to run and read it.
- `focus-steal-plan.html` — developer ergonomics: the smoke sweep and the desktop's window
  focus, FS0–FS3, all shipped. The instrument is `tools/focus_timeline.sh`
  (FS0) and every claim about focus is a measurement with it, never an anecdote. FS1: the
  watcher in `tools/godot_gui.sh` lives as long as the engine it launched — its only exit
  conditions are the child dying and a human clicking into the game — and restores on every
  activation, never onto the game itself or transient system UI. FS2/FS3: the sweep boots **once
  for the whole run** — `run_batched_sweep` in `tools/smoke_scenarios.sh` passes every scenario as
  one `--demos=` queue and **scene, fog and map are per-entry boot facts** (`+fog` stays in the
  mode name, `@<map>` is appended; neither the label nor the capture filename changes) — and
  `scenes/battle/battle_capture_batch.gd` (`BattleCaptureBatch`) runs the queue in that one
  process, held in statics because a `reload_current_scene` between scenarios is what gives each a
  fresh `Battle` in the same window, and `change_scene_to_file` is what lets the `menu_` pair join
  the same boot. `BattleCaptureBatch.scenario_args()` is the one seam: it hands `Battle` the
  process command line with the current entry's `--map`/`--fog` swapped in, so
  `MatchRequest.apply_cmdline` and the documented CLI grammar are unchanged — only where the values
  are read from moved. It parses the queue lazily and idempotently, because the first scenario's
  boot facts are asked for before any driver has adopted it. Per-scenario diagnosis is preserved by
  re-running a failed sweep one process each (R2), the per-scenario deadline lives in the driver
  where the stuck scenario's name is known (R3), and `SMOKE_ISOLATE=1` still runs the verbatim
  one-process-per-scenario path (R1). `ScreenshotUtil.save_frame` is the one shutter both the batch
  and the classic quit path share, and it forces a draw before reading the viewport: macOS stops
  presenting an occluded window, and the viewport texture then hands back a stale or blank frame.
  D2: **engine-bundle metadata tricks are refuted** — `LSUIElement` and `LSBackgroundOnly`
  clones each still stole focus 3/3;
  do not re-litigate without new evidence. D3: an interactive (tty) launch still `exec`s Godot
  directly and comes up focused; only tty-less launches get the restore watcher. D1: the sweep's
  captures staying byte-identical is the merge bar for any change here — it is what keeps the two
  text-heavy scenarios a batch runs first (the process-wide font atlas shifts them otherwise)
  honest as the roster moves. That bar is a command rather than a procedure since COM-110:
  `SMOKE_HASHES=<file> make smoke` records a manifest of what every scenario hashed to, or compares
  this run against one and names each frame that moved. It is **recorded, never committed** — a
  frame is the machine's renderer and glyph rasteriser, and the same font atlas that shifts those
  two scenarios means one queue's bytes are not another's, so a manifest answers only for the queue
  it names and the comparison refuses to cross it. D6: fewer windows beats faster restores — the
  wrapper is the safety net, batching is the fix. Nothing under `core/` or `ai/` learns the sweep
  exists.
- `replay-plan.html` — re-watching a finished match, and reading the computer's mistakes out of
  one: milestones RP1 (the format and the recorder), RP2 (playback), RP3 (the menu), RP4 (the
  offline analyser), **all shipped**. D1: **a replay is an opening envelope and a command
  log** — the opening is `SaveCodec.encode` verbatim (so it carries the roster, the grouping, the
  commanders' charge and `rng_state`, and a resumed save records correctly), and the format owns
  only the command list; map + seed rebuilt through `create` is the rejected alternative, being a
  second opinion about what a match opens as. A line names its actor by the cell it acted from,
  which is unambiguous because a carried unit can never act. **The envelope is the opening, not the
  header**: what a recording is *of* — CD3's campaign and mission ids, beside `label` and
  `recorded` — rides in the header, and the campaign-depth entry below owns that decision. D2: **the recorder observes at the two
  brokers that already exist** — `BattleCommandPipeline.execute` and `BalanceMatchEngine.play`,
  each side of `apply` exactly as `BalanceMatchRecorder` is already handed a command; nothing under
  `core/` or `ai/` gains a hook, and `tools/check_scripts.sh` already enforces that the live broker
  is the only one. D3: **a replay verifies itself** — every line carries a 48-bit board digest
  (48 because JSON has one number type and a double holds integers exactly only to 2^53), and
  playback halts at the first mismatch naming the command, because the one thing a command log
  cannot survive is the game changing underneath it; a replay is disposable, so a stale one is
  deleted rather than migrated. D4: **playback is presentation** — `BattleReplayRunner` is
  `BattleAiRunner`'s sibling driving `Battle.execute_command`, no planner is built, and
  **`game.fog_enabled` is untouched** (fog is an input to `MoveCommand.validate` and to the ambush,
  so switching it off would resolve the recorded moves differently), which is why the omniscient
  viewer is a `BattlePerspective` flag and nothing else. Playback borrows `State.AI_TURN` and its
  pause seam, so the replay controls are the pause menu's: Esc parks the runner between commands,
  `replay_step` (S) takes exactly one more command and re-parks on the board rather than under that
  menu, and the menu itself drops the two save rows (`BattleMenus.map_actions`'s `savable`) because a
  playback seats no computer — saved and resumed, a recorded AI match would come back as a hot-seat
  one. For the same reason the victory lockup's rematch button reads **Restart** over a playback and
  re-stages `MatchRequest.from_replay` off `Battle.replay_path` rather than deriving a live match
  from the recorded board. D5: omniscient viewer, always-on recording into ten rotating slots under
  `user://replays/`, appended per command so a crash costs the last line rather than the file — and
  the slot is claimed by the **first command**, never the boot, because the slots rotate and a match
  nobody played must not evict one somebody did. D6: **the analyser asks the rules, never the
  planner** —
  counterfactuals come from `AttackRange` / `MovementResolver` / `CombatResolver.forecast_at`, no
  why-hook is threaded out of `ai/`, and a finding is evidence rather than a gate, so
  `make replay-report` stays out of `make verify`. **A `REPLAY=` naming a directory surveys it** —
  `tools/replay/replay_survey.gd` (`ReplaySurvey`) folds N reports into per-kind rates and **counts
  nothing itself**, taking no counterfactual and re-running no detector, so the survey inherits D6
  whole. A recording that stopped early and a file that would not read are both counted and both
  said out loud, because a survey that silently dropped input reads exactly like one that had
  nothing to drop. **`docs/replay_survey.md` is the committed measurement** — dated, superseded
  wholesale by a later one rather than edited, and it names the analyser state it measured, because
  a rate taken before a detector was quieted is not comparable to one taken after.
  D7: `--watch` (re-plan from a seed, the balance
  plan's BS3 fidelity instrument) and `--replay=` (immune to AI changes by design) are two
  instruments, not one; a `--replay=` naming no file is a viewing that named nothing and is refused
  out loud (`MatchRequest.replay_requested` is the fact `BattleSetup` reads), never quietly played
  as an ordinary match on the default board. The merge bar is `tests/unit/test_replay_fidelity.gd`: a seeded headless
  match, recorded and re-issued, reproducing every checkpoint and an identical final board. The
  analyser's eleven detectors each have a fixture that fires them exactly once
  (the `tests/unit/test_replay_*.gd` suites over `maps/fixtures/analysis.txt`), because a false
  positive costs more than a miss — it sends the reader looking at a doctrine that was playing
  correctly. By the same rule, **a counterfactual is held to what the judged side could see**:
  every detector that weighs an enemy asks `Vision.is_hidden_from` first, so no finding ever
  accuses a side over a unit the rules hid from it. `abandoned_capture` has its first real
  sightings (2026-08-16): the first three recordings held 21 partial captures and zero
  abandonments, but a live 4-army Causeway match shows two — a mech and an infantry relaying off
  the same property on consecutive days, the relay `capture_claim_depth = 0` permits — so it now
  watches a failure the shipped planner has been seen to commit; enabling the claim dial is a
  measured retune, not a bugfix.
  `walk_into_fire` carries the shape that rule takes: it fires only when **staying put was
  survivable**, since a unit already inside the same fire did not walk into anything and reporting
  it buries the moves that did. `oscillation` carries the same shape from the other side: it says
  "having fought nothing", so it fires only when nothing was fought or captured across **both**
  turns the walk spans — a unit that went out, took its shot and came home is not walking in a
  circle, and a finding whose own detail line the board contradicts is worse than a miss.
