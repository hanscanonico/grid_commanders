# Portrait Generator

Deterministic portrait pipeline for this game, living in the repository it feeds
(`generators/portraits`, an offline instrument the engine never sees — the
sibling `generators/.gdignore` keeps Godot out of it). It bakes the art
`scenes/common/commander_visuals.gd` loads: the **five 64x64 faction emblems**,
the **twenty-three 110x134 commander busts** — twenty-two generals and the empty
seat — and the **twenty-three 31x31 face chips** the surfaces too small for a bust
draw.

The busts are **pixel art**: authored on their own small grid, painted in
sixteen tones off the board's own ramps, and drawn by the game at a whole-number
scale with nearest sampling. Nothing is supersampled and nothing is resampled —
what this tool rasterises is what the screen shows, texel for pixel.

There are **no seeds and no randomness**. Every mark is authored, so every run
reproduces the same bytes, and regenerating after an edit changes exactly the
art you edited.

## Outputs

| Generated | Installs into | What it is |
| --- | --- | --- |
| `factions/<key>.png` | `assets/portraits/factions` | 64x64 RGBA emblem, one per army |
| `commanders/<id>.png` | `assets/portraits/commanders` | 110x134 RGBA bust, one per general plus `none` |
| `faces/<id>.png` | `assets/portraits/faces` | 31x31 RGBA face chip, that same drawing repainted on the chip grid |

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
four value bands inside each, **sixteen painted tones and every one of them a
rung this bust was given**, one light polarity on all twenty-three, the collar
and chest budgets, the mouth that cannot outrank the eyes, and the chip-size
silhouette distinctness. The light is read off the two shoulders rather than off
a cheek: at sixteen tones a scar or a strap lands on the very rung a cheek is
painted in, and the coat is the one surface every general wears unbroken.

`tests/test_gauge.py` is the newest: the **minimum feature gauge**, measured.
Its bar is that **no bust holds an orphan cluster** — an opaque run of one tone
with no two-by-two square of its own and no more than two pixels in it. That is
what a mark thinner than a texel comes back as once the raster is quantised, and
it was the same defect under four names on the round-2 review: a dotted headset
cable, a dotted monocle chain, a row of stitching that had become ticks, and
opaque fleck halos strung along five silhouettes.

`tests/test_face_region.py` is the hardest of them: `CommanderVisuals.FACE_REGION`
parsed out of the game's own source, every general's chin measured against it,
and every chip checked to be that rectangle of that general's own drawing. If a
bust fails it, **the geometry moves — never the rectangle**, which the HUD chip,
the speech bust and the campaign brief all read.

`tests/preview_sheet.py --part sheet` is the reviewer's look: all twenty-three
busts over one row per faction, and the face-chip strip under them.
`--part board` is the one that answers "is this one style?": every bust beside a
strip of the board's own art — 16px terrain cells, 64x96 unit cells — at one
shared zoom.

`make portraits` re-imports because a PNG whose `.import` Godot has never seen
is baked with a default one. The busts and the chips want **no mip chain**: they
are sampled `TEXTURE_FILTER_NEAREST` at a whole-number scale, and there is no
level between the rungs to sample. The emblems keep theirs — a 64px badge drawn
at 22 has no whole rung under it. Replacing the *content* of a committed PNG is
safe, Godot keeps the existing `.import`, but a **new** commander writes a fresh
one and `tests/unit/test_commander_portraits.gd` is what catches it.

The snapshot gate compares **pixels**, not bytes: the committed PNGs may have
been encoded by a different Pillow than yours. Byte determinism is a separate
claim, checked by generating twice and diffing the two directories. It fails in
**both** directions — a generated file with no committed twin, and a committed
file the generator no longer emits.

## The rendering stack

Pillow alone, pinned at both ends (`requirements.txt`), drawing **at 1x** onto
the grid the file is baked at. The only other thing this package needs is the
sibling instrument it shares a palette with: `portraitgen/palette.py` loads
`generators/sprites/spritegen/palette.py` — stdlib-only — straight off its
path, so a bust and a tank come off one set of ramps. `ImageDraw` has no antialiasing of its own, and
nothing here adds any: a bust is hard-edged because every mark is rasterised on
the raster it ships as.

Every module states its geometry in one **design space** — 220x268, the
handoff's viewBox doubled — and `portraitgen/canvas.py` divides it onto a grid:
`BUST_DIVISOR` 2 for the bust, `CHIP_DIVISOR` 6 for the face chip. That is the
only place a design unit becomes a pixel, which is why a chip is the same
drawing rasterised coarser rather than a bust sampled down.

Integer coordinates were not enough on their own. Pillow's polygon fill and its
wide line work their own geometry out in C — a float32 slope and a
multiply-and-add per scan line, a libm `hypot` for a line's corners — and arm
compilers fold a multiply and an add into one instruction where x86-64 ones do
not. A crossing that lands exactly on a pixel boundary then falls either side of
it, which is how two busts came out a pixel apart on CI while every local
regeneration was clean. So neither is used: `portraitgen/raster.py`'s `spans`
says which whole pixels a polygon covers, in whole numbers, and `Canvas.stroke`
walks a segment's own pixels by Bresenham instead of handing Pillow a width.
The art is identical on macOS/arm64, Linux/arm64 and Linux/x86-64.

The emblems are the deliberate exception: every shape there is decided by an
integer distance test, so `portraitgen/emblem.py` draws them at 1x with integer
geometry, which is what keeps the committed PNGs pixel for pixel what they
already were.

## Palette discipline

- **Sixteen tones per bust**, and every one of them off the board's own ramps
  (`generators/sprites`): the ink, the army's six rungs, four of skin, three of
  hair and two of gunmetal. `palette.bust_palette` hands them out and
  `palette.quantise` snaps the finished raster onto them, so a blend has
  nowhere to come from.
- **Four flat named tones per material** — deep, shade, base, lit — plus a
  rim. A band is a tone taken from a ramp, never an alpha wash over a fill.
  The window's own bands are rungs too: the field is the army's shadow rung
  and the treatments step down from it. **Two materials cannot afford all four
  on a sixteen-tone bust and do not get them**: hair ships three rungs and
  gunmetal two (`palette.HAIR_SLOTS`, `METAL_SLOTS`), so their deep — and the
  metal's shade — quantises onto the rung above. The four-tone model is what
  `light.Ramp` hands a painter; what a *bust* is measured on is four value
  bands over the whole figure (`tests/test_metrics.py FourValueBands`) and the
  per-material budget itself (`ThePaletteIsSpentPerMaterial`). Buying hair its
  fourth rung means spending a seventeenth tone, which is the rule above.
- **One light**, upper-left, fixed sheet-wide. A mirrored pose flips the
  geometry, never the light; the cast shadow keeps its one offset too. **The
  figure carries no rim band.** It did — the silhouette minus a copy of itself
  stepped toward the key, in the army's own rim rung, walked one texel in under
  the ink. On a 110px bust that is one texel of a colour the face does not own,
  laid between a two-texel outline and the cheek: a near-white line down an Iron
  jaw, a mint one down a Verdant neck. The coat keeps a kicker because two
  texels of it fit (`uniform` draws it as a ribbon); a head does not.
- **Four rungs of the sixteen are not the board's** — three on the gold row
  and one on the iron — and each is named in `palette.BUST_RUNGS` with the
  reason. Gold's three lit rungs come off the funds gold, because the board's
  Gilded ramp is authored a band low on purpose and a coat painted on it is
  olive — which cost two generals the colour they are named for. Iron's field
  rung comes up to where every other army's sits, because Iron's ramp is the
  inverted one and a window at L49 is under every dark cap and every dark skin
  on the sheet. Both are spent **inside** the sixteen: `bust_palette` reads
  this same function, so the allowed set moved and the cap did not.
- **Nothing thinner than two texels** (`portraitgen/gauge.py`). The board draws
  no one-texel dotted line and neither does a bust. A run that has to read as a
  line — a chain, a cable, a lanyard, a strand of bullion — is drawn
  `Canvas.ribbon` rather than `Canvas.stroke`: two texels, a core against an
  inked edge. Anything that cannot afford two is cut instead, which is what
  happened to a scar's cross-ticks, a brow's deep hairline and two of the three
  freckles a cheek used to wear. What the rasteriser leaves behind on top of
  that, `gauge.despeckle` sweeps as the last step of `bust.paint` — an orphan
  cluster takes the tone that borders it most, so the sweep invents no colour
  and settles to a fixed point. **The transparent ground is one of those
  tones**: a speck sitting off the outline is bordered mostly by nothing and is
  trimmed rather than recoloured, which is the silhouette half of the same
  rule. It cannot puncture a figure — an orphan inside the silhouette borders
  no transparency to vote — and `tests/test_gauge.py` pins both halves.
- **Three ink weights and no others** (`INK_SILHOUETTE` 4 / `INK_FEATURE` 3 /
  `INK_DETAIL` 2, in design units), so a scar can never come out as heavy as a
  jaw. `Canvas.stroke` refuses any other width. On the bust's grid the
  hierarchy is a ceiling rather than three widths: a silhouette is two pixels
  and the two lighter weights are one, which is all a 110px bust has room for.
- Faction colour comes from `portraitgen/palette.py`, and it restates neither
  of its two sources. The game's own `FactionTheme` is read back out of
  `scenes/common/commander_visuals.gd` by `tests/test_palette_mirror.py`, and
  the board's six-slot ramps are not copied at all: the module loads
  `generators/sprites/spritegen/palette.py` off its own file — the one
  dependency this package has beyond Pillow — and paints out of that shaper,
  those ladders and that sky. The four rungs a bust takes off another ladder
  are the only difference, and the same suite holds them to being the only
  four.

## Module contracts

The painter is layered, and each module owns one layer. Generic modules own no
general; `portraitgen/roster.py` is the only per-general data and
`portraitgen/bust.py` the only place a row becomes a picture. Every vocabulary
is a **dispatch table**: an unknown key raises rather than falling through to a
default.

| Module | Owns | Entry points |
| --- | --- | --- |
| `portraitgen/canvas.py` | the two grids, the primitives, the hard cast shadow | `Canvas.polygon/ellipse/stroke/ribbon/rect`, `px`, `divisor`, `blank`, `compose`, `silhouette`, `cast_shadow`, `resolve`, `face_box`, `pen` |
| `portraitgen/gauge.py` | the smallest mark this grid holds, and the sweep | `GAUGE`, `MAX_ORPHAN`, `clusters`, `holds_gauge`, `is_orphan`, `despeckle` |
| `portraitgen/light.py` | the key direction, the ramps, the AO | `KEY`, `Ramp`, `Ramp.of_faction(key)`, `Ramp.of_material(base)`, `shade_kind`, `face_shade`, `face_light`, `TERMINATORS`, `occlusion(occluder, target, depth=, divisor=, mirrored=)` |
| `portraitgen/head.py` | skull, neck, ear, the skin ramps | `Skull(width, jaw, crown, spread)`, `JAWS`, `SKIN_BASES`, `ramp_for(skin)`, `outline(skull)`, `skull_box(skull)`, `draw(canvas, skull, ramp, mirrored=)` |
| `portraitgen/features.py` | eyes, brows, nose, mouth, facial hair | `eyes(…, scale=)`, `brow`, `nose`, `mouth`, `facial_hair`, `earring`, `freckles`, `Frame`, `eye_xs`, `ringed_ellipse` |
| `portraitgen/accessories.py` | the worn accessories: headwear, eyewear, the scar | `ACCESSORY_KINDS`, `Worn`, `accessory(…, tint=, kicker=)`, `covered_eye` |
| `portraitgen/hair.py` | the hair mass and its strand clusters | `STYLES`, `HAIR_COLOURS`, `ramp_for(colour)`, `back`, `front(…, skin=)`, `draw(…, skin=)` |
| `portraitgen/uniform.py` | shoulders, collar cut, chest treatment, rank pip | `COLLAR_CUTS`, `CHEST_TREATMENTS`, `draw(canvas, faction, collar, ramp)`, `chest(canvas, treatment, faction, ramp)`, `pip(canvas, ramp)` |
| `portraitgen/props.py` | the 22 signature props and their rigs | `PROPS`, `SHOULDERED`, `RIGHT_LIMIT`, `draw(canvas, key, faction, ramp, layer=)` |
| `portraitgen/backdrop.py` | the window field, the treatment, the ink frame | `KINDS`, `FIELD_SLOT`, `LATTICE`, `ACCENT`, `field`, `treatment`, `frame`, `draw(canvas, kind, faction)` |
| `portraitgen/roster.py` | the FACES table | `Face`, `FACES`, `NEUTRAL`, `SKIN_TONES` |
| `portraitgen/bust.py` | the draw order, the pose, the frame safety | `paint(spec, cast=, divisor=)`, `chip(spec)`, `palette_of(spec)`, `window(spec, divisor=)`, `prop_art(face)`, `busts()`, `chips()`, `FACTION_OF` |

The keyword-only arguments above are the seams the layers are composed through:
`layer=` splits a prop into the half behind the figure and the rig in front,
`skin=` is what the hair fringe casts its band in, `tint=` dresses a bandana or
a headset cup in the general's own faction cloth, `kicker=` is that cloth's lit
rung, which only the two cap crowns spend, and `mirrored=` pre-flips the light
for a layer the pose is about to turn over. `accessory` packs the first two
into a `Worn`, so the nine painters that ignore the kicker never carry it down
their signatures. `accessories.py` fits to the same `Frame` and reads the same
eye line as `features.py`, so it imports that module and nothing there imports
it back.

Draw order, all on one grid, in `bust.py`: backdrop, then the figure — prop
behind, hair behind, uniform and collar, head, features, hair over, prop in
front — then the pose over the whole figure, the hard cast shadow under it,
the snap onto the bust's sixteen tones, and the gauge sweep. Each layer inks
itself as it is laid down.

`Face` carries nineteen columns — `skin`, `hair`, `style`, `brow`, `eyes`,
`mouth`, `eye`, `facial`, `acc`, `collar`, `chest`, `head`, `nose`, `pose`,
`bg`, `prop`, `pip`, `earring`, `freckles` — and each names its vocabulary's
owner above. Eighteen of them are the retired GDScript table's own; `chest` is
the one this pipeline added, because that table wore one diagonal sash five
times over.

## The pose, and what a mirror may turn

Tilt and zoom are one affine over the raster, its coefficients rounded before
they are used so that no libm's cosine can move an edge by a pixel, and sampled
nearest — nothing anywhere in this pipeline blends two tones.

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

`FACE_REGION` is `Rect2i(9, 15, 93, 93)` on the bust's grid — `canvas.FACE_REGION`
in design units, whose origin and side divide by **both** divisors so the chip
is that same square rasterised coarser. **The chip is a repaint at the chip
divisor, not a crop of the shipped bust**: the whole drawing is painted again on
the coarser grid and that square of it is what ships. The two therefore have no
bytes in common to compare, so `TheChipIsTheSameFace` measures the picture
instead: every chip texel stands for one 3x3 block of the shipped bust's face
box, and it must carry the tone that dominates that block. The sheet agrees on
63.7% (Rhea Sol) to 86.2% (the empty seat) of its texels — a third of them sit
on an edge that falls inside a block on one grid and on a boundary on the other
— against a floor of 60%, and every chip agrees with its OWN bust by at least
22.7 points more than with any other general's, against a bar of 15. The jaw must never clip it: the sheet clears it by 8 (Holt) to 32
(Morn) pixels against a floor of 4, measured per bust by
`tests/test_face_region.py`. It is the hardest acceptance criterion here — if one
fails, the geometry moves, never the rectangle, because the HUD chip, the speech
bust and the campaign brief all read it.
