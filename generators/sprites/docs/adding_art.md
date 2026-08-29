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
   machine shares the roster's scale and light. Branch on the pose with
   `beat(pose)`, never on `pose is Pose.A`.
2. **Register it.** Add `"<id>": (<builder>, "land"|"air"|"sea")` to `UNITS`
   and the id to `ATLAS_ORDER` in `spritegen/units/__init__.py`. The column
   index is the position in `ATLAS_ORDER`, and it is the number the game reads.
3. **Decide about the move clip.** A unit in `MOVES`
   (`spritegen/units/pose.py`) draws its own stride for `Pose.MOVE_A` /
   `Pose.MOVE_B`; a unit left out of it renders its ambient poses onto the move
   sheets instead. Author the ambient pair first and add the id to `MOVES` when
   the stride exists. `CLIP_POSES` in the same file is the clip-to-frame table
   `anim.json` publishes — it changes only when a whole new clip does.
4. **Give the game the unit.** Add `data/units/<id>.tres` with `atlas_col` set
   to the new column and `battle_style` (and `secondary_battle_style`) naming a
   `data/battle_anim/*.tres` weapon signature; `tests/unit/test_battle_styles.gd`
   fails on a style that does not exist. The generator draws the weapon
   silhouette to match, so pick the style before authoring the gun.
5. **Install and gate.** `make tiles`, then `make sprites-test`,
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
| `tests/test_clips.py` | frame B reads as motion at the furthest rung, and so does the move pair |
| `tests/check_snapshots.py` | every generated PNG has an installed twin — the failure you get for skipping `make tiles` |

## Add a terrain tile

1. **Paint it.** Write the painter in its family's module under
   `spritegen/terrain/` (`plains.py`, `water.py`, `woods.py`, `mountain.py`,
   or `properties.py` for a faction-tinted building), returning one
   `terrain.CELL` square RGBA tile. Use the tones in `spritegen/terrain/tones.py`
   and stay under `TERRAIN_VALUE_CEILING` — the band above it belongs to the
   units.
2. **Register it.** Export the name from `spritegen/terrain/__init__.py`'s
   `__all__`, add the id to `TERRAIN_ORDER` (the atlas column), and add it to
   either `_PLAIN_TILES` or `PROPERTY`. A property is a **transparent
   overlay**: the building and its shadow, no ground.
3. **Autotile if it connects.** A family whose neighbours change its art needs
   a `spritegen/autotile.py` sheet (roads, rivers, coast, shoals, woods) and a
   phase table if it varies by cell (`PLAINS_PHASES`, `SEA_PHASES`,
   `MOUNTAIN_PHASES`).
4. **Give the game the tile.** Add `data/terrain/<id>.tres` with `atlas_col`
   set to the new column, `team_tinted` for a property, and the movement costs
   every move class pays on it.
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
# draw one sprite big while editing the model — writes out/preview_only.png
"$py" sprite_generator.py --only tank --team verdant --zoom 8

# whole run into ./out, without installing anything
"$py" sprite_generator.py
```

Then, from the repository root:

- `make tiles` — regenerate, install into `assets/`, reimport.
- `make sprites-test` — this pipeline's merge bar (~240 s).
- `make sprites-snapshot` — the installed art against a fresh generation; this
  is what catches an edit that never ran `make tiles`.
- `make legibility-check` — an instrument, not a gate: what a cell reads like
  on the board. A failing cell is a finding for the art to answer.
- `make verify` — the game's own gate, for the `.tres` half of the change.
