# Grid Commanders

A turn-based tactics game in the style of Advance Wars, built with Godot 4.7 and
typed GDScript. Its designs of record ship with it under `.lavish/`; `CLAUDE.md` lists them and
which decisions each one owns.

## Running

The engine binary is vendored (gitignored) at `bin/Godot.app`. To set it up:

```sh
mkdir -p bin && curl -sL -o /tmp/godot.zip \
  https://github.com/godotengine/godot-builds/releases/download/4.7.1-stable/Godot_v4.7.1-stable_macos.universal.zip \
  && unzip -q /tmp/godot.zip -d bin/
```

`make lint` and `make format` additionally need [gdtoolkit](https://github.com/Scony/godot-gdscript-toolkit)
(`pipx install "gdtoolkit==4.*"`). Everything else runs off the vendored engine alone.

Working in a `git worktree`? `bin/` is gitignored, so a new worktree has no engine and every
target fails with "Godot binary not found". Symlink the one you already have:
`ln -s /path/to/main/checkout/bin bin`.

Then:

```sh
make run             # boot the game — the menu (map, seats, difficulty, speed, commanders, fog, Start / Continue)
make hotseat         # skip the menu: straight into a two-player hot-seat match (no AI)
make verify          # the merge gate: check + lint + format-check + test, in one command
make smoke           # drive the demo scenarios (the battle scene, plus the menu ones); prove each still renders
make test            # run the GUT unit test suite (headless)
make check           # audit every .gd file: parse/types + architecture seams
make lint            # gdlint — style and smells (config: gdlintrc)
make format          # gdformat — reformat in place; format-check only reports
make tiles           # rebuild the art: ground tiles, PixVoxel + vendored unit sprites, audit, import
make unit-sprites    # re-paste the vendored unit sprites into the units atlas
make unit-placeholders    # audit the finished atlas for a cell no art reached (none today)
make sprites-check   # verify the PixVoxel build inputs without writing anything
make unit-sprites-check   # verify the vendored unit sources without writing anything
make sfx             # regenerate the placeholder sound effects (headless)
make portraits       # regenerate the commander portraits + faction emblems
make import          # (re)import assets headless
make screenshot      # boot the battle scene, save screenshot.png, quit
make menu-screenshot # the same, for the main menu
make gallery-screenshot   # render all thirteen commander cards (the G1 gate)
make commander-balance    # offline AI-vs-AI balance matrix -> reports/ (a release task)
make difficulty-check     # AI-vs-AI difficulty ladder gate -> reports/ (a release task)
make balance-sim          # the Balance Lab: any board, any commanders, any tiers, full telemetry
make balance-watch        # watch a Balance Lab match play out live, both sides AI
```

`make verify` is the one command to run before merging: it parse-checks, lints, checks formatting,
and runs the suite, cheapest step first. Every headless run ends with `ObjectDB instances were
leaked at exit` and `resources still in use` — that is the engine failing to tear down a *script*
reference cycle (`AttackCommand.validate()` referring to its sibling `MoveCommand` pins the core
script graph), reproducible in twelve lines with no GUT involved. No gameplay object leaks, so the
gate reads exit status and ignores it.

`make smoke` covers what unit tests deliberately do not: GUT is limited to the Node-free layers
(see Architecture below), so the battle scene — and, for the `menu_` modes below, the main menu — is
verified by driving it. Each demo scenario runs the same handlers a player's input reaches and must
still produce a frame. It renders, so it needs
a display — it is a local gate, not a headless-CI one. Narrow it with
`make smoke MODES="attack capture"`, and keep the captures to look at with `SMOKE_KEEP=1 make smoke`.
A name no scenario implements fails the run rather than photographing a board nothing ever staged,
so a typo in `MODES` is a failure and not a quiet pass.

The whole sweep runs in one engine process and one window: it hands the driver every scenario as a
single queue, each entry carrying its own boot facts — scene, fog, map — and the driver reloads the
battle scene between scenarios and scene-changes for the `menu_` modes. The output lines are
unchanged, and a sweep that fails in any way is automatically re-run one process per scenario, so a
failure always names a scenario (the batch's own log is kept and reported when that happens).
`SMOKE_ISOLATE=1 make smoke` skips batching altogether and runs the one-process-per-scenario path,
which is the way to bisect a scenario suspected of leaning on a batched neighbour's leftover state.

The one window is still activated as it opens and again on each scene change, so a sweep briefly
takes the front app away from you. `tools/focus_timeline.sh make smoke` measures that instead of
guessing: it wraps any command, samples the frontmost app for its whole lifetime, and prints the
timeline with runs of the same app collapsed, plus the steal count, the total and longest stolen
interval, and every restore that landed on some other app. It is macOS-only and says so (elsewhere
it runs the command untouched), exits with the wrapped command's own status unless the wrapper is
signalled (then it prints the partial timeline and exits 128+signal), and is deliberately in no
`make verify` gate — like the sweep it measures, it needs a display and a human's desktop. The
script's header comment owns the details, including `FOCUS_THIEF`.

A mode may carry a `+fog` suffix (`make smoke MODES="victory+fog"`) to rerun that scenario with fog
of war on. Fog is the only setting under which the scene hides units rather than just drawing them,
so two scenarios run both ways by default.

A mode whose name begins `menu_` boots the **main menu** instead of the board — the only scenarios
that photograph a screen the battle scene never draws:

```sh
make smoke MODES="menu_with_save"     # Continue live, on a long-named board at DAY 128
make smoke MODES="menu_no_save"       # the same layout with an empty slot, Continue greyed out
make smoke MODES="menu_setup_context" # an all-human table: every option's help line, AI difficulty dimmed
```

All three pose the save slot themselves, so a capture neither reads nor writes the running machine's
`user://save.json`, and all three are tests as well as pictures: each measures the whole centered menu
column, its map caption, every option-help line, every seat row *and* all three primary actions
against the 640×360 logical frame and fails the run if any of them leaves it. The column is the
load-bearing witness — a too-tall one is centered into an offset that runs off both ends at once, so
no single child is reliable — and the first two exist to hold the rule that a save's presence may
never change the layout budget, which is what broke when Continue first pushed the title and **Quit**
out of frame. Enclosure is not the whole gate: rows a container has not sorted yet keep their minimum
size and stack on one spot, inside every frame and drawn in none of it, so the seat strip is also
asked whether it is the table it was dealt.

`menu_setup_context` adds the half a picture cannot prove: that the tutorial board leads the picker
and its description is printed, that no option-help line is empty, that the reserved caption holds
for *every* shipped board and not just the one on screen, and that AI difficulty follows the table —
it seats a computer and unseats it again, because a dimmed control photographs the same whether it
can be undone or not.

The cut-ins — combat and its capture sibling — have their own family of modes, because they are
deliberately suppressed while capturing — a mid-animation frame is what would make two identical
captures differ. These pose the overlay at a fixed moment of its own clock instead, and the combat
modes carry the matchup in the name:

```sh
make smoke MODES="cutin"                      # the frontline tanks, defender survives
make smoke MODES="cutin_ko"                   # the same pair, defender routed
make smoke MODES="cutin_volley"               # the same pair, frozen with the round still in the air
make smoke MODES="cutin:bomber:tank"          # any matchup, staged wherever it fits the board
make smoke MODES="cutin_skip"                 # walks a skip across every beat; must never hang
make smoke MODES="capture_cutin"              # a completing capture, late in its banner
make smoke MODES="capture_cutin_partial"      # an occupying capture, the property not yet flipped
make smoke MODES="capture_cutin_skip"         # the same skip walk over the capture cut-in
make smoke MODES="cutin_iron_commander"       # Iron v Verdant: the cut-in must wear the board's factions
make smoke MODES="capture_cutin_iron_commander"   # the same, on the marching squad and the property
make smoke MODES="cutin_scenery:mech:mech"    # fought over woods and mountain: trees one half, peaks the other
```

`cutin_volley` is the only one posed *before* the round lands, and that is its reason to exist: a
unit picks its weapon by matchup, so each weapon's own firing signature — the machine gun's
stream, the cannon's shell, the missile, the lobbed bomb, the torpedo's wake, the flak burst — is
only on screen while the shot is in flight. The impact frames show what a hit looks like and
nothing of what threw it.

The two `_iron_commander` variants are the only cut-in modes that run *with* commanders, and that is
their whole reason to exist: a commander-less side draws in the row its slot number names, so a
surface reading a team int where an atlas row belongs looks correct in every other capture. They
stage Iron against Verdant — rows 3 and 4, neither equal to its slot — and fight over a property
apiece, so the armies, the ground and the flipping building all carry a faction row.

`cutin_scenery` covers the other half of the ground plane. A terrain either *paves* that plane with
its own art or *stands* a drawn shape on it, and three shapes stand: `cutin_iron_commander` already
fights over a base and an HQ and so sweeps the buildings, but every other mode fights on plains,
road or open water, all of which pave — leaving trees and peaks photographed by nothing, though
either turns up the moment a unit fires from woods or a mountain. This one stands the pair on the
default board's adjacent woods and mountain, one shape per half, and carries its matchup because a
mountain takes foot and boot only.

Every cut-in mode is a test as well as a picture: each reads the atlas rows back off the posed art
and fails the run unless every one is the row `SideIdentity` gives that side. A cut-in painted in
the wrong faction's colours writes a perfectly good frame, so "a capture exists" could never have
been the check.

The variant names above are the whole set — plus the two the capture family composes,
`capture_cutin_partial_skip` and `capture_cutin_partial_iron_commander` — and a mode is checked
against it before anything is staged: `capture_cutin_partail` fails the run rather than quietly
posing a completing capture, and `cutin_iron_commandr` fails rather than photographing the
commander-less frame under the acceptance mode's name. A typo that still poses *a* cut-in is the
one thing the row checks cannot see, because the frame they check is correct — just not the one
that was asked for.

`cutin_skip` and `capture_cutin_skip` are the ones that are tests rather than pictures: each plays
the same cut-in ten times, skipping one frame later each time, and fails unless every run finishes
exactly once. Both call sites hold the whole interaction flow on that, so a cut-in that ever failed
to finish would freeze input for the rest of the session.

`--no-battle-anim` forces the cut-ins off for one run without touching the saved preference, which
is how "with the animation off, the match plays out identically" is checked against the offline
harness.

Run a single scene directly: `bin/Godot.app/Contents/MacOS/Godot --path . scenes/battle/battle.tscn`.

Twenty maps ship. The main menu leads with the teaching board and lists the rest smallest first —
`boot_camp`, `scrimmage`, `forge`, `foursquare`, `trident`, `compass`, `pinwheel`, `timberline`,
`arsenal`, `riverline`, `isthmus`, `jet_stream`, `windrose`, `crossfire`, `first_steps`,
`the_straits`, `marchlands`, `ironworks`, `steelworks`, `heartland` — so it opens on `boot_camp`,
badged **Tutorial**, and prints the selected board's size,
army count (a range, `2–4 armies`, on a board where seats can be closed), property count and
one-line pitch in a caption under the grid (the per-cell tooltip repeats them for a mouse).
`foursquare`, `compass`, `pinwheel`, `windrose`, `marchlands` and `heartland` seat **four armies**,
and so offer the one-tap table presets in the seat strip. `foursquare` is the smallest, 12×12 and the
quickest full free-for-all in the roster: a seat in each corner in reading order — 1 NW, 2 NE, 3 SE,
4 SW — laid out under a quarter turn rather than the half turn `# symmetric` checks, so the two
opposite pairs make a fair duel and every seat's nearest cities sit the same distance out. It is also
a production board (below): nobody opens holding an army. `compass` puts an HQ and a
base at each compass point, with eight cities in a ring that closes under a half turn, so every
army's nearest two sit the same distance out. `pinwheel` seats its four at the same corners on a
14×14 laid out under the same quarter turn, `(x, y) -> (13 - y, x)`: four road blades leave their
own base, run the long edge clockwise and hook into the *next* seat's flank, so the opening question
is whether to race the wheel or cut the wooded hub in the middle. The infantry screens of
neighbouring seats meet on day 2; opposite seats — the fair duel, 1&3 or 2&4 — take until day 3.
`windrose` is the four-army air board: 17×17, laid out under a **quarter
turn** about its centre cell, seats at the corners in reading order — 1 NW, 2 NE, 3 SE, 4 SW — so the
opposite pairs 1&3 and 2&4 duel across the long diagonal. Each army opens on an HQ, a base, its own
airfield and two cities; a fifth, neutral airfield stands on the centre cell, and mountain ridges
wall each quadrant off from its two neighbours with one pass apiece, so armour meets a neighbour at a
chokepoint or goes the long way round through the middle while a t-copter simply crosses.
`marchlands` at 22×16 is the board built for the **2v2**: a wooded
ridge splits it north from south with four road passes over, seats 1 and 2 north of the ridge and
3 and 4 south, so `--sides=1+2v3+4` gives each pair a shared front and its own purse instead of two
armies standing back to back. It is not laid out on a quarter turn — a 22×16 rectangle cannot be —
but on the whole rectangle's symmetry, the two flips and the half turn, which carries every corner
onto every other: the 2v2 across the ridge is fair by the flip, an opposite-seat duel (1&3, 2&4) by
the half turn.
`heartland` at 28×20 is the **largest board in the game** and
the grand tier's: a lattice of 48 neutral cities, **two bases** to each seat's one HQ, roads down the
diagonals to a central crossroads, and woods for cover rather than a chokepoint anywhere — the
economy scales with the area, so a board this size still escalates. `trident` seats
**three**, each a prong of the fork around a central massif, where the only grouping worth naming is
a pair against the odd one out. Every other shipped board is a duel. `boot_camp` is also the only
board the first-match mission strip runs on — see **Controls** below. `jet_stream` and `the_straits`
are the boards air and naval units were added for: the first puts an airfield behind each front, the
second a port on each coast of one shared channel.
Three of the older boards have since been retrofitted with the domains that suit them — `isthmus`
gained a port and a landing beach per side, `ironworks` and `crossfire` an airfield each — while
`boot_camp`, `first_steps`, `scrimmage`, `timberline` and `riverline` deliberately stay land-only,
because each is built on a barrier that wings or hulls would simply erase — or, for `boot_camp`,
because the five things it teaches are the land game's. `foursquare`, `compass`, `pinwheel`,
`trident`, `marchlands`, `windrose` and `heartland` carry no water either: the computer cannot
plan a ferry, so a board it may have to fight
across in any grouping has to let every army reach every other on foot — which on `windrose` leaves
the air as the one domain that ignores the board's walls.
The multi-army boards seat their armies at the corners in reading order — 1 NW, 2 NE, 3 SE, 4 SW —
so the fair duel on a four-seat board is an opposite pair, 1&3 or 2&4. A square board makes that
true by quarter-turn; `heartland` is 28×20 and cannot rotate onto itself, so it is laid out under
the rectangle's own symmetry instead, mirrored left-right and top-bottom. Every seat's corner is
then a reflection of both its neighbours' and an exact half-turn of its opposite's: no seat is
favoured, and each has the same near neighbour (15 cells of HQ separation across the short axis)
and far one (23 across the long).

`forge`, `foursquare`, `arsenal` and `steelworks` are the production boards, and the only ones that
hand out **no starting units at all**: what you get instead is factories. On `forge`, `arsenal` and
`steelworks` that means two to four bases a side where the rest of the roster tops out at two, an
owned airport a side on the larger two, and neutral bases and airports to expand production itself.
`foursquare` is the lean one and the four-way answer to `forge`: one base an army, no airport, no
neutral base — just twelve neutral cities — so 2000 a day until somebody takes ground, and the
whole match is the escalation curve. The opening is a build order rather than a march, and
`steelworks` at 26×18 is the largest of the duel boards. An empty day 1 is legal without any rules
change: defeat is only ever checked when a unit dies, and the AI's planner already falls through to
production when it has nothing to move.

Command-line flags still override the menu so demos and tools can skip it: `--map=crossfire`,
`--hotseat`, `--fog`, `--difficulty=hard`, `--speed=slow`, `--seats=1,3` (which of the board's seats
play — an unnamed seat stays empty: its units never enter and its properties open neutral),
`--co=alina_ward,viktor_draeg` (one id per playing seat in seat order; any of them may be left blank
for no commander) and `--sides=1+3v2+4` (armies joined by `+` stand together, groups separated by
`v` fight each other) — e.g.
`bin/Godot.app/Contents/MacOS/Godot --path . scenes/battle/battle.tscn -- --map=crossfire --fog`.
`--sides=1v2v3v4` and an absent flag are the same free-for-all; a grouping that cannot be read, or
that leaves the board's armies with nobody to fight, is reported and the free-for-all played instead
— as is one allying a seat the same launch closed. A `--seats=` naming a seat the board never deals,
naming one twice, or leaving fewer than two armies is refused and no match is built.

Adding a map is dropping a `.txt` in `maps/` — the menu auto-discovers it and `tests/unit/`
holds it to the playability invariants (one HQ and a base per side, reachable HQs, the same
properties dealt to every seat kind for kind, a claimed `# symmetric` tag that actually mirrors)
and plays an AI-vs-AI match on it. Boards that use the
water get four more: every port opens onto sailable sea, all of a map's ports share one body of it
(the AI cannot ferry, so a fleet it cannot sail to is a fleet it can never fight), every beach is
reachable by a lander, and no beach chain quietly joins two landmasses — a shoal costs every land
class exactly what road does, so a careless one is a bridge. See the format at the top of
`core/map_data.gd`; the first comment line is the tooltip description.

Any Godot 4.7+ works too — open the project folder in the editor.

## Main menu

The game boots to the menu: pick a map, set the **seats**, pick a **Difficulty** and a **Speed**,
toggle **Fog of war** and **Battle animations** (the full-screen combat and capture cut-ins — a saved
preference, on by default),
then press **Start**, which opens the **commander selection page**; **Continue** skips selection and
resumes the save with its own map, fog setting, difficulty, commanders, grouping and AI sides. A line
under it names what it would resume — `DAY 13 · ARSENAL` — so the menu alone answers whether the save
is the match you meant; when there is nothing readable to resume it reads `NO SAVED MATCH` and the
button is greyed out (disabled, not hidden). **Quit** exits.

The **seat strip** is one row per army the board deals — how many there are is the board's answer, so
it re-deals itself whenever you pick a different map. Each row is a **Human** / **CPU** choice and a
side badge — one letter per army the board seats, **A** to **D**: armies sharing a badge fight as
allies, and armies each on their own badge are a free-for-all. A board seating more than two adds a
third choice, **Empty**: a closed seat brings no army at all — its units never enter and its
properties open neutral for the others to take — so its side badge disappears with it, and the
button greys out whenever closing one more seat would leave fewer than two armies (a duel board
never shows it at all). The defaults are the one-click paths the two old mode buttons gave you —
every seat open, seat 1 human, every other seat the computer's, every army its own side — so a duel
still sets up in the clicks it always did: **Human/A** against **CPU/B**. Putting a
person in every seat is the old hot-seat game. A four-army board additionally offers one-tap tables
— **Free-for-all**, **2v2**, **3v1**, **Duel** and **Three-way** — each setting the seating and the
grouping together (**Duel** seats the opposite pair, 1 and 3). **Start** greys out, and says why, if
fewer than two armies are seated or the badges leave nobody with anyone to fight.

Nothing decision-critical is behind the mouse: the map picker prints the selected board's size, army
count, property count and pitch beneath the grid, and **Difficulty**, **Speed**, **Fog of war** and
**Battle animations** each carry a permanent one-line explanation. **Difficulty** is match-wide — it
tunes every CPU seat at the table, never one of them — and greys out the moment there is no computer
seated at all, coming back as soon as one is. Each setting's dotted-underlined label — **Speed**,
**Difficulty**, **Fog of war**, **Battle animations** — still elaborates in a tip anchored to it, on
hover or on keyboard focus, and so do the map cells and the line under **Continue**; leaving, tabbing
away or pressing Escape dismisses one.

The selection page is a walk through the seats that play — a seat closed in the strip is skipped:
you pick **P1**'s commander, confirm, then the next seated player's, and so on — the chips along
the top preview each seat's faction name
and colour as you browse, mirror rule included, and say **CPU** for a seat the computer plays. Four
faction tabs and three peer portraits let you browse; one focused card shows the highlighted
general's doctrine and Command Power in full (no hover tooltips), and a deliberate **No Commander**
plays the plain rules.
Mouse, keyboard, and controller all navigate it, and **Back** rewinds one seat — from the first it
returns to the menu without discarding the map, seat or fog choices. Nothing is committed until every
seat is locked.

In battle the side in hand gets a portrait and charge meter in the docked bottom HUD bar — the
portrait field in the side's resolved faction colour, the power named beside the meter it charges,
and a readout that reads the live charge, `READY · F`, or `ACTIVE` — plus a faction-tinted
activation card when a power fires, a reference sheet from the map menu carrying one card per army
in the match, allies side by side (which also says what makes the meter rise), and a portrait on
the victory screen.

## Controls

By default you play the first side and the computer plays the rest; the seat strip in the menu is
what changes that. A computer turn plays itself — play is blocked while the AI moves, attacks,
captures, and builds (a confirm during it answers *CPU turn.* rather than going quiet), and the
cursor follows each of its actions so you can watch. Cancel is the one key that still acts: it
pauses the turn and opens the map menu (see the controls list below). `make hotseat` drops the AI
and lets two players share the keyboard instead.

Either way, only the team whose day it is can act; a banner announces each turn and the cursor
jumps to that team's first property. Every banner — the day card, the save and speed confirmations,
"Ambush!", an army's elimination, a power's activation card — holds play for its beat, and any key,
mouse button or pad button skips it. The press does that and nothing else: it never lands on the
board underneath, and no menu opens beneath a banner.

A first match on `boot_camp`, the **Tutorial** board, opens with a **mission strip** over the grid:
the objective line and five hints — select, move, capture, build, end turn — each retiring for good
the first time you perform it, on your own actions only (the computer taking a city retires
nothing). Every other board is an ordinary match: no strip, and nothing retired behind your back.
Retirement is a device preference in `user://settings.cfg`, so hints never come back across a
relaunch; `--reset-hints` forgets them all for one machine, which is how a fresh install is staged
for testing.

On a controller, the D-pad or left stick moves focus and the grid cursor. The bottom face button
(A / Cross) confirms, the right face button (B / Circle) cancels or opens the map menu, the right
shoulder (RB / R1) zooms in and the left (LB / L1) zooms out, the left face button (X / Square)
shows a unit's range, the left stick's click (button 7) raises and lowers the threat lens, and the
top face button (Y / Triangle) fires a ready Command Power. The same
face buttons confirm and back out of menus. One push of the stick is one step: the cursor and a
menu highlight move a single cell or row per gesture, and the stick has to return to centre before
it asks again.
The docked on-screen legend keeps the compact keyboard labels; the actions themselves accept
mouse, keyboard, or controller throughout.

- Arrow keys / mouse hover: move the grid cursor
- Mouse wheel or `+` / `-`: zoom
- Confirm (`Enter` / `Space` / `Z`) or left-click on one of *your* units: select it and highlight
  its movement range; move the cursor within range to preview the path — a red arrow laid squarely
  along the cells the unit would walk, its head on the one it would stop on — then confirm a
  destination to move there. Remaining fuel caps that range, so a dry unit is stranded where it
  stands
- Cancel (`Esc` / `X` / `Backspace`): deselect, or undo an uncommitted move — and, with nothing
  selected, open the map menu, which is the control the top bar's resting key legend names
- Confirm or left-click on a unit you *cannot* command — an enemy, or one of yours that has
  already acted — previews where it could move, in the same blue overlay. Clicking another
  visible unit moves the preview there (a ready unit of your own still just selects), and cancel
  or a click on an empty tile dismisses it. It is a look, not an order, and fog applies: a unit
  you cannot see cannot be inspected. Whose unit it is decides what the blue can promise. Your own
  — the one you are about to move, and equally one of yours that has already spent its day — shows
  its whole reach. A unit belonging to another side shows your best reading of its reach rather
  than the truth of it: it is drawn from what *you* have scouted, so it stops at the edge of ground
  you have never seen and treats a unit you have not found as though it were not there. Expect an
  enemy to sometimes go further than the blue showed — that is the fog doing its job, not the
  overlay lying to you
- A confirm the board refuses says why, in a chip beside the cursor that fades on its own and never
  blocks play: *Already acted.* on one of yours that has spent its day, *Ready next day.* on one you
  built this turn, *Occupied.* on a destination in range held by a friendly unit the mover can
  neither load into nor join, and *CPU turn.* while the computer is playing
- Cancel *while the computer is playing* pauses it, and the top bar says so before you press it
  (`CPU PLAYING   ESC · PAUSE`). The turn stops at its next command rather than mid-animation, so
  the press is answered by a *Pausing…* chip and the board settles a beat later under the same map
  menu you get on your own turn — minus the two rows that would act for the side in hand, End Turn
  and the Command Power. Closing that menu leaves the match held (`PAUSED   ENTER · RESUME   ESC ·
  MENU`), with the cursor free to walk the board and read tiles; confirm hands the turn back and
  the computer picks up where it stopped. In a match where every seat is a computer's this is the
  only way to a menu at all — and so the only way out short of quitting the application
- `R`, while any unit's movement range is on screen — selected or previewed — toggles a red
  overlay of the cells that unit could bring under fire this turn: a direct unit firing from
  anywhere it could stop, an indirect only from where it stands, since it cannot move and shoot.
  The same split as the blue: on one of your own units that is every such cell, whatever the fog;
  on another side's it is the same reading as the blue beneath it, drawn from what you have
  scouted. It shows what the weapon *reaches* — a unit with no shot left still shows its ring, one
  resupply from meaning it — and it paints over the blue until pressed again
- `T` raises and lowers the **threat lens**: red stripes over every cell a side hostile to you
  could bring under fire, all of them at once. It is `R`'s sibling and its opposite in scope —
  `R` asks what *this* unit reaches, the lens asks where it is unsafe to stand. It issues nothing
  and belongs to no unit, so unlike the fire ring it survives selection, movement and the turn:
  nothing puts it down but pressing `T` again. The top bar's `T · THREAT` chip says which it is,
  dim while the lens is down and red while it is up. It is the red half of the same bargain the
  blue makes: only enemies you have actually spotted are in it, and their reach is drawn on ground
  you have scouted, so under fog an unshaded cell is not a promise of safety — only that nothing
  you have found covers it. A unit you have never scouted, one sitting in woods, or one a
  commander's doctrine is hiding all shoot into cells the lens leaves clear. Turn fog off and
  those go with it — every one but a submerged submarine, which is under the water rather than
  merely out of sight and so stays unshaded on a clear day too, until one of your units is
  standing beside it
- After a move, the action menu opens: **Fire** (offered only when an enemy the unit has a ready
  weapon for is in range from the destination), **Capture** (offered when a capture-capable
  unit ends on a property you don't own), **Drop** and **Supply** (see transports below),
  **Wait** (commit the move), or **Cancel** (revert it)
- Choosing Fire enters targeting: attackable enemies get a red overlay and a panel previews the
  attack and counter damage; confirm on a target to resolve combat, or cancel back to the menu.
  The preview speaks HP out of 10 like every other HP display — "Deal 5–6 HP / Take 2–3 HP",
  with "Target 10 → 4–5 HP · 55% · luck included" underneath, where the dimmed percentage is
  the luck-free damage kept as secondary detail so a chip attack worth less than a displayed HP
  still shows what it took off. Every bound is the luck range the attack will roll inside — the
  attacker's answers for the opening roll too, since a lucky shot weakens or removes the counter —
  so a span of one is the roll and a single number is a certainty; the numbers come off
  `CombatResolver.Forecast`, which the panel formats and never recomputes
- Confirming onto a reachable cell held by one of *your* units offers **Load** (board a transport
  with room) or **Join** (merge into a damaged unit of the same type, adding up HP, fuel, and
  ammo). Cancel snaps the mover back, as with any uncommitted move
- A loaded transport offers **Drop** — one row per passenger with somewhere legal to step off, so
  a Lander carrying two shows a row naming each. Choosing one enters a cell picker: that
  passenger's legal unload cells get the blue overlay, and confirming on one puts it out there,
  exhausted for the turn. What a
  transport carries is its own: an APC or a T-Copter takes infantry, a Lander takes two of anything
  that drives — and unloads only onto a shoal or a port, since a landing craft cannot tip a tank
  over the side mid-channel. **Supply** refills every friendly unit within the APC's supply reach —
  normally the adjacent tiles, further under a commander who says so
- Moving spends fuel equal to the terrain cost of each step, discounted by any doctrine that makes
  that step cheaper, so you are never billed more than the range overlay showed; firing the main
  gun spends one ammo, and so does a counter-attack fired with it, so a dry unit with nothing else
  to shoot can neither fire nor counter. A Tank, a Md Tank and a Mech carry a machine gun with
  unlimited ammunition alongside that main gun, and the rules pick between the two for you: the
  machine gun is always what they answer infantry, Mechs and copters with, and it takes over
  against everything else they can hit — every land and air target; ships stay the main gun's
  alone — once the main gun runs dry, so those three are never silenced. Which one it was is on
  screen: the battle cut-in gives every weapon its own muzzle, round and recoil, and names it on a
  chip beside the unit — the same tank strafes a foot squad and slams its cannon into another one.
  At the start of your turn every unit standing on a property that services it, or in reach of one
  of your APCs, is refilled — and a transport tops up every unit riding aboard it. Which property
  services what is the point: a city refits vehicles, an airport
  aircraft, a port hulls, and none of them does another's job
- A submarine adds one row of its own: **Dive** takes it under, **Surface** brings
  it back. Submerged, only a Cruiser or another Sub can engage it, and it is
  invisible to the other side unless one of their units is standing right next to
  it — with or without fog, since being under the water is not a question of how
  far anyone can see. It does not shoot back while hiding, and staying under costs
  it five times the fuel, so a dive is a decision rather than a default
- Aircraft and ships burn fuel simply by existing — a few points every turn, before anything
  refills them — and are **destroyed** when the tank runs dry. A warning badge appears on any unit
  inside its last turn's worth of fuel. Ground units have no upkeep: an empty tank strands them and
  nothing worse. That is what makes airfields and ports worth taking rather than decoration
- Confirm on one of your empty production properties — a base, an airport or a port: the build menu
  lists what *that* facility makes, cheapest first, each row drawing the unit's artwork in your
  team's colours beside its name and cost; rows you can't afford are greyed out. A bought unit
  spawns exhausted and acts next turn
- Confirm on an empty tile, or cancel with nothing selected: the map menu opens with **End Turn**,
  which hands play to the other team (the day counter advances when the rotation wraps back to the
  first side), and **Save**, which writes the whole match — map, day, funds, ownership, every unit,
  both commanders, and the RNG stream — over the single save slot. The banner names what it stored,
  `Saved Day 4 · Scrimmage`, in the same words the menu's Continue line reads back, and says instead
  that the save failed when the disk refused it — a write that cannot land leaves the save you
  already had exactly as it was, so a full disk costs you the save you just asked for and never the
  one you could still resume. Resume it later with **Continue** on the main menu. When your Command
  Power is charged the menu lists it first, so it is reachable from the keyboard as well as from the
  HUD button
- **End Turn** asks first when any of your units still standing on the board can act — a passenger
  riding a transport is not one of them: a panel names how many are ready and lists each with its
  tile — *Tank at (4,1)*, in the board's own zero-based cells — and offers **Review units**, the
  already-highlighted answer, which closes it on the same turn with the cursor on the first of
  them, or **End anyway**, which hands play over as before. Left/right pick, up/down
  scroll a list too long to fit, Enter takes the highlighted action and Esc reviews; clicking a
  button works the same, as do the controller's D-pad or left stick and confirm/cancel face
  buttons. A turn with nothing left to act skips the panel entirely, and the computer's turns
  never see it
- The same menu is how you leave a match without closing the game. **Save & Main Menu** writes the
  slot exactly as **Save** does and only then goes back — a failed write keeps you on the board and
  says so — while **Main Menu Without Saving** asks a second time first, on a two-row confirmation
  whose safe answer is the one already highlighted. Neither adds a slot: the save model stays the
  single one Continue reads
- The HUD is two opaque bars docked above and below the board, never panels floating on it: the
  board sits in the band they leave over, and only transient things — damage numbers, the capture
  counter and the badge on the tile being taken, the movement arrow, the attack forecast, the
  action menu, the first-match mission strip — are ever drawn
  over terrain. The **top bar** carries the day, the side in hand as a faction colour chip and
  name, that commander's doctrine, the funds, a `T · THREAT` chip — dim while the threat lens is
  down, red while it is up — and a one-line **key legend** that swaps with the
  interaction — `ENTER · SELECT   ESC · MENU   +/- · ZOOM` at rest, `ENTER · FIRE   ESC · BACK`
  while targeting, and so on. The **bottom bar** carries, left to right: the commander's
  portrait, name, power name, and — for a side playing a power — the charge meter with its
  `charge / cost` readout, which reads `READY · F` when it is full and `ACTIVE` while it runs,
  plus a **FIRE** button (see Commanders below); then the unit on the hovered tile, if any — its
  sprite, name, HP as ten pips, fuel and ammo out of their maximums — `MAIN 6/9 · MG ∞` for one
  that also carries a machine gun, and no ammo readout at all for one that needs none — and an
  order line opening with `ENEMY` — or `ALLY`, once a match seats armies standing together — for a
  unit that is not yours and nothing at all for one that is, then naming its movement class, its
  range when it is an indirect, `DIVED`, `LOW FUEL`, `CARRYING …` when it is a loaded transport,
  and `WAITED` or `READY`, with
  the sprite greyed once it has acted this turn; then, pinned right, the tile's artwork, name,
  defense stars, owner, and `CAP N` while a capture is in progress — a count the tile itself also
  wears, as a green flag and the points still owed, so contested properties read at a glance
  instead of one cursor walk at a time. Under fog only the tiles you can currently see carry it: a
  capture you have not scouted stays as unannounced as the flip that will follow it. With nothing
  under the cursor the unit and tile thirds go blank and the bar keeps its height — the board
  never shifts
- An army that loses its home HQ — the one it started the match on — or its last unit is out of
  the match, announced by a banner — *Iron
  Dominion eliminated* — over the board that felled it, before play hands over. In a duel that is
  the win, so the banner runs straight into the victory screen
- Taking the enemy HQ or destroying every enemy unit ends the match on a victory screen naming
  the winner and the day, with **Rematch** (same map, fog, commanders, and sides) and **Main Menu**.
  It opens with neither action highlighted and ignores presses and clicks for half a second, so a
  key still held from the last battle cannot restart the match; the first press after that only
  highlights an action, and a second one takes it. Armies that won together are named together —
  *Meridian Coalition & Aurora Compact win!* — and from two eliminations up the day line lists who
  fell, in the order they fell

## Commanders

Each side may field a general whose *doctrine* bends the rules for their whole army — attack and
defence, movement, vision, supply, capture — and who charges toward one **Command Power** that
bends them further for a turn.

Twelve ship, three to each of four factions (Meridian Coalition, Iron Dominion, Aurora Compact,
Verdant League). `data/commanders/` is the roster: one `.tres` per general, carrying their
doctrine line, power name and description, and every balance number. Read it — or the selection
page's card, which binds the same fields — rather than a list here, so the numbers have one home.

**Colours and names.** A side wears its commander's faction: pick Verdant League and your army is
green and called *Verdant League* everywhere — the board, the day banner, the HUD bars, the
victory screen. When both sides pick the same faction, the first keeps the faction colour and the
second borrows a distinct one (Aurora blue, else Meridian red) while both keep the faction name;
the side number and commander tell them apart. A side with **No Commander** is *First*/*Second
Army* in the classic red and blue, so a commander-less match looks exactly as it always did.
("Red"/"Blue" survive only as developer slot names — the Balance Lab's `--red`/`--blue` flags and
its reports — never on a screen a player sees.)

Picking **No Commander** on either side gives that side no doctrine, no meter and no power: a
match with neither plays exactly as the game did before commanders existed.

**Charging.** Both sides bank charge from HP destroyed, valued at the victim's cost prorated by
the damage — halving a 7 000 Tank is worth 3 500 points. The side that *loses* the HP banks all
of it; the side that dealt it banks half, so winning the field does not run away with the meter
as well. The meter is capped at what that general's power costs, so it never holds a second
power's worth. And a side whose power is *running* banks nothing, dealt or lost, until it comes
down — every power is re-earned from empty, not refilled by the fighting it enables.

**Firing.** When the meter fills, a **FIRE** button appears beside it in the HUD bar — for the
mouse, and only the mouse: it deliberately never takes keyboard focus, so a press is never swallowed
by a button the battle would have refused anyway. The keyboard has the `F` shortcut and the
controller has its top face button; both can also use the map menu (confirm on an empty tile, or
cancel with nothing selected), which lists the power as its first entry. Every route goes through
the same command.
Firing spends the whole cost and raises the power immediately. Most powers last until you end that
turn; a few — Hold the Line, Vanish, Signal Jam — exist to bother the opponent and so survive their
turn, ending as yours begins.

The AI charges and fires powers too, on its own commander's judgement of the right moment. Its
meter is shown while it plays, reading `READY · AI` where yours offers the shortcut: no Fire button
appears and the key is refused — it is not yours to press.

**Quotes.** A power's activation card opens with the general speaking — a short in-character
line above the power's name, beside their portrait. The lines are data like everything else
about a general: `power_quotes` on their `.tres`, rotated in order across the match (never
randomly, so a replay speaks the same words), each capped at 60 characters so it stays a spoken
beat — `tests/unit/test_commander_quotes.gd` enforces both. The selection card shows the first
line as the general's signature. The AI's generals speak through the same banner.

## Fog of war

Off by default; turn it on in the menu or with `--fog`. Fogged cells are darkened and the units
in them are hidden — you can neither target nor inspect an enemy you cannot see. You see through
your own units (each unit type has its own vision range) and out to two tiles around every
property you own. Concealing terrain — woods, and reefs at sea — only gives itself up from an
adjacent tile, and units riding a transport see nothing. A commander can bend all of that:
lengthen their own units' sight, see into cover at range, jam the enemy's sight shorter, or hide
their units outright on a tile you can otherwise see. Vision is recomputed after each committed
action and turn change, not as the cursor moves.

A hidden enemy can also **ambush** a move: paths are planned with the mover's own vision, so a
committed move that runs onto or through an enemy you could not see stops your unit at the last
free cell short of it under an "Ambush!" banner — fuel is spent only for the steps actually
walked, and whatever the move was bound to (an attack, a capture, a drop) is called off.

A submerged submarine is the one thing hidden with fog switched off entirely —
see Dive above (it springs the same ambush). Everything else here needs fog to be on.

The view is always *your* team's, including while the AI plays — a computer move made entirely
inside your fog is applied silently, with no cursor, camera pan or footsteps to give it away. The
AI itself sees the whole board — an openly cheating opponent, not a guessing one — with two
deliberate exceptions: a unit a doctrine has hidden is hidden from it too, so an invisibility
power is not inert against it; and it plans and walks its moves with only its own vision, so a
unit it cannot see can ambush it exactly as one can ambush you.
In a fogged hot-seat match a handoff
screen blanks the board between turns so the incoming player never sees the outgoing one's
vision.

## Game speed

Pick **Slow**, **Normal**, **Quick** or **Instant** in the menu, or from the `Speed:` row on the
in-battle map menu (the one that opens on empty ground), which cycles through the four and takes
effect on the very next animation. It scales how fast moves and battles *play out on screen* and
nothing else: **no outcome, save, replay or seeded roll can change with it**, because no file under
`core/` or `ai/` is ever handed the setting.

- **Slow** — 0.18 s a tile; every step of a path is individually readable.
- **Normal** — 0.12 s a tile. The default.
- **Quick** — 0.06 s a tile, the pacing the game shipped with before the setting existed.
- **Instant** — no tweens. Units appear at their destinations, casualties vanish, sounds still fire,
  banners tighten to half a second, and the AI runs one command per frame so the board still
  repaints. For grinding out the late game.

It is a **device preference**, not match state: it lives in `user://settings.cfg` (beside the save's
`user://save.json`), never enters the match request or a save file, and both sides of a hot-seat
share it. `--speed=<tier>` overrides it for one launch without writing anything, and outranks even
the tier captures pin themselves to — which is how you photograph a tier you are tuning. Every number
lives in one table at the top of `scenes/common/game_speed.gd`.

Battle captures and the board scenarios in `make smoke` pin **Instant**: a frame must not depend on
which machine took it, and scenarios wait on the scene's state machine rather than a frame count, so
skipping the theatre
cannot change what is photographed. It is also four times faster on the scenario that plays a whole
AI turn, for a byte-identical frame. The one scenario that lifts the pin is `capture_power`, which
has to let a capture cut-in genuinely play to press the HUD's Fire button into the middle of it; it
restores the pin before its frame, so what is photographed is still an Instant board.
`make menu-screenshot` and the `menu_` scenarios, which boot that same screen, pin **Normal**
instead — the menu's
drifting backdrop and blinking **PRESS START** pin still under a capture (the animator's `capturing`
precedent), so the pin's only effect on the frame is the **Speed** segment's highlight, and that
should read as the tier a fresh install ships with.

## Difficulty

Pick **Easy**, **Normal** or **Difficult** in the menu, or pass `--difficulty=easy|normal|hard`.
It steers exactly one thing: which `AIProfile` the computer plans with. **No tier is handed an
advantage** — income, dice, the damage formula, and what the AI is allowed to see (the standing
board-wide sight described under Fog of war) are identical at Easy and at Difficult, so a harder
opponent is only ever a better-judging one. It is match-wide — every CPU seat plans at the same tier,
never one per seat — so it is inert at a table with nobody but people at it, and a save records the
tier it was played at.

- **Easy** — timid by design. It over-weights danger, retreats early, refuses good trades, passes
  up marginal plays, under-staffs property races, finishes poorly, and never fields an md tank.
  The AI-vs-AI ladder measures Normal taking 71.7% from it overall, clearing the 70% gate — but
  the two boards disagree sharply about it: 93.3% on `scrimmage`, where Normal won every game
  that ended on the board, against an even 50.0% on `ironworks`, where every match instead ran
  out the day cap and was scored on the tiebreak. `docs/difficulty_check.md` carries the standing
  numbers and how to read that split.
- **Normal** — the shipped AI, bit for bit. A test pins its profile to the planner's own defaults,
  so a same-seed replay of an old match still plays out identically.
- **Difficult** — the same economy and the same dice, with more on its mind. It builds a **threat
  map** each turn (what could shoot each cell next turn, forecast through the same combat resolver
  you see in the damage preview) and weighs it two ways: a shot is discounted by what the firing
  cell invites in return, scaled against the unit's own cost, and a unit that is only advancing
  will give up tiles of progress rather than end its move in a kill zone. It also **counter-builds**
  against your actual roster instead of a fixed shopping list. The AI-vs-AI ladder measures it
  taking 71.7% from Normal overall, clearing the 70% gate; `docs/difficulty_check.md` carries the
  standing numbers and tuning record.

Each tier is a `.tres` under `data/difficulty/` pointing at a profile in `data/ai/`, so retuning
one is a data edit. `make difficulty-check` plays the tiers against each other headless and
reports whether the ladder actually orders — see `docs/difficulty_check.md` for the standing
result, and for the superseded probes the weights were first set from, including one capability
that measured *negative* and ships switched off.

## Architecture

- `core/` — pure simulation code. **Nothing here may reference a Node or a scene.**
  All rules are unit-testable and the AI simulates through the same code.
- `ai/` — the computer opponent. `AIController` is the public façade; one
  `AIPlanningContext` supplies scan-stable facts to the coarse unit-action and production
  planners. It remains pure simulation and returns the exact same `Command` objects player input
  produces for the battle scene to apply and animate.
- `data/` — game data as `Resource` files (terrain, units, the damage chart, the commander
  roster in `data/commanders/`, the AI profiles in `data/ai/` — every weight the opponent scores
  with, so tuning its behaviour is a data edit rather than a code change — and the difficulty
  tiers in `data/difficulty/`, each of which is just a label plus one of those profiles).
- `maps/` — plain-text maps: an ASCII terrain grid, a *starting* property-ownership section, and
  an optional starting-units section. `MapData` (core) is authoritative for terrain and is never
  mutated by play; runtime ownership, funds, and turn state live in `GameState`. The TileMapLayer is just paint.
- `scenes/` — presentation: main menu, battle scene, cursor, UI panels.
- `autoload/` — singletons: the event bus, the one match request the menu (or a rematch) stages
  for the battle scene, the device preferences this machine keeps between launches (`Settings` —
  the game speed above, whether battles play the full-screen cut-ins, and which first-match hints
  this player has retired), and the sound-effect player.
- `tools/` — the art and sound build scripts: the headless ground-tile, sound, and portrait
  generators, the unit-sprite paste step and the atlas audit, plus the PixVoxel atlas builder (see
  Assets below); and the offline balance
  toolchain under `tools/balance/`, whose shared match engine serves the commander-balance matrix
  (`docs/commander_balance.md`), the difficulty ladder gate (`docs/difficulty_check.md`) and the
  Balance Lab (`docs/balance_sim.md`) alike; plus `tools/focus_timeline.sh`, the focus-theft
  instrument the smoke sweep above is measured with.
- `tests/` — GUT tests, targeting the Node-free layers: the simulation (`core/` and `ai/`), the
  offline balance harness under `tools/balance/`, and the launch layer that states which match to
  play (`MatchRequest`, `CmdArgs`) — each written that way for exactly this reason.
- `addons/gut/` — vendored [GUT](https://github.com/bitwes/Gut) 9.6.1 (MIT).

## Assets

Ground units and the city/base/hq buildings come from the CC0 [PixVoxel Revised Wargame
Sprites](https://opengameart.org/content/pixvoxel-revised-isometric-wargame-sprites); the ground
tiles are generated programmer art. The aircraft, the fleet, and the Missiles launcher are original
hand-authored isometric sprites, vendored under `assets/sprites/units`, and the airport and port
buildings are the same class of art, vendored under `assets/sprites/iso_buildings`. The iron and
verdant rows of every unit and property are design-system faction tints vendored beside the art
they colour — committed sources, not script output. The commander portraits and faction emblems are
generated too (`make portraits`) — project-original vector art drawn to the "Heroic Commander
Portraits" design handoff's spec, no third-party pixels. All sound is generated placeholder chiptune
(`make sfx`). There is no music yet — it needs licensed tracks. Third-party asset licenses must be
tracked in `assets/LICENSES.md`. No Nintendo assets or names may ever be used.

`make tiles` rebuilds the art in seven ordered steps: `sprites-check` and `unit-sprites-check`
verify the build inputs, `ground` draws the terrain headless, `sprites` composites the PixVoxel art
and the vendored buildings over it, `unit-sprites` re-pastes the vendored unit sprites,
`unit-placeholders` audits the result for a cell no art reached, and `import` reimports the
result — Godot caches image imports by size, so skipping the last step after a rebuild that changes
atlas dimensions renders a blank map. The checks run first because `ground` is destructive: it replaces the committed building
art with bare grounds that only `sprites` can finish painting, so a failure has to happen while the
tree is still clean.

The pack has no aircraft, no ships, no missiles truck, and no iron or verdant palette, so `sprites`
fills only the units atlas's nine land columns, and only their neutral, red and blue rows (the
property columns' faction rows it composites from vendored building sprites the same way it does
the airport and the port). Everything else — the air, naval and Missiles columns whole, and every
land column's iron and verdant rows — is re-pasted from vendored 64×64 sources by
`tools/paste_unit_sprites.gd` on every rebuild, which also widens the atlas to whatever
`data/units/*.tres` asks for and leaves the pack-derived rows untouched. No unit is a generated
placeholder any more: `tools/generate_unit_placeholders.gd` draws nothing today and is kept as the
last set of eyes, warning about any atlas cell that ended up empty.

The only external requirement is ImageMagick 7 (`brew install imagemagick`). The 36 CC0 source
sprites are vendored under `assets/sprites/pixvoxel_src`, so a fresh clone rebuilds with no
download. To build from a full extracted pack instead, override the default:
`make tiles PIXVOXEL=/path/to/Revised_PixVoxel_Wargame/standing_frames`.

### The menu design system

The main menu and the commander-select page are dressed by the **Grid Commander Design System**, an
external design deliverable handed off as a zip — its `handoff/main-menu/` folder holds a spec, a
mockup, five token sheets, three reference components, and a set of terrain sprites. That bundle is
**not vendored in this repo**; its numbers were transcribed into code (below), and its palette was
lifted pixel-for-pixel from this game's own tile and unit atlases, so adopting it was alignment, not
invention. The design of record that adapts it to the shipped game is
`.lavish/menu-revamp-plan.html`. The numbers it defines live
in one place, **`scenes/common/ui_theme.gd` (`UiTheme`)**: the shell palette (the slates, neutrals
and capture green the game had no authority for), the stylebox recipes (cream/dark panels, the hard
offset shadow, the faction/cream/ghost button and its states, the segmented control, the checkbox,
the focus ring), and the font loaders. Colours that already had an authority are re-exported, never
re-declared — faction hues stay `CommanderVisuals`', cream and ink stay
`CommanderVisuals.PAPER / PAPER_INK / HARD_BORDER` — so there is still exactly one value per colour.
It is built in code, not a `.tres` Theme, because that is the one form the repo can review in a diff.

A later handoff added the system's **Tooltip**, adopted the same way: the zip ships it as a React
component and this game has no React tree, so `scenes/ui/tooltip.gd` (`Tooltip`) is that spec
transcribed — an opaque slate slab with an ink border, a hard shadow and a notched tail pointing at
its trigger, with every colour, font and metric read from `UiTheme` and its pixel metrics halved for
the canvas the way the rest of the handoff's numbers are. It replaces Godot's native `tooltip_text`
throughout the menu, which drew a translucent OS-font tip floating at the cursor with no visible
referent. `Tooltip.attach` is the whole entry point, and the
component's doc comment owns the rules worth knowing before reaching for it — a group's tip hangs
off its micro-label rather than off the segments a pointer is only crossing, hover and keyboard
focus come from different controls, and a requested side flips when the 640×360 canvas leaves no
room on it.

A clickable card here — a map cell, a commander mini, a checkbox row — is dress laid *over* a
`Button`, and `Control`'s default is to hit-test, which a parent's `MOUSE_FILTER_IGNORE` does not
change for its children. So a panel or a plain `Control` in the dress eats the press and leaves only
keyboard focus able to select the card. `UiTheme.make_decoration()` is the one fix: call it once the
dress is built and it walks the whole subtree, so the `Button` stays the single input target even
when one more piece lands in the card later. Its doc comment carries the reasoning — including the
one piece of dress it must not silence, a toggle's tip label, which `Tooltip.attach` re-opens to
hover afterwards.

The map picker draws live board miniatures (`scenes/menu/map_thumbnail.gd`) by blitting the terrain
atlas per cell — column from `TerrainType.atlas_col`, row from `SideIdentity.atlas_row`, the same
authorities the battle board paints with — and the same renderer bakes the slow-panning terrain
field behind the menu, so a thumbnail can never drift from the board it launches.

Two fonts are vendored under `assets/fonts/`, both SIL OFL 1.1 from Google Fonts and recorded in
`assets/LICENSES.md`: **Pixelify Sans** (display and UI chrome) and **Silkscreen** (micro-labels,
numerals, badges). The design-system handoff named them "chosen substitutes" because the repo shipped
no UI font; the substitution ends there — they are the game's faces now, rasterised with antialiasing
off so they sit on the same pixel grid as the art.

The battle HUD followed, under a design handoff of its own (`.lavish/hud/`): the floating commander
chip and corner terrain panel were replaced by two docked, opaque, full-width bars
(`scenes/ui/hud_top_bar.gd`, `hud_bottom_bar.gd`, with `hp_pips.gd`), built in code like the menu
for the same reviewability reason. `UiTheme` stays the single authority — the bar scripts hardcode
no colour and no size: both fixed bar heights, the HUD colour tokens, and the shared
`hud_divider` / `hud_spacer` / `hud_label` builders live there. One deliberate departure from that
handoff: it assumes the app letterboxes the map with empty black bands, so docking costs the board
nothing. This build has no such bands — the map sits inside a darkened backdrop ring — so the bars
take 69 canvas pixels that used to show backdrop, and on a map larger than the viewport, board. The
win is that nothing persistent covers the board any more.
