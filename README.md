# Sprite Generator

Procedural pixel-art sprite generator built on Pillow. Produces transparent
PNGs of five sprite types — **creatures** (symmetric blobs with faces),
**ships** (fuselage + wings, cockpit and engine glow), **items** (gems and
relics with a glint), **robots** (part-assembled mechs with a visor and
panel seams) and **tanks** (high-detail top-down vehicles: link-textured
treads wrapped over sprockets, a lit glacis plate, engine-deck vents and
exhausts, a shaded turret with hatch and stowage bustle, a gun with mantlet,
bore evacuator and muzzle brake, plus cast shadows, camo and weathering) —
plus an assembled spritesheet.

Every sprite is deterministic from its seed: the seed is embedded in the
default filename (unless `--name` replaces it), so any sprite you like can be
regenerated at a different size or scale.

## Setup

```sh
python3 -m venv .venv
.venv/bin/pip install pillow
```

## Usage

```sh
# 32 mixed sprites at 16x16, upscaled x8, plus a spritesheet, into ./out
.venv/bin/python sprite_generator.py

# 16 creatures
.venv/bin/python sprite_generator.py --kind creature -n 16

# Bigger sprites, reproducible batch
.venv/bin/python sprite_generator.py --size 32 --scale 6 --seed 1234

# A fleet of blue-ish ships
.venv/bin/python sprite_generator.py --kind ship --hue 0.58

# High-detail 160x160 tanks (the tank kind's default size)
.venv/bin/python sprite_generator.py --kind tank -n 8
```

| Flag | Meaning |
| --- | --- |
| `-n / --count` | number of sprites (default 32) |
| `-k / --kind` | `creature`, `ship`, `item`, `robot`, `tank` or `mixed` (default) |
| `-s / --size` | grid size in pixels before scaling, min 8 (default 16; `--kind tank` defaults to 160 — ~100x the pixels — for high-detail assets) |
| `-x / --scale` | nearest-neighbor upscale factor (default 8; `--kind tank` defaults to 1) |
| `--seed` | master seed; sprite *i* uses `seed + i` (default random) |
| `--hue` | base hue 0..1 for the whole batch (default random per sprite) |
| `--faction` | comma list of faction palettes; each sprite is rendered once per faction (same seed → same shape, colors only). Known names: `neutral red blue iron verdant`, plus `all` and custom `label:RRGGBB`. Mutually exclusive with `--hue` |
| `--name` | fixed output name(s) instead of `<kind>_<seed>`; a comma list makes one sprite per name and each entry may pin its type as `name:kind` |
| `--canvas` | center each sprite on an exact N×N transparent canvas (after scaling) |
| `--outline` | fixed outline color `RRGGBB` (default: dark tint of the body hue) |
| `--preset` | option bundle (see below) |
| `-o / --out` | output directory (default `out/`) |
| `--no-sheet` / `--no-singles` | skip the spritesheet / the individual PNGs |

## Generating assets for Grid Commanders

`--preset grid-commanders` bundles what `../grid_commanders`'s unit pipeline
expects — 64×64 RGBA PNGs named `<unit>_<faction>.png`, one per atlas team row,
with the game's faction body colors and outline (`--size 14 --scale 4
--canvas 64 --factions all --outline 14171c`; explicit flags override the
preset, though a flag passed explicitly at its built-in default reads as
unset and takes the preset value). Tanks are the exception: the game's
vendored unit art is drawn at the cell's own resolution facing right, so
preset tanks render hi-detail at a native-scale 50px grid — past the ~40px
threshold where hatches, vents, headlights and exhausts switch on — rotated
to face right, and as **one curated design** rather than a seed roll: every
run emits the same best-of-sweep tank (big round turret, stowage bustle,
long gun with bore evacuator and muzzle brake), so there is no seed to
iterate on. `--seed` still steers the other kinds; pinning `--size`/`--scale`
explicitly puts tanks back on the shared seed-driven chunky settings (the
rotation always applies):

```sh
.venv/bin/python sprite_generator.py --preset grid-commanders \
  --names hover_tank:tank,gunship:ship,drone:ship --seed 42
```

writes `hover_tank_neutral.png`, `hover_tank_red.png` … `drone_verdant.png`
(3 units × 5 factions), plus a sheet laid out like the game's units atlas: one
row per faction, one column per unit. Tanks come out ready as-is; for the
other kinds, iterate on `--seed` until you like a shape. Then drop the five
PNGs into `../grid_commanders/assets/sprites/units/`, register the unit in
`tools/paste_unit_sprites.gd`, and run `make tiles` there.

## How it works

1. **Shape** — random noise on a half-grid, weighted by a per-type density
   mask, mirrored for bilateral symmetry, smoothed with cellular-automata
   steps, reduced to the largest connected blob, then re-symmetrized and
   centered. Robots skip the noise and are assembled from jittered rectangles
   (head/torso/arms/legs); tanks are assembled onto a **part map** (treads,
   hull with glacis nose, turret, gun) that records which component owns each
   pixel, which is what makes them read as machines.
2. **Color** — a 5-tone ramp derived from one base hue with hue-shifting
   (shadows drift toward blue, highlights toward yellow), plus a contrasting
   accent ramp painted in small symmetric blobs. Tanks use a muted variant —
   military saturation, analogous accent, free hues biased toward olive, tan
   and steel — and blend ramp tones into much finer gradients.
3. **Light** — directional shading from above, edge darkening, and a touch of
   seeded dithering.
4. **Details** — eyes with guaranteed placement and a minimum gap so they read
   as a face, cockpit glass, engine glow, gem glints, visors. Tanks are
   repainted pixel-by-pixel from their part map: tread links and sprocket
   wraps, glacis lighting, deck vents, headlights, driver and commander
   hatches, periscopes, exhausts, bolts, turret dome shading with a bright
   front rim, mantlet, bore evacuator, muzzle brake, dark bore, cast shadows
   from the raised turret and gun, camo patches and wear specks. Detail sizes
   scale with sprite resolution; the finest layers switch on at ~40px and
   ~96px, so the default 160px tanks get everything.
5. **Finish** — 1px outline in a dark tint of the body color, nearest-neighbor
   upscale, optional spritesheet.

Python 3.10+, no dependencies beyond Pillow.
