# Testing exceptions — what may be unit-tested outside `core/` and `ai/`

`CLAUDE.md`'s **Testing** section states the rule: GUT tests target the Node-free layers, and
presentation is verified by playing the scene. This file is the full list of what else the suite
is allowed to test and why each one earns it. **Add to this list only when the subject is genuinely
Node-free (or a static, pure function on a Node type) — never to make a scene testable.**

## The Node-free layers themselves

`core/`, `ai/`, the offline balance harness in `tools/balance/`, the arena's grammar, scorer and
pools in `tools/arena/`, the replay analyser in `tools/replay/`, the composite legibility
metric in `tools/legibility/`, and the dialogue scorer in `tools/prose/` — all Node-free for
exactly this reason. That's where the rules live and where bugs hurt.

`ProseMetrics` and `ProseReport` are arithmetic over strings, and their suites are built from
crafted fixtures rather than shipped dialogue: `make prose` is a measurement, so a suite pinned to
authored lines would fail on a dialogue pass instead of on a bug. `docs/prose_slop.md` holds the
measured numbers.

`LegibilityMetric` is the arithmetic only. The render sweep it reports in is an offline instrument
like the Balance Lab and stays out of `make verify`; `LegibilityBaseline` is the committed verdict
digest that sweep is diffed against, and only a PASS turning FAIL is a failure.

## The launch layer

Deliberately made Node-free and argument-taking so it could be tested at all.

| subject | suite | why it earns the exception |
|---|---|---|
| `MatchRequest`, `CmdArgs` (`scenes/common/`) | `test_match_request.gd` and the flag-grammar suites | the flag grammar every `make smoke` scenario and Balance Lab row is launched with |
| `MatchConfig`'s staging | `test_match_config.gd` | reachable without a scene, and where `take()` clearing is held |
| `CommanderPicks` (`scenes/common/`) | `test_commander_picks.gd` | the one rule that a general commands a single army, stated Node-free and database-free so the picker, the menu adapter and `--co=` all inherit it rather than each restating it |
| `BattleSetup` | `test_seats_flag.gd`, `test_sides_flag.gd`, `test_resume_setup.gd` | takes a request and the databases, hands back plain simulation objects with no `Node` and no scene path |
| `CampaignSession` | `tests/unit/test_campaign_session.gd` | the autoload is up for the whole headless run and reachable without a scene; its lifecycle — armed by `begin`, silent for every skirmish, emptied whole by `clear` — is what the suite pins |
| `CampaignSession.record`'s run facts | `tests/unit/test_campaign_run_facts.gd` | the same autoload, one seam: the nine `run:` facts it writes onto the profile after a win or a loss, dropped by `begin` and `clear` and never stored by the codec |

## Pure answers over an input or a state

| subject | suite | why it earns the exception |
|---|---|---|
| `TransitionInput` | `test_transition_input.gd` | a pure static answer over an `InputEvent`, so the boundary convention every banner and the victory lockup obey is checked without a scene |
| `TransitionInput`'s two `dismissed_by_*` readings | `test_page_dismissal.gd` | they also stamp the receipt on the page's viewport, so each case runs under a `SubViewport` rather than by booting a scene |
| `DirectionalInput` | `test_directional_input.gd` | a pure answer over an `InputEvent` and the `InputMap`, so the one-step-per-gesture convention the board cursor and every menu obey is checked without a pad |
| `SeatStrip.normalised_sides`, `SeatStrip.reopened_seats` | `test_seat_strip.gd` | the grouping and seating arithmetic a shrinking roster runs through is static and pure, so it is checked without building the strip |
| `BattleZoom.floor_for` | `test_texel_stability.gd` | which rungs the zoom ladder offers is arithmetic over a viewport and a board, checked without a camera |

## Content registries and resolved identity

| subject | suite | why it earns the exception |
|---|---|---|
| `BattleMenus` | `test_unit_pricing.gd` | which rows a menu offers is content, gated by the same command authorities the rows would run, not scene plumbing — so the suite reads a build row's price and disabled state straight off it |
| `BattleCampaign.objective_cells` | `test_objective_marks.gd` | a static, pure read over `CampaignSession` and a `GameState` with no `Node` in it, so which objectives put a mark on the board is pinned without staging a battle |
| `TutorialHints`, `ControlHints` | `test_tutorial_copy.gd`, `test_control_hints.gd` | Node-free copy registries for the same reason `GameSpeed` is: which mission step is next and which key legend a context prints are pure functions of state the suite can hand them. One suite each — the two are two subjects — and each holds its subject to its character caps |
| `CommanderVisuals`, `SideIdentity` | `test_side_identity.gd`, `test_side_identity_roster.gd` | the single authority for a side's presentation — a portrait, a faction theme, an atlas row, resolved once from the match's commander picks with no `Node` and no scene path |
| `BattleStyle` (a `Resource`) and `BattleStyleDB` (`RefCounted`) | `test_battle_styles.gd` | weapon-signature data rather than drawing, so every unit naming a style that exists is checked without staging a cut-in |
| `CombatBeats` (`RefCounted`) | `test_combat_beats.gd`, `test_combat_beats_lost.gd` | the battle cut-in's beat sheet on the same terms: `plan` is a pure function of a `CombatResult`, two `BattleStyle`s and two floats, with no `Node` and no clock in it, so this is timing arithmetic rather than drawing. It was a private static inside a `CanvasLayer` and nothing had ever checked it; the budgets are pinned at `rate = 1.0` because the aim stretch grows the sheet clock at high rates on purpose. `test_combat_beats_lost.gd` is the same subject in a second file — the `def_lost` / `atk_lost` seam fields only — because the animation-frames plan pins the timing suite as untouched |

## The ones that are not Node-free — but whose suites never build one

`PathArrow` extends `Node2D` and `MapThumbnail` extends `Control`. Neither suite builds one:
`PathArrow.segments()` and `MapThumbnail.sheet_path()` / `sheet_region()` — the pure functions the
`_draw` of each only paints — are static, and are all `test_path_arrow.gd` and
`test_map_thumbnail.gd` call. Same shape as `SeatStrip.normalised_sides` and `TransitionInput`.

`CaptureBackdrop` joins them: `light_shaft_wedge` is the static quad the capture cut-in's field
light is drawn from, so `test_capture_backdrop.gd` triangulates it directly and stages no cut-in.
A polygon's defect is in its winding — a self-crossing quad is refused by the triangulator and
simply does not draw — which is exactly what a captured frame cannot show.

`CutsceneSide` joins them on the same terms. The combat cut-in's squad motion — where a figure
sits while it rolls into its firing slot (`arrive_offset` / `march_progress`), how far its weapon
lifts and tips over the wind-up (`aim_offset` / `aim_tilt`), the scuff polygon and how a casualty's
own run splits into a knock-back and a fall (`topple_fall` / `topple_jerk`) — is static arithmetic
on the pose scalars `CombatCutscene` writes, so `test_cutscene_side_motion.gd` calls them and stages
no cut-in. The load-bearing one is `arrive_offset` returning **exactly** `Vector2.ZERO` for a posted
squad: every posed frame sits after the arrive beat closes, so an eighth of a pixel there moves a
dozen baselines for nothing, and that is a check no captured frame makes.

`CampaignHubPanel` and `CampaignPickerPanel` join them too. What a hub row's second line says
(`row_detail`), how wide the star cell every row shares has to be (`star_span`), what a picker row
reads (`row_text`) and how many lines of premise a card has room for (`premise_lines`) are static,
pure answers over a campaign and its progress, so `test_campaign_hub_rows.gd`,
`test_campaign_card_copy.gd`, `test_campaign_db.gd` and `test_campaign_route.gd` call them and build
no page.

`EditorBoard`, `EditorPalette` and `EditorSidebar` join them on exactly those terms
(COM-263). Which cell a press lands on, where a board too big for its frame is scrolled to,
where a starting unit's art lands on its cell, which order the brushes come in and which board
sizes the steppers offer are all static, pure answers over a `MapDocument`, a rect and the
`TerrainDB` — so `test_map_editor.gd` calls
them directly and builds no editor. The page itself is verified by painting on it.
