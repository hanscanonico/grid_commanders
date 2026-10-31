# Model generator

The 3D board's painted miniatures, built and baked by Python inside Blender 5.2. The art in
`assets/models/` is committed, so the game, CI and the mini PC never need Blender.

```sh
blender --background --python generators/models/build_models.py -- tank city
blender --background --python generators/models/preview_models.py -- tank --out /abs/dir
```

`build_models.py` writes `<name>.glb`, `<name>_paint.png` and `<name>_normal.png` under
`assets/models/<folder>/`, prints `BOUNDS` and `MODEL` lines, and exits non-zero when a model
breaks `modelgen/contract.py`. `preview_models.py` renders what the game would show, without a
window: `<name>_close.png`, and `<name>_board.png` at the size a unit is played. Add `--sea` for
a ship over water, and `--lift 0.47` for an aircraft in the air.

## The look

A toy wargame on a tabletop, like a painted miniature set. Chunky exaggerated shapes, soft bevels,
a dark wash in the creases, dry-brushed edges, chips and road dust.

**The board view decides.** A unit is about fifty pixels wide there, and the camera looks down at
52°. A model has to read as its own unit from the top down in that view:

- Silhouette first: one or two big exaggerated shapes say what the unit is. Details are for the
  close-up and must not break up the big shapes.
- The army's colour covers most of what the camera sees. `team`, `team_light` and `team_dark` are
  places on the army's ramp, so one texture dresses every army.
- No clutter of small dark parts: at board size they turn into black noise. Prefer a few big
  lockers to many small ones.
- Thin parts vanish or shimmer. Anything that must read is at least 0.03 cells thick.
- Keep each unit under about 4,000 triangles, a building under about 3,000.

Models face +X and stand on Z = 0, with the middle of the footprint at the origin. A ship's origin
is its waterline, an aircraft's its belly. One cell is one Blender unit. The game's +Z (toward the
camera) is Blender's -Y, and the game's -Z (away from it) is +Y.

## Writing a model

A model is a module under `modelgen/<folder>/`, with a `build(k: Kit)` that runs twice: `lo` is the
mesh the game draws and `hi` is what the bake reads. Anything inside `if k.hi:` reaches the game
only as paint and normals, so rivets, grilles, panel lines and little fittings go there.
`modelgen/units/tank.py` is the reference; read it first.

A module may also set `ROLES` (extra paints), `TEXTURE` (default 512), `NORMAL_TEXTURE` (default
256), `CAGE` and `REACH`. Black patches in the texture mean the bake's rays missed the high copy,
so raise `CAGE` and `REACH` (`modelgen/terrain/mountain.py` uses 0.08 and 0.2).

`Kit` has `box`, `loft`, `side_profile`, `cyl`, `ellipsoid`, `tube`, `rock`, `crag`, `rivets`, `seam`
and `marker`. A bevel of `ROUND_BEVEL` (0.018) or more stays round on the game's copy, so use it on
big forms. Dry-brushed edges land on bevels, so a part with no bevel gets none.

Roles (`modelgen/paint.py`): `team`, `team_light`, `team_dark`, `steel`, `gunmetal`, `rubber`, `wheel`,
`canvas`, `leather`, `glass`, `brass`, `bone`, `plaster`, `stone`, `wood`.

`k.cull` (default on) drops faces turned to the ground below Z = 0.3 from the game's copy. Turn it
off for anything seen from below or from a low cut-in lens, such as an aircraft.

### Markers

- `k.marker("muzzle", (x, y, z))` is where a shot leaves. Every armed model has one.
- `k.marker("emblem", (x, y, z))` and `k.marker("emblem_edge", (x + r, y, z))` place the army's badge,
  of radius `r`, projected straight down onto an up-facing flat surface.

### Motion

The game moves parts in its vertex shader, with no skeleton and one draw call per model:
`k.moves(part, kind, (pivot_x, pivot_z))`.

| Kind | What it does | Used for |
| --- | --- | --- |
| `WHEEL` | Spins about the axle through the pivot, with the distance driven | road wheels, hubs, sprockets |
| `TREAD` | Stays put while bands of paint crawl along it | track runs |
| `RECOIL` | Slides back along -X when firing | barrel, sleeve, muzzle brake |
| `LEG_A`, `LEG_B` | Swings about the hip pivot, in opposite phase | soldiers' legs |
| `ARM_A`, `ARM_B` | Swings against the legs, and lifts to fire | soldiers' arms and weapons |

Axles and swings run across the model, along Blender's Y.

## Contract

`modelgen/contract.py` holds the footprint and height limits, and `tests/unit/test_unit_models_3d.gd`
holds the game to them. The tiers in that test matter as much: a recon is shorter than a tank,
a tank is shorter and lower than a medium tank, a medium tank reaches the cell's edge at x = 0.42,
an APC rides lower than a tank, the bomber spans widest in the air, and the HQ is the tallest
property.
