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

The rim is the one rung that keeps its chroma, and **only the coat spends it.**
It used to be the faction's light tint on every material, laid one texel wide
along the shadow-side silhouette run of the head, walked in under the silhouette
ink. On a 110-pixel bust that is one texel of a colour the face does not own,
between a two-texel outline and the cheek: a near-white line down an Iron jaw, a
mint one down a Verdant neck, both broken into specks by the quantiser. The
round-2 review read them as fleck halos and it was right. The head's rim band is
gone; `uniform` keeps a kicker along the lit run because two texels of it fit
(`Canvas.ribbon`), and a material with no rim of its own now takes its own lit
rung, so `Ramp.rim` is still a tone the bust already spends.

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
The geometry is the handoff's own, moved into the design space every module
states its coordinates in: the handoff drew a 110x134 viewBox with its origin at
y -14 and the design space is 220x268, so a handoff x is `2x` and a handoff y is
`2(y + 14)`. Nothing was re-authored in the move — and the bust is baked back at
the handoff's own 110x134, one pixel to two design units (`canvas.BUST_DIVISOR`).

`head.draw` paints in the light's own order — neck and ears, the face, the two
bands the key writes on it (both through the face's own mask, so a shade cannot
run off the cheek onto the field), the occlusion band, then the silhouette ink.
An unknown jaw raises, as does an unknown shade kind and an
unknown band name: the vocabulary is the dispatch table.

## Two numbers this model does not meet head-on

- **Unique colours.** The bar is sixteen opaque tones per raster, and every one
  of them a rung `palette.bust_palette` handed this bust. There is no
  downsample left to blend an edge, so the count is a plain count:
  `tests/test_geometry.py` and `tests/test_metrics.py` both read it straight off
  the raster. A ramp built here that a bust does not spend a slot on is snapped
  onto one that it does, so this model may not invent a material.
- **Jaw clearance.** The skull sits where the handoff put it, so a bust's chin
  clears `FACE_REGION` by the pose's own zoom. That measurement is the busts'
  slice, not this one; nothing here may move `FACE_REGION`.
