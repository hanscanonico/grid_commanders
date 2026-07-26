# Battle HUD — docked chrome

Replaces the three floating overlay slabs in the shipped build.

## Why

In the current build the commander card, the day/funds strip, and the unit
inspector are all absolutely positioned **over the board**:

- They hide terrain and units. The commander card alone covers ~8 tiles in the
  corner the player's own HQ tends to sit in; the inspector covers the
  bottom-right quadrant, which is exactly where the cursor is when you inspect
  something there.
- They're translucent. Terrain reads through the letterforms — "Tank Iron
  Dominion" over a blue sea tile is barely legible, and HP is the single most
  glanceable number in the game.
- They're inconsistent: three different paddings, three different type sizes,
  no shared border or shadow language.
- Meanwhile the app **letterboxes** the map with black bands top and bottom.
  That space is already unavailable to the board, and it's empty.

## The fix

Move the HUD into the letterbox. Two docked bars, full width, opaque, outside
the map viewport — the board keeps every pixel it has.

```
┌──────────────────────────────────────────────┐  46px  top bar
│ DAY 8 │ ▪ Iron Dominion · Hold the line   FUNDS 13,000 │ ESC · MENU
├──────────────────────────────────────────────┤
│                                              │
│                  BOARD                       │  all remaining height
│                                              │
├──────────────────────────────────────────────┤
│ [face] Mara Voss HOLD THE LINE ▮▮▮▮▮▮ READY·F │ [sprite] Tank ▮▮▮▮▮▮▮▮▮▮ │ 92px
│                                       Fuel 59/70  Ammo 9/9   ROAD DEF 0
└──────────────────────────────────────────────┘
```

**Top bar (46px)** — turn state that never changes mid-action: day counter,
faction colour chip + name, the commander's **doctrine** (the always-on
passive), funds, menu hint. Right-aligned funds so the number sits in a stable
place. Note the doctrine is not the power name — `COMMANDERS.<id>.doctrine` is
the passive; `powerName` belongs beside the meter it charges.

**Bottom bar (92px)** — everything that changes as you move: `CommanderFace`
portrait, name, power name, the charge meter with its `powerCost` readout, and
the charged shortcut; then the selected unit (sprite, name, movement class,
order state, HP pips, fuel, ammo); then the terrain chip with DEF,
right-aligned.

**Selection lives on the board, not in a panel.** A white-on-ink reticle marks
the selected tile. The bar describes it; the board points at it.

## Rules

- **Opaque only.** `--slate-800` bars, 3px `--ink` edge against the board.
  Never a translucent slab over terrain.
- **Nothing floats over the map** except transient, self-dismissing things:
  damage numbers, the capture counter, the attack forecast. Persistent state
  goes in a bar.
- **HP is pips, not text — and not `StatBar`.** Ten 6×14px cells, `--capture`
  above 6, `--ammo` 4–6, `--red` at 3 or below — readable without reading.
  `StatBar` is the right control in a card or inspector panel (it carries its
  own uppercase label and value readout and wants ~140px), but a HUD bar has
  74px of vertical room for a whole unit row and repeats the label already
  printed beside it. Pips are the HUD-density treatment of the same data; use
  `StatBar` anywhere with room for a labelled row.
- **Real components, not raw `<img>`.** The board and both bars mount
  `TerrainTile`, `UnitSprite`, and `CommanderFace`, so tint resolution (a side
  alias or a faction name → sprite file), the exhausted state, and the
  selection brackets all come from the system rather than hardcoded
  `_iron` filenames.
- **Empty is empty.** With nothing selected the right two thirds of the bottom
  bar stay blank; the bar does not resize (a bar that grows and shrinks as you
  move the cursor is worse than one that's sometimes half empty).
- **Fixed heights.** 46 / 92. The board's viewport is computed once from
  `100vh - 138px`, so the camera never re-lays-out mid-turn.

## Tokens

`--slate-800` bar, `--slate-700` dividers and empty pips, `--slate-900` meter
trough, `--ink` borders, `--white` primary values, `--ink-3` labels,
`--paper-2` secondary values, `--capture` funds and healthy HP, `--ammo`
commander charge, `--iron-light` / faction `-light` for the colour chip (the
base `--iron` is the same value as the bar itself and disappears).

Labels are `--font-stat` uppercase at `--text-2xs` with `--tracking-label`;
values are `--font-ui` at `--text-base` or `--font-display` for the day number.

## Reference

`ui_kits/hud/index.html` (Design System tab → Battle HUD) renders the docked
HUD over a real board slice, with a button to flip back to the current
floating-overlay build for direct comparison.
