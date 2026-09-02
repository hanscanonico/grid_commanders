# The `move` clip — the contract the game implements against

The board has one clip today: `ambient`, two sheets half a second apart, played
by every unit all the time. A unit walking a path used to play it too, so a
tank crossing four cells was a parked tank sliding. This is the second clip —
the gait the tween never had — and it is the contract both sides implement
against.

Status: **shipped on both sides.** `move` is in `anim.json` beside `ambient`,
`ambient_figures`, `sea`, `ko` and `fire`, and the game plays it for exactly
the length of `BattleAnimator.animate_path`'s tween. A reader that finds no `move` key is
reading a manifest from before that batch and falls back to `ambient` — which
is the `fallback` field saying so in the file rather than in a comment.

## 1. What the clip is

| field | value |
| --- | --- |
| name | `move` |
| `sheets` | `units_atlas_move.png`, `units_atlas_move_b.png` |
| `order` | `[0, 1]` |
| `mode` | `loop` |
| `ms_per_frame` | `160` |
| `facing` | `"left"` |
| `flip_x_for` | `["right"]` |
| `fallback` | `"ambient"` |

Two frames, one facing, no figures variant — the cut-ins draw a unit standing
in front of a camera, not walking — and no per-direction sheets, ever. Four
directions would be four times the sheet for art whose only handedness is which
way it is flipped.

**Why 160 ms.** The travel is the game's tween, and the tween moves one cell in
`GameSpeed.BASE_MOVE_STEP_SECONDS` (0.06) times the tier's `anim_scale`:
normal 3.0 → 0.18 s per cell, quick 2.0 → 0.12 s per cell, instant 0.0 → no
tween at all. 160 ms is one stride per cell at the tier a fresh install plays
(0.18 s of travel per 0.16 s frame, 1.1 strides a cell); at quick the travel
outruns the gait a little — one stride per 1.3 cells — so the faster tier reads
as a longer stride rather than a faster one, which is the right way round for a
clip whose cadence is fixed. It is also deliberately not a divisor or a multiple of 500 (`AMBIENT_MS`) or
900 (`SEA_MS`): a walking unit, a parked one and the water never turn over on
the same tick, so the board never blinks at once.

**`facing`.** `voxel.py`'s projection is `x = (vx - vy) * 2`,
`y = (vx + vy) - vz * 2`, so **+y runs toward screen lower-LEFT**, and every
model on the sheet faces +y (`spritegen/units/__init__.py` header). The art therefore faces
**screen-left**, the manifest carries `"facing": "left"`, and the consumer
mirrors for the other one: `"flip_x_for": ["right"]`.

**Semantics of the two new keys.** `facing` is which screen direction the art
is drawn facing; a clip with **no** `facing` key must never be mirrored, which
is what keeps `ambient`, `ambient_figures` and `sea` byte-identical in
behaviour — the manifest schema is additive and `VERSION` stays 1.

**`fallback`** names the clip to fall back on, and it answers two absences with
one key.

*The install's.* A consumer that does not find this clip's sheets plays the
named clip instead. That is the reading `move` shipped with, and it is why a
manifest from before the move batch reads as `ambient`.

*A unit's.* Every clip past `ambient` is a per-unit opt-in, and the columns of a
unit that has not opted in carry the fallback clip's own frame, so the sheet is
a valid 18-column grid from the day it ships. A unit with no authored move pose
renders its ambient counterpart (MOVE_A → A, MOVE_B → B), so the move sheets
were initially identical to the ambient pair and the opt-in (`units.MOVES`)
grows one family at a time.

The two readings agree wherever the fallback frame is a legal thing to draw in
the clip's own place, which is the whole of `move`: a unit that does not walk is
drawn parked, and the consumer never has to know which units are authored. They
part on `ko`, where the fallback frame is the unit STANDING and drawing it as a
casualty would be a lie. Air authors no wreck in v1, so its four columns of
`units_atlas_figures_ko.png` carry pose A byte for byte, and **the consumer must
not draw them**: it takes the fallback clip's own *behaviour* for that unit
rather than its cells, which for the cut-in is `CutsceneSide.bind` leaving the
KO cut null for a flying unit and keeping the transform-topple. Which units are
authored is not in the manifest, so a consumer that cannot tell must draw
nothing from a `ko` column rather than trust the cell it finds there.

`fire` is the THIRD reading and it is ko's inverse: there the fallback frame IS
a legal thing to draw, so an unauthored column is drawn exactly as it stands.
The clip's fallback is taken PER FRAME rather than per sheet — FIRE_A → A and
FIRE_B → B — so an unarmed unit's fire pair is its own idle pair, bob and all,
byte for byte. That is what lets the cut-in bind the fire cut for every unit
and open the window on it without ever asking whether this one carries a gun:
an unarmed attacker's window opens onto the same texture the idle beat was
already drawing. A consumer may treat a `fire` column as always safe; it is a
`ko` column it may not.

## 2. Region maths — identical to ambient

The move sheets are byte-for-byte the ambient grid: **1152x480 RGBA**, 18
columns of 64 px (`units.ATLAS_ORDER`, the manifest's `columns`) by 5 rows of
96 px (`palette.FACTIONS`, the manifest's `rows`). One cell is

    Rect2(col * 64, row * 96, 64, 96)

and nothing else — same `cell.w` 64, `cell.h` 96, `cell.ground_px` **7**,
`cell.overflow` **32**. Swapping the clip swaps only which texture the
`AtlasTexture` points at; the region, the scale, the `ART_OFFSET` and the
ground line are pose-invariant.

All four poses pin to pose A's crop (`atlas._pose_a_box`), `footprint_w` and
`ground` do not move with the pose, and `bob = BOB_PX` applies to air and sea
on any beat frame (B and MOVE_B) exactly as it does today. Land never bobs via
placement.

**The sheet never translates the hull.** A move frame may not shift the unit
horizontally in-cell: the game's tween is the travel, and a sheet that also
travelled would double it and then snap back on the loop. The sheet shows gait
only.

## 3. Flip policy

`flip_h` follows the sign of the current path leg's x delta — negative x
(moving screen-left) is `false`, positive x is `true`; a purely vertical leg
holds whatever facing the previous leg left. Facing is set in `setup()` and by
`face_step` during a move, and **never** in `refresh()`, so a unit that has
walked right stays facing right through every subsequent repaint.

`Sprite2D.flip_h` mirrors about the sprite's centre, and `ART_OFFSET` is
vertical only (`Vector2(0, -SPRITE_OVERFLOW / 2.0)`), so the mirrored cell lands
on the same tile. The HP, fuel and acted badges are child nodes and are not
mirrored with it.

The cast shadow **does not** mirror, because on the move sheets it is already
centred. One sun lights the rest of the sheet from the top-left and every
ambient shadow falls down-right by `voxel.SHADOW_OFFSET` (2, 2) — but a
mirrored frame negates that x, so a rightward-moving unit would drop its
shadow down-LEFT, 5 px (land) or 9 px (air) from where the terrain tiles put
theirs: 1.25 and 2.25 board texels of a sun on the wrong side. The move poses
therefore compose with `voxel.compose_cell(centred_shadow=True)`: the shadow
keeps its full vertical drop, gives up its horizontal throw, and is drawn
symmetric about the cell's flip axis — the ellipse intersected with its own
reflection, since that axis runs between two columns and no odd-width shape
centred on a column can be symmetric about it. `flip_h` then leaves it exactly
where it was. What still mirrors is the hull, and with it which pixels of that
ground patch the hull hides, which is correct: a unit occludes its own shadow
from whichever side it faces.

The cost is a 2 px horizontal recentre of the shadow — 4 px for air, whose
shadow drops twice as far — at the instant a unit starts or stops moving: half
a board texel on the ground, a whole one under an aircraft, on the same frame
as the position tween starting or ending, which is the loudest thing on screen
at that moment. Ambient, figures and terrain keep the offset
shadow unchanged; nothing that is never mirrored gives up its sun.

**Ships keep theirs.** A sea unit's ellipse is the water its hull displaces,
not a shadow cast on a tile, and `voxel._waterline_foam` places the foam
against the composed cell's own spans — recentring the ellipse would carry the
foam line 2 px with it, and the foam line staying put across the clip is what
makes the ship ride the sea instead of the sea heaving with the ship
(`test_a_moving_hull_adds_a_bow_wave_and_moves_nothing_else`). A mirrored ship
therefore does move its displacement patch 5 px, which is the one place this
sheet still has a handedness. Nobody reads a water shading for a sun angle;
everybody reads a hard ellipse on grass for one.

**What a ship's move frames get instead is a bow wave.** A held bow-up trim
alone left a running hull almost the parked picture — 15 changed and 2 rung-1
silhouette texels between the lander's pose A and its MOVE_A, 18/3 for the
cruiser — so `voxel._bow_wave` breaks white water over the leading rim of the
displacement patch on the move poses only: 20/3 and 22/3 after, 24/6 for the
battleship, 27/7 for the sub. It is repainted displacement rather than foam
laid on open sea, and that is three things at once — it sits on the water
plane by construction so it cannot heave with the bob, it is white on
near-black rather than white on blue so it survives the board's 4:1 sample at
rung 1, and it costs almost no new pixels, which matters because all four
hulls' move poses already sit within 9 px of `MoveFrames.MAX_MASS_DRIFT`. That
budget is also the ceiling on the wave: only the 1 px lip outside the rim is
new water, and a second column of lip measures 0.083 drift on the battleship
against a gate of 0.08. That is why the parked-vs-running change count rises by
four or five texels while the SILHOUETTE count barely moves — one texel on the
lander, none on the cruiser, the sub or the battleship. Six silhouette texels
between parked and running is not reachable this way; a hull that has to change
outline that much has to change shape, not water.

The wave rides the displacement patch, so a mirrored ship carries it the same
5 px the patch moves — the handedness above, not a new one. It stays at the
mirrored hull's bow, which is where a bow wave belongs.

The wave is the same on both move frames. Ticking it with the beat is not
buildable here: at `voxel.BOW_REACH` the crest already covers every row of
every hull's patch — nine rows at the widest — so carrying it further aft on
the off-beat repaints nothing. The hulls carry the beat where they already
did, in the trim, the guns and the mast.

Nothing in a move frame may encode screen-handedness for any other reason. A
mirrored rifleman leading with the other leg is correct.

## 4. Clip lifetime

`move` plays only for the duration of `BattleAnimator.animate_path`'s tween:
set the clip before the tween, return to `ambient` after `await
tween.finished`, on the Instant early return (which sets the destination and
returns in the same frame, so there is no clip to play), and if the tween is
killed — a scene teardown or a skipped animation must not leave a unit
striding on the spot.

The frame comes from elapsed wall-clock time on the same clock `ambient_frame`
uses (`Time.get_ticks_msec()`), divided by the clip's own `ms_per_frame`, so a
whole column of moving units agrees on the beat without a conductor and pacing
stays presentation-only. Both stills pin the clip to frame A, by the same rule
that pins ambient: `UnitSprite.ambient_frozen` (a capture must not depend on
when the shutter fired) and the Instant tier (a still board shows a result
rather than playing one out).

Surface dust under a moving land vehicle is NOT part of the clip and is not
coming: `docs/move_dust.md` has the readings that refused it — a puff small
enough to fit behind the contact ellipse is invisible at ten of the board's
sixteen sampling phases, and the one that survives them all is a beige square.
If the board wants dust it belongs on the tile, game-side.

## 5. The game-side task

Files:

- A manifest loader beside `scenes/battle/unit_sprite.gd` — proposed here,
  **not built**. The game hardcodes the cell and the cadences and *pins*
  `assets/tiles/anim.json` against them in `tests/unit/test_anim_manifest.gd`
  instead, so no JSON parse sits in the draw path.
- `scenes/battle/unit_sprite.gd` — `set_clip(name)`, `clip_frame(now_ms)` and
  `face_step(delta: Vector2i)`. `set_clip` swaps the sheet the existing
  `AtlasTexture` points at and leaves the region alone; `clip_frame` is
  `ambient_frame`'s shape with the clip's own `ms_per_frame`, honouring
  `ambient_frozen` and Instant; `face_step` sets `flip_h` from the sign of
  `delta.x` and holds on `delta.x == 0`.
- `scenes/battle/battle_animator.gd` — `animate_path` sets the `move` clip
  before building the tween, appends a per-leg `face_step` callback so facing
  turns at each corner rather than once for the whole path, and restores
  `ambient` on every exit (finish, Instant early return, kill).
- `assets/tiles/` — commit `anim.json`, `units_atlas_move.png`,
  `units_atlas_move_b.png` and their `.import` files, plus the two sheets that
  are currently untracked in the game checkout: `units_atlas_figures_b.png`
  and `autotiles/sea_b.png`.
- `assets/LICENSES.md` — the new sheets in the generated-art row.
- `CLAUDE.md` — the manifest is the source for cell and clip numbers; do not
  retype them.

Verification:

- `tests/unit/test_anim_manifest.gd` — a drift alarm. The manifest's
  `cell.w/h/ground_px/overflow` must equal `UnitSprite.SPRITE_W`, `SPRITE_H`,
  `CELL_GROUND_PX`, `SPRITE_OVERFLOW`; the ambient clip's `ms_per_frame` must
  equal `UnitSprite.AMBIENT_MS`; and every `UnitType.atlas_col` must match the
  manifest's `columns` entry for that id, with the same count (18).
- `tests/unit/test_move_frames.gd` — the game's gate: the move sheets are the
  ambient grid, an unauthored column's move frames equal its ambient ones, the
  cadence and the two stills hold, and `UnitSprite.facing_for` holds facing on
  a vertical leg.
- `make smoke` — all 85 capture modes byte-identical. Captures pin Instant, so
  nothing in this change may move a single frame of them.
- Manual: walk a unit left and right across the board and check the sprite,
  the badges and the shadow.

New sheets need `make import` in the game before they load.

Out of scope: per-direction art, a figures variant of the move clip, attack or
death clips, any change to the ambient cadence or to the existing clips' keys,
and the sim — no file under `core/` or `ai/` sees any of this.

## 6. What the generator must respect

- **Same grid.** 1152x480, the same 18 columns and 5 rows in the same order.
  The move sheets are a third and fourth frame of the same atlas, not a new
  atlas.
- **Same ground line.** `cell.ground_px` is measured off the art
  (`anim.measure_ground_px`) and every pose must measure the same 7, which is
  what the shared pose-A crop and the pose-invariant `ground` buy.
- **Mirror-safe silhouettes.** Nothing that reads as left- or right-handed on
  screen; the consumer flips about the cell centre.
- **Whole-texel motion.** One board texel is 4 atlas px, i.e. dz ±2 or
  (dx ±1, dy ∓1) in voxels; forward is (dx −1, dy +1). A delta under a texel
  re-tones the inside of a shape that holds still and the sprite boils instead
  of walking.
- **No in-sheet travel.** See section 2.
- **PNG as the game imports it**: lossless (`compress/mode=0`), no mipmaps
  (`mipmaps/generate=false`), straight alpha (`process/premult_alpha=false`)
  and `process/fix_alpha_border=true`. That last one rewrites the RGB of fully
  transparent pixels at import, so any comparison against a shipped sheet —
  here or in the game's tests — must look at drawn pixels only.
- **Manifest and sheets ship together.** `sprite_generator.py --install` copies
  `anim.json` with the atlases it describes; a checkout with new sheets and
  last run's manifest is exactly the coupling the manifest exists to end.
