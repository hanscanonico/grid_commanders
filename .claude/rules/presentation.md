---
paths:
  - "scenes/**"
  - "autoload/**"
  - "assets/**"
  - "data/battle_anim/**"
  - "generators/sprites/**"
  - "export_presets.cfg"
  - "docs/sprite_legibility.md"
  - "docs/mobile_soak.md"
---

# Presentation — designs of record

These are the `## Designs of record` entries of `CLAUDE.md` that own the board, the HUD, the
cut-ins, the menus, the art pipeline and the touch builds. Read the owning entry before an
architectural decision in its area; the plans themselves are under `.lavish/`, and the long
forms named in the root index are in `docs/design_record.md`.

- `game-speed-plan.html` — the game-speed setting GS1–GS3. D1: a device preference in
  `user://settings.cfg`, never the `MatchRequest` a launch is staged as and never a save. Standing
  invariant: **nothing under `core/` or `ai/` may import `GameSpeed` or read `Settings`** — pacing
  can never move an outcome, a save or a replay. Instant is an explicit branch, not an animation
  scale of zero. **The GS3 subjective retune landed from playtest (COM-226/230)**: the tiers are
  **Normal / Quick / Instant**, Normal carrying the old Slow's numbers, Quick the old Normal's and
  Slow dropped — a stored `slow` needs no migration, since `GameSpeed.by_id` answers a stranger with
  the default and the default is now the tier holding the numbers that preference asked for. COM-230
  is the other half: **the cut-in clock obeys the tier, and `CutscenePlayback` is the one place it
  does** — the two directors own beat sheets only, those sheets are authored in seconds at the
  default tier, and `GameSpeed.cutscene_rate()` states a tier as a *rate* on that clock rather than
  as `anim_scale` on the sheet, which would stretch a two-second exchange to six. Skip stays
  `t = total` at any rate, and Instant never reaches a cut-in at all.
- `faction-identity-plan.html` — armies wear their commander's faction, FI1–FI3 shipped. D1:
  **identity is presentation-only** — the sim keeps its team ints; `scenes/common/side_identity.gd`
  (`SideIdentity`) resolves `team → {theme, display name, atlas row}` once per match from the
  commander picks and is the single authority every surface reads — ask it, never re-derive a
  side's colour or name. Its fallbacks are load-bearing and total: a no-CO match is
  board-identical to before factions. The atlas-row order (`0 neutral, 1 meridian, 2 aurora,
  3 iron, 4 verdant, 5 gold`) is a contract between `SideIdentity._ROW_FOR_KEY` and the art
  pipeline — since 2026-08-14 `generators/sprites`, whose `palette.FACTIONS` tuple mirrors it
  row for row and reads this game's own `CommanderVisuals` themes; the original "rows 0–2 stay
  byte-for-byte" clause retired with the PixVoxel art it froze. **That mirror is a test rather
  than a comment** — `generators/sprites/tests/test_palette_mirror.py`, run by `make sprites-test`,
  parses `commander_visuals.gd` and `side_identity.gd` and fails on the drifted key by name.
  **The generator lives at `generators/sprites` since 2026-08-28** and every "generator `<hash>`"
  citation below names a commit of the archived sibling repo, now also this repo's history through
  the subtree; a change to the art is an ordinary PR here from that date on.
  **A property column of that atlas is a transparent overlay** (generator `e26154e`, adopted
  2026-08-18): the building, its plinth and an opaque shadow (solid since the clause below), alpha
  everywhere else, so a
  city on road or beach no longer wears a baked green square. Two rules follow and neither is a
  per-cell judgement. **`TerrainDB.GROUND_ID` / `ground()` is the single answer to what is
  underneath** — the *default* ground everywhere, never a per-context one, because a map has one
  terrain per cell and the property *is* that terrain; inventing a context would be a map-format
  change. And **every surface that draws a property composes ground-then-building**:
  `BattleView.ground_layer` is a second `TileMapLayer` under `terrain_layer` painted only on
  property cells — under rather than instead, so the property keeps its cell in `terrain_layer`
  and `repaint_property`, `_last_seen_owner` and the fog pass are untouched — `MapThumbnail`
  answers `ground_region` beside `sheet_region` (and its `bake` must `blend_rect` the building,
  since `blit_rect` copies alpha and would punch the ground back out), `HudBottomBar` stacks two
  `TextureRect`s, and `LegibilityArt.board_cell` hands the composite an `under` cell. The
  out-of-bounds backdrop needed nothing: it already substitutes plains for a team-tinted cell.
  **`CutsceneScenery.cell_tint` skips `a == 0`** for the same reason — the capture cut-in's roof
  window is always aimed at a property column, and transparent pixels read as black dragged a city
  roof a third of the way to it. D5: **"Red"/"Blue" survive only as developer slot vocabulary** (the Balance Lab's
  `--red`/`--blue` grammar, identifiers, comments) — never on a screen a player sees.
- `tile-info-panel-plan.html` + `.lavish/hud/SPEC.md` — the tile info panel and the docked HUD
  (`HudTopBar`, `HudBottomBar` under `scenes/ui/`, built in code; `show_tile()` is the bottom
  bar's). Presentation-only; the fog/doctrine gate stays in `battle_view.gd`'s `refresh_panel`,
  which nulls units the viewer cannot see before the panel gets them. Every metric — bar heights,
  the pad and gap, the chip, the rule heights, the portrait, the two icons and the charge meter —
  plus the colour tokens and the shared builders (`hud_divider`, `hud_spacer`, `hud_label`) live in
  `UiTheme`: the bar scripts hardcode no colour and no size, which COM-98 made true of the size half
  as well. The bars' one metric disagreement resolved with it — `_PAD` was declared 7 on the top bar
  and 6 on the bottom, and the 6 had never reached a pixel, because `hud_spacer` floors a negative
  width at zero and each bar is inset by its own gap; one `HUD_PAD` of 7 is what both had always
  drawn. The terrain chip asks `BattleView` for the atlas and its cell size rather than mirroring
  them. `BoardCamera._apply_board_offset` is the **only writer**
  of `camera.offset` (the combat shake composes through `BoardCamera.shake_offset`), and both bars
  swallow the pointer (`MOUSE_FILTER_STOP`) so events can't fall through to cells rendered behind
  them.
- `battle-animations-plan.html` — the combat cut-in BA1–BA4, all shipped. **Long form:
  `docs/design_record.md` § `battle-animations-plan.html`** — the snapshot-field list and how COM-83
  arrived at it, the scenery departure's argument, the figure sheet's history, the ground-line
  measurement and the three solid-shadow readings with their moved-frame counts. D1: **the cut-in
  replays a snapshot, it computes nothing** — `core/` gained only snapshot fields on `CombatResult`
  (`attacker_hp_before` / `defender_hp_before` and their `_after` siblings, the two weapon slots the
  rules selected, `attacker_indirect`); `AttackRange` stays the one authority on who is indirect and
  `BattleStyleDB.for_weapon` the one map from a weapon to a style, neither ever re-decided at replay
  time. D2: board art, blown up; nothing redrawn — with **one recorded departure, the cut-in's
  scenery**, where a terrain either *paves* the ground or *stands* on it, said by two presentation
  keys on `TerrainType` beside `atlas_col` (`cutin_ground` / `cutin_scenery`) and asked through
  `stands_in_cutin()`, never by terrain id; `tests/unit/test_terrain_db.gd` lints the pair together.
  D5: how a weapon looks is a `BattleStyle` under `data/battle_anim/`, `UnitType.battle_style` /
  `secondary_battle_style` are presentation keys like `atlas_col`, and no gameplay number may ever
  appear in a style. **A figure is that art minus the shadow the tile needed** —
  `UnitSprite.figure_texture_for` is the one way to ask for it,
  `assets/tiles/units_atlas_figures.png` and its frame-B sibling the sheets it cuts from, the pixels
  **subtracted by the generator** and never by a redraw or a colour-keyed shader in `scenes/`;
  `tests/unit/test_figure_sheet.gd` is the pin. **`UnitSprite.CELL_GROUND_PX` (7) is the cell's
  ground line, and it is not the cell's bottom edge** — it is where a cut-in centres its own contact
  ellipse. **The board's cast shadow and the buildings' drop shadow are both SOLID**, measured
  through the board's own sampling rather than argued, and the tone and the parity are the
  generator's alone: there is no shadow tone and no parity anywhere in `scenes/`, which is what
  keeps the figure sheet's subtraction exact.
  **The beat sheet is `CombatBeats` and it is Node-free** (2026-08-31):
  `scenes/battle/cutscene/combat_beats.gd`, a `RefCounted` whose
  `plan(result, atk_style, def_style, tail, rate)` is pure, is **the single statement of what
  windows exist and when** — nothing else under `scenes/battle/cutscene/` computes one, and
  `tests/unit/test_combat_beats.gd` is the first check the cut-in's timing has ever had without a
  scene. It added an **arrive** beat (0.20 → 0.34, opening where the wipe's own inward slide *ends*,
  since two opposed translations on one axis make the squad jerk) and a **per-weapon aim** beat
  whose *length* is `BattleStyle.aim_seconds`; `aim_lift` and `aim_pitch` are **two** signed scalars
  rather than one reinterpreted per domain. The recoil ramp ends as the barrel lights and runs back
  `max(0.4 × aim, 0.10)`, allowed to open inside the arrive. The **casualty** beat gates the
  counter (`settled = max(impact.y, casualty.y)`) and its tail is flat and capped at two steps —
  0 / +0.10 / +0.20 — so a single loss **does** cost 0.10 s and four figures buy only ~0.10 s more
  than one; multi-figure losses read *better*, not fully, and the lever if playtest disagrees is a
  third cap step, never the uncapped per-figure form.
  **The streak lever's shape is now recorded correctly**: `CutsceneDirector._process` advances the
  clock by `delta * speed`, so `cutscene.speed` is a **global rate over the whole sheet** and
  compresses the volley, the impact and the HP tick along with everything else — only `tail_scale`
  is selective, and it takes the closing hold and wipe. The claim that the lever spares the volley
  and the impact was false and is not to be re-recorded. The one beat defended is the wind-up:
  `CombatBeats.aim_stretch` multiplies it by `max(1, rate / AIM_RATE_CEILING)` (ceiling 1.5), so a
  style's *real* wind-up floors at `aim_seconds / 1.5`. `rate` is read **once** in
  `CombatCutscene._pose` before `run()` — a per-frame read would re-plan the sheet mid-run — and
  `FastForward` is deliberately out of it. Long form, with the budget table, the pose constants and
  the rejected mechanisms: `docs/design_record.md` § `battle-animations-plan.html`.
- `capture-animation-plan.html` — the capture cut-in CP1–CP3, the combat cut-in's structural
  sibling: same D1 (replays a snapshot), same gate (`capturing`, Instant, viewer visibility via
  `BattlePerspective`). `core/` gained only the `CaptureCommand.result` snapshot; the mash chips
  are a presentation split of `points_before − points_after`, never a call back into
  `capture_strength`; the property flip is a `SideIdentity.atlas_row` swap. Deliberately does not
  tier-scale (structural parity with the combat sibling). Faction tinting for its buildings and
  all art families has one authority — the generator's faction ramps, read from
  `CommanderVisuals` (see `assets/LICENSES.md` "Board sprites — generated").
- `range-preview-plan.html` — the range preview RP1–RP3, shipped. D1: **the fire ring is the
  single authority's geometry, never a second opinion** — `AttackRange.threat_cells` /
  `firing_cells` / `ring_cells` in `core/rules/` own "every cell a unit could bring under fire
  this turn", and `ai/threat_map.gd` is rebuilt on them (keeping only its dry/unarmed filter and
  per-enemy attribution), so the red overlay and the planner's fear are one computation. That one
  computation answers for two sets of eyes: `MovementResolver.reachable` takes a `sight_team`
  (default `MOVER_SIGHT`, threaded down through `firing_cells` / `threat_cells`) naming whose
  knowledge of **occupancy** fills it — the planner and every committed move keyed to the mover's
  own sight, a preview of **another side's** unit keyed to the **viewer's**, because a
  fill keyed to the mover is walled by the units that mover can see and planned through the ones it
  cannot, so a previewed silhouette alone would report which of the viewer's own pieces that unit
  has spotted (COM-57). Terrain, budget and doctrine stay the mover's throughout. So this slice
  does reach into `core/` and that parameter is the whole of it — a second, fog-redacted board for
  the fill to walk is still the rejected answer. Everything else is presentation, gated by the same
  `perspective.can_see_unit` fog rule targeting uses and then masked to scouted ground by
  `BattlePerspective._viewer_safe`; `make screenshot` stays byte-stable.
- **Field overlays** (no plan artifact; the *Field Overlays* design handoff, and this entry is its
  record) — the threat lens, the arrowed movement path and the capture pip. **Nothing under `core/`
  or `ai/` was touched, because the handoff's rules helpers already existed**: its `threat()` /
  `ring()` / `pathTo()` are `AttackRange.threat_cells` / `ring_cells` and
  `MovementResolver.Reach.path_to`, same indirect rule and all. So the whole slice is presentation,
  and its four decisions are:
  D1: **the lens is a union over the one per-unit authority, never a second walk** —
  `BattlePerspective.all_threat_overlay_cells` calls `threat_overlay_cells` once per hostile unit
  the viewer can see, so it inherits both the sight rule the fill is keyed to and the scouted-ground
  mask, and the range preview's D1 keeps holding without being restated. It repaints from
  `Battle.refresh_fog`, the pass that already reruns after every committed command and turn change,
  and costs nothing while the lens is down. It belongs to no unit and no selection: nothing clears
  it but the player, because a lens that switched itself off when a unit was picked up would be off
  exactly when the question it answers is being asked.
  D2: **the lens gets its own layer, striped** — `attack_layer` is already two things (R's fire ring
  *and* the pickable targets during `TARGETING`), so a lens sharing it would either erase a target
  list or be mistaken for one. `T` raises it; `R` still shows one unit's ring, indirect units
  included, which is why the handoff's separate min–max ring needed no code at all.
  **`R` answers from rest as well as from a unit in hand** (added after this entry): with nothing
  selected it reads the cell under the cursor **through `_enter_preview`**, so the ring costs one
  key rather than a confirm and then `R`, and every unit a click may only inspect — an enemy's, one
  of ours that has already acted — is one press away. Routing it through the preview rather than
  painting from IDLE is the whole of the decision: `R` then inherits the click's `can_see_unit`
  gate (it can no more probe fog than a click can), the ring cannot outlive its subject, and `ESC`
  keeps meaning what it meant. **The cursor names the subject in both rest states, not just IDLE**:
  from a preview `R` already put up, a cursor that has walked onto a *different* visible unit
  re-enters the preview on that one rather than toggling the last one's ring off — otherwise
  scanning a second unit costs `ESC` and then `R`, which is the two presses this whole entry exists
  to retire, and the ring outlives its subject exactly as the preview route promises it cannot. A
  cursor still on the same unit keeps the momentary-lens toggle, and a unit in hand
  (`UNIT_SELECTED`) is untouched: there the cursor is planning a move, not scanning, so `R` stays
  that unit's ring and a plain toggle. Because `R` now does the same thing in every board
  context, it is stated **once as a chip beside `T`'s** (`ControlHints.RANGE_CHIP`, lit while
  the ring is up) and is gone from the two legends that named it — `IDLE`'s was already at
  `MAX_CHARS` and could never have carried it. `Battle._range_shown` is setter-backed for that
  chip, the same shape as
  `Battle.state`'s: half a dozen sites clear the ring, and a chip only some of them told would
  advertise one that is not on the board. Nothing under `core/` moved; `scenes/battle/`'s
  `enemy_range_preview` smoke scenario is the gate, walking both units from rest.
  D3: **`scenes/battle/battle_overlays.gd` (`BattleOverlays`) owns the transient paint** — reach,
  fire, threat, route, capture chips — and `BattleView` keeps the board itself. The split is what
  the `max-public-methods` ratchet bought rather than a raise; ask `overlays` for anything laid
  *over* the board and `view` for the board.
  D4: **the two board marks are drawn, and every number in them was handed over.** `PathArrow`
  splits into a pure `segments(path)` (checked by `tests/unit/test_path_arrow.gd`, no scene) and a
  `_draw` that only paints what it returns; `CapturePips` is dumb like `UnitSprite` and never calls
  back into `capture_strength` — `BattleOverlays.show_capture_pips` puts `GameState.capture_progress`
  through the same fog gate the board uses and hands the result over (the gate sat in `Battle` until
  the objective marks paid for themselves by giving it to the class that owns the paint). Both wear
  outlined marks rather than filled panels: the
  handoff's ink chip is trim on its 44px tile and covers the building being captured on this
  board's 16. Every captured battle frame shifts, because the threat chip is permanent top-bar
  chrome and so is in all of them; the `capture` and new `field_overlays` frames additionally move
  on the board itself, the path no longer being a yellow polyline and capturing tiles now carrying
  a pip.
- **The zoom ladder is integers above its floor**, and the animation milestone's nine slices (no
  plan artifact; this entry is its record). **Long form: `docs/design_record.md` § The zoom ladder
  and the animation milestone** — the crawling-edge diagnosis, the playtest that overruled half of
  the first slice, every slice's measurements and moved-frame counts, and the rejected mechanisms.
  The board is sampled with nearest filtering, so a rung that is not a whole number of screen pixels
  per world pixel drops and doubles rows, and which rows it drops moves as the camera pans.
  **`BattleZoom` is the one statement of what rungs exist** — `rungs_for` is the ladder a board
  offers and `floor_for` its furthest-out rung, so `BoardCamera.min_zoom` asks rather than deriving
  a second answer; `set_zoom` settles on the nearest rung and a press steps one place, so nothing
  else can invent a level. **A playtest has since overruled half of that slice**:
  `window/stretch/scale_mode` is back off and the floor rung is the fit-whole one again, fractional,
  with every rung above it still whole — so a board the default rung fits inside is *fought* on
  whole rungs, and `boot_camp` and `quartet`, whose fit rung sits above the default, play on a
  fractional one. `tests/unit/test_texel_stability.gd` is the gate and states both weakenings and
  `scale_mode`'s absence in its own header, so re-forcing either is a decision rather than a drift.
  The remaining slices are all presentation and none touches `core/` or `ai/`.
  **The second slice parks the board on whole screen pixels**, four decisions: **A1** a continuous
  zoom is played on a rendered still, never on the camera (`scenes/battle/board_punch.gd`,
  `BoardPunch`, clipped to the band and best-effort; `camera.zoom` is now a rung and nothing else,
  and a `SubViewport` around the cut-in layer is the rejected mechanism); **A2** the board docks on
  a whole screen pixel (`MobileDock.board_lift_px()`, a lift of 12, the odd pixel to the bottom);
  **A3** the camera lands on the cell rather than gliding to it (no `position_smoothing`); **A4** an
  atlas cell is drawn on whole texels (`CaptureStage.FIGURE_PX` is `UnitSprite.SPRITE_W` and the
  draw origin is rounded — the mash squash is deliberately untouched, being drawn shapes rather than
  sampled texels).
  **The third slice is the board's ambient beat**, a two-frame flip over
  `assets/tiles/units_atlas_b.png` and nothing more: the beat is a **wall clock, not an
  accumulator**, **Instant is a still board and a capture is pinned**, and `UnitSprite.animates` is
  deleted so every sprite processes. `tests/unit/test_ambient_frames.gd` pins the sheets cell by
  cell on *drawn* pixels rather than bytes.
  **The fourth slice is the on-map muzzle flash** — `scenes/battle/muzzle_flash.gd` (`MuzzleFlash`),
  a dumb drawer in the `CapturePips` idiom posed by `BattleAnimator._flash_muzzle`, sized and tinted
  from the `BattleStyle` the result's own weapon slot names through `BattleStyleDB.shared()` so the
  cut-in and the board read one registry. **It obeys the cut-in's fog rule, both combatants
  visible**, and Instant draws nothing.
  **The fifth slice is the 64x96 unit cell** — `UnitSprite.SPRITE_H` is 96 with every vertical
  landmark measured up from the cell's **bottom** edge, so the extra rows are sky and an unraised
  unit is byte-identical. **The headroom is spent on MASS, not height** (`docs/density_128.md`), and
  **a square icon slot shows the tile, not the cell** (`UnitSprite.tile_texture_for`); each cut-in
  carries a `FIGURE_H` beside its `FIGURE_PX`, pinned by `tests/unit/test_texel_stability.gd`.
  **The sixth slice is the animation install, the board's new ambient baseline**:
  **`scenes/battle/board_beat.gd` (`BoardBeat`) is the one clock every looping sheet reads** — the
  cadences (`AMBIENT_MS` 500, `MOVE_MS` 160, `SEA_MS` 900, deliberately not multiples of one
  another), the frozen pin and the Instant rule, Node-free statics so a beat is checkable without a
  scene. **The constants stay hardcoded and `assets/tiles/anim.json` is *pinned*, never read at
  runtime**, `tests/unit/test_anim_manifest.gd` the one place it is consumed. **The legibility ruler
  reads a REGRESSION** against the previous art; nothing was tuned in response and answering it is
  the generator's, with `docs/sprite_legibility.md` carrying the re-read.
  **The seventh slice is the sea's swell**, and it costs one pointer:
  **`TerrainAutotiles.sheet_path(family, frame)` is the filename authority**, as it is for every
  other sheet, and frame 0 is what every surface has always read — the miniature and the legibility
  ruler are deliberately unedited, a time frame being another axis. **`scenes/battle/sea_beat.gd`
  (`SeaBeat`) is where the tick lands**, handed its source by `BattleView`, and the backdrop and the
  property ground swell by construction.
  **The eighth slice is the move clip**, played for exactly the length of
  `BattleAnimator.animate_path`'s tween. **It is a clip, not a second beat** —
  `UnitSprite._sheet_path(frame)` is the one answer to which sheet a sprite draws from, so no repaint
  mid-walk snaps a striding unit back to parked. **The clip's lifetime is the tween's, and since
  2026-08-29 its cadence is the tween's tier** — `BoardBeat.move_ms()` over
  `GameSpeed.clip_period_ms` restates `MOVE_MS` at the tier being played (160 ms at Normal, 107 at
  Quick); `MOVE_MS` itself stays the authored constant the manifest is held against, and the
  ambient beat and the sea's swell stay authored. **The sheets face screen-left and a rightward
  step mirrors them** — `UnitSprite.facing_for(delta, was)`
  is that policy, a purely vertical leg holds the previous facing, and facing is never set in
  `refresh()`. **The mirror is the CLIP'S and ends with it**, because the ambient pair's cast shadow
  is not cell-centred and a unit left mirrored at rest drops its shadow to the other side of itself.
  An unauthored unit needs no fallback code; `tests/unit/test_move_frames.gd` pins all of it.
  **The ninth slice is the cut-ins' idle beat** — `UnitSprite.figure_texture_for` grew a
  **defaulted** `frame` and stays the one way to ask for a figure, and
  **`BoardBeat.frame_at(period_ms, elapsed_ms)` is the arithmetic, read off the director's own `t`
  rather than the wall clock**, so a posed still and a skip both land on a fixed pose. The board's
  two stills stay `frame`'s and do not reach in.
  **Since 2026-08-29 the legibility ruler reads all six unit sheets**: a `frame` axis names a clip
  and a beat (`idle_a`/`idle_b`/`walk_a`/`walk_b`), the view says which file draws it — the board's
  own cells, the cut-in's shadow-subtracted pair — and every report row and `--dump` key carries it
  (`LegibilityArt.BOARD_SHEETS` / `CUTIN_SHEETS`, `docs/sprite_legibility.md`'s 2026-08-29
  re-read). The sea's swell frames stay out, a *time* frame still being another axis.
- **The next-ready-unit key** (no plan artifact; the long form is `docs/design_record.md` § The zoom
  ladder and the animation milestone, where the index carried it) — `N` walks the cursor to the next
  unit on the side in hand that has not acted, so the last one is never hunted across a 49×32 board.
  **`scenes/battle/ready_units.gd` (`ReadyUnits`) is the one authority for who can still act and for
  the order they are walked in** — `of()` is the list the End Turn guard prints and `after()` is the
  step through it, one reading order (`precedes`) stated once; Node-free statics, so the walk is
  checked without a scene (`tests/unit/test_ready_units.gd`). **It moves the cursor and nothing
  else**: selecting stays the player's confirm press, no command is issued, nothing under `core/`
  learns it happened, and a board with nothing ready gets the ordinary `ActionFeedback` refusal
  rather than a dead key. Live in `IDLE` and `PREVIEW` only — never with a unit in hand, never over
  a computer turn, a replay or the guard. The guard's Review button is the same call, so pressing it
  repeatedly walks the list. Stated as a chip beside `T`, `R` and `O` (`ControlHints.NEXT_CHIP`)
  with **no lit state**, a jump not being a way of looking at the board.
- `menu-revamp-plan.html` — main-menu and commander-select redress MN1–MN3, shipped. D1:
  **design-system tokens live in one code authority, `scenes/common/ui_theme.gd` (`UiTheme`),
  never a `.tres` Theme** — it re-exports colours that already have an authority (faction hues,
  cream/ink) so there is exactly one value per colour. `scenes/ui/ui_kit.gd` (`UiKit`) is its
  sibling and the split is what each answers: `UiTheme` owns the *recipe* — a colour, a size, a
  stylebox — and `UiKit` owns the *widget* built from it (the padded box, the micro-label, the
  divider, the action button, the segmented control, the toggle row, the identity chip), so a
  screen assembles rather than draws. Two files because the kit depends on `Tooltip` and because
  `UiTheme` sits at the repo's public-method ceiling; a widget a screen keeps its own copy of is
  the drift D1 exists to prevent, which `pad` had already done in three files. The cut-in's shared
  colour vocabulary is `scenes/battle/cutscene/cutscene_palette.gd` (`CutscenePalette`), declared
  once, after a `SLATE_800` there held a different value from `UiTheme.SLATE_800`; the board's three
  overlay washes are its sibling, `scenes/battle/overlay_palette.gd` (`OverlayPalette`) — a
  translucent wash over art is a different vocabulary from the shell's opaque chrome, so neither
  belongs on `UiTheme` and both are declared once where they are painted. **The picker's Random cell
  is a menu action, not a selection state** — it rolls on `pressed` (a map cell selects on *focus*
  for keyboard preview, so a roll on focus would re-roll on every arrow pass) through the pure
  static `MapPicker.random_index` and then calls the ordinary `select(index)`, so the request always
  names a concrete board and nothing outside the picker learns Random exists. Map thumbnails
  (`scenes/menu/map_thumbnail.gd`) draw from `TerrainAutotiles` × `SideIdentity.atlas_row` —
  a miniature can never be a second opinion, which is why an autotiled cell asks the board's own
  authority rather than reading `TerrainType.atlas_col` (a one-tile lake was a blue square in the
  picker and a coasted pond in the match). `TerrainAutotiles` owns the family sheets' paths and
  their contact-sheet cut, and every board read it takes is clamped to the rim — so it answers for
  a cell beyond the edge too, and `BattleView`'s out-of-bounds backdrop is autotiled by the same
  arithmetic as the board it continues. **A family is keyed by connection, by position, or by
  both, and `variant(map, cell)` is the ONLY place that knows which** — ask it, never `mask`, and
  `sheet_cells` is the matching statement of what a sheet holds, so the board, the backdrop, the
  miniature and the legibility harness cannot phase a cell differently. **Phase 0 of a
  phase-keyed family is that terrain's atlas column byte for byte**, which is what makes adopting
  a phase sheet additive: a surface that has not adopted it is unchanged. **`PHASE_COUNTS` is the
  one statement of which families are keyed by position and how many phases each holds**, so
  `variant`, `sheet_cells` and `atlas_coords` cannot disagree about which is which. Three families
  are keyed by position today — open water (generator `1216fd5`, adopted 2026-08-18), plains
  (`21175fc` at five phases, **eight since the animation install's `e16d261`**, the shipped maps
  being about 56% plains) and mountain (generator `8569ba4`, both adopted 2026-08-20) — because what
  a field of one tile repeats at is the tile, so the glints, the tufts or the peaks line up however
  they are spread inside it. The generator emits the
  phases and the game places them, `TerrainAutotiles.phase(cell, count)` hashing the cell so the
  lattice breaks deterministically and with no stored state; one hash serves every phase-keyed
  family, since a second would be a second opinion about the same lattice. A phase varies a
  ground's texture and never its value — plains is the reference ground most contrast pairs are
  read against — so `make legibility-check` is these families' gate and it reads every phase and
  reports the worst (`docs/sprite_legibility.md`'s two 2026-08-20 re-reads: no class, no cell
  moved either time). **Mountain's phases additionally may not move the horizon**: the ground line
  and the contact shadow are drawn at a fixed row in every phase, because a range whose peaks stood
  at different altitudes would read as a jumble rather than as a range — the generator owns that
  rule and pins it, and Bulwark's rampart (rows 16–18, four two-cell passes that are locked balance
  geometry) is the board it is read on.
  Variants may not be extra rows of the base terrain atlas: `BattleView._last_seen_owner` reads
  an atlas cell's y as the faction row.
  The shared `CommanderCard`'s deferred dress is that
  named follow-up, and it landed (COM-92/93): the card wears Pixelify for its name and rules copy
  and Silkscreen for its micro-labels and its cost, at `UiTheme` sizes and off `UiTheme.flat` —
  and because the card is also the in-battle info sheet, that one edit re-dressed commander
  select, the sheet and the gallery together, which is why it was one pass. What stays card-local
  is one size and one colour, each named and each with its reason on the constant: `_NAME_SIZE`,
  the card's headline, because the shell has no size between a button's and a banner's; and
  `_MICRO_INK`, faint ink on *cream*, where the shell's `INK_3` is mixed for slate. A page
  title, by contrast, *is* a shell token — `UiKit.page_title` off `UiTheme.SIZE_PAGE_TITLE`, built
  by every full-screen page rather than sized page by page. Fonts (Pixelify Sans, Silkscreen) are
  vendored, OFL, recorded in `assets/LICENSES.md`.
- `ux-recovery-plan.html` — first-contact and new-player registers U-01–U-26; the onboarding
  slice (COM-12), the rejected-confirm feedback (COM-13, `scenes/ui/action_feedback.gd`), the
  end-turn ready-unit guard (COM-14/U-10, `scenes/ui/end_turn_guard.gd`), the transition-input
  convention (COM-15/U-11) and the visible match setup (COM-19/U-15) are shipped. The setup slice's
  one durable fact: **`MapCatalog.TUTORIAL_MAP_PATH` is the single authority for which board leads**
  — `ordered()` pins it at item zero and the menu reads the same key for its Tutorial badge, so
  order and explanation cannot drift; everything else it added (the caption, the per-option help,
  Difficulty dimmed while no computer is seated — asked of the seat strip since FP5, not of a mode)
  is presentation, gated by the `menu_setup_context` capture. D3 is the transition-input convention
  and it has one authority:
  `scenes/common/transition_input.gd` (`TransitionInput`) answers "was that a press?" for every
  boundary — a banner is an awaited blocking beat any press skips, no interactive menu may sit
  under a banner or cut-in, and the victory lockup (`scenes/battle/battle_outcome.gd`) opens
  unfocused and eats input for `INPUT_GUARD_MS` so a buffered press cannot restart a match. D1:
  everything in it is presentation-only, and tutorial state is a device preference
  (`user://settings.cfg`, never the match request, never a save). D6: the tutorial
  owns no rule and observes rather than instruments — steps retire off existing `EventBus`
  signals, filtered to human sides so the computer cannot retire a hint; nothing in `core/` or
  `ai/` gained a hook. **The strip runs on the tutorial board and nowhere else** (COM-122,
  superseding the plan's "no tutorial map"): `MapCatalog.teaches` is the one answer to which board
  that is, and the gate covers *retirement* as well as visibility, so an ordinary match can never
  burn steps of a tutorial its player has not opened. `maps/boot_camp.txt` is shaped to the promise
  — turn one can reach a neutral property and afford a build, checked by `tests/unit/test_maps.gd`.
  A capture pins the hint set (`Settings.pin_hints`, from `Battle._ready`) so
  `make smoke` frames don't depend on play history; its sibling `Settings.pin` does the same for
  the speed tier and stands the end-turn check, menu motion, battle animations and volume back at
  their defaults, so no preference stored on the capturing machine reaches a frame. `--reset-hints`
  is the one `Settings` flag that deliberately writes. The key legend
  (`scenes/ui/control_hints.gd`) is printed by
  **`Battle.state`'s setter** via `Battle.STATE_CONTEXT` — never refreshed from the dozen sites
  that assign the state.
- **Standing terrain is interactive; the ground plane is where ambient variety lives** (no plan
  artifact; the "Borrowed Doctrine" art research handoff, and this entry is its record) — a design
  invariant to hold before the tall-buildings plan is written, not a change to any shipped surface.
  Anything drawn rising off the cell's ground plane (a property, an HQ, a factory) reads to a player
  as a thing to interact with, so nothing that merely decorates a cell may stand: decoration —
  phase-keyed texture variety, mountain scenery, future biome dressing — stays flat in the ground
  plane the way `TerrainAutotiles.variant`/`stands_in_cutin()` already draw it. The moment a
  decorative tree "stands" the height a property does, a player will try to capture it.
- `mobile-builds-plan.html` — the whole command table in two hands: MB1–MB9, **all shipped** (MB7 a
  no-op under `keep`). **Long form: `docs/design_record.md` § `mobile-builds-plan.html`** — every
  slice's measurements, the packaging facts, the refutations, the known hit-area limits and the
  device proofs still owed. The engine profile was already right, so all of it is presentation and
  packaging. D1: **nothing under `core/` or `ai/` learns a phone exists** — no `OS`, no
  `DisplayServer`, no feature tag, no touch class, and a mobile build and a desktop build trade save
  files. D5: **the gate is `MobileProfile` and the bar is `make smoke` byte-stable** — mobile chrome
  is never *constructed* on desktop. D8: touch targets grow their **hit** rectangles, never their
  drawn heights, because a drawn height feeds `UiTheme.HUD_BARS_H` and therefore every board's floor
  rung. D9: the planner is not a mobile task. **Landscape only** (user decision) and
  **`aspect="keep"`**; `window/stretch/scale_mode` stays **absent** on Android and iOS alike, both
  by measurement rather than by assumption. D7's mechanism is **refuted** — a feature-tagged autoload
  override does not clear an autoload on 4.7.1, the engine reading each `autoload/*` property raw, so
  unregistering the editor addon's runtime belongs to the addon that registers it. D4's safe-area
  half is a no-op under `keep`, which is why no `SafeArea` authority exists.
  The five authorities the plan left behind, to ask rather than re-derive: **`MobileProfile`** is the
  one answer to whether this build is played with a finger (the engine's `mobile` tag or the
  presentation-only `--mobile`, resolved once, and nothing under `core/` or `ai/` may ask it at
  all); **`TouchTarget.inflation` / `UiKit.touchable`** are the single statement of how far a hit
  rectangle grows, on the `UiTheme.TOUCH_MIN` (44) metric, claiming half of each gap to a neighbour
  and never past the canvas; **`MobileDock`** is the third docked bar, disabled rather than hidden,
  dispatching through `UiKit.action_chip` the same actions the keyboard dispatches and asking
  `BattleLegend` what a context permits — it also owns the docked chrome's geometry (`chrome_h()`,
  `board_lift_px()`, which retired `BattleView.BOARD_LIFT_PX`); **`TouchGestures` / `BoardPointer`**
  are the pure recogniser (fingers in, **whole cells and whole rungs** out, sensitivity per ladder
  via `gain_for`, `BattleZoom.settle_at` the one way onto a rung, a pan walking the cursor rather
  than the camera) and the one owner of both pointer doors, where the release confirms inside
  `TAP_SLOP_PX`; and **`TransitionInput.is_touch_press`** is the single answer to what a finger
  press is, with the touch branch live only while mouse emulation is off, since a tap arrives
  through both doors otherwise. `tools/run_mobile_soak.gd` (`make mobile-soak`) is an instrument out
  of `make verify` and `docs/mobile_soak.md` is its dated record, superseded wholesale by a later
  soak rather than edited.

## The autoloads

`project.godot` registers `_mcp_game_helper` beside the game's own singletons — the godot_ai editor
addon's runtime. It loads in every run today; keeping it out of export builds is an open decision,
recorded here so the extra autoload is never a surprise.

## The battle scene's seams — the long form

`CLAUDE.md`'s **Working in this repo** section states each of these in one or two lines. The full
shape lives here, where it loads with the files it governs.

- **`BattlePerspective` is the one adapter from the vision rules to viewer policy.**
  `scenes/battle/battle_perspective.gd` owns viewing team plus hot-seat blackout, firing geometry
  delegated to `AttackRange`, typed transport drop options, and how much of a unit's reach and fire
  ring an overlay may show (that rule is the range-preview plan's, above). `Battle`, `BattleView`,
  `BattleAnimator`, `BattleCommandPipeline`, `BattleTargeting`, `BattleHandoff` and
  `BattleScenarioDriver` ask it; none re-derives visibility or reaches through a sibling's private
  helper, and the runner drives AI turns through `Battle`'s own named entry points. The rule
  authority itself is `core/rules/vision.gd` — its rationale is in `docs/design_record.md`.
- **A live command applies once.** `scenes/battle/battle_command_pipeline.gd`
  (`BattleCommandPipeline`) is the only live-scene owner of command validation, application and
  result presentation; both `Battle` and `BattleAiRunner` enter through `Battle.execute_command`.
  It captures combat/join/drop references before apply, replays `AttackCommand.result` and
  `CaptureCommand.result`, gates AI movement through `BattlePerspective`, and reconciles sprites,
  properties, fog, the panel and the HUD. Its typed `BattleCommandReceipt` returns validation,
  turn, winner, watch and ambush facts. The callers still own selection/input transitions, AI
  planning and pacing, save policy, and victory presentation — do not move those into the
  pipeline. The headless `BalanceMatchEngine` stays separate.
- **Which match to play is a typed request, not an autoload's fields.**
  `scenes/common/match_request.gd` (`MatchRequest`) states one launch in full — board, which of its
  seats play (`seats`, empty = every one; `--seats=` is read before `--co=` because the commander
  list is positional over the seats that play), who plays them, how they group into sides, fog,
  tier, commanders, resume, seed, watch, day cap, raw side specs, the recording to watch — and is
  built by one of four adapters: `from_menu`, `from_match` (a rematch, derived from the *live*
  `GameState`, so a match resumed from a save replays its own board and commanders), `from_replay`
  (a recording, which states its own board, seating, grouping, commanders and fog in its opening
  envelope, so naming the file is the whole request) and `apply_cmdline`, layered over any of them
  on **every** battle boot, which is how a headless capture and a menu launch reach the same board
  by the same route. `BattleSetup.build(request, …)` reads no autoload, scans no command line and
  writes nothing back; it returns `null` with a pushed error when the board or the state cannot be
  built (`assert` is stripped from a release build), and `Battle` disables itself rather than
  dereferencing a null map. `MatchConfig` carries exactly one staged request, and `take()` clearing
  is load-bearing rather than tidy: it is what makes a resume that found no save on disk unable to
  latch into the next boot.
- **The command line is parsed in one place.** `scenes/common/cmd_args.gd` (`CmdArgs`) — `user()`
  is the only `OS.get_cmdline_user_args()` call outside `tools/`, and the six inline scans it
  replaced are why one flag was last-wins and another first-wins with nobody deciding either.
  `value()` is last-wins, `flag()` matches a bare switch, and `has()` exists because an *empty*
  flag is not an *absent* one — `--co=` clears the commanders the menu picked and `--seed=` pins
  seed 0 — so gate an override on `has`, never on a non-empty value. `autoload/settings.gd`
  deliberately keeps its own ordered walk (its `pin()` latches, so there the *first* `--speed=`
  lands and `--reset-hints` must see the flags before it); a comment there says so.
- **The battle cut-in replays; it never decides.** `BattleAnimator.animate_combat` is the one
  seam — its one live call site, `BattleCommandPipeline`, `await`s it, and it returns exactly once,
  full-screen cut-in or on-map hit. Inside `scenes/battle/cutscene/` everything is a pure function
  of one clock: skipping sets the clock to the end rather than cancelling tweens, which makes "any
  press, at any beat, lands on the right board" true by construction. That clock is literally one
  object — `cutscene_playback.gd` (`CutscenePlayback`), the shell both directors compose: it owns
  the clock, the letterbox, the camera's return to rest, the cue ledger and what counts as a skip
  press, so no cut-in gets a second opinion on any of them. A director owns only its beat sheet and
  what it paints in the band. Every number the cut-in shows was handed to it (the result's two HP
  snapshots, the units themselves); none is recomputed from the damage chart or the RNG. It is
  suppressed while `capturing` — so `make screenshot` stays byte-stable, posed cut-ins go through
  `pose_at` — and it only plays when the *viewer* can see both combatants, asked of
  `BattlePerspective` (and so of `Vision`), never re-derived.
- **A computer turn is held between commands, never inside one.** `Battle.pause_gate` is the one
  point `BattleAiRunner` stops at, so Esc during an AI turn is *requested* and honoured at the next
  boundary — where the board has settled and nothing of that turn's own is on screen, which is what
  keeps "no interactive menu sits under a banner or a cut-in" (ux-recovery D3) true here rather
  than by luck. The press still gets an answer of its own, so a pause never reads as a dead key.
  `Battle.rest_state()` is the single answer to where a closing menu, sheet or banner lands — the
  player's board, or the frozen board of a paused turn — because IDLE mid-computer-turn hands over
  a board nobody may play; ask it, never spell `State.IDLE` for "back to rest" again. The pause is
  presentation and nothing else: no rule, no command and nothing under `core/` or `ai/` learns it
  happened, the runner picks its turn up where it stopped, and the only thing the menu itself
  changes is `BattleMenus.map_actions(game, commandable)` dropping the two rows that would act for
  the side on turn. The wake-up is a signal rather than a flag the runner polls, so leaving the
  match from the pause menu takes the parked await with the scene instead of resuming into a board
  that is gone. It matters most in a watched match, where every turn is a computer's and there was
  otherwise no route to a menu — or out — at all; `ai_pause` in `BattleTransitionScenario` is the
  driven proof, and the claim it exists for is that a resumed turn really resumes.
