# Sprite Generator

Deterministic sprite pipeline for this game, living in the repository it feeds
(`generators/sprites`, an offline instrument the engine never sees — the
sibling `generators/.gdignore` keeps Godot out of it). It generates the game's
complete **units atlas** (18 units x 6 faction rows) and **terrain atlas**
(14 terrains x 6 rows) as curated isometric-voxel pixel
art, in the same dimetric style as the PixVoxel pack the game shipped with —
but with more detail: finer voxels, baked ambient occlusion, front-edge rim
light, per-part outlines, and consistent scale, light and palette across the
whole roster.

There are **no seeds and no randomness**. Every sprite is a hand-authored
voxel model (`spritegen/units/`, `spritegen/buildings.py`) or tile painter
(`spritegen/terrain/`); texture "noise" comes from a fixed hash, so every
run reproduces the same bytes. Regenerating after an edit changes exactly the
sprites you edited.

**Adding a unit, a terrain tile or a faction: `docs/adding_art.md`** — the
end-to-end recipe, the game-side files each owes, and which gate catches what.
The rest of this document is why the art looks the way it does.

## The roster

| Group | Columns (atlas order) |
| --- | --- |
| Land | infantry, mech, recon, tank, md_tank, anti_air, artillery, rockets, apc (0-8), missiles (13) |
| Air | fighter, bomber, b_copter, t_copter (9-12) |
| Sea | battleship, cruiser, sub, lander (14-17) |
| Terrain | road, plains, woods, mountain, river, city, base, hq, sea, airport, port, shoal, bridge, reef (0-13) |

Rows follow `SideIdentity._ROW_FOR_KEY`: 0 neutral, 1 meridian (red),
2 aurora (blue), 3 iron, 4 verdant, 5 gold — every row's ramp is the exact
`CommanderVisuals.FactionTheme` (color / dark / light) from the game's code,
neutral's slate theme included. Weapon silhouettes follow each unit's
`battle_style` family (small arms, rocket, cannon, autocannon, bomb,
torpedo, unarmed); an id split off one of those for the cut-in alone —
recon's `pintle`, mech's `bazooka`, the APC's `convoy` — draws its parent's
silhouette. Property terrains (city, base, hq, airport, port) are tinted per
row; every other terrain repeats one tile down its column.

The five property columns are **transparent overlays**: the building, its
base plate and a solid drop shadow, with the ground around them left
empty. Baking the plains green into those cells put a green square around
every city standing on road or beach; the board paints the ground under a
property and the building reads as an object on it. Consumers compose
default ground first, then the property cell — `preview_map.png` does
exactly that, with the plains phase the cell's coordinate hashes to.

Units are painted out of **indexed ramps**: six slots per faction — S0
contour, S1 under, S2 shadow, S3 body, S4 top, S5 rim — plus one shared
gunmetal ramp and a small derived ramp per fixed accent. A face normal picks
the slot and the ramp picks the colour, so a sprite spends about twenty
palette entries instead of a few hundred, and a faction is a ramp swap rather
than a blend. **S3 is the design-system token itself**: the old livery
multiplied the faction hue against a chassis grey, which preserved hue and
halved brightness, so every army read a value darker than its own brand.
Every pixel also carries a **material id** — 0 contour, 1 faction, 2
gunmetal, 3 fixed accent — and only material 1 moves between rows. A ramp is
**built rather than typed**: an authored value ladder per faction, and one
shared chroma shape over it — saturation peaking mid-ramp and collapsing at
the rim, a single cool `AMBIENT` sky mixed into the shadow steps, and a small
hue rotation toward that sky in the dark and toward the sun in the light. Six
literal hexes drift into one hue at six brightnesses, which is what makes
indexed sprites read as tinted grey rather than as lit objects
(`docs/ramps.md`).
**Iron is inverted**: its theme colour is at the value floor, so it is Iron's
shadow plane and the identity comes from the near-black-to-light-steel jump
no other faction has. Its ceiling is pulled in — lit planes stop at the body
slot and only the rim steps above — because the previous pass overshot and
made the dark faction the brightest thing on the board. Neutral goes warm
khaki so it separates from Iron by hue rather than by value, and its top
plane sits below the bright band so the row nobody owns is never the loudest
one. The **rim is a lit plane's leading edge**, not just the model's front
corner, and it is the one place a ceiling gives way, Iron's included — that
edge light is how every unit claims the L200+ band the terrain ceiling
reserves for it. Two build gates hold the pair up, with no unit exempt from
either: at least 3% of a unit's pixels above L200 on every row, and at least
55% of a unit changing colour when the row does. A third gate holds the rows
in **order** rather than at a number: no row's share of the band above L160
may sit more than a percentage point over the widest chromatic row's. Freezing
that as an absolute figure is what let Iron come back as the loudest row once
the rim pass lifted everybody (17.3% against 14.0-14.9%, round 6) — the pixels
moved, the pinned number did not. Buildings are warm stone and cool concrete
under faction-colored roofs, caps, banners and paint, and are drawn by the
indexed renderer too, one band lower than an army (`BUILDING_TOP_SLOT`).
**The cast shadow is solid**, and there is **one sun**: every caster on the
board drops its shadow down-right by the same `voxel.SHADOW_OFFSET`, which
terrain re-exports rather than keeping a second copy of. What encodes
altitude is the shadow's SIZE and how far it falls along that one diagonal,
never its direction — land units get a tight contact shadow, air units a
larger one dropped much further with ground showing between, ships a
displacement shadow with waterline foam, and a wood or a mountain the same
displacement — the wood of its own fringe, the massif of its whole
silhouette, the way a building drops one. Three of those four used to lay
their shade straight down or straight under, lit from nowhere and
disagreeing with the building in the next cell; `OneSun` holds all four drawers to the one offset,
pixel by pixel where the shadow is a stamped silhouette. It was a 1px
checkerboard until the board was measured through it — see "The shadow is drawn for every rung" below. The sub carries a
**wake** on top of that — running foam down its own underside and trailing off
the stern — because a hull with no freeboard has nothing else to separate it
from open sea. Its hull and awash deck also sit two bands under every other
keel (both in the under slot, so their lit faces land on shadow), so the sneak
boat is the darkest ship in the line and separates as a contrast pair — dark
hull against mid water, under a lit sail and a light wake edge — rather than
by out-valuing the sea, which is a contest a boat awash cannot win. Nothing a
unit emits is semi-transparent — every shadow and every fleck of foam is opaque,
because partial alpha is a blurred halo at cut-in scale.

**A land unit's ellipse is CONTACT**, so its width is read off the footprint
the model plants on the ground (`voxel.footprint_width`, the lowest-z plane)
rather than off the whole crop a barrel or a raised rifle widens, and it
touches the unit's own lowest row instead of hanging two rows under it. Only
the WIDTH is the footprint's — the ellipse's depth still reads the crop,
narrowing both axes having taken area off a vehicle rather than fitting it —
and the fit may only ever take width away, the pre-fit radius being a ceiling
every vehicle still lands on. `tests/test_shadows.py::FootprintContact` holds
both halves, and asserts the rows of daylight an aircraft keeps on purpose.

### The shadow is drawn for every rung

The board offers whole zoom rungs 1 to 5 and draws the 64px cell onto a 16px
grid with nearest filtering, so it keeps one source pixel in 4/z: 4:1 at rung
1, 2:1 at rung 2, **1:1 at rung 4**. A shadow with 1px structure is therefore
a different picture at every rung, and the checkerboard was: measured over one
army's shadows, a sampling phase drew between **0% and 285%** of the shadow's
own density at rung 1 and between **0% and 268%** at rung 2 — on the board,
solid when zoomed out, all but gone at the default rung, and loose black dots
at 1:1, which two players reported as "ugly black dots".

Solid is the only shape with no sub-pixel structure to lose, and it measures
**0.92-1.07** at rung 1, **0.99-1.01** at rung 2 and exactly 1.0 at rung 4.
The two alternatives were rendered against it at rungs 1, 2 and 4 rather than
argued: a **logical-pixel checker** (4px blocks, the round-10 rule applied to
the dither) reads as a chequered flag under an aircraft at 1:1 and as a dashed
line at rung 2, and a **solid core with a dithered fringe** reads as debris.
`tests/test_shadows.py::CastShadow` is what holds the shipped shape
to it. The sub's **wake** followed: it ran on the shadow's own parity so that
it showed exactly where the checkerboard did not reach, so it is now drawn
solid and over the shadow — foam is what the surface does over the
displacement shading, not a stipple interleaved with it.

The **buildings' drop shadow** (`terrain._drop_shadow`, a different drawer)
was left on the checkerboard by that pass, which is why a city still wore a
stippled fringe at 1:1. It is solid now on the same reading: over the five
property cells the checkerboard drew **0%-276%** of its own density at rung 1
and **0%-200%** at rung 2 — a whole sampling phase drawing none of it — where
solid measures 0.97-1.06 at rung 2 and exactly 1.0 at rung 4. At rung 1 solid
still spreads 0.69-1.38, and that residual is the band's own **shape**: a
building's shadow is a ~130px silhouette two pixels wide, so the sampling grid
lands on more of one diagonal than another however it is filled.
`PropertyOverlays` holds it. The tone is unchanged and deliberately still the
units' `SHADOW` — one shade on one board — the doubled coverage having been
rendered on plains, road and shoal at all three rungs against the dither and
three lighter tones: solid is indistinguishable from the dither at rungs 1 and
2, reads as shade rather than dots at rung 4, and every lighter tone loses the
shadow entirely on road and shoal when zoomed out.

The **ground the shadow falls on** was read the same way in 2026-08-29, and
`../../docs/terrain_grain.md` is that record. The subject is what the board
paints — `TerrainAutotiles` sends almost every ground terrain to an autotile
sheet, so the census reads all 101 cells of the ten sheets plus the two
`terrain_atlas.png` columns (reef, and the interior wood) a board still shows,
and none of the columns a sheet answers for. Every one of the 101 is stable: the
terrains' grain is picked per 4px block, which is the block the furthest rung
samples at, so each draws the same share of its texture at every phase of every
rung, worst swing 0.12 against a 0.15 bar. Nothing was tuned in response.
`make grain-census` re-runs it, `GRAIN=--detail` cell by cell.

### The unit cell is 64x96, and armour spends the headroom

A tank has to read as heavier than the grass tile it is parked on, and the
tile is only 64px. So the unit cell is **one tile wide and half a tile
taller** (`atlas.CELL_W` / `CELL_H`), and `compose_cell` measures every
vertical landmark — the ground line, the hover line, the air shadow's ground
— **up from the cell's bottom edge**. The extra 32 rows are therefore sky: an
untouched model composes in the taller cell byte for byte
(`tests/test_cell_geometry.py`), and the game anchors the cell by its
footprint, so what a model draws above the tile hangs over the row behind it.

The **armour family is the first to spend it** — tank, md tank, artillery and
rockets, all grown upward with their footprints, contact shadows and waterline
logic untouched. What the growth is, is **mass**: deeper running gear, a
deeper hull and a turret raised on a full armour ring, plus the two guns that
elevate (the howitzer one step longer, the rocket rack pitched at the
howitzer's own two z per tile) which are what actually break the tile's line.
What it is **not** is fine detail. This projection puts one voxel of height at
2px, so a turret tall enough to clear a whole tile is a silo rather than a
tank — that was rendered on the md tank and rejected — and a mast thin enough
to look right is one source pixel wide, which the board's 4:1 decimation at
rung 1 draws or drops depending on the sampling phase. That is the same lesson
`../../docs/density_128.md` records: at board scale the win is silhouette, not
greebling. `tests/test_raised_armour.py` holds both halves — only the family
reaches out of its tile, and what it gained still draws at every rung-1
sampling phase.

### A pose smaller than one board texel is not motion

The same arithmetic sets the size of the smallest move the ambient animation
can make. The board samples the 64x96 cell down to **16x24 texels at zoom
rung 1** and **32x48 at rung 2**, so one board texel is **4 atlas pixels** at
rung 1. One voxel is a 4x4px cube projected to `sx = (x - y) * 2`,
`sy = (x + y) - 2z`, which makes four atlas pixels either a **dz of two
voxels** or a **(dx +1, dy -1) diagonal**: anything a pose moves by less than
that cannot carry the silhouette a texel across. Inside the shape it only
re-tones texels in place; along the edge it flips boundary texels on and off
with the sampling phase, which reads as shimmer rather than movement.
`tests/measure_motion.py` is the readout — per unit, per rung, the changed
texels, how many of those are the silhouette, and the shimmer index — and its
docstring records the table before and after the pass that applied the rule to
the land roster. Before it, the whole tracked family moved zero silhouette
texels at both rungs: six of them only crept a tread link, at a period of two
voxels, which is exactly Nyquist at the board's 4:1 sample and so inverted in
place instead of travelling, and the rest settled a sub-assembly one voxel,
half a texel. Each of the eight now moves one named sub-assembly a whole texel
— a gun laid, a howitzer recoiled, a rack pitched, a nose dipped — and the
tread's link stripe runs a period of eight so pose B advances it four. The two
foot figures followed: the rifleman leans his whole upper body, belt line up,
one diagonal step over planted boots with his rifle and both hands riding the
shoulders (2 -> 12 silhouette texels at rung 1), and the rocket trooper's left
pauldron drops `dz = -2` under its launch tube (2 -> 7). The rifleman leans
rather than compresses because a `dz = -2` on him costs 4 px of height and 64
opaque pixels, below the floors his own read tests hold. The four hulls came
last: they cleared the bar on the `atlas.BOB_PX` bob alone, which is a fleet
rising and falling in unison with nothing on any ship moving, so each now
rides one assembly a texel on top of the bob — the battleship lays both main
batteries, the cruiser elevates its autocannon, the sub raises its search
periscope, the lander walks its bow visor UP its hinge posts (a dip cancels
the bob at the bow and pins the outline where pose A left it, 18 -> 17).
`AmbientFrames.test_every_unit_moves_a_whole_board_texel` holds the floor at
three changed silhouette texels at rung 1 for every unit of every livery —
fighter and bomber clear it on the `atlas.BOB_PX` bob alone, which moves every
boundary texel they own, and carry a named beat besides: the fighter lights a
course of burner plume past its nozzles, and both retone rather than move
(its canopy glint and elevon tips, the bomber's tail tips), because the
legibility ratchet fails a silhouette texel added anywhere on either idle beat
(`units/air.py`'s `beat(pose)` branches). **Since S8 the bomber's retone reaches
no composed pixel**: its tail tips sit on the silhouette, which now falls to the
same ground-facing contour in both poses, so the model differs and the drawn
cell does not — measured and waived for that one unit's idle beat alone by
`AmbientFrames.test_the_bob_lifts_the_airframe_and_a_named_delta_besides`, its
move clip untouched. And
`test_no_unit_shimmers_more_than_it_moves` caps the other half of the ratio, so
the floor can never be bought by repainting an interior under an outline that
holds still. The picture behind those numbers is
`tests/preview_motion.py OUTDIR`, which writes a contact sheet of every unit's
two poses at both rungs plus one GIF per unit at the manifest's cadence, all
composited over the terrain the unit stands on; it takes its output directory
on argv, so it adds nothing to `out/` and the snapshot gate never sees it.

Both instruments take a `--clip` (default `ambient`) and read the clip's frames
from `units.CLIP_POSES`, so a clip that gains a frame is measured without this
file being edited: `measure_motion.py` offers every two-frame clip there
(`{ambient,fire,move}` today). `preview_motion.py` also needs the clip's sheet
tuple and its cadence (`*_MS`) in its own `CLIP_SHEETS`, which names the
ambient and move pairs — `{ambient,move}` — so drawing the fire pair is one
table entry away.
`measure_motion.py` adds a `MOVES?` column on the move clip — a "no" row is a
unit rendering its ambient counterpart, and says nothing about a stride.
`preview_motion.py` draws the move clip FLIPPED as well by default, each unit's
frames beside their mirror, because that mirror is the only place a
screen-handed silhouette would show; `--no-flip` turns it off and `--flip`
forces it on for any clip.

The generator's five dev instruments — `tests/measure_motion.py`,
`tests/preview_motion.py`, `tests/measure_livery.py` (`docs/ramps.md`),
`tests/measure_128.py` (`../../docs/density_128.md`) and
`tests/grain_census.py` (`../../docs/terrain_grain.md`) — all run under the one
interpreter `make generators-venv` builds, from this directory, with nothing on
`PYTHONPATH`:

```sh
py=~/.cache/grid_commanders/venv-sprites/bin/python
"$py" tests/measure_motion.py --clip move
"$py" tests/preview_motion.py OUTDIR
"$py" tests/grain_census.py
```

None of them is a test — `unittest discover`'s `test*.py` pattern matches no
`measure_`, `preview_` or `grain_` name — and none writes into `out/`, so
`make sprites-test` and the snapshot gate never see one.

### A move clip is a gait, not a translation

The texel rule above is the same one, unchanged: one board texel is 4 atlas px,
a `dz` of two voxels or a `(dx -1, dy +1)` forward diagonal. What changes is the
floor. `MoveFrames.MIN_SILHOUETTE_TEXELS` is **6** at rung 1, double the idle's
3, for every unit of every livery — an idle shifts one named assembly and three
texels is the quietest of those anyone can see, where a gait is the whole
running gear and a board that cannot see six texels of it move is watching a
unit slide. `MAX_SHIMMER` (5.0) and `MAX_MASS_DRIFT` (0.08) carry over from
`AmbientFrames` unchanged, the drift measured against pose A for both move
frames so a stride may not grow the unit either.

**The sheet may never translate the hull.** The game's `animate_path` tweens the
sprite one cell per 0.06 s x `anim_scale`; that tween IS the travel. A frame
that also travelled would double it and then snap back on the loop, so what a
move frame owns is the running gear and the chassis's reaction to it, and the
placement pins all four poses to pose A's crop.

All 18 units author the clip (`units.MOVES`), by family:

- **Tracked** (`tank`, `md_tank`, `anti_air`, `artillery`, `apc`) — the tread's
  link stripe walks a half period (`_track`'s eight-voxel stripe, so the step is
  one whole texel along the run) under a hull jolted one texel of ride height on
  the off-beat (`_roll`). The MBT pitches its NOSE that texel instead: rolled
  whole, its rung-1 silhouette matched `md_tank`'s frame A better than its own
  (0.799 against 0.761) and the unit stopped reading as itself. Weapons stay at
  pose A's travel-lock throughout — a vehicle on the move does not lay its gun,
  recoil its howitzer or track a target.
- **Wheeled** (`recon`, `rockets`, `missiles`) — the same `_roll`, and nothing
  on the wheels: a hub dot is one voxel, half a texel, so no rotation of it
  survives the sample (`_tire`). `recon` is the exception again for the same
  identity reason the MBT is — lifting all of a low car reads as the apc — so it
  pitches the nose a texel and lays its whip antenna one diagonal step back over
  the tail.
- **Foot** (`infantry`, `mech`) — a HELD forward `(dx -1, dy +1)` lean (an
  alternating one would be a man rocking on the spot at 160 ms), a hip line that
  alternates a texel of rise, and the legs taking it in turns to be at toe-off.
  The rifleman's pair swaps through the hip centre (`_stride`); the trooper's
  stand side by side with nothing to swap, so his gait alternates a lift
  (`_mech_legs`). Toe-off alone measured 6 texels on the rifleman and 5 on the
  mech — the bob is what carries both clear.
- **Air** (`fighter`, `bomber`, `b_copter`, `t_copter`) — a held nose-down
  attitude, one texel of `dz` on the forward fuselage about a wing root or a
  rotor mast that stays, which is what says heading on a sheet that may not
  translate. The frame-to-frame change is the `atlas.BOB_PX` bob, the two
  helicopters' rotor blades a notch further round, the fighter's nozzles lit a
  course beyond the burn `MOVE_A` holds (which reaches only the occluded mouth
  course, so the visible plume is `MOVE_B`'s alone), and the bomber's four
  nacelle mouths flaring with its nose dipped a further texel over `MOVE_A`'s
  trim — all of which tick with the FRAME rather than the clip (`beat(pose)`).
  The bomber's mouths are gated on `moving` besides: the same flare on the idle
  beat costs the legibility ratchet two baseline cells, which `units/air.py`'s
  `beat(pose)` branches and `tests/measure_motion.py` record.
- **Sea** (`battleship`, `cruiser`, `lander`) — a held bow-up TRIM, the forward
  hull a texel up over a waterline course that never moves (the foam is placed
  against the composed cell's lowest spans), plus one working assembly on the
  off-beat: the aft battery trained, the mast head running up the lattice, the
  bow visor's centre lip cracked. `sub` takes no trim — decks awash is the whole
  identity and a raised bow is a boat that has surfaced — and runs its masts
  instead, search periscope held up, dive planes rigged down, attack scope up on
  the off-beat.

`docs/move_clip.md` is the consumer contract: sheet names, region maths, the
flip policy, when the clip starts and stops, and the game-side task.

## Usage

`make tiles` from the repository root is the whole of it: it regenerates the
sheets and the UI chrome, installs them and reimports, and `make generators-venv` is the one-off interpreter setup it
needs. The venv is deliberately kept **outside** the checkout
(`~/.cache/grid_commanders/venv-sprites` by default, overridable as
`SPRITEGEN_PY=<python>`), because a git worktree shares no ignored files with
the main checkout and a per-worktree venv is a per-worktree reinstall.
`make sprites-test` is this pipeline's own gate.

To drive the script directly:

```sh
py=~/.cache/grid_commanders/venv-sprites/bin/python

# everything: atlases + per-cell sprites + review sheets, into ./out
"$py" sprite_generator.py

# iterate on specific sprites at high zoom while editing models
"$py" sprite_generator.py --only tank,city --team verdant --zoom 8

# copy the atlases and the UI chrome into a game checkout — path required
"$py" sprite_generator.py --install ../..
```

| Flag | Meaning |
| --- | --- |
| `-o / --out` | output directory (default `out/`) |
| `--only` | comma list of unit/terrain ids — renders just `preview_only.png` |
| `--team` | faction row for `--only` (neutral/red/blue/iron/verdant/gold) |
| `--zoom` | zoom factor for `--only` previews (default 6) |
| `--no-cells` | skip the 138 per-cell PNGs, write only atlases + previews |
| `--install` | copy the installed outputs into a grid_commanders checkout (explicit path; no default) — the per-cell PNGs are review output and stay here |

## Outputs

| File | Contract |
| --- | --- |
| `units_atlas.png` | 1152x576 RGBA — 64x96 cells, drop-in `assets/tiles/units_atlas.png` |
| `units_atlas_b.png` | ambient animation frame B: every unit's second key pose (`units.Pose.B`) — treads walked, suspensions settled, rotors turned a notch on their own blades, air and sea bobbed one board texel (`atlas.BOB_PX`) over a shadow, a wake and a foam line that stay on the surface. Every pose is placed by the model's screen origin, never by its own crop, so a beat moves the unit and not the cell |
| `units_atlas_figures.png`, `units_atlas_figures_b.png` | the same two ambient frames with the tile's cast shadow subtracted, for the cut-ins (see below) |
| `units_atlas_figures_ko.png` | one AUTHORED casualty frame per unit — a crumpled figure, a burnt-out hull, a hull settled by the stern — shadowless like the figure pair. The board never draws it, so there is no board-sheet sibling; air carries no frame in v1 and draws its own rest key instead (`units.KOS`), which the cut-in never asks for |
| `units_atlas_figures_fire.png`, `units_atlas_figures_fire_b.png` | one AUTHORED muzzle-lit frame per ARMED unit — a barrel at full recoil, a rack at launch elevation, bay doors open — shadowless like the figure pair. The board never draws it, so there is no board-sheet sibling; a unit outside `units.FIRES` draws its own rest key instead (`units.pose._FALLBACK`), which the cut-in DOES ask for — an attacker's fire window opens whatever it carries — and gets a column byte-identical to its idle pair, bob included, which is what makes the fallback need no domain gate. The second sheet is a real second key only for the sustained weapon families (`units.pose.FIRE_PAIRS`) — everything else draws the same model into both, so the pair reads as a held muzzle flash rather than a cycle |
| `units_atlas_move.png` | 1152x576 RGBA — the move clip's frame A (`units.Pose.MOVE_A`): the same 18 columns by 6 rows of 64x96 cells as the ambient sheet, the same army under way instead of parked. One facing only — the models face +y, which this projection puts at screen lower-LEFT, so these are the left-facing sheets and the consumer mirrors them about the cell centre for a rightward move (`clips.move.facing`/`flip_x_for`). Nothing in a move frame encodes screen-handedness |
| `units_atlas_move_b.png` | the move clip's frame B (`units.Pose.MOVE_B`), one stride later — gait only, never travel (see below). All four poses pin to pose A's crop, so swapping the clip never moves the cell, and a unit outside `units.MOVES` renders its ambient counterpart instead (MOVE_A -> A, MOVE_B -> B), which keeps the pair valid whatever is authored |
| `terrain_atlas.png` | 896x384 RGBA — drop-in `assets/tiles/terrain_atlas.png`; property columns carry alpha |
| `units/<id>_<team>.png` | 108 cells, the atlas's own art exported cell by cell for review — **cut out of the units sheet the run already built** (`atlas.cell_box`), so a cell is the atlas's cell by construction rather than by a second render agreeing with it. Installed nowhere: the game loads the sheet |
| `iso_buildings/<id>_<team>.png` | 30 property-building cells, review output the same way |
| `preview_units.png`, `preview_terrain.png` | 2x atlas contact sheets on checkerboard |
| `preview_map.png` | an authored little battle map proving the sheet in context: the shipped maps' terrain mix, autotiled, phased by the game's own coordinate hash |
| `autotiles/{roads,rivers,coast,shoals,woods}.png` | 16-variant connection sheets (see below) |
| `autotiles/bridges.png` | the two bridge deck orientations, E-W then N-S |
| `autotiles/sea.png` | the three sea phase variants, phase 0 first (see below) |
| `autotiles/sea_b.png` | the same three phases in the same order, one time frame later: only the glints have moved (see below) |
| `autotiles/plains.png` | the eight plains phase variants, phase 0 first (see below) |
| `autotiles/mountain.png` | the three mountain phase variants, phase 0 first (see below) |
| `anim.json` | the sheet contract in machine-readable form (see below) |

`anim.json` is the same numbers the sheets are built from, written down for the
game to read instead of retype: the cell's size, its ground line and its
overflow, the clips (which sheets, in what order, at what cadence — the
army's ambient beat on the board, the same beat on the cut-ins' shadowless
`ambient_figures` pair because they are the same motion, the sea's own, the
`move` clip's, and the `ko` clip's — one held frame, `mode: "hold"`, and a
`fallback: "ambient"` key naming what a consumer with no authored frame
plays instead, the move clip's own idiom restated), the units atlas's column
and row order, and how many
phase variants each terrain family ships. Every field is derived from the live tables in `spritegen/` —
`atlas.CELL_W/CELL_H`, `units.ATLAS_ORDER`, `palette.FACTIONS`, the terrain
phase tables — and `ground_px` is **measured** off a rendered cell (a composed
cell minus the shadowless one is the cast shadow alone; an ellipse is widest on
the row it is centred on) rather than restated, so the manifest cannot become
one more place the number drifts. It is written deterministically like
everything else here: sorted keys, two-space indent, trailing newline. See
`spritegen/anim.py`.

`clips.move`, `clips.ko` and `clips.fire` are the clips with keys past the
common four, and they are additive: `version` stays **1**, because their
ABSENCE is the reading a version-1 consumer already makes. `facing`
(`"left"`) and `flip_x_for` (`["right"]`) are `move`'s alone — the screen
direction the art is drawn facing and the direction the consumer mirrors it
for; a clip with no `facing` — `ambient`, `ambient_figures`, `sea`, `ko`,
`fire` — must never be mirrored. `fallback` (`"ambient"`) is shared by the
three clips a unit may be left out of, and `docs/move_clip.md` owns what it
means: the install's absence for `move`, and a unit's own for the other two.
An unauthored `ko` column must not be drawn; an unauthored `fire` one is drawn
and is simply the unit's idle key, which is the contract the cut-in leans on.

The move cadence is `anim.MOVE_MS` = **160 ms**, and it is chosen against the
game's tween rather than against the art: the board moves a unit one cell in
0.06 s x `anim_scale` — 0.18 s per cell at the normal tier, 0.12 s at quick —
so 160 ms is about one
stride per cell crossed. It is also deliberately neither a divisor nor a
multiple of 500 (`AMBIENT_MS`) or 900 (`SEA_MS`), so a walking unit, a parked
one and the water never turn over on the same tick and the board never blinks
at once. `docs/move_clip.md` is the full contract the game implements against —
region maths, flip policy, clip lifetime, and what the generator owes it.

The figure sheets exist because a figure standing on a drawn ground
already has a shadow. The tile shadow grounds the cell against the board's
tile; the game's cut-ins draw the same 64px cell over a ground plane and a
contact shadow **of their own**, so the tile's would be a second shadow rather
than the same one. (It was first cut for a sharper reason — the shadow was a
checkerboard then, and at 1:1 the cut-in resolved its dots one by one. The
shadow is solid now and that half of the argument has retired; the doubling
has not.) Each sheet **subtracts** that shadow
from the composed cell rather than composing a cell without one, so it is the
board's art and can never drift from it: the waterline foam is placed against
the composed cell's own spans, so a shadow that was never drawn would have
moved the foam. Everything else — every hull pixel, every fleck of foam — is
identical, which is what the `FigureSheet` tests hold it to.

There are two SUBTRACTED ones, one per ambient key pose, because a frozen figure is
the closest look a player ever gets at this art and the cut-in should breathe
like the board does. `_b` is frame B put through the same subtraction, and
`clips.ambient_figures` in `anim.json` names the pair at the ambient cadence,
so the game plays a cut-in idle without retyping either filename.

The `autotiles/` sheets are the opt-in upgrade path beyond the fixed
14-column terrain contract: roads and rivers as N/E/S/W connection sets (so
they can turn and junction), both bridge orientations, coastline tiles for
sea bordering land, shoals surfed on whichever edges face water, and woods
whose canopy runs off the edges the wood continues across and scallops to a
tree line on the rest (so a stand of trees stops ending in a razor cut
against the grass — the crowns stop a hash-keyed 0-6px short of a border
they end at, so the tree line is bays and points and a woods block is not a
rectangle). A crown that overhangs a continued border is drawn again a whole
cell along, so two woods cells butt on the same crown rather than on two
halves of different ones. A shore is bays and points for the same reason a
tree line is, and the wobble is on the WATERLINE rather than on decoration
laid over a ruled one: the fixed hash sampled every 16px along the edge and
smoothstepped between the samples, 5px peak to trough, with the wet lip and
the breaking foam following that line. The profile wraps on the cell, so the
shore of the tile alongside begins where this one's ends, and coast and shoal
draw the same wobble per direction, so where the two meet along one shore the
bays are in phase (the bands keep their own widths, 5px of sand on a coast
and 8px of water on a shoal). Where two seaward edges meet the point of sand
is taken off on an arc (`autotile._inland`, the rounded-rectangle distance)
rather than crossing two bands at a right angle, which is what had a beach
reading as a beige square in a blue picture frame; a shoal takes the same
diagonal `corners` mask a coast does. Each connection sheet lays out masks 0-15
row-major (bit order N=1, E=2, S=4, W=8); `bridges.png` carries its two
decks side by side. Mask 15 on the woods sheet is the atlas tile exactly, so only a wood's fringe
leaves the base sheet. A river is cut into a bank rather than laid on the
grass — silt, its shaded outer edge and a wet lip at the waterline, all mixed
from the same ground constants the plains and shoal tones come from — a run
that stops ends on a rounded nose, and a river's mask 0 is a banked pond,
since a watercourse joined to nothing is a pool rather than an E-W bar — a
pool whose bank is widest and darkest down the shadow diagonal and thins to a
one-pixel lip in the notches its reeds stand in, because a ring of one weight
and one tone is a badge rather than a shore. A feature's outline is
**directional**, for the reason the units' is (`autotile._edge_pass` mirrors
`voxel._selective_outline`): the two sunward sides of a road, a bank or a
channel step UP a tone and only the two sides turned away from the light keep
the dark contour, because one tone ringing all four sides is a sticker
stamped into the tile rather than a thing lying on the ground. Each lit tone
is one the tile already spends, except the bank's, which is the largest step
the terrain ceiling leaves over `BANK` itself (`TileSunwardEdges`). The
demo map composes from these, which is why its roads connect and its island
has a shoreline; the atlases themselves are
unchanged drop-ins.

`autotiles/sea.png`, `autotiles/plains.png` and `autotiles/mountain.png` are
the sheets that are not connection sets. The sea's is the
same open water in three **phases**, laid out left to right with a 2px gutter
like every other sheet. A field of sea reads visibly row-aligned however the
glints are spread inside one tile, because what lines up is the repeat — so
the fix is more than one tile and a rule for choosing between them. **The
generator emits the phases; the game places them**, by hashing the cell
coordinate into `0..2`. **Phase 0 is the terrain atlas's sea column byte for
byte**, so a board that knows nothing about this sheet is unchanged and a
board that adopts it keeps every cell it does not re-key; nothing has to move
on the day the game registers the sheet. `preview_map.png` places them with
that hash copied out of `scenes/battle/terrain_autotiles.gd`
(`atlas.phase`, pinned against the engine's own arithmetic in
`tests/test_demo_map.py`), so the review sheet is the board the game draws
cell for cell rather than a plausible-looking one.

A phase is a place, not a moment: it re-salts the water base, so the phases
**cannot be played as frames** — every pixel of the cell would repaint on the
same tick, which is the boil that makes cheap animated water read as static.
`autotiles/sea_b.png` is the sea a moment later instead: the same three
columns in the same order, `_water_base` byte for byte identical, and every
glint dash slid **one board texel** (4 atlas px at the 4:1 rung) along its own
row, both rows of a dash together so the stagger that makes it read as a
streak survives the move. The slide wraps inside the tile's interior band, off
the outer 2px ring — the rule the plains tufts are held to at their own one-px
margin — so a cell animating beside a neighbour on another phase never opens a
seam. A cell keeps its phase across the frames and only swaps which sheet it
samples, so the board animates without rehashing anything.
`tests/test_sea_frames.py` is the no-boil proof:
mask out the two glint tones and the frames are one image, and that image is
the untouched base. The clip is in `anim.json` as `clips.sea`, at 900 ms a
frame — slower than the 500 ms ambient beat because a swell is the slow motion
on the board, and deliberately not a multiple of it, so the water and the army
do not turn over on the same tick.

`autotiles/plains.png` is that rule on the ground most of a board is made of,
and it is phased the same way: eight tiles, phase 0 the atlas plains column
byte for byte, chosen by the same coordinate hash. Eight and not the sea's
three because the shipped maps are ~56% plains: at that share a five-phase
field still puts the same fleck back at the same in-tile position often enough
to read as a lattice at a longer pitch, and the phase count is the only dial
that lengthens it. `TerrainAutotiles.PLAINS_PHASES` counts the sheet's cells,
so the game's constant moves with the table. A phase's salt keys **the clump
field and the grain**, and its offset stands the tufts somewhere else — same
count, same tones, same clump coverage, every tuft drawn whole inside the cell
— because plains is the reference ground most contrast pairs are read against,
so a phase varies the field's arrangement and not its value.

The field itself is **two tones**, not one green with a grain on it: GRASS with
a darker grass clumped over 30% of the tile in 4px blocks, laid out by a
wrapping value field and taken by rank so every phase gets the same coverage. A
±3% per-pixel grain is a texture the game's 4:1 downsample averages away — the
old tile put 97.9% of its pixels within 8L of its mean — and a clump is a shape
that survives it (sd 4.5 -> ~10). Woods and the mountain's apron draw the same
plate, so no grass cell steps against its neighbour.

A phase wraps against **every other phase**, not only against itself: the game
hashes a phase per cell, so what butts on a board is one phase's right edge
against another's left. Every tile's outermost 4px ring is therefore drawn from
one **shared field**, on a 60px period so a tile's last block column is its
first — the two blocks that meet at a seam are one block, and the mean luma
step across a 64px boundary on a hashed field is 0.0 against 1.9 inside a tile
(it was 9.6). Each phase's own field dithers in behind the ring.

The field is also **indexed**: the grain is a ramp of three steps rather than a
mix per block, so a plains tile spends 7-11 colours where it spent 29-33, and
every ground on the sheet came down with it (27.8 colours a cell -> 9.4).
`docs/plains_field.md` carries the measurements, the tests restated for a
two-tone ground, and the one thing it costs: a clump ties in value with road
gravel and separates from it by hue alone.

Seven of the eight phases carry **decals**: a stone, a knot of tall grass, a
patch the summer dried out — all of them in grass's own hue under S0.45, and
under the terrain value ceiling. A find is 1-3px, which is a size that carries
a hue and not a material: gravel grey and wildflower tan at that size read as
dead pixels on a hue-100 field, so the field's ramp is what a find is drawn in.
They are ground detail and never a game object — no signpost, fence or marker,
which a board reads as a property from across the room — and they are drawn
inside the cell rather than wrapped, so a decal never overhangs its neighbour.
Phase 0 stays bare because it is the atlas column. Rarity used to be this
table's job — three of the five phases empty, since a decal was the only thing that
told two phases apart; the clump field is what a stretch of field varies by
now, so a decal is scattered detail on an already-varied field. If a field ever
reads busy, thin the table's decals rather than the clumps.
`autotiles/mountain.png` is the same rule on the tile a repeat shows up in most
loudly: mountain is the board's most silhouette-dominant terrain, so a range of
identical peaks is the loudest repeat on any map. Phase 0 is the atlas mountain
column byte for byte. A phase moves where the massif's three summits stand in
the model's voxel grid and reseeds the relief its spurs and gullies come out
of; the mass stands on the same row in every phase, so a ridge of mountains
stands on one horizon.

The three phases are **one dominant summit with shoulders under it**, not three
summits of a height: playtest read the earlier trio as rock piles, because
nothing in the silhouette said which peak the tile was about. Two things answer
that — the shoulders drop well under the peak, and the snow line is measured
**down from the tallest summit** (`buildings.MASSIF_CAP`), so only that peak
wears a cap. The cap is also the sheet's one material lifted a slot above its
family's convention (`palette.TERRAIN_MATERIALS`): snow may not be made whiter,
`SNOW_RAMP` stopping just under the ceiling that reserves the top band for
units, so what a cap gains it gains from the rungs it is drawn at. Darkening
the rock under the line instead is the rejected answer — it spends the massif's
darkest rung over the middle of the cell, where a unit stands, and
`make legibility-ratchet` failed a score of mountain cells on it.

The massif itself is a **voxel height field**, rasterised by the same
`render_indexed` the units and the buildings go through
(`buildings.massif`). It used to be the one object on the sheet drawn in a
projection of its own — a front elevation, a fitted silhouette at slope
-1.20/+0.92 with the light split by an `x <= apex` comparison, no top plane on
it anywhere and no y axis at all, standing in a board where everything else is
a dimetric mass. Now it is three oriented planes off the face normals, one
flat rung of `palette.ROCK_RAMP` each, with snow on the summits and talus at
the foot; its footprint lies IN the ground plane at the projection's own 2:1
and its summit flanks climb out of it at the slope they are authored at
(`buildings.MASSIF_SLOPE`, which the projection puts on screen at
SLOPE / sqrt(2)). `MountainProjection` in `tests/test_mountain_phases.py`
measures both, and the plane count with them.

Note the game's `make tiles` rebuilds its atlases from its own PixVoxel
pipeline and would overwrite installed atlases; the per-cell exports exist so
that pipeline's paste step can be pointed at this art instead.

## How it works

1. **`spritegen/voxel.py`** — a tiny dimetric voxel engine. Screen
   `x=(vx-vy)*2, y=(vx+vy)-vz*2`, each voxel a 4x4 cube sprite overlapping
   its neighbours by 2px (the classic 2px stair edge), painter's-algorithm
   ordering, and `Model.chamfer` cutting corner columns so turrets, cabs and
   roofs read as octagonal masses instead of cubes. Two renderers sit on
   that geometry:
   - `render_indexed` (units) shades **per face normal into ramp slots** —
     top, rim, body, shadow, under — with ambient occlusion, the ground
     contact and the depth gradient charged as whole slot steps rather than
     as fractions of a colour. It also returns a per-pixel material id, and
     the depth and normal planes behind the picture. Then **one outline pass
     reads those planes** and a despeckle pass folds lone pixels into the
     plane they were nearly part of. The alpha never moves: the silhouette is
     the shape the model drew, and only the colour under it changes.

     **Outlines are classified per pixel and selective**, and on a unit the
     line they classify is then grown inward into a band (S8, below).
     `gbuffer.edge_mask` finds every pixel whose 4-neighbour breaks the depth
     step a continuous surface can carry, which in this projection is the
     silhouette and a self-overlap
     in one reading. What each one becomes is fixed by where the break is, in
     one order, so no pixel is both dark and light: a break toward the ground
     (down or right) is the faction's own S0 — the outer boundary is S0's
     absolutely, round 9's precedence, kept; a break against a nearer surface
     draws on the FAR side only, at the material's own dark step, so a turret
     keeps its shape and the hull behind it takes the line; a break toward the
     sun (up or left) **lightens** — `SEL_OUT_LIFT` slots up the pixel's own
     ramp, clamped by the ceiling the painting voxel already answered to, so
     Iron draws no lit line at all rather than one it has no business
     wearing. `gbuffer.convex_edges` adds the same lift along a convex crease
     on a lit top face, and concave gutters get nothing. The sunward lift is
     also **graded per faction** (`palette.OUTLINE_LIGHT` / `OUTLINE_HEAVY` /
     `OUTLINE_RIM`): a lit line only separates a figure from the tile it
     stands on where it clears the ground's own value band, so where it
     cannot, neutral (the sand's own khaki) and Iron (achromatic, capped at S3,
     the middle of that band) fall to the ground-facing contour, while aurora
     and verdant — whose own hue a ground owns — climb to the **rim** instead,
     the band the terrain ceiling reserves for units
     (`palette.shares_a_ground_hue`).
     **Since S8 that grading is a PROPERTY's alone.** The board's 4:1 reading
     measured no row's ordinary lift clearing the ground band at all, so on a
     unit every grade falls to the contour and the rim climb is switched off:
     the three constants draw one and the same unit and are kept only for the
     rows they still tell apart off the board. **A unit's line is no longer
     1px either** — `voxel._thicken_contour` grows it inward to
     `CONTOUR_DEPTH` (4 lit, 2 ground-facing) so it survives that downsample,
     moving no alpha. A building is outside both: it stops at
     `BUILDING_TOP_SLOT`, so the rim is not a rung it can climb to and the band
     never reaches it.
     Selective outlining
     is still what buys the interior back: round 10's 4px band spent 34.5% of
     every unit's pixels on S0 (53.1% on the worst sprite) against 32.7-33.0%
     and 50.43% now, every grade alike, with round 11's own 14-17% / 24-31% the
     reading in between. The livery gates moved with all of it — the composed
     rows' closest pair was 34.6 under the band and 45.2 under round 11, and is
     33.0 now against a bar of 30.
     **docs/outlines.md** has the full
     reading, its S8 section the board-scale answer.
     The **property buildings** are drawn by this renderer too, one band
     lower: `voxel.BUILDING_TOP_SLOT` stops every ramp at the top plane, so
     the rim step — the flash the band above the terrain ceiling is reserved
     for — stays a unit's alone. They are painted out of three shared
     families built by the same shaper (`palette.PROPERTY_MATERIALS`:
     masonry, concrete, machinery) with the owner's roof in the faction ramp,
     and they wear the same selective outline. That took a building from
     61-74 colours to 13-23 (the unit cap is 24) and its dark boundary share
     from an unconditional 100% to 0.65-0.74 on the light grade — the units'
     own figures. `PropertyPalette` in the tests is where both are held, and
     **docs/properties.md** carries the ladders and the readings.
   - `render` (the nature props) is the older path: three shaded face
     tones per material, fractional occlusion, and two rules that keep it
     countable (`docs/terrain_outlines.md`) — a **1px contour in one
     deliberate tone per material** (`PROP_CONTOUR_DARKEN`, drawn only where
     the silhouette meets transparency: the partial grade a thing an army is
     read *against* gets, not the units' heavier band), and a **two-tone
     dither confined to flat tops of at least `DITHER_MIN_TOP_AREA` painted
     pixels**, because a speckle on a 4px feature is a chewed edge at board
     zoom rather than a material.
2. **`spritegen/palette.py`** — the indexed ramps and the material-to-slot
   table units are painted from, the faction colours mirroring the game's
   `CommanderVisuals`, fixed materials (gunmetal, track, glass, skin, ...),
   the older shading math, and the deterministic hash noise.
3. **`spritegen/units/`** — 18 authored models, all facing +y
   (screen lower-left) like the game's art, split by what they are:
   `foot.py` (rifleman, mech), `land.py` (the eight vehicles), `air.py`
   (two jets, two helicopters), `sea.py` (the four hulls), with the
   chassis parts they share in `parts.py` and the clips and their frames
   in `pose.py`. The package's `__init__.py` is the roster — the atlas
   order, the builder table and the header that states what a key pose may
   move — so every importer still reads `spritegen.units`.
4. **`spritegen/buildings.py` / `spritegen/terrain/`** — voxel property
   buildings and nature props composed onto 64px tile grounds. The grounds
   keep the engine script's original hues but not its values: every tone is
   authored under `terrain.TERRAIN_VALUE_CEILING` so the top of the ramp
   stays the units'. **A ground's shadow tone is not typed, it is built**:
   `terrain._shade` puts a lit tone through the same three steps
   `palette._shape` builds a ramp's dark rungs with — rotated toward the sky,
   a touch more chroma than the lit face, AMBIENT blended in — and then keys
   the result back onto the luma that tone was already authored at, so the
   ceilings, the ~18L movement-cost steps and `palette.GROUND_BAND` are
   preserved by construction and only the colour of the light moves. The board
   was two scenes before it: armies lit by a named sky, standing on ground
   whose shadows were the lit tone with the value pulled down and the hue left
   alone (2.6° on grass, under a degree on sand and timber). The same helpers
   took the two grounds that cover a map off poster chroma (grass S0.60 ->
   0.51, water S0.71 -> 0.60, at their own luma) and gave the greys a
   TEMPERATURE — rock, stone and concrete are warm in the sun at S0.14 and
   take the sky's own hue in shade, where they used to be one S0.05 neutral
   under both lights. `docs/terrain_tones.md` has the before/after table, the
   re-measured gates and the two places the pass could not land exactly where
   it aimed. A building is painted out of RAMP SLOTS, like a unit:
   four rungs of one warm **masonry** ramp for the mass, its trim and its
   openings, a cool **concrete** for the lot it stands on, and a **machinery**
   ramp a full band over both for a crane, a mast or a chimney cap — so a
   plate and the walls on it separate by hue rather than by spending the
   value the units are keyed against. The two families are a sandstone and a
   slate rather than two cards, because the row nobody owns is built out of
   the cool one end to end and every owned row out of the warm one: that
   temperature is what tells an unowned property from an **Iron** one, whose
   own colour is a grey. The ladder is authored where the old
   fixed greys' lit planes landed: the **mass** of every wall, lot and roof
   is dark — the lit half of a property measures L70-109 — and the rung above
   it is **trim, drawn only as a line**: a parapet, a coping, a ridge, a
   seam. A lit window and a pane of glazing are the only things that glint
   into the units' band (`BUILDING_KEY_CEILING`), which is why the base's
   hazard stripe is dashed rather than solid. Roofs follow the same rule
   inside the faction's own ramp, two bands under the unit convention — the
   owner's shadow band as the plane and the token itself as the ridge,
   because a `body` roof lit to L152 sat exactly on a verdant unit's own top
   slot. On Iron that is the row's whole identity: near-black panels under a
   light-steel ridge. The token is also the **paint** — a fascia under the
   eaves, a kerb, an apron's guide line, the band round a chimney — because a
   roof deck is four pixels at the board's 4:1 rung and an owner that lives
   only on roofs does not survive the downsample. What that is held to is the
   4:1 gate in `PropertyPalette`: two rows of one property stand 27-64 RGB
   apart as the board samples them, against 12-27 before the pass. The massif is two more shared ramps on the same
   shaping — **rock**, whose four upper rungs sit on the four values
   `terrain.ROCK` was authored at, warm in the sun and rotated onto the sky
   in the shade, and a cool **snow** for the caps. A crown of woods is a
   ground-parallel disc, and this camera draws one at **2:1**: the canopy is
   an ellipse twice as wide as it is deep — the same 2:1 a voxel's top face
   is drawn at — with the leaf mass hanging under it, banded into a lit top
   plane, a rim lit or shaded by which way it faces the sun, and the mass
   rolling off below. That lit top plane is what gives a dark or green unit
   standing in woods a value step to separate against: it is authored one
   step under the dimmest plains pixel and covers most of a crown rather than
   its cap alone, so a green hull is actually seen against it while the
   woods/plains seam rule stays true. Both tiles stopped painting per-pixel
   noise on the way through: the hash still rags a band boundary so an arc
   does not read as a stripe, but it no longer makes tones, and woods went
   from 77 colours and 53.7% of its pixels sitting on a colour change to 28
   — 32 on the widest variant — and 33.5% (`TileTexture`). Drawn as one
   stamp at one size in staggered courses, though, that canopy read as roof SHINGLES, so what a wood varies
   by is stated too: five crown sizes, centres jittered off the table by the
   fixed hash, a shuffled overlap order, ragged outlines and a dappled
   surface, a fringe that stops short of its border by a hash, and trunks
   that belong to crowns instead of to fixed tile coordinates. Held by
   period, not by taste — the strongest 8-16px band in the tile's row
   profile, 12.05L shingled against 6.2L now (`CanopyGrain`).
5. **`spritegen/autotile.py`** — the direction-aware road/river/bridge/
   coast/shoal/woods variants and the sea's phase variants, exported under
   `autotiles/`.
6. **`spritegen/aa.py`** — the last word on a rendered sprite, run between the
   renderer and the cell: a **single mid-tone pixel in the inner corner of a
   staircase step**, and only where both runs meeting there are three pixels
   or longer and the riser between them is no taller than two. It writes an
   existing slot off the sprite's own ramp — the one halfway between the 1px
   outline the corner sits on and the body just inside it — so a softened
   corner costs no palette entry, and it never touches alpha, so the
   silhouette is still the shape the model drew. It reads whatever that line
   is rather than assuming it is dark, and where line and body are one slot
   apart there is nothing between them to write: today that leaves every
   sunward `SEL_OUT_LIFT` edge alone and softens only the shaded ones. Since
   S8 the six rows no longer differ, every unit row's sunward silhouette
   falling to the same contour, and the band behind that line has taken most
   of the rest: 8 pixels a row per pose, on seven units, where round 11 spent
   146 across the sheet. A write that would strand the corner's only
   same-toned neighbour is refused (`_safe`, settled to a fixed point, and
   the band is what made that a live case). The
   restraint is the point: the projection draws its diagonals as runs of TWO,
   which is already the smoothest line a grid can hold, and softening every
   step of one would only grey the outline down. What is left for it are the
   shallower stretches — a wing root, a hull front, the shoulders of a foot
   unit. The property buildings come
   through the same seam (`terrain.property_sprite`) and it moves no pixel of
   any of them: walls and a base plate are runs of two end to end, so
   `MIN_RUN` excludes every corner they have. `ENABLED` turns the pass off;
   `MIN_RUN` is the knob that decides what counts as a staircase.
7. **`spritegen/cell.py`** — where a rendered sprite is placed in its 64x96
   atlas cell: the vertical landmarks measured up from the cell's bottom
   edge, the cast shadow, and the foam, wake and bow wave a hull needs to
   read as being in the water rather than on it. It imports no renderer, so
   nothing here can be a second opinion about how a voxel is shaded.
8. **`spritegen/atlas.py`** — assembles the atlases and exports the cells.
9. **`spritegen/demo.py`** — the review pictures, which are not shipped
   assets: the checkerboard sheet backdrop and the demo map, which resolves
   roads, the river, the bridge, every coastline and every wood's tree line
   through the autotile variants, so it shows the CELLS the board would
   paint rather than the tiles the atlas holds.
10. **`spritegen/chrome.py`** — the UI chrome: the range overlay the scene
   modulates, the board cursor and the project icon. Flat rectangles, no
   model and no ramp, folded in on 2026-08-29 from the engine script that
   drew them (`make ui-art`, retired) so the one art the game shipped from a
   second palette is now generated and snapshot-gated with the rest. The
   icon was redrawn here on 2026-08-30 as the command table — a dark plate
   ruled into a 3x3 board, an army in two opposite cells and the gold mark
   on the one between them, every measure a multiple of the 8px rule so all
   four platform sizes land on whole pixels, the 16 the desktop shrinks to
   included — but it keeps the two team hues the retired script typed,
   `d84a3c` / `3c64d8` against `CommanderVisuals` meridian `db4a3b` and
   aurora `3865d8`. `ChromeDrift` in `tests/test_chrome.py` holds the
   two team tokens within 4/255 and 2 degrees of the rows they stand for, so
   the gap can widen no further unquietly; closing it is a recolour, and a
   recolour is an art change of its own.

Python 3.10+, no dependencies beyond Pillow. The old seed-driven generator
(creatures/ships/items/robots/tanks) lives in git history before this
rewrite.

## Checks

The repository's `sprites` CI job runs on every push to `main` and every pull
request: `ruff check` and `ruff format --check` (ruff pinned in the workflow,
style settings in `ruff.toml`), the contract tests
(`python -m unittest discover tests`, which is what `make sprites-test` runs
locally), two generator runs diffed against each other for byte determinism,
and a pixel comparison of the art the game has installed — `assets/tiles/**`
and `assets/ui/**` — against fresh generator output. Change what the
generator draws without running `make tiles` in the same commit and CI fails.

That comparison is `tests/check_snapshots.py`, and it enumerates nothing by
hand: it pairs off every PNG the generator emitted with the installed file of
the same relative path, and fails in both directions, so a new output landing
with no home is a failure rather than a silence. The exceptions are the two
cell directories, which install nowhere: rather than ship 138 duplicates of art
the sheets already carry, each exported unit cell must be pixel for pixel one of
the cells of the run's own `units_atlas.png` — which the exporter cropping the
built sheet makes true by construction — and the building cells are pinned to
the terrain tiles by `tests/test_properties_art.py`. The previews are the one thing the
game does not load, so they stay compared against the review gallery's own
copies under `.lavish/assets`. Run it against your own output with
`~/.cache/grid_commanders/venv-sprites/bin/python tests/check_snapshots.py out`.

A pixel mismatch also writes a contact sheet per differing sheet —
installed art, fresh output and a map of what moved, cropped to the changed
cells and scaled up — into `reports/sprite_snapshot_diffs/`, and names the
file in the failure message beside the count of pixels and cells that moved.
Most failures here are an art change somebody meant, so the reviewer gets a
picture rather than a path.

The suites read composed art back, and composing it is what the run costs, so
`tests/pixel_helpers.py` is where a gate asks for a cell or a sheet
(`pose_cell`, `units_sheet`, `terrain_sheet`) and each is rendered once for the
whole run. The images it hands back are shared: read them, never paint on them.
A gate that needs a *fresh* render — the determinism ones, which compare two
builds, and the two that render under a patched module — calls `atlas` itself
and says why.

## Cell density

The sheet is emitted at a **64px cell**, and that is the shipped default.
`voxel.render_indexed` takes a density `k` — the pixels one voxel edge is
drawn at, over the shipped 4x4 cube — so a 128px candidate (`k = 2`) can be
emitted and measured. It defaults to 1 and the 64px output is byte-identical
with it.

**`../../docs/density_128.md` is the committed measurement of whether 128
should ship, and the verdict is no** — the board's own arithmetic gives a 128
cell the same 16 logical pixels per tile that 64 has, decimates it 2:1 at the
default rung where 64 lands exactly 1:1, and the emission the models produce
today is 93.3% a nearest 2x upscale of the 64px art. Read that document before
re-opening the question; it also records the order a future attempt should
take (the cut-in before the models).
