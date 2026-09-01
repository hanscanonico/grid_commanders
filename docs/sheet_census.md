# Sheet census — 2026-09-01

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
| `units_atlas.png` | 80.9 KiB | 2592.0 KiB | 108 | 0 | 0% | yes |
| `units_atlas_b.png` | 82.2 KiB | 2592.0 KiB | 108 | 0 | 0% | yes |
| `units_atlas_figures.png` | 77.7 KiB | 2592.0 KiB | 108 | 0 | 0% | yes |
| `units_atlas_figures_b.png` | 79.0 KiB | 2592.0 KiB | 108 | 0 | 0% | yes |
| `units_atlas_move.png` | 81.5 KiB | 2592.0 KiB | 108 | 0 | 0% | yes |
| `units_atlas_move_b.png` | 86.0 KiB | 2592.0 KiB | 108 | 0 | 0% | yes |
| `autotiles/bridges.png` | 1.5 KiB | 35.6 KiB | 2 | 0 | 0% | yes |
| `autotiles/coast.png` | 5.9 KiB | 276.4 KiB | 16 | 0 | 0% | yes |
| `autotiles/mountain.png` | 3.6 KiB | 53.1 KiB | 3 | 0 | 0% | yes |
| `autotiles/plains.png` | 4.6 KiB | 140.8 KiB | 8 | 0 | 0% | yes |
| `autotiles/rivers.png` | 6.1 KiB | 276.4 KiB | 16 | 0 | 0% | yes |
| `autotiles/roads.png` | 5.0 KiB | 276.4 KiB | 16 | 1 | 6% | yes |
| `autotiles/sea.png` | 1.3 KiB | 53.1 KiB | 3 | 0 | 0% | yes |
| `autotiles/sea_b.png` | 1.3 KiB | 53.1 KiB | 3 | 0 | 0% | yes |
| `autotiles/shoals.png` | 5.4 KiB | 276.4 KiB | 16 | 1 | 6% | yes |
| `autotiles/woods.png` | 16.9 KiB | 276.4 KiB | 16 | 0 | 0% | yes |

**Totals: 619.9 KiB of PNG, 18,614.7 KiB of decoded RGBA, over 18 sheets — every one of which the
battle scene loads.** The instrument reads that last column off the game rather than off a list:
it scans `scenes/` for `res://assets/tiles/*.png`, and finds `scenes/battle/unit_sprite.gd` naming
the six unit sheets, `scenes/battle/terrain_autotiles.gd` the ten autotile sheets,
`scenes/battle/battle_view.gd` (and `scenes/menu/map_thumbnail.gd`) the terrain atlas, and
`scenes/battle/battle_overlays.gd` the overlay. How each sheet is cut comes from the contract
shipped beside the art, `assets/tiles/anim.json`: it names the unit sheets and their 64×96 cell,
and the row list is where the faction row count comes from — everything else is cut on the board's
own 64px tile. **47 of the loaded cells are duplicates, 752.0 KiB of the decoded total.**

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
720 KiB of decoded RGBA — but the terrain atlas is only 1.3 MiB of an 18.2 MiB runtime set, and
the five property columns that genuinely differ per faction are why the six-row shape exists at
all. The cost that dominates is the six 1152×576 unit sheets: **15.2 MiB, 84% of the decoded
total, with no duplicate cell between them.** Squeezing every repeated cell out of every sheet
would return 752 KiB, about 4% of what the game holds — so the case for a relayout is a tidiness
case, not a memory one, and it is paid for in `BattleView`'s region maths, which reads a terrain's
cell as (column, faction row). Two small oddities the instrument turned up and this page does not
explain: `autotiles/roads.png` cell 10 and `autotiles/shoals.png` cell 4 are byte-identical to
cell 0 of their own sheets — two connection variants the art draws the same, not a layout choice.

## What a plan would weigh

1. **Dedupe the terrain atlas columns.** Give a non-property terrain one row instead of six and
   the atlas becomes 896×64 plus a six-row property block, saving 720 KiB of decoded RGBA. It
   costs a new region rule in `scenes/battle/battle_view.gd` and `scenes/menu/map_thumbnail.gd`
   ("faction row only if the terrain is a property"), a matching change in `build_terrain_atlas`,
   and a re-render of every shipped sheet.
2. **Keep the six-row contract.** One rule — cell = (terrain column, faction row) — with no
   special case anywhere, for 720 KiB of an 18.2 MiB set. A terrain that later wants faction
   colour (a fortified woods, a paved road) already has a row waiting, and a sixth army would add
   its row here without a second layout to teach.

Nothing here is implemented. Re-run with `make sheet-census`; it takes under a second and reads
only the installed art.
