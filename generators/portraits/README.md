# Portrait Generator

Deterministic portrait pipeline for this game, living in the repository it feeds
(`generators/portraits`, an offline instrument the engine never sees — the
sibling `generators/.gdignore` keeps Godot out of it). It bakes the art
`scenes/common/commander_visuals.gd` loads: the **four 64x64 faction emblems**
and the **twenty-three 220x268 commander busts** — twenty-two generals and the
empty seat.

There are **no seeds and no randomness**. Every mark is authored, so every run
reproduces the same bytes, and regenerating after an edit changes exactly the
art you edited.

## Outputs

| Generated | Installs into | What it is |
| --- | --- | --- |
| `factions/<key>.png` | `assets/portraits/factions` | 64x64 RGBA emblem, one per army |
| `commanders/<id>.png` | `assets/portraits/commanders` | 220x268 RGBA bust, one per general plus `none` |

`portraitgen/pipeline.py`'s `OUTPUTS` table is the one statement of what a run
produces; `install` derives its copy list from that same table, so there is no
second list to keep in step. Nothing else bakes this art: the GDScript pipeline
that drew the busts as SVG is gone, and `make portraits` is the whole bake.

## Running it

```sh
make generators-venv     # once: builds the interpreter outside the checkout
make portraits           # generate, install into assets/portraits, reimport
make portraits-lint      # ruff check + ruff format --check
make portraits-test      # this package's own suites
make portraits-snapshot  # a fresh generation against the installed art
```

## What the suites hold

`tests/test_metrics.py` is the style brief's own bars as measurements over the
sheet this generator emits — the cast shadow lands outside every silhouette,
four value bands inside each, at most 48 painted tones, one light polarity on
all twenty-two faces, the collar and chest budgets, the mouth that cannot
outrank the eyes, and the chip-size silhouette distinctness. `tests/test_face_region.py`
is the hardest of them: `CommanderVisuals.FACE_REGION` parsed out of the game's
own source and every general's chin measured against it. If a bust fails it,
**the geometry moves — never the rectangle**, which the HUD chip, the speech
bust and the campaign brief all read.

`tests/preview_sheet.py --part sheet` is the reviewer's look: all twenty-three
busts at 220 over one row per faction, and the 31px face-crop strip under them.

`make portraits` re-imports because a PNG whose `.import` Godot has never seen
is baked with **mipmaps off**, and the portraits are the one art in the game
sampled `TEXTURE_FILTER_LINEAR_WITH_MIPMAPS`. Replacing the *content* of a
committed PNG is safe — Godot keeps the existing `.import` — but a **new**
commander writes a fresh one, and `tests/unit/test_commander_portraits.gd`
is what catches it.

The snapshot gate compares **pixels**, not bytes: the committed PNGs may have
been encoded by a different Pillow than yours. Byte determinism is a separate
claim, checked by generating twice and diffing the two directories. It fails in
**both** directions — a generated file with no committed twin, and a committed
file the generator no longer emits.

## The rendering stack

Pillow alone, pinned at both ends (`requirements.txt`), drawing at **3x** and
downsampling once to 220x268 with a box filter. `ImageDraw` has no
antialiasing of its own; the downsample is where the smooth edge comes from, and
a plain box average at an exact integer ratio is reproducible on any machine
Pillow runs on and does not ring on hard ink edges. `portraitgen/canvas.py` is
the only place a float coordinate becomes an integer, so no edge can move by a
pixel between two machines' libm.

The emblems are the deliberate exception: they are axis-aligned and 45-degree
shapes, so `portraitgen/emblem.py` draws them at 1x with integer geometry, which
is what keeps the committed PNGs pixel for pixel what they already were.

## Palette discipline

- **Four flat named tones per material** — deep, shade, base, lit — plus a rim.
  A band is a tone taken from a ramp, never an alpha wash over a fill.
- **One light**, upper-left, fixed sheet-wide. A mirrored pose flips the
  geometry, never the light; the cast shadow keeps its one offset too.
- **Three ink weights and no others** (`INK_SILHOUETTE` 4 / `INK_FEATURE` 3 /
  `INK_DETAIL` 2), so a scar can never come out as heavy as a jaw.
  `Canvas.stroke` refuses any other width.
- **At most 48 unique colours** in a finished raster.
- Faction colour comes from `portraitgen/palette.py`, which mirrors the game's
  own `FactionTheme` — `tests/test_palette_mirror.py` reads the values back out
  of `scenes/common/commander_visuals.gd` and fails loudly on a rename.

## Module contracts

The painter is layered, and each module owns one layer. Generic modules own no
general; `portraitgen/roster.py` is the only per-general data and
`portraitgen/bust.py` the only place a row becomes a picture. Every vocabulary
is a **dispatch table**: an unknown key raises rather than falling through to a
default.

| Module | Owns | Entry points |
| --- | --- | --- |
| `portraitgen/canvas.py` | the 3x surface, the primitives, the hard cast shadow | `Canvas.polygon/ellipse/stroke/rect`, `compose`, `silhouette`, `cast_shadow`, `resolve` |
| `portraitgen/light.py` | the key direction, the ramps, the rim, the AO | `KEY`, `Ramp`, `build_ramp(base, rim_hue=)`, `shade_kind`, `face_shade`, `face_light`, `TERMINATORS`, `rim_light(silhouette, ramp, weight=, inset=, scale=, mirrored=)`, `occlusion(occluder, target, depth=, scale=, mirrored=)` |
| `portraitgen/head.py` | skull, neck, ear, the skin ramps | `Skull(width, jaw, crown, spread)`, `JAWS`, `SKIN_BASES`, `ramp_for(skin)`, `outline(skull)`, `skull_box(skull)`, `draw(canvas, skull, ramp, mirrored=)` |
| `portraitgen/features.py` | eyes, brows, nose, mouth, facial hair, worn accessories | `eyes(…, scale=)`, `brow`, `nose`, `mouth`, `facial_hair`, `accessory(…, tint=)`, `earring`, `freckles` |
| `portraitgen/hair.py` | the hair mass and its strand clusters | `STYLES`, `HAIR_COLOURS`, `ramp_for(colour)`, `back`, `front(…, skin=)`, `draw(…, skin=)` |
| `portraitgen/uniform.py` | shoulders, collar cut, chest treatment, rank pip | `COLLAR_CUTS`, `CHEST_TREATMENTS`, `draw(canvas, faction, collar, ramp)`, `chest(canvas, treatment, faction, ramp)`, `pip(canvas, ramp)` |
| `portraitgen/props.py` | the 22 signature props and their rigs | `PROPS`, `SHOULDERED`, `RIGHT_LIMIT`, `draw(canvas, key, faction, ramp, layer=)` |
| `portraitgen/backdrop.py` | the window field, the treatment, the ink frame | `KINDS`, `OPACITY_BAND`, `field`, `treatment`, `frame`, `draw(canvas, kind, faction)` |
| `portraitgen/roster.py` | the FACES table | `Face`, `FACES`, `NEUTRAL`, `SKIN_TONES` |
| `portraitgen/bust.py` | the draw order, the pose, the frame safety | `paint(spec, cast=)`, `window(spec)`, `prop_art(face)`, `busts()`, `FACTION_OF` |

The keyword-only arguments above are the seams the layers are composed through:
`layer=` splits a prop into the half behind the figure and the rig in front,
`skin=` is what the hair fringe casts its band in, `tint=` dresses a bandana or
a headset cup in the general's own faction cloth, and `mirrored=` pre-flips the
light for a layer the pose is about to turn over.

Draw order, all at 3x, in `bust.py`: backdrop, then the figure — prop behind,
hair behind, uniform and collar, head, features, hair over, prop in front — then
the pose over the whole figure, the hard cast shadow under it, and the
downsample. Each layer inks itself as it is laid down.

`Face` carries nineteen columns — `skin`, `hair`, `style`, `brow`, `eyes`,
`mouth`, `eye`, `facial`, `acc`, `collar`, `chest`, `head`, `nose`, `pose`,
`bg`, `prop`, `pip`, `earring`, `freckles` — and each names its vocabulary's
owner above. Eighteen of them are the retired GDScript table's own; `chest` is
the one this pipeline added, because that table wore one diagonal sash five
times over.

## The pose, and what a mirror may turn

Tilt and zoom are one affine over the working raster, its coefficients rounded
before they are used so that no libm's cosine can move an edge by a pixel, and
sampled nearest — the downsample stays the only place a tone is blended.

A mirrored pose flips **geometry, never light**. Only the layers carrying a
face's asymmetry turn: the hair and the head with its features. The uniform,
the props and the window never do, so the shoulder the sheet is lit on is the
same shoulder on all twenty-three busts — which is what
`tests/unit/test_commander_portraits.gd` measures off the shipped PNGs. Inside
the flipped group the light is pre-flipped, so it lands on the screen's shadow
side once the group is turned over.

A shoulder is meant to bleed off the side of the raster; a signature prop is
not. `props.RIGHT_LIMIT` is stated in portrait pixels and the zoom is applied
after it, so `bust.py` walks a prop that would cross the line back inside it,
both halves together, before the pose.

## Frame safety

`FACE_REGION` is `Rect2i(16, 25, 190, 190)` and the jaw must never clip it: the
shipped busts clear it by 12 to 21 pixels against a floor of 8, measured by
`tests/unit/test_commander_face.gd`. It is the hardest acceptance criterion here
and it is checked per bust — if one fails, the geometry moves, never the
constant, because the HUD chip, the speech bust and the campaign brief all read
that rectangle.
