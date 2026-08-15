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
(`pipx install "gdtoolkit==4.*"`). `make check` and `make balance-pool` need `python3` (stdlib
only, no packages). Everything else runs off the vendored engine alone.

Working in a `git worktree`? `bin/` is gitignored, so a new worktree has no engine and every
target fails with "Godot binary not found". Symlink the one you already have:
`ln -s /path/to/main/checkout/bin bin`.

Then:

```sh
make run             # boot the game — the menu (map, seats, difficulty, speed, commanders, fog, Start / Continue / Campaign)
make hotseat         # skip the menu: straight into a two-player hot-seat match (no AI)
make verify          # the merge gate: check + lint + format-check + test + determinism, in one command
make smoke           # drive the demo scenarios (the battle scene, plus the menu ones); prove each still renders
make test            # run the GUT unit test suite (headless)
make check           # audit every .gd file: parse/types + architecture seams, plus the balance pool's self-check
make campaigns       # the campaign content gate (what it refuses: docs/campaign_authoring.md)
make determinism     # replay one pinned balance match; byte-diff it against the committed golden
make lint            # gdlint — style and smells (config: gdlintrc)
make format          # gdformat — reformat in place; format-check only reports
make tiles           # rebuild the art: generator atlases (SPRITEGEN=<path>), UI chrome, import
make audio           # reinstall the sound effects + music from the sibling audio_generator repo
make portraits       # regenerate the commander portraits + faction emblems
make import          # (re)import assets headless
make screenshot      # boot the battle scene, save screenshot.png, quit
make menu-screenshot # the same, for the main menu
make gallery-screenshot   # render all twenty-three commander cards (the G1 gate)
make commander-balance    # offline AI-vs-AI balance matrix -> reports/ (a release task)
make difficulty-check     # AI-vs-AI difficulty ladder gate -> reports/ (a release task)
make bulwark-measure      # Bulwark's win spread over N seeds -> reports/ (docs/bulwark_balance.md)
make balance-sim          # the Balance Lab: any board, any commanders, any tiers, full telemetry
make balance-pool         # the same engine, sharded across processes: resumable, several cores
make ai-arena             # play two arbitrary AIProfiles against each other -> one JSON record a match
make arena-report         # score an arena run -> a leaderboard (docs/ai_arena.md)
make arena-anchors ARENA_POOL=training   # play one fixed pool of the three shipped tiers, and score it
make arena-search SEARCH="--block=all --dry-run"   # search a block of planner dials (state the budget first)
make balance-watch        # watch a Balance Lab match play out live, both sides AI
make replay REPLAY=<file> # re-watch a recorded match
make replay-report REPLAY=<file>  # read one instead: what the computer left on the table
```

`make verify` is the one command to run before merging: it parse-checks, lints, checks formatting,
runs the suite, and replays the pinned determinism match, cheapest step first. Every headless run
ends with `ObjectDB instances were leaked at exit` and `resources still in use` — that is the engine
failing to tear down a *script* reference cycle (`AttackCommand.validate()` referring to its sibling
`MoveCommand` pins the core script graph), reproducible in twelve lines with no GUT involved. No
gameplay object leaks, so the gate reads exit status and ignores it.

It is also run for you: `.github/workflows/verify.yml` fetches the pinned engine and plays the same
targets, in the same order, on every pull request and every push to `main`. `make smoke` is not
in it — it renders, so it needs a display and stays a local gate. Every target reads `GODOT`, so a
machine with the engine somewhere else runs the gate with `make verify GODOT=/path/to/godot`.

`make determinism` is the gate's last step, and asks about reproducibility rather than style:
it replays one pinned AI-vs-AI match — one board, one seed, about a second — and byte-diffs its
report against the golden committed under `tests/fixtures/determinism/`. That is the balance plan's
fixed-seed merge bar with a committed side to diff against at last. A rules, data or planner change
is *supposed* to move it: the diff it prints is what that change did to a whole match, and
`make determinism REFRESH=1` is how you accept it. `docs/balance_sim.md` has the rest.

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

What the sweep asserts of a capture is that it exists and clears a 2 KB floor — the real checks
are the ones each scenario carries above (a measured layout, the cut-in's atlas rows, a flow that
must reach its state). It never compared a byte. The frames *are* byte-stable, and
`SMOKE_HASHES=<file> make smoke` is how a change is held to that: with no such file it records one
hash per scenario, with one it compares and fails naming every frame that moved. Record before the
change, compare after — the shape `make determinism` uses, minus the committed side. A manifest is
deliberately not committed: unlike that golden's arithmetic, a frame is this machine's renderer and
glyph rasteriser, and the process-wide font atlas shifts glyph edges with the queue's composition,
so the same scenario writes different bytes under `MODES="cutin"` than in the full sweep. The
manifest names the queue it was recorded from and the comparison refuses to cross it, so a narrowed
run asks for a new manifest instead of crying wolf.

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
make smoke MODES="menu_four_seats"    # a board that deals more than a duel: its · NP mark, a seat row per army
make smoke MODES="menu_replays"       # the recordings page, over a posed list of three
```

All five pose what they photograph, so a capture neither reads nor writes the running machine's
`user://save.json` or its recordings, and all five are tests as well as pictures: each measures the
named chrome against the 640×360 logical frame and fails the run if any of it leaves. The first four
measure the whole centered menu column, its map caption, every option-help line, every seat row *and*
its primary actions; `menu_replays` photographs its own page over a hidden menu, so it measures that
page's title, first row and Back instead — the menu's geometry is not what that picture claims. The column is the
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

Thirty-one maps ship. The main menu leads with the teaching board and lists the rest smallest
first — `boot_camp`, `scrimmage`, `forge`, `powder_keg`, `foursquare`, `trident`, `compass`, `pinwheel`,
`timberline`, `arsenal`, `blackwood`, `riverline`, `isthmus`, `exclave`, `jet_stream`, `windrose`, `crossfire`,
`first_steps`, `meridian`, `the_straits`, `tideflats`, `the_slough`, `marchlands`, `coal_and_crown`, `ironworks`,
`atoll`, `steelworks`, `heartland`,
`causeway`, `confluence`, `bulwark` — so it opens on `boot_camp`, badged **Tutorial**, and prints the selected
board's size, army count (a range, `2–4 armies`, on a board where seats can be closed), property
count and one-line pitch in a caption under the grid (the per-cell tooltip repeats them for a mouse).
`foursquare`, `compass`, `pinwheel`, `windrose`, `marchlands`, `heartland`, `atoll`, `causeway`,
`confluence`, `coal_and_crown` and `bulwark` seat **four armies**, and so offer the one-tap table
presets in the seat strip.
`foursquare` is the smallest, 12×12 and the quickest full free-for-all in the roster: a seat in each
corner in reading order — 1 NW, 2 NE, 3 SE, 4 SW — laid out under a quarter turn rather than the
half turn `# symmetric` checks, so the two opposite pairs make a fair duel and every seat's nearest
cities sit the same distance out. It is also
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
`atoll` is the naval one, and the first four-army board with water on it: four home shores at the
corners in the same reading order on a closed ring of land around one lagoon, a port each, and
eight neutral cities on a central island no road reaches. The whole board turns onto itself under a
quarter turn, which is what makes every seat's shore, dock and first city the same distance out.
`coal_and_crown` at 24×16 is the second board written **for** a grouping rather than dealt one, and
the first 2v2 that is deliberately not level seat by seat: seats 1 and 2 are the northern industry,
three bases and two cities each; seats 3 and 4 the southern territory, one base and four cities
each. Six properties a seat either way, so the sides open on twelve apiece and the same income, and
what its `# grouping 1+2v3+4` tag claims — allied seats identical kind for kind, neither side
out-owning the other's total — is exactly what the parity lint checks. The missing factories are
paid for in board state and nothing else: broken ground in the south against the north's open
plains, forward cities against a rear third base, and one extra mech to each southern seat. The
middle two rows are the coalfield, four neutral bases and eight neutral cities laid out the same
either side of the line.
`heartland` at 28×20 opens the grand tier: a lattice of 48 neutral cities, **two bases** to each
seat's one HQ, roads down the diagonals to a central crossroads, and woods for cover rather than a
chokepoint anywhere — the economy scales with the area, so a board this size still escalates.
`causeway` at 30×22 and `confluence` at 32×24 continue it, and `bulwark` at 49×32 — 1568 cells to
`confluence`'s 768 — is the **largest board in the game**: the one board authored *for* a grouping
and deliberately not fair seat by seat, three allied seats on the north edge against a lone army dug
in behind a mountain rampart, its `# grouping 1+2+3v4` header tag the claim the parity lint checks.
`causeway` is four island homes joined to a neutral mid-sea chain by bridges: the land is
a tree with no loop in it, which is what lets every army march on every other *and* leaves the water
one body every port opens onto. `confluence` is the only four-army board where **every seat fields
all three domains** — two bases, an airport and a port apiece, four rivers running into one central
sea, and a harbour island of neutral docks nothing walks to. It is the board a 3v1 wants, and asks
which domain the three will neglect.

Both grand water boards are **slow, and worth knowing about before you start one**. A
computer-versus-computer free-for-all on either tends to run past forty days without an army falling
— `causeway` is more than half water and the bridges are its only crossings, and `confluence` is
simply a lot of ground to hold. `confluence` settles fastest as a 3v1, inside a fortnight. For both,
a shorter day cap or a human at the table suits them better than an unattended match.

`trident` seats **three**, each a prong of the fork around a central massif, where the only grouping
worth naming is a pair against the odd one out. Every other shipped board is a duel. `boot_camp` is
also the only board the first-match mission strip runs on — see **Controls** below. `jet_stream`
and `the_straits` are the boards air and naval units were added for: the first puts an airfield
behind each front, the second a port on each coast of one shared channel.

The newer duels are each built around a single idea, and each one's header states it. `exclave`
(20×14) puts every army's HQ in the *other* army's corner, walled into a mountain pocket with two
one-cell doors and held by a detachment of three: your bases and cities are home, the crown you
cannot lose is not, and the shortest march to a match-ending capture is the one your own infantry
make on turn one. `powder_keg` (14×10) is the roster's smallest economy: an HQ and one base a side,
two neutral cities and nothing else, so three properties a seat pays 3000 a turn and the army you
open with is very nearly the army you finish with — what grows over those days is the Command Power
meter, which charges off damage rather than off income. `blackwood` (18×13) is the board fog was
drawn for: woods nearly wall to wall, exactly two roads — one running north-west to south-east, the
other north-east to south-west, crossing in the middle — and fourteen properties. Off the roads
nothing is visible past an adjacent tile, so the recon's five tiles of sight pay for themselves and
an ambush on the move is the ordinary way a march ends. It plays with fog off; it is simply a
quieter board then. `the_slough` (22×15) promotes `riverline`'s crossing rule to a whole front: the
middle three rows are fen wall to wall — five at the flanks — and the only ground a vehicle crosses
is a two-cell causeway. A mech wades the middle in two turns and infantry in three, so the armour
queues while the boots go round it, and artillery ranges the far bridgehead without crossing at all.
`tideflats` (20×16) is the second naval duel: two coasts with a tidal apron on each, joined by a
single two-cell causeway — road down the beach, bridge over the deep water, road up the far side.
Shoal costs every land class 1 and carries no defence at all, so the aprons are fast ground with
nothing to hide behind, and everything that walks between the coasts does so inside a hull's reach.
The sea runs right around the board, which is what keeps it one body all four docks open onto.
`meridian` (40×8) is the corridor: mountain walls the top and bottom rows for twenty-eight of the
forty columns, so the fight happens in a six-row channel with a home at each end and no way round
either. Reach and rotation decide it — artillery and rockets fire down the length of the channel
from behind a screen that has to be relieved before it breaks — and the only flank that exists is
overhead, which is what the airfield behind each home is for. At 320 cells it is long rather than
large: `bulwark` keeps the largest-board title, and the menu's backdrop with it.
Three of the older boards have since been retrofitted with the domains that suit them — `isthmus`
gained a port and a landing beach per side, `ironworks` and `crossfire` an airfield each — while
`boot_camp`, `first_steps`, `scrimmage`, `timberline` and `riverline` deliberately stay land-only,
because each is built on a barrier that wings or hulls would simply erase — or, for `boot_camp`,
because the five things it teaches are the land game's. `foursquare`, `compass`, `pinwheel`,
`trident`, `marchlands`, `windrose`, `heartland`, `coal_and_crown` and `bulwark` carry no water
either: the computer
cannot plan a ferry, so a board it may have to fight
across in any grouping has to let every army reach every other on foot — which on `windrose` leaves
the air as the one domain that ignores the board's walls. `atoll` is how a four-army
board carries a sea anyway — its land is one closed ring, so every army can still walk to every
other, and its water is one lagoon every dock opens onto, so a fleet built at any port can sail to
any other without a transport. The island in the middle is the one thing on it a ferry is needed
for, which is why it is a prize a player takes and the computer leaves alone.
`heartland` seats its armies at the corners in reading order — 1 NW, 2 NE, 3 SE, 4 SW — so its
fair duel is an opposite pair, 1&3 or 2&4, the same convention `foursquare`, `pinwheel` and
`windrose` follow on their squares (`compass` seats its four at the compass points, and `trident`'s
three are the prongs). The plan's rotational convention assumes a board that turns onto itself;
`heartland` is 28×20 and cannot, so it is laid out under the rectangle's own symmetry instead,
mirrored left-right and top-bottom. Every seat's corner is then a reflection of both its
neighbours' and an exact half-turn of its opposite's: no seat is favoured, and each has the same
near neighbour (15 cells of HQ separation across the short axis) and far one (23 across the long).

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
and plays an AI-vs-AI match on it. A board authored for one grouping declares it — `# grouping
1+2+3v4` — and that property check moves from the seat to the side: allied seats still match kind
for kind, and a side fielding no more armies than its opponents do between them may not out-own
them all combined. The tag is a claim the lint checks, never an instruction a match follows; a
launch still plays whatever `--sides=` says. Boards that use the
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
is the match you meant. With nothing to resume the line reads `NO SAVED MATCH`; with a save this
build cannot open — a truncated file, a damaged one, or a board that has moved since — it reads
`SAVED MATCH UNREADABLE` and says why underneath, because being told you never had a save is the
wrong thing to hear about one you did. Either way the button is greyed out (disabled, not hidden).
**Campaign** opens the campaign select (see Campaigns below), **Replays** opens the recordings
page (see Replays below), and **Quit** exits.

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
faction tabs and a peer portrait per member let you browse; one focused card shows the highlighted
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
shows a unit's range, the left stick's click (button 7) raises and lowers the threat lens, the
Start button (Options / Menu, button 6) lowers and raises a campaign mission's card, the Back
button (Select / View / Share, button 4) jumps to the next unit that can still act, and the top
face button (Y / Triangle) fires a ready Command Power. The same
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
- `R` toggles a red overlay of the cells the unit under the cursor could bring under fire this
  turn: a direct unit firing from anywhere it could stop, an indirect only from where it stands,
  since it cannot move and shoot. It answers from rest, on whatever unit you are hovering — an
  enemy's, or one of yours that has already spent its day — so reading what something threatens
  costs one key rather than a click and then `R`, and its blue movement reach comes up with it,
  exactly as clicking the unit would give you. It follows the cursor: walk onto a second unit and
  press `R` again and you get *that* unit's ring, while a second press with the cursor still on
  the same unit puts the ring down. A unit you have picked up is the exception — there `R` is that
  unit's ring and a plain toggle, since the cursor is planning its move. The top bar's `R · RANGE`
  chip says which it is, dim while no ring is up and red while one is. It can no more see through
  fog than a click can, and the same split as the blue applies: on one of your own units the ring
  is every such cell, whatever the fog; on another side's it is the same reading as the blue
  beneath it, drawn from what you have scouted. It shows what the weapon *reaches* — a unit with
  no shot left still shows its ring, one resupply from meaning it — and it paints over the blue
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
- `N` walks the cursor to the next unit of the army in hand that has not acted yet — yours on your
  turn, and an ally's units are their own to walk — in reading order and
  wrapping round, so the last ready unit on a board the size of `bulwark` is a press away rather
  than a pan. It moves the cursor and nothing else — selecting is still your confirm — and it is
  live only at rest: never with a unit in hand, where the cursor is planning a move, and never
  during a computer turn or a replay. A board with nothing left to act says *No unit ready.* in the
  same chip a refused confirm uses. The End Turn guard's **Review units** walks the same list in the
  same order, so the two can never disagree about who is still owed a turn
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
  `CombatSnapshot.Forecast`, which the panel formats and never recomputes
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
  team's colours beside its name and the price *your* side pays for it — a commander whose doctrine
  moves prices moves this menu with it; rows you can't afford are greyed out. A bought unit
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
- The same menu's **Auto** row hands *your own* seat to the computer for as long as you like: it
  opens a submenu of **Off** and the four difficulty tiers, a banner confirms the change, and the
  computer picks the turn up from where you left it. Taking it back is the same row's Off, reachable
  while its Auto turn is paused. The row is offered only for a seat you may hand over — never a
  genuine opponent's turn, and never over a replay, which seats no computer to hand anything to —
  and which seats are on Auto, at which tier, survives **Save & Main Menu** and **Continue**
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
  single one Continue reads. A campaign mission is the one exception — both save rows write it
  into its campaign's profile instead of the skirmish slot (see Campaigns below)
- The HUD is two opaque bars docked above and below the board, never panels floating on it: the
  board sits in the band they leave over, and only transient things — damage numbers, the capture
  counter and the badge on the tile being taken, the movement arrow, the attack forecast, the
  action menu, the first-match mission strip — are ever drawn
  over terrain. The **top bar** carries the day, the side in hand as a faction colour chip and
  name, that commander's doctrine, the funds, a `T · THREAT` chip, an `R · RANGE` chip and, only
  while a campaign mission is being fought, an `O · MISSION` chip — each dim while its lens is
  down, red while it is up — then an `N · NEXT` chip, which has no lit state because a jump is not
  a way of looking at the board — and a one-line **key legend** that swaps with
  the interaction — `ENTER · SELECT   ESC · MENU   +/- · ZOOM` at rest,
  `ENTER · FIRE   ESC · BACK` while targeting, and so on. The **bottom bar** carries, left to
  right: the commander's
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
  the winner and the day, with **Rematch** (same map, fog, commanders, and sides), **Watch Replay**
  and **Main Menu**. Watch Replay plays back the match that just ended, and is offered only when
  there is a recording to name: a playback, a capture run and a match nobody moved in wrote none,
  and a finished campaign mission is watched from the Replays page instead.
  It opens with no action highlighted and ignores presses and clicks for half a second, so a
  key still held from the last battle cannot restart the match; the first press after that only
  highlights an action, and a second one takes it. Armies that won together are named together —
  *Meridian Coalition & Aurora Compact win!* — and from two eliminations up the day line lists who
  fell, in the order they fell

## Commanders

Each side may field a general whose *doctrine* bends the rules for their whole army — attack and
defence, movement, vision, supply, capture, what a unit costs to build and what a kill is worth in
funds — and who charges toward one **Command Power** that bends them further for a turn.

Twenty-two ship, spread across four factions (six each to the Meridian Coalition and the Iron
Dominion, five each to the Aurora Compact and the Verdant League). `data/commanders/` is the
roster: one `.tres` per general, carrying their doctrine line, power name and description, and
every balance number. Read it — or the selection page's card, which binds the same fields —
rather than a list here, so the numbers have one home.

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
down — every power is re-earned from empty, not refilled by the fighting it enables. Charge comes
from fighting and from nothing else: a unit taken off the board outside a fight — one standing in
Hammerfall's square, or an aircraft that starves its own tank — pays neither meter.

**Firing.** When the meter fills, a **FIRE** button appears beside it in the HUD bar — for the
mouse, and only the mouse: it deliberately never takes keyboard focus, so a press is never swallowed
by a button the battle would have refused anyway. The keyboard has the `F` shortcut and the
controller has its top face button; both can also use the map menu (confirm on an empty tile, or
cancel with nothing selected), which lists the power as its first entry. Every route goes through
the same command.
Firing spends the whole cost and raises the power immediately. Most powers last until you end that
turn; a few — Hold the Line, Vanish, Signal Jam — exist to bother the opponent and so survive their
turn, ending as yours begins.

A power that names a cell — Hammerfall is the one — asks *where* before it spends anything. Every
route into it enters an **aim** instead: whatever move was in hand is put back, the square the
strike would clear is painted under the cursor as you walk it, and the legend reads
`ENTER · STRIKE   ESC · BACK`. Cancel costs nothing, and confirming is what spends the meter —
whether or not anything was standing in the square. Any cell of the board is a legal aim, fog or no
fog, and the square is drawn over the ground rather than over units: what fog costs you is knowing
what was standing there.

The AI charges and fires powers too, on its own commander's judgement of the right moment. Its
meter is shown while it plays, reading `READY · AI` where yours offers the shortcut: no Fire button
appears and the key is refused — it is not yours to press.

**Quotes.** A power's activation card opens with the general speaking — a short in-character
line above the power's name, beside their portrait. The lines are data like everything else
about a general: `power_quotes` on their `.tres`, rotated in order across the match (never
randomly, so a replay speaks the same words), at least three lines to a general with a power so the
rotation is a rotation rather than a refrain, each capped at 60 characters so it stays a spoken
beat — `tests/unit/test_commander_quotes.gd` enforces all three. The selection card shows the first
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

## Sound

The pause menu's **Sound** row cycles **Full → Half → Quiet → Off**, banner-confirmed like the
**Speed** row beside it. It is a device preference on the same terms: it lives in
`user://settings.cfg`, never enters a match request or a save, and both sides of a hot-seat share
it. The step is applied to the master bus, so music and effects come down together — the complaint
it answers is "turn it down", not "mix it" — and **Off** mutes the bus outright rather than trusting
a very low decibel to be inaudible. Every step lives in one table at the top of
`autoload/settings.gd`. `--mute` silences one launch without writing anything, the same family as
`--no-battle-anim`.

## Campaigns

**Campaign** on the main menu opens six authored wars against the Iron Dominion — *The Six
Marshals*, *The Collection*, *The Furnace Winter*, *The Hollow Crown*, *The Long Front* and *The
Quiet War* — eighteen missions each, every mission on its own board under `maps/campaign/`. You
play the other three factions' commanders; the casting, seating, grouping, fog and difficulty are
each mission's own (`data/campaigns/<campaign>/missions/`), so an act can be a 2v2 as easily as a
duel, and difficulty is always one of the shipped tiers — no mission carries tuned AI numbers of
its own.

Picking a war opens its **hub**: the mission list in play order under its block headers, stars
beside every cleared mission and a `cleared · stars` line up top — counted out of the missions this
war can still offer you rather than out of the whole list, so a route that leaves one behind still
finishes. A row you cannot start yet is greyed out and reads `locked`; one the war walked past
without opening reads `not taken`, because a road you declined is not ground you have yet to reach.
Under the title, once there is anything to say, a strip carries the war itself: what your run has put
on the record, in the words of the beats that wrote it, and the condition of the veterans it is
carrying.

Picking a mission swaps the list for its **briefing** — the board in miniature beside the enemy
general it is fought against, the story, spoken by the generals themselves, each line beside its
speaker's bust, under their name in their faction's colour, then the objectives, what
fails it, the par day — and **Deploy** stages it through the same launch path a skirmish uses; the
button reads **Resume** instead when that mission is the one you saved midway. A mission is won by satisfying
every objective at once (or by ordinary tactical victory) and lost by any failure condition — or by
tactical defeat, and **losing outranks winning**: a deadline that expires on the very board that
completed the objective is a failure. The shipped missions are lost three ways where a deadline
used to be the only one in the game: 85 of them run out of days, 20 spend a loss limit, and 6 lose
somebody the board named and you were told to keep alive.
A mission asks for more than the enemy's headquarters: take a cell or so many properties, hold out
to a day, **hold** named ground for a run of whole days, get a number of units onto an **exit
zone**, **destroy** or **keep alive** a unit the board names, break one named **army**, or finish
having lost no more than so many units. Everything is counted across your **side** — an ally
reaching the zone reaches it for both of you, and an ally's casualty is on your bill — except
"break that army", which is about one army on purpose. Two units merged into one spend a unit, and
a loss limit counts it as such.

A mission can also **script what happens while you fight it**. A beat waits for conditions of its
own — a day reached, a day not yet reached, ground held by a side, a named unit destroyed or
arrived somewhere, a side worn down to (or built up to) so many units, an objective already
satisfied, or how an earlier mission of the war went — and every one of them has to hold at once,
so "took the depot, and took it by day four" is one beat. When it comes due it says its piece and changes the board: reinforcements land,
a garrison changes sides, a named column is withdrawn, a property changes hands, a purse or a
Command Power meter is topped up, an objective held back until now comes into play, or the mission
ends there and then. The words are spoken over the board by the generals themselves, exactly as a
briefing's lines are, and any press moves them on.

A beat is applied as **an ordinary command at a command boundary** — the same broker your own
clicks go through — so it lands in the log, in a mid-mission save and in the recording like
anything else, and a replay speaks the same words in the same place. Beats fire *before* the
mission is judged, so a relief column arriving on the day the deadline expires is on the board the
deadline is judged against; losing still outranks winning, so that mission is still lost. A beat
marked once fires once, and a mission picked back up from a save does not play it again. **Every
one of the 108 missions carries at least one**, 208 beats in all.

**A war remembers.** A beat can write a fact to its campaign's ledger — Greenwater held, the
courier lost, three marshals still standing — and a later mission reads it: a briefing line only
said on that kind of run, or a beat that fires only then, which is how a board opens two defenders
short because of what happened in mission five. Facts are numbers rather than yes-or-no, so a
ledger can count, and a condition on one can ask for a floor, a ceiling or both — "was quick or
careful" as readily as "went wrong". Which missions you have cleared and the stars they earned are
asked after in the same words, straight off your record. What a mission writes is taken **when it
is won**: it reads the war as it stood when it began, a lost or abandoned attempt banks nothing,
and replaying a mission you have already cleared does not rewrite what later missions were briefed
off — it can still improve your stars and your best day. When a win does move the war, the debrief
says so on a `RECORDED` line in the beat's own words, and the hub's strip keeps saying it for the
rest of the war. **Fifty-eight of the 108 missions write a fact**, every war keeping a handful of
its own — whether Ferrow was ever paid, how much of the fuel road runs east, whether the marshal
you fought beside is still standing.

**A war has a route through it.** A mission can state how the war has to read for it to open at all,
and the campaign walks its list forward to the first mission that does — so a fact you wrote four
missions ago can hand you a mission another player never sees, or take one away. A mission the route
went past is gone for that run rather than owed: it is not counted against you, and a war with
nothing left to offer reads as finished even though a mission of it was never played. What has
already opened stays open, so nothing you do later can shut a mission you are standing on. **Ten
missions across five of the six wars are authored this way** — *The Hollow Crown*'s ultimatum is
offered only to a commander who let Morn's vanguard walk away, and *The Collection* holds two back
— one for a commander who got the witness out, one for a commander who proved the forgery.

**An army carries.** A war can hand one mission's survivors to the next. The second board marks some
of its own starting units as slots those veterans stand in, at the HP and the name they came off the
last board with, refit to whatever minimum that mission's author set. A slot the war has no unit of that type for keeps the fresh one
the board authored, so every board still fields exactly the army it was balanced for — a wounded
tank is a decision you have to make about it, never a tank you are missing. Nothing else crosses:
what was riding inside a transport is banked as itself and arrives on its own feet. A lost mission
banks nothing, so a **Retry** deploys the army the attempt began with, and replaying a mission you
have already cleared does not re-deal what the ones after it opened on. Two chains are authored
today — the two *Long Front* missions Mara Voss fights in a row, and the whole third act of *The
Furnace Winter*, whose veteran column marches from the last mile to Vale's own furnace — and every
other board opens at full strength as it always did.

While you are fighting it, the mission's terms stay on the board: a card in the top-left corner
names the mission and where it is fought, lists what wins, what loses and the bonuses — the par
day counted among them — ticks each condition as it is satisfied and counts the
ones that count down — `DAY 4/8`, `2/3 DAYS`, `1/2 LOST`. It lists exactly the conditions you are
being judged on, so an objective a mission is holding back stays off the card until a beat brings it
into play, and then appears there. `O` lowers the card and raises it again, so the ground under it
is never covered for longer than you want it to be, and the `O · MISSION` chip is on the top bar
only while a mission is being fought. Lowering it lasts as long as the board you are on: every
mission opens with the card up, its terms being the first thing a new board has to say. The card is
up only inside a campaign mission; a skirmish looks exactly as it always did.

The victory screen reads
**Mission complete** or **Mission failed** with the reason, counts stars — one for finishing, one
for beating the par day, one per bonus objective — and its action button reads **Retry**, which
re-arms the mission itself rather than rematching its finished board. Leaving the battle plays
the **debrief** before the hub — what the generals say about what just happened on a win, the
narrator's one line on a loss — with the stars earned and the mission the win opened. Winning the
last mission of a block plays an **interlude** between the debrief and the hub: a page of the war
between the acts, spoken by the generals exactly as a briefing is, and reading differently depending
on how the block went. Replaying a mission keeps the best stars and best day it ever earned.

Progress is one file per campaign under `user://campaigns/`, written through a temp and a backup
like the skirmish save, so the six wars advance independently and finishing one cannot corrupt
another's record. Inside a mission, both save rows on the map menu write the match *into its
campaign's profile* rather than the skirmish slot — **Continue** on the main menu still means the
one skirmish save, and the hub is where a saved mission picks its board back up. What the mission
has counted rides with the board: resuming one carries on with the days it had held and the units
it had lost, and a **Retry** starts both clean.

`make campaigns` is the authoring gate. It walks every mission of every campaign and refuses, at the
door, anything that would only show up as a mission quietly not doing what it promised — a board
that does not build, a beat that never fires, a briefing line nobody could ever hear, a mission the
board it opens on has already won. `docs/campaign_authoring.md` is the author's side of it: what the
gate refuses in full, what a mission may say and what it may not, what each war records, and the two
traps it deliberately leaves to a hand test.

## Replays

**Every match records itself** as it is played, to a rotating slot under `user://replays/` — ten of
them, oldest pruned. There is nothing to arm and nothing to remember: the match worth re-watching is
the one you did not know was interesting until it ended. The slot is claimed by the first command
rather than by the boot, so a match opened and left takes nobody else's place in the ten.

**Replays** on the main menu is the way in: it lists what has been recorded, newest first, each row
naming the board, the commanders that played it and when — pick one and it plays, **Back** lands on
the setup exactly as it was left. From a terminal, name the file instead:

```sh
make replay REPLAY=~/Library/Application\ Support/Godot/app_userdata/Grid\ Commanders/replays/<file>.jsonl
```

A recording plays back **in the battle scene**, through the same executor a player's click goes
through — the same animations, cut-ins, banners, ambush cues and elimination cards. `Esc` pauses it
at the next command boundary and opens the map menu, exactly as it does during a computer turn —
without the two save rows, because a recording is a match already played and writing it to the one
save slot would come back as a hot-seat game nobody was sitting at — and without the Auto row, since
a playback seats no computer for it to hand a turn to. While it is paused, `S` takes
one more command and stops again, and Enter lets it run. When it ends, the victory screen's first
action reads **Restart** and plays the recording again rather than starting a match on its board.
The board is drawn **omniscient** whatever fog the match was played under: the match is over, so
there is nobody left to hide it from, and a fogged AI-versus-AI match watched through one army's
eyes is mostly a black rectangle.

A replay is **an opening board and the commands that were applied to it** — never a video and never
a series of states. The opening line is a save envelope verbatim (so it carries the roster, the
grouping, each commander's charge and the RNG state, and a match resumed from a save records
correctly from wherever it was picked up); every line after it is one applied command, appended as
it happens, so a crash costs the last line rather than the file. A twenty-day match is about 100 KB.
A recording of a **campaign mission** names its war and its mission up top, because a scripted beat
is recorded as the beat's own name and the mission is what that name means; one whose mission this
build no longer ships is refused by name before it starts rather than stopping at the moment the
story was about to happen. A recording of a skirmish names neither and is the file it always was.

Each line also carries a **digest of the board that command left behind**, and playback stops at the
first mismatch and names the command. That is the one thing a command log cannot do for itself:
survive the *game* moving underneath it. Retune a `.tres`, fix a rule, add a doctrine hook, and
yesterday's recording describes a match this build would not play — without the digest it would
quietly play a different one and look fine. Replays are disposable: nothing resumes from one, so a
stale one is deleted rather than migrated.

### Reading one

A recording can also be read instead of watched:

```sh
make replay-report REPLAY=<file>        # add ARGS="--team=2" for one side
```

It re-issues every command offline and reports what the sides left on the table, ranked, into
`reports/replay/<name>/findings.md` and `.json`. Nine detectors: `walk_into_fire` (a move out of
safety into ground the enemy can kill it on), `worse_shot` (a better target was in range from the
same cell), `hoarding` (funds left on an idle factory), `missed_capture`, `idle_unit`,
`banked_power`, `stranded_transport`, `oscillation` and `undefended_hq`.

Every counterfactual comes from the **rules** — `AttackRange`, `MovementResolver`,
`CombatResolver.forecast_at`, the same authorities the planner scores through — and never from the
planner itself. Nothing under `ai/` has a why-hook, and no finding claims to know what the computer
was thinking: it says what happened, what was available instead, and roughly what the difference was
worth. That is what makes a finding a fact about the *game* rather than about one revision of the
AI, and it is why the report survives the planner being rewritten.

It is **evidence, not a gate**, and deliberately out of `make verify`: several detectors fire on a
doctrine playing exactly as intended — Sable Wren sitting in woods is an `idle_unit`, and a
commander whose power wants a particular board is a `banked_power`.

The Balance Lab writes them too. `make balance-sim SIM="… --replays"` puts one file per match in a
`replays/` directory beside its report, named by the same match id the CSV rows carry, so a
suspicious row becomes a match you can watch. That is a different instrument from `make
balance-watch`, which re-plans a row from its seed and is *supposed* to diverge when the AI changes;
a replay cannot diverge, because the decisions are in the file.

## Difficulty

Pick **Easy**, **Normal**, **Difficult** or **Brutal** in the menu, or pass
`--difficulty=easy|normal|hard|brutal`.
It steers exactly one thing: which `AIProfile` the computer plans with. **No tier is handed an
advantage** — income, dice, the damage formula, and what the AI is allowed to see (the standing
board-wide sight described under Fog of war) are identical at Easy and at Difficult, so a harder
opponent is only ever a better-judging one. It is match-wide — every CPU seat plans at the same tier,
never one per seat — so it is inert at a table with nobody but people at it, and a save records the
tier it was played at.

- **Easy** — timid by design. It over-weights danger, retreats early, refuses good trades, passes
  up marginal plays, under-staffs property races, finishes poorly, and never fields an md tank.
  It also lets its army spread out and has no instinct to defend ground you are taking from it,
  so marching on its headquarters is a plan that works.
- **Normal** — the shipped AI. It notices an enemy capturing its property and answers, and it
  advances as a column rather than one unit at a time. A test pins its profile to the planner's
  own defaults, so an install whose profile file is missing plays exactly the same game.
- **Difficult** — the same economy and the same dice, with more on its mind. It builds a **threat
  map** each turn (what could shoot each cell next turn, forecast through the same combat resolver
  you see in the damage preview) and weighs it two ways: a shot is discounted by what the firing
  cell invites in return, scaled against the unit's own cost, and a unit that is only advancing
  will give up tiles of progress rather than end its move in a kill zone. It also **counter-builds**
  against your actual roster instead of a fixed shopping list, defends its ground harder than
  Normal, and keeps a tighter column.
- **Brutal** — nobody wrote this one. It is the vector the self-play arena found over 93,744
  headless matches, shipped exactly as measured: sixteen weights off Normal, taking 93.8% of its
  matches against the other three tiers on boards and seeds the search never saw. It values a kill
  *less* and notices incoming fire *more* than Difficult does, and it banks nothing — it spends
  every day's income on whatever counters what you field, which is why it drowns you in units
  rather than out-fencing you. Two caveats it earns honestly: the search played it commander-free
  on land duels only, and it optimises winning a headless match rather than being a good afternoon.
  `docs/ai_arena_results.md` is the measurement.

Every tier now runs a **supply economy**: it buys an APC and drives it up to top its units back up,
which is how its artillery and its aircraft stop running dry with no recourse. How patiently is the
tier's own weight — highest on Difficult, well below Normal's on Easy, which lets a rack go nearly
bare first. Rockets are on every tier's build list too. Transports are still only ever suppliers:
the computer cannot plan a ferry, so it never buys one to carry anything.

Each tier is a `.tres` under `data/difficulty/` pointing at a profile in `data/ai/`, so retuning
one is a data edit. What separates the tiers is judgement and never a handicap — but how far apart
they actually measure is its own question, and today the answer is "not far enough": the AI-vs-AI
ladder `make difficulty-check` plays comes out narrower than the 70% margin this project holds
itself to, because the capabilities that made Normal competent closed the gap the ladder measures.
`docs/difficulty_check.md` carries the standing numbers, why that shortfall was accepted rather
than tuned away by making Normal worse, and the superseded probes the weights were first set from
— including one capability that measured *negative* and ships switched off. That ladder steps
Easy → Normal → Difficult and stops there: Brutal is deliberately outside it, because its evidence
is the arena's held-out pool rather than the ladder's two maps, and adding a rung to a gate that is
already failing would muddy both readings.

## Architecture

- `core/` — pure simulation code. **Nothing here may reference a Node or a scene.**
  All rules are unit-testable and the AI simulates through the same code.
- `ai/` — the computer opponent. `AIController` is the public façade; one
  `AIPlanningContext` supplies scan-stable facts to the coarse unit-action and production
  planners. It remains pure simulation and returns the exact same `Command` objects player input
  produces for the battle scene to apply and animate.
- `data/` — game data as `Resource` files (terrain, units, the damage chart, the match-wide
  balance levers in `data/rules.tres` — capture speed, income, repair, the charge split, the
  pricing floor and step, the neutral luck bounds — the commander
  roster in `data/commanders/`, the AI profiles in `data/ai/` — every weight the opponent scores
  with, so tuning its behaviour is a data edit rather than a code change — and the difficulty
  tiers in `data/difficulty/`, each of which is just a label plus one of those profiles, and the
  campaigns in `data/campaigns/` — one directory per war, `campaign.tres` plus its
  `missions/*.tres` and any `interludes/*.tres`, discovered by `CampaignDB` rather than listed by
  hand).
- `maps/` — plain-text maps: an ASCII terrain grid, a *starting* property-ownership section, and
  an optional starting-units section; campaign boards live under `maps/campaign/<campaign>/`. `MapData` (core) is authoritative for terrain and is never
  mutated by play; runtime ownership, funds, and turn state live in `GameState`. The TileMapLayer is just paint.
- `scenes/` — presentation: main menu, battle scene, cursor, UI panels.
- `autoload/` — singletons: the event bus, the one match request the menu (or a rematch) stages
  for the battle scene, the device preferences this machine keeps between launches (`Settings` —
  the game speed above, whether battles play the full-screen cut-ins, and which first-match hints
  this player has retired), the sound-effect player, the background-music player (`Music` — one
  looping track at a time, stated by the scene that wants it), and the campaign session
  (`CampaignSession` — which war and mission is being played, plus the few things that mission has
  tallied over the
  boards it has been played on — days a square has been held, units lost, the facts its beats have
  written and the war has not taken yet — carried across the
  scene change; navigation intent only, it decides no rule and holds no board).
- `tools/` — the art and sound build scripts: the headless UI-chrome (overlay, cursor, icon),
  sound, music, and portrait generators (the board atlases come from the sibling
  `sprite_generator` repo — see Assets below); and the offline balance
  toolchain under `tools/balance/`, whose shared match engine serves the commander-balance matrix
  (`docs/commander_balance.md`), the difficulty ladder gate (`docs/difficulty_check.md`), the
  Balance Lab (`docs/balance_sim.md`) and the AI Arena under `tools/arena/`
  (`docs/ai_arena.md` — seating an arbitrary candidate, what "better" means, and the block search
  laid over both; `docs/ai_arena_results.md` for what the first campaign found) alike; the
  recording reader under `tools/replay/` (Replays
  above); `tools/run_bulwark_measure.gd`, the Bulwark board's own fairness measurement
  (`docs/bulwark_balance.md`) — a four-army board `BalanceMatchEngine` cannot play, so it runs the
  match loop itself; plus `tools/focus_timeline.sh`, the focus-theft
  instrument the smoke sweep above is measured with.
- `tests/` — GUT tests, targeting the Node-free layers: the simulation (`core/` and `ai/`), the
  offline balance harness under `tools/balance/`, the arena's scorer and pools under
  `tools/arena/`, the recording reader under `tools/replay/`, and
  the launch layer that states which match to play (`MatchRequest`, `CmdArgs`) — each written that
  way for exactly this reason.
- `addons/gut/` — vendored [GUT](https://github.com/bitwes/Gut) 9.6.1 (MIT), with one local
  patch: `summary.gd` no longer prints the end-of-run version banner, which claimed on every
  `make test` that this GUT "may not be compatible with Godot 4.7.1" over 1098 passing tests
  (9.6.1's own `versions.json` stops at 4.6.999, and no config or CLI switch turns the banner
  off). It reads no network — the detector only fetches for the editor plugin and for
  `-gcheck_update`. The patch site names the ticket; re-apply or drop it on the next upgrade,
  and record any further local edit here.

## Assets

Every board sprite — the full unit roster, the terrain tiles and the property buildings, all
five faction rows — is generated by the sibling
[`sprite_generator`](https://github.com/hanscanonico/sprite_generator) repo: a deterministic Python
voxel pipeline where each sprite is a hand-authored model rendered with one projection, light,
palette and outline rule, and the faction ramps are read from this game's own `CommanderVisuals`
themes so the sprites and the UI chrome can never disagree about a faction's colour. The committed
atlases are its exact output; the per-cell PNGs under `assets/sprites/units` and
`assets/sprites/iso_buildings` are the same art exported cell by cell as reviewable reference
copies. The UI chrome that has no home there — the range overlay, the cursor, the icon — is drawn
by `tools/generate_tiles.gd`. The commander portraits and faction emblems are
generated too (`make portraits`) — project-original vector art drawn to the "Heroic Commander
Portraits" design handoff's spec, no third-party pixels. All sound — the nine effects and two
project-original looping marches, `parade` for the menu and `advance` for the battle — is composed
and rendered deterministically in the sibling
[audio_generator](https://github.com/hanscanonico/audio_generator) repo, gated there (determinism,
loop-seam, loudness and distinctness measurements), and installed here as committed WAVs by
`make audio`. Third-party asset licenses must be
tracked in `assets/LICENSES.md`. No Nintendo assets or names may ever be used.

`make tiles` rebuilds the art in three ordered steps: `atlases` regenerates both sheets in the
`sprite_generator` checkout and installs them here (clone it beside this repo, or point
`SPRITEGEN=<path>` at one), `ui-art` draws the overlay, cursor and icon headless, and `import`
reimports the result — Godot caches image imports by size, so skipping the last step after a
rebuild that changes atlas dimensions renders a blank map. A clone without the generator still
plays and still passes every gate: the atlases are committed art, and only `make tiles` needs the
sibling repo (plus its `.venv` — see its README; Python + Pillow, no ImageMagick).

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
