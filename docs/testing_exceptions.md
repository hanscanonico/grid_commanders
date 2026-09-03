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

One launch, stated in full without booting one: objects a suite can build itself and flags it can
hand them, so a match starts here the way the command line starts it.

| subject | suite | why it earns the exception |
|---|---|---|
| `MatchRequest`, `CmdArgs` (`scenes/common/`) | `test_match_request.gd` and the flag-grammar suites | the flag grammar every `make smoke` scenario and Balance Lab row is launched with |
| `MatchConfig`'s staging | `test_match_config.gd` | reachable without a scene, and where `take()` clearing is held |
| `CommanderPicks` (`scenes/common/`) | `test_commander_picks.gd` | the one rule that a general commands a single army, stated Node-free and database-free so the picker, the menu adapter and `--co=` all inherit it rather than each restating it |
| `BattleSetup` | `test_seats_flag.gd`, `test_sides_flag.gd`, `test_resume_setup.gd`, `test_launch_failure.gd` | takes a request and the databases, hands back plain simulation objects with no `Node` and no scene path |
| `Settings` | `test_audio_settings.gd`, `test_settings_pin.gd`, `test_end_turn_confirm.gd`, `test_menu_animations.gd`, `test_fullscreen_setting.gd` | `--speed=`, `--mute` and `--no-battle-anim` are launch flags this autoload owns, and `pin` is what a captured frame depends on; the volume ladder (`VOLUME_STEPS`, `volume_index`) is static and pure, and every preference case runs on a fresh `autoload/settings.gd` instance rather than the singleton, so nothing here writes `user://settings.cfg` |

## The autoloads a headless run already stands up

`Node` subclasses, so not Node-free — the singleton itself is the exception. The engine has each
one up for the whole run and reachable without a scene, and what a scene asks of it is what these
suites pin.

| subject | suite | why it earns the exception |
|---|---|---|
| `CampaignSession` | `tests/unit/test_campaign_session.gd` | its lifecycle — armed by `begin`, silent for every skirmish, emptied whole by `clear` — is what the suite pins |
| `CampaignSession.record`'s run facts | `tests/unit/test_campaign_run_facts.gd` | one seam: the nine `run:` facts it writes onto the profile after a win or a loss, dropped by `begin` and `clear` and never stored by the codec |
| `CampaignSession.previous_record`, `CampaignDebriefPanel.worth_line` / `standing_line` | `tests/unit/test_campaign_debrief_report.gd` | the same autoload's copy of a mission's record before the run that beat it, and the two static, pure lines the debrief prints off it — pinned without building the page |
| `CampaignSession.record_event`, `recorded_notes`, `save_battle` | `tests/unit/test_campaign_ledger.gd` | the consequence ledger's seam on the autoload: which facts a run commits, what the debrief reads back off them, and the mid-mission save that carries the whole envelope — a retried mission writing the war twice is the failure it exists for |
| `CampaignSession.deploy_army` | `tests/unit/test_campaign_roster.gd` | the carried army, walked across three missions of one chain — that a carry slot always ends up occupied by exactly one unit of the type the board authored |
| `CampaignSession.mission`, `due_events` | `tests/unit/test_campaign_soak.gd` | every shipped mission played with its script live, driving this autoload rather than reimplementing the boundary order, so which beats come due is the shipping answer and not the soak's own |
| `CampaignSession.tally` | `tests/unit/test_mission_tallies.gd` | the `MissionProgress` the hold and loss objectives are read from, which this session is the only writer of — including the re-baseline a resume has to make against the board it is handed |
| `Music` | `test_music.gd` | one looping track at a time, faded rather than cut, is all a scene asks of it in `_ready` and at victory |

## Pure answers over an input or a state

| subject | suite | why it earns the exception |
|---|---|---|
| `TransitionInput` | `test_transition_input.gd` | a pure static answer over an `InputEvent`, so the boundary convention every banner and the victory lockup obey is checked without a scene |
| `TransitionInput`'s two `dismissed_by_*` readings | `test_page_dismissal.gd` | they also stamp the receipt on the page's viewport, so each case runs under a `SubViewport` rather than by booting a scene |
| `DirectionalInput` | `test_directional_input.gd` | a pure answer over an `InputEvent` and the `InputMap`, so the one-step-per-gesture convention the board cursor and every menu obey is checked without a pad |
| `SeatStrip.normalised_sides`, `SeatStrip.reopened_seats` | `test_seat_strip.gd` | the grouping and seating arithmetic a shrinking roster runs through is static and pure, so it is checked without building the strip |
| `BattleZoom.floor_for` | `test_texel_stability.gd` | which rungs the zoom ladder offers is arithmetic over a viewport and a board, checked without a camera |
| `BoardBeat`, `TerrainAutotiles` (both `RefCounted`) | `test_board_beat.gd`, `test_ambient_frames.gd`, `test_move_frames.gd`, `test_anim_manifest.gd`, `test_terrain_autotiles.gd`, `test_terrain_autotiles_beat.gd`, `test_terrain_autotiles_mountain.gd`, `test_terrain_autotiles_water.gd` | a frame is a pure function of the clock and a sheet path a pure function of a family and that frame, both Node-free statics, so which variant a cell wears and which cadences may share a tick are checked with no board on screen — `test_board_beat.gd` is the one place every pair of cadences meets, `test_anim_manifest.gd` is the one place the generator's `assets/tiles/anim.json` is read at all, and the autotile files split only to stay under the public-method ceiling. The three frame suites pair a cadence with `UnitSprite`'s sheets, so they are listed on that row too |
| `BattleLegend` | `test_battle_legend.gd`, `test_end_turn_key.gd` | `context_for` and the four readings off it (`commands_board`, `dock_live`, `paused_in`, `steppable`) are static answers over the battle's own flags, so which contexts still command the board is checked without a HUD |
| `BattlePerspective.can_see_funds` / `can_see_holdings` | `test_battle_perspective_economy.gd` | the adapter is a `RefCounted` over a `GameState`, and neither reading takes a cell or a sprite: they are the only thing keeping the commander sheet's economy row off an enemy treasury and off a capture made inside the viewer's fog, and a captured frame cannot show a rule that was asked the wrong way round |
| `BattlePower.refusal_for` | `test_battle_power.gd` | a static read of a `GameState` and the computer's seats, so why the power row is refused says the same thing in a test as on the board |
| `PowerEffects` | `test_power_effects.gd` | `snapshot` and `marks` are a pure diff of two readings of one `GameState` into the marks the board floats, so what a power did is arithmetic rather than a captured frame |
| `BattlePerspective` | `test_battle_perspective.gd` | a `RefCounted` with no `Node` in it — the scene layer's single adapter from `Vision` and `AttackRange` to viewer policy, so the blackout, the replay's omniscience, the scouted-ground mask, the dive and the refused Fire row are pinned without a board on screen. The two a captured frame cannot show are why it earns a suite at all: that omniscience never writes `fog_enabled` back onto the state, and that `drop_options` deliberately KEEPS a cell whose only occupant is hidden rather than disclosing the ambush by the shape of the offer |
| `ReadyUnits` | `test_ready_units.gd` | `of` and `after` are static reads of a `GameState` — the reading order the `N` key walks, pinned without a cursor |
| `TouchGestures` | `test_touch_gestures.gd` | `gain_for`, `rung_step` and `cells_in` are static, and the recogniser itself is a `RefCounted` fed synthetic events, so the pinch ladder and the tap slop are checked without a touchscreen |
| `FastForward`, `CutscenePlayback` | `test_fast_forward.gd` | `held` / `rate` is a static read of the `InputMap` and the clock's `advance` is arithmetic over its own fields, so the whole held-key rate path is checked without a cut-in |
| `MobileProfile.touch` | `test_mobile_profile.gd` | pure over the arguments handed in and the engine's feature tag, like `CmdArgs`, so the gate the touch chrome is built behind is checked without an exported package |

## Content registries and resolved identity

| subject | suite | why it earns the exception |
|---|---|---|
| `BattleMenus` | `test_unit_pricing.gd`, `test_battle_menus_auto.gd`, `test_battle_menus_objectives.gd`, `test_battle_menus_fire.gd` | which rows a menu offers is content, gated by the same command authorities the rows would run, not scene plumbing — so the suite reads a build row's price and disabled state straight off it, `map_actions` is read the same way for the Auto and Objectives rows a recording drops, and `test_battle_menus_fire.gd` holds the refused Fire row to naming its reason instead of disappearing |
| `BattleCampaign.objective_cells` / `briefing_lines` | `test_objective_marks.gd`, `test_battle_menus_briefing.gd` | static, pure reads over `CampaignSession` and a `GameState` with no `Node` in them, so which objectives put a mark on the board and which lines the Briefing row re-says are pinned without staging a battle |
| `GameSpeed` | `test_game_speed.gd` | the speed table itself — `ordered`, `by_id`, `has_id`, `default_speed` and the base durations every pacing read scales — which is the exception the copy registries below are held to |
| `TutorialHints`, `ControlHints` | `test_tutorial_copy.gd`, `test_control_hints.gd`, `test_touch_copy.gd`, `test_battle_legend.gd`, `test_end_turn_key.gd` | Node-free copy registries for the same reason `GameSpeed` is: which mission step is next and which key legend a context prints are pure functions of state the suite can hand them. `test_tutorial_copy.gd` and `test_control_hints.gd` take one subject each and hold it to its character caps; `test_touch_copy.gd` holds the touch build's second legend table (`chip_for`, `TOUCH_LEGENDS`) to those same caps, `test_battle_legend.gd` the dock's own words (`dock_back_for`, `DOCK_CHIPS`) to a narrower one, and `test_end_turn_key.gd` the `END_TURN_CHIP` that leads with its key and is deliberately not in `CHIPS` |
| `UiTheme`, `DisabledPalette` | `test_ui_theme_box.gd`, `test_ui_theme_font.gd`, `test_disabled_palette.gd` | fonts, style boxes and the drained palette come back from static calls as `Resource`s and `Color`s, so the metrics a layout depends on and the contrast a greyed row keeps are read without building a `Control` |
| `CommanderVisuals`, `SideIdentity` | `test_side_identity.gd`, `test_side_identity_roster.gd`, `test_side_identity_colorblind.gd`, `test_commander_face.gd`, `test_commander_portraits.gd` | the single authority for a side's presentation — a portrait, a faction theme, an atlas row, resolved once from the match's commander picks with no `Node` and no scene path. `test_commander_face.gd` and `test_commander_portraits.gd` read `face_for` and `portrait_for` on the same terms — a region over a baked bust, whose *measurement* (that the crop clears every jaw) is held per bust by `generators/portraits/tests/test_face_region.py` instead — and `test_side_identity_colorblind.gd` measures the same five `theme_for` hues once red and green have collapsed onto one axis |
| `BattleStyle` (a `Resource`) and `BattleStyleDB` (`RefCounted`) | `test_battle_styles.gd` | weapon-signature data rather than drawing, so every unit naming a style that exists is checked without staging a cut-in |
| `CombatBeats` (`RefCounted`) | `test_combat_beats.gd`, `test_combat_beats_lost.gd` | the battle cut-in's beat sheet on the same terms: `plan` is a pure function of a `CombatResult`, two `BattleStyle`s and two floats, with no `Node` and no clock in it, so this is timing arithmetic rather than drawing. It was a private static inside a `CanvasLayer` and nothing had ever checked it; the budgets are pinned at `rate = 1.0` because the aim stretch grows the sheet clock at high rates on purpose. `test_combat_beats_lost.gd` is the same subject in a second file — the `def_lost` / `atk_lost` seam fields only — because the animation-frames plan pins that suite's existing budget and pose assertions as untouched — a slice may add to the file (S5's `fire_window` shape tests), never move a pin |

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
dozen baselines for nothing, and that is a check no captured frame makes. `terrain_note` is in the
same file on the same terms — whether the defence row qualifies the stars it printed is a pure
answer over two ints, and a plate promising a flier the ground's cover renders a frame that looks
perfectly correct.

`CampaignHubPanel` and `CampaignPickerPanel` join them too. What a hub row's second line says
(`row_detail`), how wide the star cell every row shares has to be (`star_span`), what a picker row
reads (`row_text`) and how many lines of premise a card has room for (`premise_lines`) are static,
pure answers over a campaign and its progress, so `test_campaign_hub_rows.gd`,
`test_campaign_card_copy.gd`, `test_campaign_db.gd` and `test_campaign_route.gd` call them and build
no page. `CampaignRouteMap` is the same shape over the hub's rows: which state every node on the
route is in (`plot`) and what the standing at its right says (`standing`) are static reads of a
campaign and its `CampaignState`, so `test_campaign_route_map.gd` calls them and draws nothing —
which is also where the map is held to `offered_count` rather than the authored list.

`EditorBoard`, `EditorPalette` and `EditorSidebar` join them on exactly those terms
(COM-263). Which cell a press lands on, where a board too big for its frame is scrolled to,
where a starting unit's art lands on its cell, which order the brushes come in and which board
sizes the steppers offer are all static, pure answers over a `MapDocument`, a rect and the
`TerrainDB` — so `test_map_editor.gd` calls
them directly and builds no editor. The page itself is verified by painting on it.

The HUD, the menus and the touch chrome join them wherever the answer is arithmetic — a `Node`
subclass whose suite calls only its statics:

| subject | suite | the statics it calls |
|---|---|---|
| `MuzzleFlash` (`Node2D`) | `test_muzzle_flash.gd` | `reach_for`, `arms`, `core_mark` — the rects the flash's `_draw` paints |
| `UnitSprite` (`Sprite2D`) | `test_figure_sheet.gd`, `test_ambient_frames.gd`, `test_move_frames.gd`, `test_anim_manifest.gd` | `texture_for`, `figure_texture_for`, `facing_for`, and the `UNITS_ATLAS_*` sheet paths against the cell metrics (`SPRITE_W`, `SPRITE_H`, `SPRITE_OVERFLOW`, `CELL_GROUND_PX`) — atlas regions and file names, so a sheet regenerated on one side of a clip is caught without a sprite |
| `MapPicker` (`VBoxContainer`) | `test_map_picker.gd` | `cell_name`, `caption_text`, `armies_label`, `fullest`, `is_custom`, `random_index` — the picker's words, all pure over a `MapData` |
| `ActionMenu` (`PanelContainer`) | `test_action_menu_icon.gd`, `test_action_menu_window.gd` | `icon_cap`, and `visible_window` / `rows_that_fit` — the scrolling window a build menu becomes in the band a touch build leaves it |
| `MissionObjectivesPanel` (`PanelContainer`) | `test_objective_card_dock.gd` | `dock_for` — which corner the objectives card parks in, geometry and nothing else |
| `MobileDock` (`PanelContainer`) | `test_mobile_dock.gd` | `chrome_h`, `height`, `board_lift_px` — the mobile plan's D5, that a desktop build's pixels do not move, stated as arithmetic |
| `TouchTarget` (`Control`) | `test_touch_target.gd` | `inflation` — how far a control drawn smaller than a finger may grow, and where two neighbours have to stop |

`test_touch_press.gd` is the one suite in this file that does build controls, and deliberately:
it pushes a real press through a `CanvasLayer` of its own onto `UiKit.touchable`, `UiKit.segment`
and `UiKit.toggle` widgets under a pinned `MobileProfile`, because the failure it exists for is a
*wiring* failure no pure call can see — a hit area that flips `button_pressed` and stops there is
silent to every control that reads `pressed`, and a segmented control reads `pressed`. Same terms
as `test_page_dismissal.gd`: its own viewport rather than a booted scene.
