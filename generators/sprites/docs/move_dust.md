# Dust under a moving land vehicle — measured and refused, 2026-08-25

The `move` clip's obvious next effect: a puff of surface dust shed behind a
tank under way, composed on the cell like the wake and the waterline foam
(`voxel._wake`, `voxel._waterline_foam`) rather than modelled, so it costs the
unit no faction-share pixels and no despeckle.

**Verdict: no. The 64x96 cell cannot draw dust that reads.** Not a taste — the
sampling arithmetic and the room behind the contact ellipse settle it, and both
readings were taken on rendered sheets before it was written down. Dust belongs
to the GROUND; on this board the ground is the game's to draw, so this is a
game-side effect on the tile or it is nothing.

Take the readings again by giving `voxel.compose_cell` a `dust` argument and
laying the shapes below just behind `_shadow_ellipse`'s right tip.

## 1. Why a small puff cannot be drawn at all rungs

The board draws the 64px cell onto a 16px grid with nearest filtering, so at
rung 1 it keeps one source pixel in four on each axis — the same fact
`_shadow_ellipse` is solid for. A shape is therefore drawn at a given sampling
phase only if it owns a pixel in that phase's residue class `(x mod 4, y mod
4)`. There are sixteen classes, so **a shape under sixteen pixels is invisible
at some phase of the board, whatever its silhouette.**

That is not the parked art's problem — a still sprite sits at one phase per
zoom rung — but dust exists only while the unit is *tweening across the cell*,
which sweeps the phase continuously. A puff that owns six classes blinks in and
out six frames in sixteen during exactly the move it was drawn for.

Measured, on the shape a 3–6 pixel budget buys (a six-pixel stair climbing back
and up out of the running gear):

| reading | result |
| --- | --- |
| rung 1 (16x24), all sixteen phases | one screen pixel at 6 phases, nothing at 10 |
| rung 2 (32x48) | one or two pale pixels beside the shadow's tip |
| rung 4 (1:1) | a beige tick mark — reads as debris, not as dust |

## 2. Why the stable version is worse

The one puff that survives every phase is a texel-aligned 4x4 block: exactly
one screen pixel at rung 1 at every phase, 2x2 at rung 2. Rendered at 1:1 it is
a flat beige SQUARE sitting on the grass beside the shadow — the same 1:1
failure `_shadow_ellipse`'s docstring records for the shapes it beat: a 4px
logical-pixel checker that reads as a chequered flag, a dithered fringe that
reads as debris.

Spreading those sixteen pixels into a cloud that reads as a cloud is what the
cell has no room for. The contact ellipse is
`min(int(silhouette_w * 0.34), int(footprint_w * 0.41))` wide from the cell
centre, and the widest hulls leave almost nothing behind it:

*Amended 2026-09-01: S3 fitted the ellipse to the footprint, so the radius is
now that pair rather than the single `0.34` term this was written against.
Every vehicle below is capped at its old radius, so the readings stand; the
column is the whole crop, which is what `silhouette_w` is now called.*

| unit | silhouette | ellipse right tip | columns to the cell edge |
| --- | --- | --- | --- |
| md_tank | 63 | 55 | 9 |
| tank | 59 | 54 | 10 |
| apc, rockets | 53 | 52 | 12 |
| recon, artillery | 51 | 51 | 13 |

A puff shed backwards also costs one whole board texel of that room between the
two frames (4px, the texel rule), so a cloud six to eight columns wide needs
ten to twelve columns behind the ellipse and md_tank has nine. Widening the
cell is not available: the game addresses `Rect2(col*64, row*96, 64, 96)`.

## 3. What the gates said while it was up

Two of them, worth recording because they are what a future attempt will hit
first:

* Dust may not take shadow pixels the way `_wake` does. With the puff eating
  the ellipse's back tip, `OneSun.test_every_unit_drops_its_shadow_down_right_
  of_itself` reads rockets' MOVE_A shadow at **+0.13px** lateral of its caster
  against a 0.2 floor — the shadow's own centroid dragged up-left by the dust.
* Dust may not be counted as a CASTER either: left in the caster set, the same
  unit reads **+0.07px**. It is the ground's, like the shadow, and it is placed
  by the direction of travel rather than by the sun, so the reading has to
  exclude it by colour the way `UnitBandCoverage` excludes the shadow and the
  foam.

Both are cheap to satisfy; neither buys back section 1.

## 4. What would carry the cue instead

The move clip already says "under way" with the gait itself (`tests/measure_
motion.py --clip move`: 451 rung-1 silhouette texels across the roster, and
`MoveFrames`' floor of six met by every unit in every livery). If the board wants dust, the place for it
is a game-side effect drawn on the TILE under the sprite, where it is not
bounded by the unit cell, not resampled with the unit, and free to be as large
and as short-lived as a puff of dust actually is.
