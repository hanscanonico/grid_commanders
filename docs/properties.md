# The properties pass — buildings on the indexed ramps, 2026-08-22

Units moved onto six-slot ramps in round 4 and the five property buildings did
not: they kept drawing through `voxel.render`, the shading path, which computes
a tone per pixel out of three face constants, a fractional ambient occlusion, a
vertical gradient and a uniform contour. `docs/terrain_outlines.md` took the
worst of that off — one contour tone per material instead of one per lit
neighbourhood — and said in as many words that what was left was the shading
arithmetic itself. This is that debt paid.

## What a building is made of now

Three shared families, built by the same `build_ramp` shaper as the faction
ramps, so a wall's shadow steps sit in the same `AMBIENT` sky an army's do:

| family | anchor | ladder (Rec. 601) | painted by |
| --- | --- | --- | --- |
| `MASONRY_RAMP` | warm stone | 24 / 56 / 84 / 112 / 140 / 168 | `detail` S0, `wall_dk` S1, `wall` S2, `trim` S3 |
| `CONCRETE_RAMP` | cool grey | 20 / 48 / 74 / 100 / 128 / 156 | `pad_rim` S1, `pad` S2 |
| `MACHINE_RAMP` | steel | 26 / 60 / 92 / 124 / 150 / 170 | `machine` S3 |

Plus the owner's own ramp for `roof` (S1) and `roof_trim` (S2). The mapping is
`palette.PROPERTY_MATERIALS`; the models name it through the constants at the
top of `spritegen/buildings.py`, which is why the ladder round 7 authored —
mass dark, the rung above it a LINE — survives the port unchanged in meaning.

Two things are stated by the structure rather than by a number now. Masonry is
warm and concrete is cool at nearly the same values, so a lot and the building
standing on it separate **by hue** and neither has to spend the value the units
are keyed against. And machinery sits a full band over both, because metal
catches this light where stone does not — it is the one thing on a building
that may.

## The band a building may not enter

`voxel.BUILDING_TOP_SLOT = S_TOP` clamps every ramp on a property to the top
plane, so the **rim** step never draws. That is the whole difference between a
unit's ramp and a building's: the rim is the flash the band above
`terrain.TERRAIN_VALUE_CEILING` is reserved for, and a building is what an army
is read against. It is also what keeps the roofs honest — a faction `roof_trim`
ridge is a leading edge on nearly every voxel, so without the clamp the sawtooth
factory would have worn S5 (L205-219) along three full-width ridges.

The roofs come down two bands with it, to the owner's shadow band for the plane
and the token itself for the ridge. On Iron that is not a compromise but the
row's identity: near-black panels under a light-steel ridge.

## Measurements

Distinct opaque colours, this branch against `main`:

| sheet | before | after |
| --- | ---: | ---: |
| `terrain_atlas.png` | 519 | 260 |
| `preview_terrain.png` | 521 | 262 |
| `preview_map.png` | 407 | 235 |

Per property tile (worst faction row; a tile is the building plus its one
shadow tone):

| tile | before | after |
| --- | ---: | ---: |
| airport | 75 | 24 |
| city | 66 | 24 |
| hq | 71 | 22 |
| base | 43 | 22 |
| port | 58 | 21 |
| unowned row (any) | 37-62 | 14-15 |

`IndexedPalette` holds a unit to 24 colours; the ratchet was written to be
reached toward, and it is reached. `TerrainPalette.PROPERTY_CEILING` comes down
from **90 to 25** — the unit cap plus the shadow.

The other outlier was the outline. The shading path drew an unconditional
keyline: every silhouette pixel dark, on the side the sun is on as hard as on
the side it is not. Buildings wear `_selective_outline` now, grade and all, and
the share of a sprite's own boundary drawn as the contour lands where the units
of the same grade land:

| grade | units | buildings before | buildings after |
| --- | --- | ---: | ---: |
| light (meridian, aurora, verdant) | 0.579-0.696 | 1.000 | 0.650-0.743 |
| heavy (neutral, iron) | 0.791-0.941 | 1.000 | 0.821-0.985 |

Buildings sit a little over the units of their grade, and the reason is
geometric: a lot is a flat plate, so its whole sunward edge is a ground-facing
step with nothing above it to lift. The heavy pair sits near the top for the
reason `docs/outlines.md` gives for the rows themselves — a lit line only pays
where it clears the ground's value band, and nothing on a building is allowed
high enough to.

The value gates are unchanged and still pass on their original thresholds:
tile medians under `TERRAIN_MEDIAN_CEILING`, the unowned row with **zero**
pixels over the terrain ceiling, glazing under 2% and the glint under 1%, and
the lit half of every property under L120 (measured L74-112). The one model
change the numbers forced is the factory's hazard stripe, which is dashed
rather than solid: amber is the brightest thing a property owns and a solid
band of it across the widest door on the sheet spent 2.3% of the building's
pixels over the ceiling on its own.

## What stayed on the shading path

The reef rock. `voxel.render` still draws it, still contours it one tone per
material, and its tops are still far too narrow to dither — so
`docs/terrain_outlines.md`'s rules hold for the one prop that still answers to
them, and `PropOutline` measures them there.
