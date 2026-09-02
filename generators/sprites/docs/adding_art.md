# Adding art: a unit, a tile, a faction

The recipe for putting new art on the board. Everything else in this folder
explains why the art looks the way it does; this is the order of operations.

Set the interpreter up once with `make generators-venv` from the repository
root, and keep `py=~/.cache/grid_commanders/venv-sprites/bin/python` handy.

## Add a unit

1. **Author the model.** Write a builder in the file its family lives in —
   `spritegen/units/land.py`, `air.py`, `sea.py` or `foot.py` — with the
   signature every other builder has, `def <id>(pose: Pose = Pose.A) -> Model`.
   Build out of `spritegen/units/parts.py` (tracks, rotors, shifts) so the new
   machine shares the roster's scale and light. Branch on the pose with a
   membership helper, never on `pose is Pose.A`: `moving(pose)` for the gait,
   `fires(pose)` for the muzzle, and `beat(pose)` for whatever ticks with the
   frame inside the ambient and move clips. `beat` is an INDEX, not a flag —
   0/1 across the ambient pair, 0-3 across the move clip's four — so write
   `beat(pose) % 2` for the usual builder, which authors one off-beat delta
   and plays its two keys twice across the four move frames, and plain
   `beat(pose)` only where the model genuinely has four things to say (a rotor
   phase, the rifleman's stride). `if beat(pose):` is the trap: it is truthy on
   MOVE_C as well, so a two-key builder written that way draws its off-beat on
   three frames of four. `beat` deliberately excludes
   `FIRE_B` — a fire branch written behind it makes a single-shot unit a pair —
   and the fire pair's own altitude is `off_beat`'s, asked by the placement
   rather than by a builder.
2. **Register it.** Add `"<id>": (<builder>, "land"|"air"|"sea")` to `UNITS`
   and the id to `ATLAS_ORDER` in `spritegen/units/__init__.py`. The column
   index is the position in `ATLAS_ORDER`, and it is the number the game reads.
3. **Decide about the move clip.** A unit in `MOVES`
   (`spritegen/units/pose.py`) draws its own stride for all four move poses,
   `Pose.MOVE_A` through `Pose.MOVE_D`; a unit left out of it renders its
   ambient poses onto the move sheets instead, per frame rather than per clip
   (`pose._FALLBACK`: MOVE_A and MOVE_C → A, MOVE_B and MOVE_D → B). Author
   the ambient pair first and add the id to `MOVES` when the stride exists.
   The four frames need not be four keys — most families author two and let
   `beat(pose) % 2` play them twice — but MOVE_C and MOVE_D must either say
   something new or repeat MOVE_A and MOVE_B byte for byte, which
   `tests/test_clips.py GaitPhases` pins per family. `CLIP_POSES` in the same
   file is the clip-to-frame table `anim.json` publishes — it changes only when
   a whole new clip does.
4. **Author the KO frame.** Same shape, same file, one opt-in table over:
   a unit in `KOS` draws its own wreck for `Pose.KO`, and a unit left out
   renders its rest key there instead. Unlike `MOVES` this is not optional for
   a land or sea unit — `tests/test_ko_pose.py` fails a non-air id missing from
   `KOS`, and fails an id in `KOS` whose builder grew no `Pose.KO` branch, so
   the two land together. Air authors none in v1 and keeps the cut-in's
   transform-topple.
5. **Author the fire frame.** The third opt-in table, and the same shape
   again: a unit in `FIRES` (`spritegen/units/pose.py`) draws a muzzle-lit
   `Pose.FIRE_A` behind `if fires(pose):`, and a unit left out renders its idle
   PAIR there (FIRE_A → A, FIRE_B → B) — per frame, so an unarmed column keeps
   the beat its idle one rides. Like `KOS` this is not optional: every ARMED id
   must be in `FIRES` and every id in `FIRES` must author a branch, and
   `tests/test_fire_pose.py` fails each half by name. A second key is authored
   ONLY for `FIRE_PAIRS` — the units whose primary weapon is sustained — with a
   `pose is Pose.FIRE_B` sub-branch inside that same block; everything else
   draws one model into both frames. Whatever the branch moves must stay
   attached to the machine and must be VISIBLE in this projection: a part
   carried past the face it shared comes off as a floating island, and a frame
   authored where the wing root or the hull occludes it changes nothing the
   player can see. Both are gates, not advice.
6. **Give the game the unit.** Add `data/units/<id>.tres` with `atlas_col` set
   to the new column and `battle_style` (and `secondary_battle_style`) naming a
   `data/battle_anim/*.tres` weapon signature; `tests/unit/test_battle_styles.gd`
   fails on a style that does not exist. The generator draws the weapon
   silhouette to match, so pick the style before authoring the gun. An armed
   unit also needs its row and its columns in `data/damage_chart.tres` —
   `tests/unit/test_damage_chart.gd` fails a gun that can hit nothing and a
   unit nothing can hit.
7. **Install and gate.** `make tiles`, then `make sprites-test`,
   `make sprites-snapshot` and `make verify`.

Gates a new unit meets, and what each wants:

| Gate | Wants |
| --- | --- |
| `tests/test_atlas_contract.py` | the sheet is `len(ATLAS_ORDER)` cells wide and byte-deterministic — a 19th unit changes the atlas size stated there and in `README.md` |
| `tests/test_anim_manifest.py` | `anim.json` derives its columns from `ATLAS_ORDER`, so nothing is retyped |
| `tests/test_livery.py` | pixels come out of the faction ramps, no partial alpha, no isolated pixel, at most 24 colours |
| `tests/test_value_bands.py` | 3% of the unit above L200 on every row, 55% of it changing colour when the row does, and no row out-lighting the chromatic band |
| `tests/test_board_read.py` | a silhouette no other unit shares, at board zoom and zoomed out |
| `tests/test_cell_geometry.py`, `tests/test_raised_armour.py` | the model is anchored to the cell's bottom edge and spends the 64x96 headroom on mass, not on fine detail |
| `tests/test_clips.py` | frame B reads as motion at the furthest rung, and so does every adjacent step of the move clip's four — the quietest step still crosses a whole board texel and the noisiest does not boil the interior. `GaitPhases` also wants each uid in `MOVES` to settle the third and fourth frames one way or the other: author something new on MOVE_C/MOVE_D, or repeat MOVE_A/MOVE_B byte for byte AND join `GaitPhases.REUSED` — a silent repeat off that list fails by name |
| `tests/test_ko_pose.py` | a land or sea unit is in `KOS` and its `Pose.KO` is an authored model rather than its rest key, floored above the sheet's own ink and narrower in tone than the unit it was |
| `tests/test_fire_pose.py` | an armed unit is in `FIRES` and authors a `fires(pose)` branch, a `FIRE_PAIRS` member's two keys differ and nobody else's do, an unarmed column is byte-identical to the idle pair, every pose draws as ONE connected sprite, and the fire frame changes enough pixels to be seen |
| `tests/check_snapshots.py` | every generated PNG has an installed twin — the failure you get for skipping `make tiles` |

## Add a terrain tile

1. **Paint it.** Write the painter in its family's module under
   `spritegen/terrain/` (`plains.py`, `water.py`, `woods.py`, `mountain.py`),
   returning one `terrain.CELL` square RGBA tile. Use the tones in
   `spritegen/terrain/tones.py` and stay under `TERRAIN_VALUE_CEILING` — the
   band above it belongs to the units. A faction-tinted property is a voxel
   model instead: build it in `spritegen/buildings.py`, register it in
   `BUILDINGS`, and give it a `PROPERTY_ANCHOR` entry in
   `spritegen/terrain/properties.py`, whose `property_overlay` composites the
   model and its shadow onto empty ground.
2. **Register it.** Export the name from `spritegen/terrain/__init__.py`'s
   `__all__`, add the id to `TERRAIN_ORDER` (the atlas column), and add it to
   either `_PLAIN_TILES` or `PROPERTY`. A property is a **transparent
   overlay**: the building and its shadow, no ground.
3. **Autotile if it connects.** A family whose neighbours change its art needs
   a `spritegen/autotile.py` sheet (roads, rivers, coast, shoals, woods) and a
   phase table if it varies by cell (`PLAINS_PHASES`, `SEA_PHASES`,
   `MOUNTAIN_PHASES`).
4. **Give the game the tile.** Add `data/terrain/<id>.tres` with `atlas_col`
   set to the new column, the movement costs every move class pays on it, and
   — for a property — `team_tinted`, plus the `builds` and `services` move
   classes it produces and refits.
5. **Install and gate.** `make tiles`, `make sprites-test`,
   `make sprites-snapshot`, `make verify`.

Extra gates a tile meets: `tests/test_terrain_paint.py` (colour budget,
texture, connection masks, seams), `tests/test_terrain_tones.py` (the sky the
ground is lit by), `tests/test_properties_art.py` (a property's outline,
slots and transparent ground), `tests/test_value_bands.py` (nothing medians
into the unit band) and `tests/test_demo_map.py` (`preview_map.png` keeps the
shipped maps' terrain mix).

## Add a faction

A faction row is a `Faction` in `spritegen/palette.py`'s `FACTIONS`, mirrored
off the game's own `CommanderVisuals` theme, and it widens every sheet by a
row. `docs/ramps.md` is how a row's six slots get their colour; read it before
touching a ramp.

## The loop

```sh
# draw one sprite big while editing the model — writes preview_only.png
# into the gitignored out/ directory
"$py" sprite_generator.py --only tank --team verdant --zoom 8

# whole run into ./out, without installing anything
"$py" sprite_generator.py
```

Then, from the repository root:

- `make tiles` — regenerate, install into `assets/`, reimport.
- `make sprites-test` — this pipeline's merge bar (several minutes).
- `make sprites-snapshot` — the installed art against a fresh generation; this
  is what catches an edit that never ran `make tiles`.
- `make legibility-check` — an instrument, not a gate: what a cell reads like
  on the board. A failing cell is a finding for the art to answer.
- `make verify` — the game's own gate, for the `.tres` half of the change.
