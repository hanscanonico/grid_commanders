# The plains field: clumps instead of grain — 2026-08-22

Plains is roughly 78% of a Grid Commanders map, and it was a flat rectangle
of one green. Measured on the atlas tile before this pass:

| | before | after |
| --- | --- | --- |
| tile luma sd | 4.5 | 9.70-9.95 (per phase) |
| pixels within 8L of the tile mean | 97.9% | 55-75% |
| tile median | L157.7 | L156.0 |
| phase-to-phase difference | five translations of one tuft table, tile means within 0.31L | five different clump layouts, 8-33% of their clumped area shared |

The ±3% per-block grain was doing none of that work and could not: it is a
wobble of a couple of luma steps, and the game draws the board at a 4:1
nearest downsample, which averages a wobble away. What survives a downsample
is a SHAPE, so the field is now two tones — GRASS with a darker grass clumped
over 30% of the tile in 4px blocks.

## How the field is built

`terrain._grass_ground(salt)` draws `_ground(GRASS, salt)` and then paints the
clumps over it:

- `_clump_field` is a smooth value field on a 16px lattice — four nodes across
  the cell, indexed modulo 4, so the field **wraps** and repeated tiles still
  butt seamlessly — roughened by the block's own hash so a clump's edge is
  ragged instead of a circle. Every term is `palette.h01`; there is no
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
that rule is retired: **four of the five phases carry a find**, and phase 0
stays bare only because it is the atlas column, the tile a board that has not
adopted the sheet draws everywhere. `tests/test_plains_phases.py` states the
replacement — clump coverage per phase, a floor under the field's sd, and no
two phases laying their clumps the same way.

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
