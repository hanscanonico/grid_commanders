# Portrait Generator

Deterministic portrait pipeline for this game, living in the repository it feeds
(`generators/portraits`, an offline instrument the engine never sees — the
sibling `generators/.gdignore` keeps Godot out of it). It bakes the art
`scenes/common/commander_visuals.gd` loads: the **four 64x64 faction emblems**
today, and the **220x268 commander busts** once the painter modules below are
built.

There are **no seeds and no randomness**. Every mark is authored, so every run
reproduces the same bytes, and regenerating after an edit changes exactly the
art you edited.

## Outputs

| Generated | Installs into | What it is |
| --- | --- | --- |
| `factions/<key>.png` | `assets/portraits/factions` | 64x64 RGBA emblem, one per army |
| `commanders/<id>.png` | `assets/portraits/commanders` | 220x268 RGBA bust — **not emitted yet** |

`portraitgen/pipeline.py`'s `OUTPUTS` table is the one statement of what a run
produces; `install` derives its copy list from that same table, so there is no
second list to keep in step. Until the busts land, `tools/generate_portraits.gd`
still bakes them and `make portraits-check` is still their gate.

The four committed emblems are already, pixel for pixel, what this generator
draws — they were not reinstalled, so their bytes are still the engine's own
encode. Running `make portraits` re-encodes them with Pillow: no pixel moves,
but `make portraits-check`, which byte-diffs against the engine's bake, goes red
until that bake retires with the busts.

## Running it

```sh
make generators-venv     # once: builds the interpreter outside the checkout
make portraits           # generate, install into assets/portraits, reimport
make portraits-lint      # ruff check + ruff format --check
make portraits-test      # this package's own suites
make portraits-snapshot  # a fresh generation against the installed art
```

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
general; `portraitgen/roster.py` is the only per-general data. The stubs below
raise `NotImplementedError` until their slice lands, and every vocabulary is a
**dispatch table**: an unknown key raises rather than falling through to a
default.

| Module | Owns | Entry points |
| --- | --- | --- |
| `portraitgen/canvas.py` | the 3x surface, the primitives, the hard cast shadow | `Canvas.polygon/ellipse/stroke/rect`, `compose`, `silhouette`, `cast_shadow`, `resolve` |
| `portraitgen/light.py` | the key direction, the ramps, the rim, the AO | `KEY`, `Ramp`, `build_ramp(base)`, `rim_light(silhouette, ramp, weight)`, `occlusion(occluder, target, depth)` |
| `portraitgen/head.py` | skull, neck, ear | `Skull(width, jaw, crown, spread)`, `JAWS`, `outline(skull)`, `draw(canvas, skull, ramp)` |
| `portraitgen/features.py` | eyes, brows, nose, mouth, facial hair, worn accessories | `eyes`, `brow`, `nose`, `mouth`, `facial_hair`, `accessory`, `earring`, `freckles` |
| `portraitgen/hair.py` | the hair mass and its strand clusters | `STYLES`, `HAIR_COLOURS`, `draw(canvas, skull, style, ramp)`, `ramp_for(colour)` |
| `portraitgen/uniform.py` | shoulders, chest, collar cut, strap, rank pip | `COLLAR_CUTS`, `draw(canvas, faction, collar, ramp)`, `pip(canvas, ramp)` |
| `portraitgen/props.py` | the 22 signature props and their straps | `PROPS`, `SHOULDERED`, `draw(canvas, key, faction, ramp)` |
| `portraitgen/backdrop.py` | the window field, the treatment, the ink frame | `KINDS`, `OPACITY_BAND`, `draw(canvas, kind, faction)` |
| `portraitgen/roster.py` | the FACES table | `Face`, `FACES`, `SKIN_TONES` |

Draw order, all at 3x: backdrop, cast shadow, uniform mass, neck and head base,
the light pass, features, hair, prop, ink, then the downsample.

`Face` carries the roster's eighteen columns — `skin`, `hair`, `style`, `brow`,
`eyes`, `mouth`, `eye`, `facial`, `acc`, `collar`, `head`, `nose`, `pose`, `bg`,
`prop`, `pip`, `earring`, `freckles` — and each names its vocabulary's owner
above, so the table stays a transcription of `tools/commander_faces.gd` rather
than a re-art of it.

## Frame safety

`FACE_REGION` is `Rect2i(16, 25, 190, 190)` and the jaw must never clip it: the
shipped busts clear it by 12 to 21 pixels against a floor of 8, measured by
`tests/unit/test_commander_face.gd`. It is the hardest acceptance criterion here
and it is checked per bust — if one fails, the geometry moves, never the
constant, because the HUD chip, the speech bust and the campaign brief all read
that rectangle.
