# The mobile soak — 2026-08-26

The committed record of MB8 (mobile plan, MOB-13): what an Android build of this
game actually costs and actually survives. Like `docs/bulwark_balance.md` and
`docs/difficulty_check.md`, this is a **dated measurement** — a later soak
supersedes it wholesale rather than editing it — and it **tunes nothing**. Every
defect it names is reported here for the milestone that owns it; none was fixed
in the pass that measured it.

**Read the scope first: this is a partial soak.** The plan's proof line is
thirty minutes across a campaign mission, a four-army skirmish on a large board,
a replay watched to its end and a save resumed after backgrounding, *on a real
phone*. What ran was an **API 34 arm64 emulator** (`Pixel_3a_API_34`,
2220x1080 landscape, 440 dpi, SwiftShader through ANGLE) on a **loaded** Mac,
playing a Boot Camp skirmish against the computer. §5 lists what that leaves
owed. Nothing below is presented as a phone reading, and the one number that
would be meaningless from an emulator — frame rate — is not reported at all.

## 1. Method

Two clocks are read on the desktop by a new instrument,
`tools/run_mobile_soak.gd` (`make mobile-soak`), which is a measurement rather
than a gate: out of `make verify` and `make test`, writing nothing but the
scratch file its storage clock times and then removes, and touching nothing
under `core/` or `ai/`. Its planner loop is
`tools/run_bulwark_measure.gd::_play`'s — one `AIController` per army, neutral
commanders, the same per-turn safety net — with a clock around
`plan_next_command` and the result thrown away.

The device half was hand-driven over `adb` (taps, screenshots, `run-as` reads of
`user://`), because **a device build takes no launch flags**: Godot 4.7.1's
`GodotActivity` ignored both `command_line_params` and `command_line` intent
extras (`Launch intent … with parameters []` in `logcat`), so every scenario has
to be reached through the menus. That is a method fact MB9 inherits.

One instrument note, because it shaped what could be measured: **a `-s` script
cannot compile `BoardBeat` or `UnitSprite`** — they read the `Settings` autoload,
which a script main loop does not have (`Compile Error: Identifier not found:
Settings`). The board's own per-frame cost is therefore read from the running
scene (§4), not from the tool.

## 2. The planner clock — the R5 estimate is optimistic

Bulwark, 1+2+3v4, four computer seats, fog **on** (the live game's setting, and
the one that leaves the AR1 plan cache inert), 2 seeds x 20 days. Milliseconds.

| tier | commands | cmd mean | cmd p50 | cmd p90 | cmd max | **turn mean** | **turn max** |
|---|---|---|---|---|---|---|---|
| easy | 2552 | 40.2 | 21.4 | 106.7 | 290.8 | **640.4** | 2754.4 |
| normal | 2799 | 14.2 | 9.2 | 34.1 | 105.6 | **248.7** | 1073.8 |
| hard | 3187 | 28.7 | 15.7 | 71.1 | 285.0 | **571.8** | 1939.0 |
| brutal | 3863 | 38.3 | 20.9 | 100.3 | 408.7 | **924.1** | 3519.6 |

A *turn* is the sum of the planning calls between two `EndTurnCommand`s, which
is what a player waits through. Two more readings, same board and horizon:

| run | tier | turn mean | turn max |
|---|---|---|---|
| Bulwark, fog **off** | normal | 87.2 | 427.3 |
| `meridian` duel (1v2), fog on | normal | 18.3 | 37.7 |
| `meridian` duel (1v2), fog on | brutal | 146.4 | 362.8 |

Three things follow.

- **R5's "60–400 ms per computer turn" is a floor, not a band.** On a *desktop*
  the four-army board already means 0.25 s (Normal) to 0.92 s (Brutal) of mean
  planning per turn, with worst turns of 1.1–3.5 s — and up to three computer
  seats play back to back. A phone at 2–4x slower puts a Bulwark computer round
  in the **seconds**, not the hundreds of milliseconds.
- **Fog is the dominant term, and it is not a mobile decision.** The same board
  and tier plans 2.9x faster with fog off, which is the AR1 cache being live
  there and inert with fog on. Nothing here proposes changing that; it is the
  measured size of a known trade.
- **Board size dwarfs tier.** A duel board's Normal turn is 18 ms — 14x cheaper
  than Bulwark's. A phone plays the small boards comfortably today.

These numbers were taken twice. The first pass ran with the emulator up and the
machine at load ~16 and read roughly **2x higher** (Normal 504 ms mean / 2.6 s
max, Brutal 1.9 s / 7.4 s); the table above is the quiet re-read at load 6–12.
Both are desktop numbers on a shared machine, so read the **ratios** as the
finding and the absolutes as an upper bound on a good desk.

## 3. The replay recorder's per-command flush

`ReplayFile.append` stores one line and flushes it, once per applied command.
Desktop (SSD), 200 appends of a real encoded line (17 bytes):

```
append ms  mean 0.008  p50 0.007  p90 0.008  p99 0.028  max 0.134
```

Free next to a 250 ms planning turn. On device the write was proven to *happen*
rather than timed: after one day of play, `run-as` shows
`files/replays/2026-08-26T14-50-16.jsonl` at 1849 bytes, plus `files/save.json`
(2115 B, written from the map menu's Save) and `files/settings.cfg` carrying a
retired hint. **Nothing about storage looks like a mobile risk**, but a real
phone's flash still owes the timed reading.

## 4. The board's ambient beat is not a frame cost

Read off the running scene rather than the tool, headless with `--print-fps`
(process side only — headless draws nothing, so this is the CPU cost of
`UnitSprite._process` and its `BoardBeat` poll, not of rendering):

| board | mspf |
|---|---|
| `bulwark`, idle, hot seat | 0.28 |
| `boot_camp`, idle, hot seat | 0.24 |

About 0.04 ms per frame for a whole board's sprites. Whatever a phone's frame
budget goes on, it is not the beat.

## 5. The device soak — what was played, and what it found

Boot Camp, one human seat against the computer, no commanders, driven entirely
by taps. The whole loop worked: main menu → match setup → commander select
(twice) → battle → select a unit → END TURN → the ready-unit guard → *End
anyway* → a computer turn → day 2 → map menu → Save. No input dead end, no
duplicated command, no lost save, and no crash. Findings, in the order a reader
should care about them:

1. **The END TURN button loses its last drawn pixel to the dock** (MB3 review
   finding (a), reproduced). A tap at device y 947 (inside the button, ~1 canvas
   px above its bottom edge) opened the guard; a tap at y 952 — inside the
   button's bottom 2 canvas px, which is where the dock chips' `TouchTarget`
   rectangles overlap it — did nothing at all. The button is 17 canvas px tall,
   so this is a small strip, but it is a control that silently eats a press.
   **MB3's to answer**, not this pass.
2. **The mobile dock sits inside the system gesture strip.** The window is the
   full 2220x1080 while `mAppBounds` is 2220x**1014**: 66 px of the bottom edge
   belong to the navigation/gesture bar, and the dock row draws at device y
   ≈1013–1068 — effectively all of it. A *tap* still reaches the game (the
   window is immersive; the dock's NEXT chip walked the cursor to the next ready
   unit from y 1042), but any *swipe* that starts there is the system's, which
   is exactly the ground MB6's gestures want. This is MB7's residual, measured:
   under `aspect="keep"` the pillarbox pads the **sides** (the 640x360 canvas
   renders 1920x1080 with 150 px bars left and right) and nothing pads the
   bottom.
3. **`UiTheme.HUD_DOCK_H` is 28 canvas px** = 84 device px here, so the chips do
   clear a 44 pt finger on a 3x screen by growing out of the bar (MB3 review
   finding (b)). Recorded, not judged: it is only comfortable *because* the
   scale is 3x, and MB4/MB5's hit-rectangle work owns the general answer.
4. **Rotation is refused.** With `accelerometer_rotation=0` and
   `user_rotation=0` (portrait) forced, the display stayed 2220x1080 landscape
   and the game never reflowed.
5. **Background and resume are clean.** HOME then relaunch produced
   `OnPause`/`OnStop` then `OnStart`/`OnResume` with the same board, the same
   cursor and the same day; the only log noise is the expected
   `BufferQueue has been abandoned` on surface teardown. The process was never
   killed, so a *cold* resume from `save.json` after an eviction is still owed.
6. **The dock obeys the modal rule.** Under the end-turn guard and under the map
   menu the dock chips render dimmed and inert while the bar stays at full
   height — MOB-04's D5 requirement, seen rather than argued.
7. **The emulator is not a performance platform.** SwiftShader rendering
   2220x1080 burned ~490% CPU on the host and starved the emulator's own
   `system_server` into repeated ANRs ("Process system isn't responding"), which
   is why no frame rate, no turn wall-clock and no hitch measurement is reported
   from the device at all.
8. **Package**: the debug APK is 33,627,148 B (32.07 MiB), unchanged from MB1's
   reading.

Not measured, and honestly so: **audio interruption** (the emulator was booted
`-no-audio` to keep it affordable on a shared machine), **a campaign mission**,
**a four-army large board on device**, **a watched replay** — and with it the
Step chip, which MB3's review already records as never driven — and the plan's
**thirty continuous minutes**.

## 6. What the next soak owes

A real Android phone, one sitting, in this order: a campaign mission with its
objectives card up; a four-army Bulwark skirmish, timing the computer round with
a stopwatch against §2's desktop figures; a replay watched to its end using the
dock's Pause/Step/Resume only; a save resumed after the app has been evicted
from memory (not merely backgrounded); and a phone call or alarm over the top of
all of it for the audio interruption. Add `dumpsys gfxinfo <pkg> framestats`
around the computer round if the hitch needs a shape rather than a stopwatch.
