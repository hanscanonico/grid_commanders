# Sheet census — 2026-09-03

What the art installed under `assets/tiles/` costs, and how much of it is the same cell twice.
A reading of one run of `make sheet-census`
(`generators/sprites/tests/sheet_census.py`), not a gate: nothing here is enforced, and no
relayout is proposed. Re-run the instrument and this page reproduces to the byte.

## The sheets

`dup` is cells that are byte-for-byte copies of an earlier cell in the same sheet; `RGBA` is what
the sheet decodes to at 4 bytes a pixel, before whatever the engine does with it in VRAM.

| sheet | PNG | RGBA | cells | dup | dup% | loaded |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| `overlay.png` | 0.1 KiB | 1.0 KiB | 1 | 0 | 0% | yes |
| `terrain_atlas.png` | 81.0 KiB | 1344.0 KiB | 84 | 45 | 54% | yes |
| `units_atlas.png` | 79.9 KiB | 2592.0 KiB | 108 | 0 | 0% | yes |
| `units_atlas_b.png` | 80.9 KiB | 2592.0 KiB | 108 | 0 | 0% | yes |
| `units_atlas_figures.png` | 76.8 KiB | 2592.0 KiB | 108 | 0 | 0% | yes |
| `units_atlas_figures_b.png` | 77.8 KiB | 2592.0 KiB | 108 | 0 | 0% | yes |
| `units_atlas_figures_fire.png` | 78.5 KiB | 2592.0 KiB | 108 | 0 | 0% | yes |
| `units_atlas_figures_fire_b.png` | 80.1 KiB | 2592.0 KiB | 108 | 0 | 0% | yes |
| `units_atlas_figures_ko.png` | 87.2 KiB | 2592.0 KiB | 108 | 0 | 0% | yes |
| `units_atlas_move.png` | 83.1 KiB | 2592.0 KiB | 108 | 0 | 0% | yes |
| `units_atlas_move_b.png` | 86.1 KiB | 2592.0 KiB | 108 | 0 | 0% | yes |
| `units_atlas_move_c.png` | 83.3 KiB | 2592.0 KiB | 108 | 0 | 0% | yes |
| `units_atlas_move_d.png` | 86.5 KiB | 2592.0 KiB | 108 | 0 | 0% | yes |
| `autotiles/bridges.png` | 1.5 KiB | 35.6 KiB | 2 | 0 | 0% | yes |
| `autotiles/coast.png` | 5.9 KiB | 276.4 KiB | 16 | 0 | 0% | yes |
| `autotiles/mountain.png` | 3.7 KiB | 53.1 KiB | 3 | 0 | 0% | yes |
| `autotiles/plains.png` | 4.6 KiB | 140.8 KiB | 8 | 0 | 0% | yes |
| `autotiles/rivers.png` | 6.1 KiB | 276.4 KiB | 16 | 0 | 0% | yes |
| `autotiles/rivers_b.png` | 6.1 KiB | 276.4 KiB | 16 | 0 | 0% | yes |
| `autotiles/roads.png` | 5.0 KiB | 276.4 KiB | 16 | 1 | 6% | yes |
| `autotiles/sea.png` | 1.3 KiB | 53.1 KiB | 3 | 0 | 0% | yes |
| `autotiles/sea_b.png` | 1.3 KiB | 53.1 KiB | 3 | 0 | 0% | yes |
| `autotiles/shoals.png` | 5.4 KiB | 276.4 KiB | 16 | 1 | 6% | yes |
| `autotiles/shoals_b.png` | 5.5 KiB | 276.4 KiB | 16 | 1 | 6% | yes |
| `autotiles/woods.png` | 16.9 KiB | 276.4 KiB | 16 | 0 | 0% | yes |

**Totals: 1,044.7 KiB of PNG, 32,127.5 KiB of decoded RGBA, over 25 sheets — every one of which
the battle scene loads.** S9's two new frame-B sheets are the whole of the growth since the last
reading: `autotiles/rivers_b.png` and `autotiles/shoals_b.png`, the sea's own idiom (a second frame,
only the moving tone changed) extended to the other two water families — 552.8 KiB of decoded RGBA,
the cost of a beat rather than a new tile. The instrument reads that last column off the game rather
than off a list:
it scans `scenes/` for `res://assets/tiles/*.png`, and finds `scenes/battle/unit_sprite.gd` naming
the eleven unit sheets, `scenes/battle/terrain_autotiles.gd` the twelve autotile sheets,
`scenes/battle/battle_view.gd` (and `scenes/menu/map_thumbnail.gd`) the terrain atlas, and
`scenes/battle/battle_overlays.gd` the overlay. How each sheet is cut comes from the contract
shipped beside the art, `assets/tiles/anim.json`: it names the unit sheets and their 64×96 cell,
and the row list is where the faction row count comes from — everything else is cut on the board's
own 64px tile. **48 of the loaded cells are duplicates, 768.0 KiB of the decoded total** — one more
than the last reading, `shoals_b.png` carrying the same single self-duplicate cell `shoals.png`
does (see below), `rivers_b.png` none.

## The terrain atlas, column by column

`generators/sprites/spritegen/atlas.py`'s `build_terrain_atlas` pastes one tile down all six
faction rows (neutral plus the five armies) for a terrain that is not a property, so nine of
fourteen columns are six copies of row 0:

| col | terrain | rows identical to row 0 |
| ---: | --- | ---: |
| 0 | road | 5/5 |
| 1 | plains | 5/5 |
| 2 | woods | 5/5 |
| 3 | mountain | 5/5 |
| 4 | river | 5/5 |
| 5 | city | 0/5 |
| 6 | base | 0/5 |
| 7 | hq | 0/5 |
| 8 | sea | 5/5 |
| 9 | airport | 0/5 |
| 10 | port | 0/5 |
| 11 | shoal | 5/5 |
| 12 | bridge | 5/5 |
| 13 | reef | 5/5 |

## The reading

The duplication is real and it is small. The terrain atlas is 54% redundant — 45 of its 84 cells,
720 KiB of decoded RGBA — but the terrain atlas is only 1.3 MiB of a 30.8 MiB runtime set, and the
five property columns that genuinely differ per faction are why the six-row shape exists at all.
The cost that dominates is the eleven 1152×576 unit sheets: **27.8 MiB, 90% of the decoded total**,
and every byte of the duplication *between* sheets sits in a clip — the move clip and the two
authored cut-in clips — 204 cells and 4,896 KiB decoded. The move clip is over half of that on
its own: the nine families with nothing new to say between the walk's two halves repeat MOVE_A
and MOVE_B on MOVE_C and MOVE_D (`generators/sprites/tests/test_clips.py`, `GaitPhases.REUSED`),
so 54 of `units_atlas_move_c.png`'s cells are `units_atlas_move.png`'s and 54 of
`units_atlas_move_d.png`'s are `units_atlas_move_b.png`'s — 2,592 KiB, the price of one uniform
four-sheet clip rather than a per-unit frame count the scene layer would have to carry. 24 of
`units_atlas_figures_ko.png`'s 108 cells are the four air columns (9–12) on all six rows,
byte-identical to the same cells of `units_atlas_figures.png`. The fire pair adds 18 apiece — the
three unarmed columns (`apc` 8, `t_copter` 12, `lander` 17),
`units_atlas_figures_fire.png` matching the idle sheet and `units_atlas_figures_fire_b.png` the
idle sheet's frame B, per frame rather than per sheet. And 36 are shared between the two fire
sheets themselves: the six LAND units that fire a single shot (`mech`, `tank`, `md_tank`,
`artillery`, `rockets`, `missiles`) draw one model into both frames, and having no bob to ride
they land on the same pixels too — `bomber`, `battleship` and `sub` draw the same model and are
still not duplicates, their frame-B cell sitting `BOB_PX` higher. All of it is deliberate and it
is what a valid grid costs: air authors no wreck in v1 and a transport no muzzle, so
`units.build_model` fills those columns with the idle key of the same frame rather than leaving
holes in an 18-column sheet. Nothing draws the KO fallback — `CutsceneSide.bind` leaves that cut
null for a flying unit — while the fire fallback IS drawn and is exactly the point: an unarmed
attacker's window opens onto its own idle pair. The table above cannot see any of this, because
`dup` counts only cells repeated inside **one** sheet, which is why those rows read 0. Squeezing
every repeated cell out of every sheet would return 768 KiB within sheets plus those 4,896 across
them, about 18% of what the game holds — so the case for a relayout is a tidiness case, not a
memory one, and it is paid for in `BattleView`'s region maths, which reads a terrain's cell as
(column, faction row). Three small oddities the instrument turned up and this page does not
explain: `autotiles/roads.png` cell 10, `autotiles/shoals.png` cell 4 and (S9)
`autotiles/shoals_b.png` cell 4 are byte-identical to cell 0 of their own sheets — `shoal_tile`'s
own fallback (mask 0 draws as mask `S`, a beach with no water on it reading as a dry run of sand
rather than nothing) is why cell 4 already matched cell 0 before S9, and a frame that moves the
foam and nothing else inherits the match in both frames rather than only one.

## What a plan would weigh

1. **Dedupe the terrain atlas columns.** Give a non-property terrain one row instead of six and
   the atlas becomes 896×64 plus a six-row property block, saving 720 KiB of decoded RGBA. It
   costs a new region rule in `scenes/battle/battle_view.gd` and `scenes/menu/map_thumbnail.gd`
   ("faction row only if the terrain is a property"), a matching change in `build_terrain_atlas`,
   and a re-render of every shipped sheet.
2. **Keep the six-row contract.** One rule — cell = (terrain column, faction row) — with no
   special case anywhere, for 720 KiB of a 30.8 MiB set. A terrain that later wants faction
   colour (a fortified woods, a paved road) already has a row waiting, and a sixth army would add
   its row here without a second layout to teach.

Nothing here is implemented. Re-run with `make sheet-census`; it takes under a second and reads
only the installed art.
