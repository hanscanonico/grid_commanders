# Sprite Generator

Procedural pixel-art sprite generator built on Pillow. Produces transparent
PNGs of four sprite types — **creatures** (symmetric blobs with faces),
**ships** (fuselage + wings, cockpit and engine glow), **items** (gems and
relics with a glint) and **robots** (part-assembled mechs with a visor and
panel seams) — plus an assembled spritesheet.

Every sprite is deterministic from its seed: the seed is embedded in the
filename, so any sprite you like can be regenerated at a different size or
scale.

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
```

| Flag | Meaning |
| --- | --- |
| `-n / --count` | number of sprites (default 32) |
| `-k / --kind` | `creature`, `ship`, `item`, `robot` or `mixed` (default) |
| `-s / --size` | grid size in pixels before scaling, min 8 (default 16) |
| `-x / --scale` | nearest-neighbor upscale factor (default 8) |
| `--seed` | master seed; sprite *i* uses `seed + i` (default random) |
| `--hue` | base hue 0..1 for the whole batch (default random per sprite) |
| `-o / --out` | output directory (default `out/`) |
| `--no-sheet` / `--no-singles` | skip the spritesheet / the individual PNGs |

## How it works

1. **Shape** — random noise on a half-grid, weighted by a per-type density
   mask, mirrored for bilateral symmetry, smoothed with cellular-automata
   steps, reduced to the largest connected blob, then re-symmetrized and
   centered. Robots skip the noise entirely and are assembled from jittered
   rectangles (head, torso, arms, legs), which is what makes them read as
   machines.
2. **Color** — a 5-tone ramp derived from one base hue with hue-shifting
   (shadows drift toward blue, highlights toward yellow), plus a contrasting
   accent ramp painted in small symmetric blobs.
3. **Light** — directional shading from above, edge darkening, and a touch of
   seeded dithering.
4. **Details** — eyes with guaranteed placement and a minimum gap so they read
   as a face, cockpit glass, engine glow, gem glints, visors. Detail sizes
   scale with sprite resolution.
5. **Finish** — 1px outline in a dark tint of the body color, nearest-neighbor
   upscale, optional spritesheet.

Python 3.10+, no dependencies beyond Pillow.
