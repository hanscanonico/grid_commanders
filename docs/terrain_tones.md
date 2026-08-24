# Terrain tones: one sky, less chroma, warm stone — 2026-08-22

The units have been lit by a named sky since the ramp rewrite: every shadow
rung is rotated toward `palette.AMBIENT` (86, 112, 190) and mixed with it, so
an army's unlit faces are all the same colour of shade. The ground they stand
on was not. `terrain.py` held ten hand-typed tones, and what its shadows said
about the light was nothing at all — the dark tone was the lit tone with the
value pulled down and the hue left where it was:

| pair | hue rotation, lit -> dark, before |
| --- | --- |
| GRASS / GRASS_DARK | +2.5° |
| WATER / WATER_DARK | +2.8° |
| ROAD / ROAD_DARK | -1.5° |
| SAND / SAND_DARK | -0.9° |
| TIMBER / TIMBER_DARK | -0.1° |

Two more things were wrong with the same ten literals. The board is roughly
79% grass and water and both were near-poster chroma (S0.60 and S0.71), which
leaves the five armies — whose bodies are the design system's own saturated
tokens — nothing to be the colourful thing on. And every grey on the sheet was
the same grey lit and shaded (rock S0.05, stone S0.08, concrete S0.06, the
mountain's four faces S0.07-0.08): the colour of cut card, not of stone.

## What replaced them

A shadow tone is **built** from its lit tone by `terrain._shade`, which is
`palette._shape`'s dark-rung recipe — rotate the hue toward the sky, keep a
touch more chroma than the lit face, blend in AMBIENT — and then re-keyed onto
**the luma that tone was already authored at** by `terrain._at_value`.

That last step is what makes the pass safe to do wholesale. Every rule the
terrain palette is measured by is a rule about LUMA: `TERRAIN_VALUE_CEILING`,
`TERRAIN_MEDIAN_CEILING`, the ~18L steps between road, bridge and shoal,
`palette.GROUND_BAND` (which decides the outline grade before any tile
exists), `CANOPY_TOP` sitting one step under the dimmest plains pixel. Keying
the result back onto the old luma preserves all of them by construction; only
the hue and the chroma move. Chroma changes go through `terrain._tone`, which
is the same idea for a lit tone: an exact saturation at the tone's own luma.

`_shade` departs from `_shape` in one place. `palette._rotate` moves a hue
toward the sky the short way round the wheel, which is a sane 6-11° for grass
and water but meaningless for gravel and rock: they sit almost **opposite** the
sky, so a small rotation is a coin flip that lands on red and makes the shadow
warmer than the face casting it. Under `_SHADE_GREY = 0.20` a tone has no hue
worth defending, so its shaded face takes the sky's hue outright. That is where
the greys' temperature comes from: warm in the sun, cool in the shade.

## Before and after

Hue in degrees, S from HSV, L is `terrain.luminance` (Rec. 709).

| tone | before | H | S | L | after | H | S | L |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `GRASS` | (108, 181, 73) | 101 | 0.60 | 157.7 | (116, 177, 87) | 101 | 0.51 | 157.5 |
| `GRASS_DARK` | (81, 150, 54) | 103 | 0.64 | 128.4 | (88, 145, 79) | 112 | 0.46 | 128.1 |
| `CLUMP` | (94, 166, 64) | 102 | 0.61 | 143.3 | (102, 161, 83) | 105 | 0.48 | 142.8 |
| `CLUMP_DK` | (84, 154, 56) | 103 | 0.64 | 132.0 | (91, 149, 80) | 110 | 0.46 | 131.7 |
| `ROAD` | (146, 142, 133) | 42 | 0.09 | 142.2 | unchanged | 42 | 0.09 | 142.2 |
| `ROAD_DARK` | (115, 111, 103) | 40 | 0.10 | 111.3 | (108, 111, 120) | 225 | 0.10 | 111.0 |
| `TIMBER` | (150, 120, 87) | 31 | 0.42 | 124.0 | unchanged | 31 | 0.42 | 124.0 |
| `TIMBER_DARK` | (113, 90, 65) | 31 | 0.42 | 93.1 | (114, 89, 73) | 23 | 0.36 | 93.2 |
| `WATER` | (63, 143, 220) | 209 | 0.71 | 131.6 | (79, 140, 199) | 209 | 0.60 | 131.3 |
| `WATER_DARK` | (42, 111, 191) | 212 | 0.78 | 102.1 | (63, 106, 177) | 217 | 0.64 | 102.0 |
| `WATER_LIGHT` | (113, 179, 219) | 203 | 0.48 | 167.9 | (123, 177, 209) | 202 | 0.41 | 167.8 |
| `SAND` | (178, 166, 127) | 46 | 0.29 | 165.7 | unchanged | 46 | 0.29 | 165.7 |
| `SAND_DARK` | (150, 139, 106) | 45 | 0.29 | 139.0 | (145, 140, 108) | 52 | 0.26 | 138.8 |
| `SHADOW` | (16, 18, 24) | 225 | 0.33 | 18.0 | (16, 18, 24) | 225 | 0.33 | 18.0 |
| `ROCK[0]` rock_hi | (166, 161, 153) | 37 | 0.08 | 161.5 | (170, 161, 146) | 38 | 0.14 | 161.8 |
| `ROCK[1]` rock_lt | (148, 144, 137) | 38 | 0.07 | 144.3 | (151, 144, 130) | 40 | 0.14 | 144.5 |
| `ROCK[2]` rock_dk | (117, 113, 108) | 33 | 0.08 | 113.5 | (108, 114, 128) | 222 | 0.16 | 113.7 |
| `ROCK[3]` rock_deep | (98, 95, 91) | 34 | 0.07 | 95.3 | (91, 95, 108) | 226 | 0.16 | 95.1 |
| `MATERIALS.rock` | (145, 142, 138) | 34 | 0.05 | 142.3 | (150, 141, 129) | 34 | 0.14 | 142.0 |
| `MATERIALS.rock_dk` | (108, 106, 104) | 30 | 0.04 | 106.3 | (102, 106, 120) | 227 | 0.15 | 106.2 |
| `MATERIALS.stone` | (158, 154, 146) | 40 | 0.08 | 154.3 | (161, 154, 139) | 41 | 0.14 | 154.4 |
| `MATERIALS.stone_dk` | (122, 118, 111) | 38 | 0.09 | 118.3 | (114, 118, 133) | 227 | 0.14 | 118.2 |
| `MATERIALS.concrete` | (176, 174, 166) | 48 | 0.06 | 173.8 | (178, 174, 160) | 47 | 0.10 | 173.8 |
| `MATERIALS.concrete_dk` | (140, 138, 130) | 48 | 0.07 | 137.8 | (134, 138, 150) | 225 | 0.11 | 138.0 |
| `MATERIALS.asphalt` | (111, 116, 124) | 217 | 0.10 | 115.5 | (110, 115, 131) | 226 | 0.16 | 115.1 |

Every derived bank follows through `mix()` without being touched — this is not
a post-process over finished pixels, so `autotile`'s shores and edge tones are
still arithmetic on the constants above:

| tone | before | after |
| --- | --- | --- |
| `autotile.BANK` | (159, 163, 112) S0.31 L158.5 | (160, 162, 117) S0.28 L158.3 |
| `autotile.BANK_DARK` | (116, 156, 80) S0.49 L142.0 | (120, 153, 96) S0.37 L141.9 |
| `autotile.BANK_LIT` | (164, 164, 116) S0.29 L160.5 | (164, 163, 120) S0.27 L160.1 |
| `autotile.WATER_LIT` | (88, 161, 220) S0.60 L149.7 | (101, 158, 204) S0.50 L149.2 |
| `autotile.POND_BANK` | (108, 155, 74) S0.52 L139.2 | (113, 151, 92) S0.39 L138.7 |
| `terrain.CANOPY_TOP` | (102, 175, 73) S0.58 L152.1 | (109, 172, 84) S0.51 L152.3 |

Shadow hue rotation, lit tone to dark tone, after: grass **+11.2°**, water
**+7.9°**, sand **+6.0°**, timber -8.0° (rotated the short way, which for a
brown is toward red), and the greys snap to the sky's 225° outright.

## The gates, re-measured

Nothing here loosened a threshold; the full suite (206 tests) passes.

| gate | bar | before | after |
| --- | --- | --- | --- |
| `GroundSeparation` plains tone vs road/bridge/shoal, worst RGB distance | >= 40 | 73.6 | **62.1** |
| `GroundSeparation` field tone vs gravel, luma step | >= 15 | 18.1 | **15.3** |
| road / bridge / shoal value steps | >= 18 | 18.2 / 23.5 / 41.7 | unchanged (those three tones did not move) |
| `GroundContrast` GROUND_BAND pin, Rec. 601 of GRASS_DARK / GRASS / SAND_DARK / SAND | 118-166 | 118.4 / 146.9 / 138.5 / 165.1 | 120.4 / 148.5 / 137.8 / 165.1 |
| `GroundContrast` heavy row boundary tying in value, worst row x ground | <= 0.02 | 0.0061 (iron, shoal) | **0.0079** (both rows, plains) |
| `GroundContrast` same, worst single sprite | <= 0.04 | 0.0224 | 0.0224 |
| `GroundContrast` light row tying in value AND colour, worst row x ground outside `SAME_HUE` | <= 0.02 | 0.0015 | 0.0015 |
| `CanopyLight` lit plane over canopy | > 68 | 72.6 | 72.8 |
| plains tile median | < 165 | 156.0 | 155.8 |

The two heavy rows pay a little for the regrade: a desaturated grass sits
slightly deeper inside the band neutral and Iron are capped in, so their
plains boundary goes 0.56% -> 0.79% of pixels tying in value, against a bound
of 2%. The two open `SAME_HUE` pairs move with it in the same direction
(verdant on plains 12.2% -> 12.5%, aurora on shoal 7.9% unchanged) and stay
what they were: named defects, not a loosened rule. (Both were answered on
2026-08-24 by the rim outline grade, and `SAME_HUE` is gone — the row x ground
reading above is now taken over every non-heavy row with nothing set aside.)

The claims this pass makes — sky-lit shadows, the greys' temperature, the
chroma ceilings and the luma ladder that makes all of it safe — are pinned in
`tests/test_terrain_tones.py`, which fails on the old literals.

**The tight one is the field-vs-gravel step, at 15.3 against a bar of 15.0.**
It moved because desaturating a green at constant Rec. 709 luma changes which
of the field's tones wins the count over the tile's light half: the dominant
used to be a grain-lightened green at L160.3 and is now GRASS itself at L157.5.
Between the two AUTHORED tones the step is 15.5 and was 15.3 -- it is which
tone wins the count that moved, not the palette's spacing. Either way it is
0.3L of headroom, and the next pass that touches the grass has to re-measure
it.

## Two things this pass could not do cleanly

**GRASS is S0.51, not the S0.48 that was asked for.** `WoodsSeam` requires the
plains plate and the woods plate to be the same tones — they are one GRASS
under two grain salts — and the ±3% grain only rounds to the same 25 integers
on both salts for some values of GRASS. S0.48 misses by one tone at each end of
the band, which is a seam the test is right to refuse. S0.508-0.511 is the
admissible window nearest the target; the sweep's other windows are S0.404-0.438
and S0.532-0.536.

**`terrain.SHADOW` is now derived and comes out at exactly (16, 18, 24)** — the
literal it replaces. The cast shadow was already the sky's hue at a third of
its chroma; nothing said so, so it is now written as that. `voxel.SHADOW` is
the unit cells' copy of the same triple and still agrees byte for byte. If the
derivation is ever retuned, that constant has to move with it — the two are
meant to be one constant, and only live in two modules because `voxel` cannot
import `terrain`.

## Adjacent fix

`terrain._lit` caps a highlight at `TERRAIN_VALUE_CEILING` by scaling, and then
rounded three channels — which could put the tone back over the line it had
just been scaled onto. The grass tuft highlight landed at L175.04 after the
regrade. The ceiling is a hard "no pixel above it", so the channel that gained
most from rounding now gives its step back until the tone is under. On the old
palette the fix is a no-op; nothing was overshooting.

## Where the massif's four faces went (2026-08-23)

`terrain.ROCK`'s four tones are still authored here and still measured here,
but the mountain no longer paints with them: it is a voxel mass drawn out of
`palette.ROCK_RAMP`, one flat rung per oriented plane. The ramp is authored ON
this ladder — its four upper rungs land within 0.5L of ROCK's four faces —

| ramp rung | luma | the face it replaces | luma |
| --- | --- | --- | --- |
| `ROCK_RAMP[5]` rim | 162.9 | `ROCK[0]` rock_hi | 161.8 |
| `ROCK_RAMP[4]` top | 145.2 | `ROCK[1]` rock_lt | 144.5 |
| `ROCK_RAMP[3]` body | 117.7 | `ROCK[2]` rock_dk | 113.7 |
| `ROCK_RAMP[2]` shadow | 95.0 | `ROCK[3]` rock_deep | 95.1 |

— so a face that used to be painted `rock_lt` is still drawn at `rock_lt`'s
value, and the warm/cool split those literals carry is now `palette._shape`'s
doing. One thing had to be said out loud in the ramp that `_shape` cannot
infer: the three rungs below the body are built off a SKY-hued base rather
than off the warm stone. `_shape` mixes 7-26% of AMBIENT into a dark rung and
rotates its hue a fraction of `_HUE_ARC`, which is the right move for a tone
with chroma to defend and a coin flip for a grey — the same finding
`terrain._SHADE_GREY` records for the painted tones. `ROCK_RAMP[2]` comes out
at (90, 95, 110) against `ROCK[3]`'s (91, 95, 108).

## The massif drops the sheet's shadow (2026-08-23)

`terrain._contact_shadow` stamped the massif's silhouette in `GRASS_DARK`,
which is the grass's own shaded rim — the tone the tufts and the boulders shed
on the apron are drawn in — so the darkest pixel anywhere on the mountain tile
was its (30, 32, 36) outline. Every other raised thing on the board drops
`SHADOW` (16, 18, 24) at `voxel.SHADOW_OFFSET`: units through
`voxel.compose_cell`, buildings through `terrain._drop_shadow`. A massif
standing next to either of them read as flat-lit beside a hard shadow.

It drops the same tone now, at the same offset, with the same two clips it
already had (inside the cell, and never where the rock stands on it). Nothing
about the shadow's SHAPE moved, so `MountainPhases`' horizon reading is the
same row it was; only the tone the test picks the shadow out by changed, and
`OneSun`'s per-pixel caster reading is unaffected because it reads a difference
against the same tile drawn with no offset.

The woods keep `GRASS_DARK`: that fringe is a line under each crown's shaded
rim rather than one massing's cast silhouette, and the clearings between the
crowns are the plains plate `WoodsSeam` measures the tile on.
