# The terrain outline and the dither — 2026-08-22

Units are drawn out of six-slot ramps; terrain props and the five property
buildings still go through `voxel.render`, the shading path. (The buildings
left it later the same day — see `docs/properties.md`. Everything below still
describes the path the nature props draw on, and the numbers are the ones the
properties pass measured its own against.) Two of its
decisions were made per pixel rather than per material, and both of them spent
colours the way the pre-indexed units did.

**The outline was a neighbour average.** Every transparent pixel touching the
silhouette took the mean of its opaque neighbours and darkened it by 0.68. The
neighbours are shaded faces — top, left, right, ambient-occluded, dithered — so
one physical edge came out as thirty-odd near-blacks, none of them a step from
the next, and the "line" around a mass was a gradient nobody authored. It is
now **one deliberate tone per material**: `darken(resolve(mat), 0.55)`, taken
from the material rather than from the lit pixel beside it. Where two materials
meet along one edge the darker contour wins, so the line is a line rather than
a dotted seam of two.

0.55 is a *partial* grade, and deliberately lighter than the units' contour
band. A building is what an army is read **against**: its edge has to state the
shape without keying like a unit's. The tone still lands a clear step under the
material's own darkest face (the right face is 0.60 of the material), so the
line reads on every side of the mass.

**The dither was noise.** `DITHERED` materials got `(h01(x, y, 7) - 0.5) *
0.07` added to every top-face pixel — a continuous amplitude, so a top plane
cost one colour per distinct amplitude that landed on it, and it was applied to
every top regardless of size. Uniform dither at sprite scale is the failure
Gerstner names: on a 4px chimney cap or a sawtooth ridge it is not texture, it
is a chewed edge, and the board's 4:1 nearest downsample keeps one source pixel
in four, so which speckles survive is a function of phase.

It is now a dither: **two tones** — the face tone and one step under it
(`DITHER_STEP = 0.06`), chosen by the same hash — on **flat tops of at least
`DITHER_MIN_TOP_AREA = 96` painted pixels**. A plane is a 4-connected run of
same-material voxels at one z whose tops are open to the sky, and its area is
the union of the top faces it paints — a 12-voxel slab and a 12-voxel diagonal
ridge are the same voxel count and nothing like the same surface. Measured
across the prop set, the planes are:

| plane | area (px) | dithered |
| --- | --- | --- |
| airport hangar roof | 136 | yes |
| hq fort roof | 116 | yes |
| city tower top (large) | 96 | yes |
| city tower top (small) | 81 | no |
| base shed ridges (x3) | 61, 61, 56 | no |
| port warehouse roofs (x2) | 56, 56 | no |
| airport tower cap, hq parapets, ... | ≤ 56 | no |
| reef rock | — | no top plane at all |

96 is where the three genuinely broad roofs sit; nothing in the set reaches
144 (the 12x12 the research suggests), which is itself the finding — these
models have no surface large enough to carry a texture field, only three large
enough to carry a whisper.

## Palette counts, before and after

Distinct opaque colours, this branch against `main`.

| sheet | before | after |
| --- | ---: | ---: |
| `terrain_atlas.png` | 1455 | 517 |
| `preview_terrain.png` | 1457 | 519 |
| `preview_map.png` | 609 | 351 |

Per tile (the property tiles are per faction row, worst row shown):

| tile | before | after |
| --- | ---: | ---: |
| airport | 204 | 75 |
| hq | 188 | 71 |
| city | 165 | 66 |
| port | 164 | 58 |
| base | 95 | 43 |
| reef | 44 | 38 |
| every other nature tile | 24-73 | unchanged |

The nature tiles other than reef are drawn flat in `terrain.py` and never
touched the shading path, so they do not move; reef falls because its rock
outcrops are `voxel.render` props. `TerrainPalette.PROPERTY_CEILING` comes down
from **220 to 90** with that; the remaining spend is the shading arithmetic
itself — three computed tones per material, plus fractional occlusion and the
vertical gradient — which is the properties pass's to bring down, not this
one's. It did: 90 to 25, `docs/properties.md`.

The terrain value ceilings are untouched and still pass: the contour and the
dither's second tone are both *darker* than what they replaced, so nothing
moved toward the band the units key in.
