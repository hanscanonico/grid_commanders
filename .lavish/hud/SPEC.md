# Battle HUD — handoff

Replaces the three floating overlay slabs in the shipped build with two docked
chrome bars.

## Why

In the current build the commander card, the day/funds strip, and the unit
inspector are absolutely positioned **over the board**:

- They hide terrain and units. The commander card covers ~8 tiles in the corner
  the player's own HQ tends to sit in; the inspector covers the bottom-right
  quadrant — exactly where the cursor is when you inspect something there.
- They're translucent. Terrain reads through the letterforms; HP is the single
  most glanceable number in the game and it's sitting on a sea tile.
- Three different paddings, three type sizes, no shared border or shadow.
- Meanwhile the app **letterboxes** the map with black bands top and bottom.
  That space is already unavailable to the board, and it's empty.

## The fix

Move the HUD into the letterbox. Two docked bars, full width, opaque, outside
the map viewport — the board keeps every pixel it has.

```
┌────────────────────────────────────────────────────────────┐ 46px
│ DAY 8 │ ▪ Iron Dominion  Direct units +20% counterattack…  │
│                              FUNDS 13,000 │ ESC · MENU     │
├────────────────────────────────────────────────────────────┤
│                          BOARD                             │ 100vh − 138px
├────────────────────────────────────────────────────────────┤
│ [face] Mara Voss HOLD THE LINE ▮▮▮▮▮▮ READY·F │            │ 92px
│   [sprite] Tank TREADS·WAITED ▮▮▮▮▮▮▮▮▮▮ Fuel 59/70        │
│   Ammo 9/9                          [tile] ROAD  DEF 0     │
└────────────────────────────────────────────────────────────┘
```

**Top bar (46px)** — turn state that never changes mid-action: day counter,
faction colour chip + name, the commander's **doctrine** (the always-on
passive), funds, threat-lens chip, menu hint. Funds right-aligned so the number
sits still.

The **threat chip** is the one thing on either bar that reports a *view* rather
than a fact about the match: `T · THREAT`, dim while the lens is down and
`--red` while it is up. It sits beside the key legend rather than inside it,
because the legend is swapped per interaction and this control outlives every
one of them — and because the resting legend is already at its width. Its words
are `ControlHints`', like every other key this HUD names.

**Bottom bar (92px)** — everything that changes as you move: `CommanderFace`
portrait, name, power name, charge meter with its `powerCost` readout and the
charged shortcut; then the selected unit (sprite, name, movement class, order
state, HP pips, fuel, ammo); then the terrain chip with DEF, right-aligned.

**Selection lives on the board, not in a panel.** `TerrainTile`'s own cursor
brackets mark the selected tile. The bar describes it; the board points at it.

## Rules

- **Opaque only.** `--slate-800` bars, 3px `--ink` edge against the board.
  Never a translucent slab over terrain.
- **Nothing floats over the map** except transient, self-dismissing things:
  damage numbers, capture counter, attack forecast. Persistent state goes in a
  bar.
- **HP is pips, not text — and not `StatBar`.** Ten 6×14px cells, `--capture`
  above 6, `--ammo` 4–6, `--red` at 3 or below. `StatBar` is right in a card or
  inspector (it carries its own label + value readout and wants ~140px); a HUD
  row has 74px of vertical space and already prints the label beside it. Pips
  are the HUD-density treatment of the same data.
- **Empty is empty.** With nothing selected the right two thirds of the bottom
  bar stay blank; the bar does **not** resize. A bar that grows and shrinks as
  the cursor moves is worse than one that's sometimes half empty.
- **Fixed heights.** 46 / 92. Compute the board viewport once from
  `100vh - 138px` so the camera never re-lays-out mid-turn.
- **Real components, not raw `<img>`.** Mount `TerrainTile`, `UnitSprite`, and
  `CommanderFace` so tint resolution (side alias *or* faction name → sprite
  file), the exhausted state, and the selection brackets come from the system
  instead of hardcoded `_iron` filenames.

## Two token bugs found while building this

- **`--warn` does not exist** in this design system. The commander charge meter
  was rendering unstyled. It's `--ammo` (`#e0a92e`).
- **`--iron` is the same value as the HUD bar** (`#2b3238` ≈ `--slate-800`), so
  a faction colour chip painted with it is invisible. Use the `-light` variant
  (`--iron-light`) for any faction chip on a dark surface.

## Content — read it from `COMMANDERS`, don't retype it

`COMMANDERS.mara_voss` has both a `doctrine` (always-on passive) and a
`powerName` ("Hold the Line") with `powerCost: 11000`. The shipped build prints
the *power name* as if it were the doctrine. Doctrine → top bar; power name and
cost → beside the meter they charge.

## Tokens

`--slate-800` bar · `--slate-700` dividers and empty pips · `--slate-900` meter
trough · `--ink` borders · `--white` primary values · `--ink-3` labels ·
`--paper-2` secondary values · `--capture` funds and healthy HP · `--ammo`
commander charge · faction `-light` for the colour chip.

Labels: `--font-stat` uppercase at `--text-2xs` with `--tracking-label`.
Values: `--font-ui` at `--text-base`; the day number in `--font-display`.

## Reference

`hud.html` in this package renders the docked HUD over a real board slice, with
a button to flip back to the current floating-overlay build for direct
comparison. It needs `styles.css` + `tokens/` (included) and the sprite folders
from the faction-sprites package (or the repo's own `assets/sprites`).
