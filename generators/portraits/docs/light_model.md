# The light model

One sun, four flat tones per material, and a rim. This is what
`portraitgen/light.py` owns and what every painted layer asks it for; the head
in `portraitgen/head.py` is the first caller and the shape of the rest.

## One light, and it never turns

The key is upper left, stated once as `light.KEY` and agreeing with the board's
own sun in `generators/sprites/spritegen/sun.py`. Everything the key does not
reach falls **down and to the right** (`light.SHADOW_STEP`), on every bust,
mirrored poses included: a pose flips geometry, never light. The cast shadow
obeys the same rule from `portraitgen/canvas.py` — the figure's silhouette at
+6 portrait pixels, `#000` at 0.30, one flat tone, zero blur.

`tests/test_geometry.py` reads that back the way the game does: the lit patch
`(22, 242, 12, 12)` against the shaded patch `(186, 242, 12, 12)` with a floor
of 0.01, the rectangles and the floor
`tests/unit/test_commander_portraits.gd` measures the shipped sheet with.

## Four tones, built rather than typed

`build_ramp(base, rim_hue=…)` returns `deep`, `shade`, `base`, `lit` and `rim`.
Values step on one authored ladder as multiples of the base's own luma; the
chroma over it is ported from `generators/sprites/spritegen/palette.py`:
saturation peaks in the middle and collapses toward the light, the two shadow rungs mix toward one
cool ambient, and hue rotates a little toward the sky in shadow and the sun in
light. Six literal hexes drift into one hue at six brightnesses, which is the
flattest a ramp can be — so a ramp is never typed out.

The rim is the one rung that keeps its chroma. It is the faction's **light**
tint re-keyed to the rim's value, so the band that separates a green bust from
a green field costs the palette no new hue. `rim_light` lays it 2.5 portrait
pixels wide along the shadow-side silhouette run, walked in under the
silhouette ink so it reads as light on the form rather than as a second
outline.

Ramps are cached (`functools.lru_cache`): a bust asks for the same handful on
every layer. One stand-in bust renders in about 15 ms on the dev machine —
two orders under the 2 s the plan's runtime risk allows — so the supersample
stays where it is.

## Occlusion is a hard band, not a blur

`occlusion(occluder, target, depth=…)` steps the occluder's mask away from the
key and intersects it with what is under it. The caller paints the target's
`deep` tone through the mask it returns, so an occluded band is a named tone
like every other mark. There is no blur anywhere in this package: the design
system's shadows are `4px 4px 0`, and a gradient is the one thing this style
does not own. The head's call site is the jaw onto the neck and the skull onto
the ear; the hair fringe and the collar are the same pass at their own layers.

## Three face shades, and none of them down the nose

`shade_kind(crown, width)` picks one of three geometries off the roster's own
`head` column, so the sheet does not wear one shade shape twenty-two times:

| Shape | Taken when | What it is |
| --- | --- | --- |
| `brow_socket` | `crown >= 1.0` | the shadow a lifted, heavy brow casts into the socket |
| `jaw_under` | `width >= 1.06` | the mass under the cheek along a wide jaw |
| `cheek_wedge` | otherwise | the cheekbone-to-jaw wedge |

Every shape starts at least `NOSE_AXIS_CLEARANCE` of a half-width out from the
face's centre line — outside the nose and the mouth — because a boundary
running down the nose-mouth axis reads as a two-tone mask rather than as a lit
head, and each one closes on its own horizontal run (`TERMINATORS`, in skull
heights from the crown) so the shade ends as a plane turning away from the
light rather than as a line drawn down the face. `face_light` is the one shape on
the key side — a single band across the forehead and cheekbone, not a mirror of
the shade, so the two sides of a face are never the same drawing.

## What the head module hangs on it

`head.Skull(width, jaw, crown, spread)` is the roster's `head` column exactly.
The geometry is the handoff's own, moved into portrait pixels: the handoff drew
a 110x134 viewBox with its origin at y -14 and the pinned raster is 220x268, so
a handoff x is `2x` and a handoff y is `2(y + 14)`. Nothing was re-authored in
the move.

`head.draw` paints in the light's own order — neck and ears, the face, the two
bands the key writes on it (both through the face's own mask, so a shade cannot
run off the cheek onto the field), the occlusion band, the silhouette ink, then
the rim inside it. An unknown jaw raises, as does an unknown shade kind and an
unknown band name: the vocabulary is the dispatch table.

## Two numbers this model does not meet head-on

- **Unique colours.** The brief's bar is 48 RGBA per raster. A 3x box
  downsample blends across every edge it smooths, so a finished raster carries
  a few hundred values whatever it is painted in — the stand-in row measures 202 to 213
  against the shipped sheet's 528 to 2,877. The bar is therefore read as what
  it was written for: `tests/test_geometry.py` counts the tones a raster is
  *painted* in — colours covering at least a thousandth of it — and holds that
  to 48.
- **Jaw clearance.** The skull sits where the handoff put it, so a bust's chin
  clears `FACE_REGION` by the pose's own zoom. That measurement is the busts'
  slice, not this one; nothing here may move `FACE_REGION`.
