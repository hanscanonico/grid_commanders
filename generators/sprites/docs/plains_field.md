# The plains field: clumps instead of grain — 2026-08-22

Plains is roughly 78% of a Grid Commanders map, and it was a flat rectangle
of one green. Measured on the atlas tile before this pass:

| | before | after |
| --- | --- | --- |
| tile luma sd | 4.5 | 9.87-10.07 (per phase) |
| pixels within 8L of the tile mean | 97.9% | 44-66% |
| tile median | L157.7 | L156.0 |
| phase-to-phase difference | five translations of one tuft table, tile means within 0.31L | eight different clump layouts, 23-33% of their clumped area shared |

The ±3% per-block grain was doing none of that work and could not: it is a
wobble of a couple of luma steps, and the game draws the board at a 4:1
nearest downsample, which averages a wobble away. What survives a downsample
is a SHAPE, so the field is now two tones — GRASS with a darker grass clumped
over 30% of the tile in 4px blocks.

## How the field is built

`terrain._grass_ground(salt)` draws `_ground(GRASS, salt)` and then paints the
clumps over it:

- `_clump_field` is a smooth value field on a lattice of four nodes to a
  period, indexed modulo 4, so the field **wraps** — roughened by the block's
  own hash so a clump's edge is ragged instead of a circle. (The period was the
  64px cell, which wraps one phase against itself and nothing else; see round
  two below.) Every term is `palette.h01`; there is no
  randomness anywhere.
- Coverage is fixed by **rank**, not by a threshold on the field: the darkest
  12% of a tile's blocks take `CLUMP_DK` and the next 18% take `CLUMP`. With
  only four lattice nodes across a tile, an absolute cut gave one salt 4%
  coverage and another 43%; ranking makes every phase and both plates the same
  field in a different arrangement.
- A clump is **flat**. A clump is meant to read as a shape at the board's rung,
  which a grain inside it only blurs, and a grained clump spends a colour per
  rung — woods measured 88 colours that way, over the 80-colour
  `TerrainPalette.NATURE_CEILING`. Flat costs the plate exactly two tones.

`CLUMP` (L143) and `CLUMP_DK` (L132) are mixes of GRASS toward GRASS_DARK, so
they keep the saturated green hue that `GroundContrast`'s COLOUR_BREAK relies
on, and they sit **inside** `palette.GROUND_BAND` — darker than GRASS, lighter
than the GRASS_DARK tuft tone. That matters: the band is what `voxel.render`
picks a silhouette's outline grade out of before any tile exists, so a clump
cannot present a unit with a ground value the renderer did not already plan
for. Measured over every sprite and pose on plains, before -> after: Iron and
neutral 0.56% -> 0.61% of their boundary tied in value, verdant 14.86% ->
15.05%, aurora 15.30% -> 15.50%. The gates are 2% per row for the heavy grade
and colour distance for the light rows, and both hold.

The field **darkens only**. The median stays on a GRASS grain tone, so the
`TERRAIN_MEDIAN_CEILING` headroom is untouched.

Plains, woods and the mountain's apron all draw this plate. Roads, rivers and
the autotile variants inherit it through `plains()`. The mountain was included
because a flat-green apron next to a clumped field is the same lighter-cell
seam the woods plate was fixed for in the first place.

## The doctrine that changed

`PLAINS_PHASES` used to be five translations of one tuft grid, three of them
carrying nothing at all, so a decal was the only thing that told two phases
apart — and the table therefore held decals rare on purpose ("most of the
table is bare"). The clump field is what a stretch of field varies by now, so
that rule is retired: **all but one phase carries a find**, and phase 0 stays
bare only because it is the atlas column, the tile a board that has not adopted
the sheet draws everywhere. The table went to **eight** phases on 2026-08-23
for the reason it has one at all — the boards are ~56% plains, so five variants
still recur often enough for the eye to find the fleck at the same in-tile
position across the lattice. The three added phases (salts 31, 253, 316) are
salt variants of the same field: nothing in the painter moved, so their
coverage, tone count and clump-layout overlap sit inside the bounds the first
five are measured against. `tests/test_plains_phases.py` states the replacement
— clump coverage per phase, a floor under the field's sd, and no two phases
laying their clumps the same way.

## Two measurements restated, and one left open

Neither is a threshold change; both are the same question asked of a
two-tone ground.

1. **`WoodsSeam`**. The plate is `_grass_ground` now rather than `_ground`, so
   "the woods plate is the plains plate" and the clearing count are read
   against the whole grass palette, clumps included (the clearing floor of 300
   px is untouched; the thinnest variant cleared 389 and clears 465 since
   the de-shingling pass). The value BAND a woods pixel may not cross stays the FIELD tone's band — the grain over
   GRASS, without the clumps — because the canopy's lit top plane is authored
   one luma step under that floor, and folding a darker tone into the band
   would drop it past CANOPY_TOP and stop measuring anything.
2. **`GroundSeparation`**. `dominant()` over the tile now returns whichever of
   the field's two tones wins the count, which is not the tile's read. The
   plains clause is stated on the **field tone** — `dominant()` over the light
   half of the tile, the same number it returned before on a one-tone ground —
   and the colour clause is now asked of **every** tone the field is made of
   rather than only the commonest, which is strictly more than it asked.

**Open, measured, not hidden:** a `CLUMP` block (L143) ties in VALUE with the
gravel of a road (L142); only its hue (RGB distance 89) separates them. The
field tone still clears gravel by 15.7L, which is what the test holds, but the
dark half of the field does not. Any darkening of plains costs some of the
plains-vs-road value step — the tile mean fell from L156.9 to L151.4 against
road's L140.4 — and the alternative was keeping the flattest ground on the
board flat. The `SAME_HUE` verdant-on-plains exemption was re-measured over
the same boundaries and did not move: 12.2% of the boundary ties in both value
and colour, the same figure to the same decimal as before this pass. The
clumps are a value variation inside a hue that exemption already names.
(The exemption itself is gone as of 2026-08-24: verdant answers the grass with
`OUTLINE_RIM` now and ties on 0.39% of its boundary — docs/outlines.md.)

## Round two: seamless, indexed, on-ramp — 2026-08-23

The clump field above wraps at the cell, and the visual-QA pass measured what
that is worth on a board: nothing. The game does not repeat one phase, it
**hashes a phase per cell**, so what actually butts is phase 3's right edge
against phase 1's left — two different fields cut off at the border. On a
synthetic 8x8 field of hashed phases:

| mean \|luma step\| | before | after |
| --- | --- | --- |
| across a 64px boundary, horizontal | 9.58 | 0.00 |
| across a 64px boundary, vertical | 9.68 | 0.00 |
| inside a tile | 1.89 / 2.03 | 2.10 / 2.19 |
| seam : interior | 5.1x / 4.8x | 0.0x |

Two other measurements from the same pass, both about tones rather than shapes:
one plains tile carried **29 colours, 28 of them green**, 17 inside a single
0.03 slice of luma — the ±3% grain was a continuous mix per 4px block, so the
tile spent a colour per block. And the decals were drawn out of the grounds
they depicted: gravel (H41 S0.09) for a stone, its shadow (H225), the
wildflower (H40 S0.73). At 1-3px on a hue-100 field those are not a stone and a
flower, they are three dead pixels.

### The shared border ring

Two tiles can only butt with no step if their edges are the **same pixels**, so
every phase carries one:

- The outermost 4px block ring is drawn from a single shared field
  (`_SEAM_SALT`), grain and clumps both, and it is the same ring in every phase
  and on both plates.
- That field has a period of **60px — fifteen blocks** — so block column 15
  starts at x=60 and reads the same value as block column 0. The two blocks that
  meet at a seam are one block. The period is the field's own rather than a
  duplicated column, which is what keeps the ring smooth against the interior.
- Behind it, each phase's own field **dithers** in over `_SEAM_FADE` blocks: a
  block takes its own field or the shared one by its own hash. The first
  attempt averaged the two, and averaging halves the variance a rank is taken
  over — every phase then put its darkest blocks in the middle of its tile and
  drew a sparse frame around every cell, which is the quilt this pass exists to
  remove.
- Coverage is still exact: the ring spends some of the tile's fixed clump
  budget and the interior is ranked to whatever is left, so every phase spends
  the same number of blocks on each tone (29.0-29.6% of the tile, as before).

What it costs is that a fifth of a tile's clumps are laid the same way in every
phase — a floor of ~0.15 under any two phases' layout overlap. The seven free
salts were picked for the interiors that agree least: the worst of the 28 pairs
is 0.33 against the `MAX_LAYOUT_OVERLAP` bar of 0.40, which did not move. The tufts
stopped wrapping around the tile for the same reason the ring exists — a tuft
cut at one phase's edge met another phase's uncut one — and are now folded
inside the cell, all twelve of them, in every phase.

### Six greens and a three-step grain

`_grain` picks one of three tones — the base, `_lit` by 3%, `darken`ed by 3% —
instead of mixing one per block. The texture is the same (the hash still
decides which block is lighter); what changes is that the field is a set of
authored tones rather than a spray of near-duplicates. Measured per plains
phase: **7, 10, 11, 11, 10 colours** against 29-33, under a new
`MAX_TILE_COLOURS` ratchet of 14. `_ground` is shared, so every ground on the
sheet came down with it: the terrain atlas averages **9.4 colours a cell**
against 27.8, and the woods tile 13 against a `NATURE_CEILING` of 80.

The plate's tones are now exactly six greens plus what a decal spends: GRASS
and its two grain steps, `CLUMP`, `CLUMP_DK`, and the `GRASS_DARK` tuft.

### Decals on the field's ramp

The wildflower pair is gone from the field — four pixels of H40 and H214 on a
hue-100 ground — and the three decals are drawn in grass's own hue, held under
S0.45 (`DECAL_HUE_ARC`, `DECAL_MAX_SAT`):

| find | tones | hue / sat |
| --- | --- | --- |
| pebble | `_STONE` L152, `_STONE_DK` L120 | H100 S0.10 / S0.15 |
| tussock | `_LEAF` L105, `_BLADE` L174 | H112 S0.44 / H100 S0.38 |
| dry patch | `_DRY` L147, `_DRY_DK` L127 | H80 S0.34 / S0.38 |

The dry patch leans 20° toward sand — as far as the arc allows — so a worn
patch still reads as ground worn thin rather than as another clump. Every
phase but one still carries a find; phase 0 is still the atlas column and still
bare.

### What did not move

`TERRAIN_MEDIAN_CEILING` (the tile median is L153.1, as it was),
`GroundContrast`, the `GroundSeparation` 15.0 bar (field-vs-gravel measures
15.33, the same figure as before this pass — the field tone is untouched), the
`WoodsSeam` plate identity and its 300px clearing floor, and
`MAX_LAYOUT_OVERLAP`. No threshold in `tests/` was loosened for this pass; two
were added.
