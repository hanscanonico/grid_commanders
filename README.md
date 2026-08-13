# Sprite Generator

Deterministic sprite pipeline for [`../grid_commanders`](../grid_commanders):
it generates the game's complete **units atlas** (18 units x 5 faction rows)
and **terrain atlas** (14 terrains x 5 rows) as curated isometric-voxel pixel
art, in the same dimetric style as the PixVoxel pack the game shipped with —
but with more detail: finer voxels, baked ambient occlusion, front-edge rim
light, per-part outlines, and consistent scale, light and palette across the
whole roster.

There are **no seeds and no randomness**. Every sprite is a hand-authored
voxel model (`spritegen/units.py`, `spritegen/buildings.py`) or tile painter
(`spritegen/terrain.py`); texture "noise" comes from a fixed hash, so every
run reproduces the same bytes. Regenerating after an edit changes exactly the
sprites you edited.

## The roster

| Group | Columns (atlas order) |
| --- | --- |
| Land | infantry, mech, recon, tank, md_tank, anti_air, artillery, rockets, apc (0-8), missiles (13) |
| Air | fighter, bomber, b_copter, t_copter (9-12) |
| Sea | battleship, cruiser, sub, lander (14-17) |
| Terrain | road, plains, woods, mountain, river, city, base, hq, sea, airport, port, shoal, bridge, reef (0-13) |

Rows follow `SideIdentity._ROW_FOR_KEY`: 0 neutral, 1 meridian (red),
2 aurora (blue), 3 iron, 4 verdant — every row's ramp is the exact
`CommanderVisuals.FactionTheme` (color / dark / light) from the game's code,
neutral's slate theme included. Weapon silhouettes follow each unit's
`battle_style` (small arms, rocket, cannon, autocannon, bomb, torpedo,
unarmed). Property terrains (city, base, hq, airport, port) are tinted per
row; every other terrain repeats one tile down its column.

Team color follows a livery convention: vehicle chassis and ship hulls wear
a desaturated faction tint (the `hull` ramp), while identity surfaces — tank
turret crowns, truck cabs, aircraft wings, ship decks, building roofs — carry
the pure faction color, so ownership reads from the top-down view without
the whole sprite turning into a paint blob. Buildings are neutral concrete
and stone under faction-colored roofs, caps and banners.

## Setup

```sh
python3 -m venv .venv
.venv/bin/pip install pillow
```

## Usage

```sh
# everything: atlases + per-cell sprites + review sheets, into ./out
.venv/bin/python sprite_generator.py

# iterate on specific sprites at high zoom while editing models
.venv/bin/python sprite_generator.py --only tank,city --team verdant --zoom 8

# copy atlases and cells into the game checkout
.venv/bin/python sprite_generator.py --install            # ../grid_commanders
.venv/bin/python sprite_generator.py --install ~/somewhere/grid_commanders
```

| Flag | Meaning |
| --- | --- |
| `-o / --out` | output directory (default `out/`) |
| `--only` | comma list of unit/terrain ids — renders just `preview_only.png` |
| `--team` | faction row for `--only` (neutral/red/blue/iron/verdant) |
| `--zoom` | zoom factor for `--only` previews (default 6) |
| `--no-cells` | skip the 115 per-cell PNGs, write only atlases + previews |
| `--install` | copy outputs into a grid_commanders checkout |

## Outputs

| File | Contract |
| --- | --- |
| `units_atlas.png` | 1152x320 RGBA — drop-in `assets/tiles/units_atlas.png` |
| `terrain_atlas.png` | 896x320 RGB — drop-in `assets/tiles/terrain_atlas.png` |
| `units/<id>_<team>.png` | 90 cells, the inputs `tools/paste_unit_sprites.gd` reads |
| `iso_buildings/<id>_<team>.png` | 25 property-building cells for `assets/sprites/iso_buildings` |
| `preview_units.png`, `preview_terrain.png` | 2x atlas contact sheets on checkerboard |
| `preview_map.png` | an authored little battle map proving the sheet in context |
| `autotiles/{roads,rivers,coast,shoals}.png` | 16-variant connection sheets (see below) |
| `autotiles/bridges.png` | the two bridge deck orientations, E-W then N-S |

The `autotiles/` sheets are the opt-in upgrade path beyond the fixed
14-column terrain contract: roads and rivers as N/E/S/W connection sets (so
they can turn and junction), both bridge orientations, coastline tiles for
sea bordering land, and shoals surfed on whichever edges face water. Each
connection sheet lays out masks 0-15 row-major (bit order N=1, E=2, S=4,
W=8); `bridges.png` carries its two decks side by side. The demo
map composes from these, which is why its roads connect and its island has a
shoreline; the atlases themselves are unchanged drop-ins.

Note the game's `make tiles` rebuilds its atlases from its own PixVoxel
pipeline and would overwrite installed atlases; the per-cell exports exist so
that pipeline's paste step can be pointed at this art instead.

## How it works

1. **`spritegen/voxel.py`** — a tiny dimetric voxel engine. Screen
   `x=(vx-vy)*2, y=(vx+vy)-vz*2`, each voxel a 4x4 cube sprite overlapping
   its neighbours by 2px (the classic 2px stair edge). Painter's-algorithm
   ordering, three face tones per material (pure color on the player-facing
   left face), neighbour-aware ambient occlusion plus ground-contact
   occlusion and a vertical depth gradient (tall masses darken toward their
   base), rim light on unshadowed front corners, hash dither on broad tops,
   then a 1px per-part outline — each silhouette pixel is a dark tint of the
   part it borders. `Model.chamfer` cuts corner columns so
   turrets, cabs and roofs read as octagonal masses instead of cubes.
2. **`spritegen/palette.py`** — faction ramps mirroring the game's
   `CommanderVisuals`, fixed materials (gunmetal, track, glass, skin, ...),
   shading math, and the deterministic hash noise.
3. **`spritegen/units.py`** — 18 authored models, all facing +y
   (screen lower-left) like the game's art. Land units get a contact
   shadow, ships sit in a flat displacement shadow with foam hugging the
   waterline, air units hover high over a small detached one.
4. **`spritegen/buildings.py` / `spritegen/terrain.py`** — voxel property
   buildings and nature props composed onto 64px tile grounds that keep
   `tools/generate_tiles.gd`'s palette and darkened-edge grid convention.
5. **`spritegen/autotile.py`** — the direction-aware road/river/bridge/
   coast/shoal variants exported under `autotiles/`.
6. **`spritegen/atlas.py`** — assembles atlases, exports cells, renders the
   preview sheets and the demo map (which resolves roads, the river, the
   bridge and every coastline through the autotile variants).

Python 3.10+, no dependencies beyond Pillow. The old seed-driven generator
(creatures/ships/items/robots/tanks) lives in git history before this
rewrite.
