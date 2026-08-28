# The unit ramps: how a slot gets its colour — 2026-08-22

The six-slot ramps used to be six literal hex triples per faction, typed out
by hand. Read as colour rather than as art direction, what they mostly were
was one hue at six brightnesses: across meridian's ramp the hue moved 13°
in total and the saturation moved 6 points before the rim step, so five of
the six rungs were the same paint under a dimmer. That is the flattest thing
a six-colour ramp can be, and it is what makes indexed sprites read as tinted
grey rather than as lit objects.

They are **built** now: an authored value ladder per faction (unchanged — the
value structure is what every livery gate measures) and one shared chroma
shape applied to every rung of it, in `spritegen/palette.py`'s `build_ramp`.
The shape is three rules.

1. **Saturation peaks mid-ramp and collapses at the top.** `_SAT_SCALE` is
   `(1.10, 1.22, 1.24, 1.00, 0.82, 0.42)` over S0..S5. The rim step is the
   sun itself and has to read as light rather than as paint; the mid steps
   are where an object's own colour lives. The dark end keeps slightly more
   chroma than the light end, because a shadow is lit by a coloured sky and
   a highlight is washed out by a white one.
2. **The shadow steps sit in a coloured ambient.** One constant, `AMBIENT =
   (86, 112, 190)`, a cool sky, blended into S0/S1/S2 by `(0.26, 0.16,
   0.07)`. It is mixed at equal luminance and the rung is re-keyed
   afterwards, so the ambient changes only the colour of the shadow, never
   its value. Shared across all five armies, the props and the accents, so
   the sheet reads as one scene rather than five.
3. **Hue rotates a little.** Dark rungs rotate toward the sky hue (225°),
   light rungs toward the sun (45°), along the shorter arc, capped by
   `_HUE_ARC = 14°` and scaled per rung by `_HUE_PULL`. The magnitude is
   empirical: there is no "20° per step" rule that survives contact with a
   red faction, whose shadow goes violet and stops being the same army.

S3 does not move — it is the faction token, bit for bit, and the gate
`Livery.test_the_body_slot_is_the_design_system_token` says so. Iron and
neutral anchor off-token on purpose (Iron's token is its shadow plane;
neutral's khaki is a hue-separation choice), so their anchors are the light
steel and the sand their lit planes are actually made of.

`_at_luminance` is what keeps the value ladder exact: it scales a colour to
a target luminance and only washes toward white once a channel is pinned at
255, which is why the saturated mid rungs stay saturated and only the rim
goes pale.

## Swatches

Before → after, per slot. Luminance per rung is unchanged by construction
(±0.4 from rounding), so every row of this table is a chroma change only.

| ramp | slot | before | after | L | S before → after | H before → after |
| --- | --- | --- | --- | --- | --- | --- |
| meridian | S0 | `2b0f0e` | `2b0d16` | 23 | 0.67 → 0.70 | 2° → 342° |
| | S1 | `6b2320` | `811625` | 56 | 0.70 → 0.83 | 2° → 352° |
| | S2 | `a4362c` | `db1d1e` | 86 | 0.73 → 0.87 | 5° → 360° |
| | S3 | `d84a3c` | `da4a3b` | 115 | 0.72 → 0.73 | 5° → 6° |
| | S4 | `f2705a` | `e3775b` | 148 | 0.63 → 0.60 | 9° → 12° |
| | S5 | `ffc0ab` | `f7c3ab` | 208 | 0.33 → 0.31 | 15° → 19° |
| aurora | S0 | `0e1330` | `0c152f` | 21 | 0.71 → 0.74 | 231° → 225° |
| | S1 | `1f3070` | `143187` | 50 | 0.72 → 0.85 | 227° → 225° |
| | S2 | `2d47a4` | `1a48d3` | 74 | 0.73 → 0.88 | 227° → 225° |
| | S3 | `3c64d8` | `3c64d8` | 101 | 0.72 → 0.72 | 225° → 225° |
| | S4 | `6188f2` | `5c8de2` | 136 | 0.60 → 0.59 | 224° → 218° |
| | S5 | `bacdff` | `afd4fa` | 205 | 0.27 → 0.30 | 224° → 210° |
| verdant | S0 | `0d2113` | `0c2016` | 25 | 0.61 → 0.62 | 138° → 150° |
| | S1 | `174d24` | `144d29` | 56 | 0.70 → 0.74 | 134° → 142° |
| | S2 | `22682c` | `166e2a` | 76 | 0.67 → 0.80 | 129° → 134° |
| | S3 | `2c8636` | `2c8636` | 98 | 0.67 → 0.67 | 127° → 127° |
| | S4 | `51b45c` | `52b552` | 140 | 0.55 → 0.55 | 127° → 120° |
| | S5 | `b6ecbc` | `b4efac` | 214 | 0.23 → 0.28 | 127° → 113° |
| iron | S0 | `05070a` | `070708` | 7 | 0.50 → 0.12 | 216° → 240° |
| | S1 | `1b2026` | `1d1f23` | 31 | 0.29 → 0.17 | 213° → 220° |
| | S2 | `2b3238` | `2d3237` | 49 | 0.23 → 0.18 | 208° → 210° |
| | S3 | `79838d` | `79838d` | 129 | 0.14 → 0.14 | 210° → 210° |
| | S4 | `8f99a2` | `8e9aa1` | 151 | 0.12 → 0.12 | 208° → 202° |
| | S5 | `dfe6ec` | `dde8eb` | 229 | 0.06 → 0.06 | 208° → 193° |
| neutral | S0 | `1c1207` | `191310` | 20 | 0.75 → 0.36 | 31° → 20° |
| | S1 | `4a3a22` | `4d3826` | 60 | 0.54 → 0.51 | 36° → 28° |
| | S2 | `7a6440` | `826135` | 102 | 0.48 → 0.59 | 37° → 34° |
| | S3 | `a4874f` | `a4874f` | 137 | 0.52 → 0.52 | 40° → 40° |
| | S4 | `b89a5e` | `af9d65` | 156 | 0.49 → 0.42 | 40° → 45° |
| | S5 | `ecdcab` | `e8dcb5` | 219 | 0.28 → 0.22 | 45° → 46° |
| gunmetal | S0 | `14161a` | `151619` | 22 | 0.23 → 0.16 | 220° → 225° |
| | S1 | `3a4048` | `3b3f48` | 63 | 0.19 → 0.18 | 214° → 222° |
| | S2 | `5a626d` | `5a626e` | 97 | 0.17 → 0.18 | 215° → 216° |
| | S3 | `7a848f` | `7a848f` | 130 | 0.15 → 0.15 | 211° → 211° |
| | S4 | `a7b1bb` | `a5b2bb` | 175 | 0.11 → 0.12 | 210° → 205° |
| | S5 | `d2dae1` | `d1dadf` | 216 | 0.07 → 0.06 | 208° → 201° |

Two rows look like saturation *losses* and are not. Iron's S0 and neutral's
S0 sit at L7 and L20, where an 8-bit channel has three or four values to
spend: `1c1207` was "0.75 saturated" on a 28-unit-wide gamut, which is one
quantisation step, not a colour. What those rungs gained is the ambient —
neutral's contour is now a warm near-black leaning to the sky rather than a
brown one, and Iron's is neutral-black instead of a blue that no longer
resolves. The chroma that matters is on the rungs a model actually spends
its area on, S1–S4, and there the mid steps gained 8–15 saturation points.

The fixed accents (`amber`, `flame`, `skin`, glass, ...) go through the same
`build_ramp`, over the value ladder `_derived_ramp` already computed — so
their shadow steps pick up the same sky without their values moving either.

## Gate margins, measured after the change

The livery gates are all value gates, and the value ladders are unchanged, so
these are the same numbers to the digit except the two the chroma moves.

| gate | bar | before | after |
| --- | --- | --- | --- |
| `UnitBandCoverage` rim share above L200, worst unit | ≥ 3.00% | 3.13% (infantry/iron) | 3.13% (infantry/iron) |
| team-tinted share, worst unit | ≥ 55.0% | 60.61% (anti_air f0) | 60.61% (anti_air f0) |
| L160 row band: neutral vs loudest army | ≤ +1.00 pp | 13.89% vs 13.86% | 13.89% vs 13.86% |
| L160 row band: worst row vs chromatic ceiling | ≤ +1.00 pp | 13.89% vs 13.86% | 13.89% vs 13.86% |
| `neutral[S_TOP]` luminance | < 160 | 156.1 | 156.1 |
| smallest gap between adjacent rungs | > 12 | 18.2 | 18.2 |
| `RowSeparation` iron ↔ neutral | > 60.0 | 64.7 | **63.7** |
| `RowSeparation` closest faction pair | > 30.0 | 60.6 (neutral/meridian) | **63.7** (neutral/iron) |
| units atlas distinct colours | (budget) | 67 | 67 |

The iron↔neutral margin is the one to watch — it is the standing headroom
debt, and the shared ambient costs it 1.0 of its 4.7 points, because both
rows' shadow steps now lean toward the same sky. It buys back more than it
spends elsewhere: the *closest* pair over all ten was neutral/meridian at
60.6 and is now 63.7, because pushing chroma into the mid rungs separates a
warm khaki from a red faster than the shared sky converges them.

Meridian's faction pixels, as composed on the sheet: median saturation
0.674 → 0.698, p90 0.732 → **0.868**. The median barely moves because half a
sprite's faction area is S3, which may not move; the p90 is the shadow and
under planes, which is where the flatness was.

The shape itself is gated by `RampShape` in `tests/test_livery.py`:
the mid-ramp chroma peak, the shadow steps' pull toward `AMBIENT`, the rim's
turn toward the sun, and `build_ramp` landing on its ladder to within 0.6 of
a luminance step. Every one of the six shipped hex ramps fails at least one
of those, which is what the gate is for.

Re-measure with `~/.cache/grid_commanders/venv-sprites/bin/python tests/measure_livery.py`.
