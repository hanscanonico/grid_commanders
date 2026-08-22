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

## The faction read, 2026-08-23

The pass above bought the colour counts and the outline with a building's
owner. Measured as the board actually samples one — each 64px property tile
downscaled 4:1 NEAREST into its 16px cell, mean RGB distance between two owner
rows over every pixel either of them draws — the five properties came out of
that pass at **12.4-57.5**, and the two rows a player most needs to tell apart
were the bottom of it: the unowned row against Iron at **12.4** on the airport,
Iron against verdant at **16.6** on the port. Two units of different armies
stand 34-95 apart on the same measure. A property is allowed to say less than
an army does; it is not allowed to say nothing.

Three things were wrong and all three were the same thing — the owner had no
area left at a scale where a roof is four pixels.

**The unowned row was built out of the owned rows' stone.** `_NEUTRAL_GREYS`
resolved every hue-carrying material onto masonry, so an unowned property and
an Iron one were the same warm building with slightly different dark roof
panels — and Iron's own colour is a grey, so value could not separate them
either. The unowned row is drawn out of **concrete** end to end now, rung for
rung, against masonry for every owned row. Nobody's lights are on and nobody's
stone is in the sun: the row nobody owns is COLD. That is a temperature rather
than a value, so it costs the row nothing in the bands below.

**The two grey families were two cards.** Masonry sat at H37/S0.13 and
concrete at H210/S0.09 — 11.6 RGB apart at the contour rung, 46 at the widest.
They are a sandstone (H39/S0.43, `a68d5e`) and a slate (H211/S0.27,
`74889e`) now, 29-66 apart the whole ladder up, which is what makes the
paragraph above a read rather than a claim. Masonry's ladder also comes up
off the near-black it started at (24/56/84/112 to 38/70/96/116): a property
was the darkest, least saturated
family on the sheet — S0.234 against an army's S0.411 — and it is S0.406
now.

**The owner lived only on roofs.** A roof deck is four pixels at 4:1 and a
tower is mostly wall, so the token is the **paint** as well as the ridge: a
fascia under the eaves (city, port), a painted lintel and an apron guide line
(airport), a quay edge and a crane in the owner's livery (port), merlons along
the two parapets the camera sees (hq), a band round the chimney cap (base).
The share of a building that changes colour when its owner does goes from
0.23-0.35 to **0.31-0.49**, which is the ceiling
`IndexedPalette.test_property_buildings_are_mostly_neutral_masonry` sets — a
property is still mostly the material it is built of.

| pair, worst property | before | after |
| --- | ---: | ---: |
| neutral / iron | 12.4 | 29.0 |
| iron / verdant | 16.6 | 27.1 |
| aurora / verdant | 21.2 | 34.1 |
| neutral / verdant | 21.5 | 38.4 |
| aurora / iron | 24.4 | 36.2 |
| meridian / verdant | 24.8 | 39.3 |
| meridian / iron | 26.3 | 40.3 |
| neutral / aurora | 27.0 | 47.6 |
| neutral / meridian | 25.4 | 59.3 |
| meridian / aurora | 30.1 | 48.0 |

`PropertyPalette.test_two_owners_are_tellable_apart_at_the_boards_own_scale` is
that measurement: every coloured pair over 25, and neutral against Iron — two
greys, buying their margin with hue alone — over 20. The 1x reading it sits
beside asks a different question and is kept: this one bounds how much of a
cell changes, that one how far apart the pixels that changed are (45.0 at the
worst pair, over the 40 bar; it fell from 48.9 because the unowned row now
differs from an owned one in far more pixels, each by less).

Nothing above moved a band. Every value gate passes on its original threshold:
the lit half of a property measures **L72-115** against the L120 ceiling, the
glazing share stays at 1.2% of 2%, the unowned row still puts zero pixels over
the terrain ceiling, tile medians are untouched, no ramp reaches the rim step,
and the colour ratchets come DOWN with the pass — 23 colours on the widest
property tile against 24, and the unowned row spends 5-8 where it spent 13-14,
because a building drawn out of one family is cheaper than one drawn out of
two.
