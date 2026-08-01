GODOT := bin/Godot.app/Contents/MacOS/Godot
# Windowed launches go through a wrapper that hands window focus straight back
# when the launch came from a script or an agent (no tty); from an interactive
# terminal it execs $(GODOT) directly. See tools/godot_gui.sh for why the
# steal can't be prevented outright.
GODOT_GUI := GODOT="$(GODOT)" tools/godot_gui.sh
BATTLE := scenes/battle/battle.tscn
# The 36 source sprites the atlases are built from are vendored (CC0), so a
# fresh clone rebuilds with no setup. Override to build from a full extracted
# Revised_PixVoxel_Wargame_1.7z — see assets/LICENSES.md for the source.
PIXVOXEL ?= assets/sprites/pixvoxel_src

run: import
	$(GODOT_GUI) --path .

hotseat: import
	$(GODOT_GUI) --path . $(BATTLE) -- --hotseat

test:
	$(GODOT) --headless --path . -s res://addons/gut/gut_cmdln.gd

# The merge gate, in one command. Order is cheapest-feedback-first: parsing
# fails fastest, style next, the suite last.
#
# Note on exit noise: every headless run ends with "N ObjectDB instances were
# leaked at exit" and "resources still in use". That is the engine failing to
# tear down a *script* reference cycle — AttackCommand.validate() referring to
# its sibling MoveCommand pins the core script graph — and it reproduces in
# twelve lines with no GUT involved. No gameplay object leaks. Attempted
# workarounds (static call, split statements) do not avoid it, so the gate
# reads exit status and ignores the diagnostics.
#
# Needs Godot 4.7+ (vendored under bin/, see README) and gdtoolkit 4.x for the
# lint and format steps: pipx install "gdtoolkit==4.*"
verify: check lint format-check test

# Presentation smoke: drives the battle scene's demo scenarios and proves each
# still produces a frame. Renders, so it needs a display — keep it out of any
# headless CI job. `make smoke MODES="attack capture"` narrows it down;
# a `+fog` suffix reruns a scenario with fog of war on (`victory+fog`), which is
# the only setting where sprites are hidden rather than merely drawn;
# SMOKE_KEEP=1 keeps the captures for eyeballing, and SMOKE_ISOLATE=1 turns off
# the one-boot batching (one process per scenario; see README).
# A `menu_` mode boots the main
# menu instead of the board and gates it against the 640x360 frame (COM-5); the
# set and what each one proves is in the README.
MODES ?=
smoke:
	tools/smoke_scenarios.sh $(MODES)

# Offline commander balance: plays AI-vs-AI across every pairing on five
# rotationally-symmetric scenarios and writes a per-match CSV + a JSON summary to
# reports/ (gitignored). The full batch (no args) is a long headless release task,
# deliberately out of `make verify` and `make test` — docs/commander_balance.md has
# its exact size and every flag. Narrow it for iteration, e.g.:
#   make commander-balance BAL="--commanders=alina_ward,cass_orlov --seeds=2"
# The committed artifacts of a balance pass are tuned data/commanders/*.tres and
# docs/commander_balance.md, never the generated report.
BAL ?=
commander-balance:
	$(GODOT) --headless --path . -s res://tools/run_commander_balance.gd -- $(BAL)

# The difficulty ladder gate (plan DF4): the same runner in --difficulty-check
# mode, playing Easy-vs-Normal and Normal-vs-Difficult on two mirrored maps with
# both sides swapped. Unlike commander balance this one *is* a gate — with no
# economy or damage handicap at any tier, the higher tier's win rate is the only
# evidence that "smarter, not cheating" is true, so a shortfall fails the run.
# It fails today, knowingly — read docs/difficulty_check.md's standing verdict
# before treating a red run as a regression. Narrow it for iteration, e.g.:
#   make difficulty-check DIFF="--seeds=2 --days=15"
# The committed artifacts of a tuning pass are the profiles under data/ai/ and
# docs/difficulty_check.md, never the generated report.
DIFF ?=
difficulty-check:
	$(GODOT) --headless --path . -s res://tools/run_commander_balance.gd -- \
		--difficulty-check $(DIFF)

# The Balance Lab: the general instrument the two presets above are special
# cases of. Any shipped map, any commander at any tier per side, N seeded
# matches with both seats swapped, and a turn-by-turn timeline of how each one
# went. Like its two siblings it is an opt-in instrument, not a merge gate, so
# it stays out of `make verify` and `make test`; only its own unit tests
# (recorder attribution, engine determinism) are in the suite.
# docs/balance_sim.md has every flag and how to read the output. Examples:
#   make balance-sim SIM="--map=ironworks --red=gideon_holt:normal --blue=cass_orlov:normal --seeds=10"
#   make balance-sim SIM="--sweep=maps --seeds=6"
SIM ?=
balance-sim:
	$(GODOT) --headless --path . -s res://tools/run_balance_sim.gd -- $(SIM)

# Watch a match from a report play out in the real game window, both sides AI.
# Same spec grammar and the same seed, so a suspicious row in matches.csv
# becomes the exact battle it describes:
#   make balance-watch SIM="--map=ironworks --red=gideon_holt:normal --blue=cass_orlov:normal --seed=1003"
# Windowed, so it goes through the focus-safe wrapper like every other GUI target.
balance-watch: import
	$(GODOT_GUI) --path . $(BATTLE) -- --watch $(SIM)

# Watch a recorded match. Every match records itself to a rotating slot under
# user://replays/ as it is played, and `make balance-sim SIM="... --replays"`
# writes one per headless match beside its report:
#   make replay REPLAY=~/Library/Application\ Support/Godot/app_userdata/Grid\ Commanders/replays/<file>.jsonl
# Unlike `balance-watch`, which re-plans a row from its seed, this re-issues the
# commands that were actually played — so it is immune to AI changes by design,
# and stops out loud when a rules or data edit means the board no longer matches.
REPLAY ?=
replay: import
	$(GODOT_GUI) --path . $(BATTLE) -- --replay="$(REPLAY)"

# Read a recording instead of watching it: re-issue every command offline and
# report what the sides left on the table — a unit that stood still, funds never
# spent, a Command Power banked to the end, a tank walked into three guns.
#   make replay-report REPLAY=<file> [ARGS="--team=2"]
# Every counterfactual comes from the rules, never from the planner, so a finding
# is about the game rather than about one revision of ai/. It is evidence and not
# a gate — several detectors fire on a doctrine playing exactly as intended — so
# it stays out of `make verify`. Writes to reports/ (gitignored).
ARGS ?=
replay-report:
	$(GODOT) --headless --path . -s res://tools/run_replay_report.gd -- \
		--replay="$(REPLAY)" $(ARGS)

# Every .gd file that is actually ours: skips the engine cache, vendored addons,
# the engine binary, and .claude/worktrees, which holds whole nested checkouts of
# this same repo and would otherwise be linted as if it were project source.
SOURCES := $(shell find . -name '*.gd' \
	-not -path './.godot/*' -not -path './addons/*' -not -path './bin/*' \
	-not -path './.claude/*')

# Parse/type check plus lightweight architecture invariants without booting the
# scene tree. Rules live in tools/check_scripts.sh.
check:
	tools/check_scripts.sh

# Style and smells. Rule overrides live in gdlintrc.
lint:
	gdlint $(SOURCES)

# Reformat in place; `make format-check` only reports. Both need gdtoolkit:
#   pipx install "gdtoolkit==4.*"
format:
	gdformat $(SOURCES)

format-check:
	gdformat --check $(SOURCES)

# generate_tiles.gd draws only the ground; it leaves every property column —
# city/base/hq, airport, port — as bare grounds and no longer writes
# units_atlas.png, so the buildings step (`sprites`) must follow it.
# The two `*-check` preflights run first because `ground` is destructive: it
# replaces the committed building art with bare grounds that only `sprites` can
# finish painting, so a missing ImageMagick, source sprite, or iso PNG
# has to fail while the tree is clean.
# `import` runs last because Godot caches image imports by size: without it a
# rebuild that changes the atlas dimensions renders a blank map.
# .NOTPARALLEL keeps that order under `make -j` — the two atlas steps write the
# same file, so running them concurrently produces a torn terrain_atlas.png.
.NOTPARALLEL:

tiles: sprites-check unit-sprites-check ground sprites unit-sprites unit-placeholders import

sprites-check:
	tools/build_pixvoxel_atlases.sh --check "$(PIXVOXEL)"

# Preflight for `unit-sprites`: proves the vendored per-unit sources exist,
# are the right size, and map onto the roster, without writing anything.
unit-sprites-check:
	$(GODOT) --headless --path . -s res://tools/paste_unit_sprites.gd -- --check

ground:
	$(GODOT) --headless --path . -s res://tools/generate_tiles.gd

sprites:
	tools/build_pixvoxel_atlases.sh "$(PIXVOXEL)"

# The PixVoxel pack has no aircraft, ships, missiles, or iron/verdant palette.
# `sprites` writes units_atlas.png outright at that pack's nine columns and
# three pack-derived rows, so everything else — the air/naval/missiles columns
# whole, the land columns' iron and verdant rows — is re-pasted here from
# assets/sprites/units/ on every rebuild; without this step a `make tiles`
# silently drops it. Must follow `sprites`.
unit-sprites:
	$(GODOT) --headless --path . -s res://tools/paste_unit_sprites.gd

# Audits the finished atlas cell by cell for one no art reached (none today;
# this drew the Missiles placeholder until real art landed on column 13).
# Must follow `unit-sprites`, whose output it preserves.
unit-placeholders:
	$(GODOT) --headless --path . -s res://tools/generate_unit_placeholders.gd

sfx:
	$(GODOT) --headless --path . -s res://tools/generate_sfx.gd

# Regenerates the commander portraits (220x268 busts, drawn as SVG by
# tools/commander_face_svg.gd) and the four faction emblems, then re-imports so
# the new PNGs register. These are committed art, so this only needs rerunning
# when either generator changes or a commander is added.
portraits:
	$(GODOT) --headless --path . -s res://tools/generate_portraits.gd
	$(GODOT) --headless --path . --import

import:
	$(GODOT) --headless --path . --import

# The battle scene is launched directly so demos and captures skip the menu.
screenshot: import
	$(GODOT_GUI) --path . $(BATTLE) -- --screenshot=$(CURDIR)/screenshot.png

menu-screenshot: import
	$(GODOT_GUI) --path . -- --screenshot=$(CURDIR)/screenshot.png

# The G1 gate: renders a card for all thirteen commander records at once, so a
# missing portrait or empty copy field shows up as a crash or a blank card.
gallery-screenshot: import
	$(GODOT_GUI) --path . scenes/menu/commander_gallery.tscn -- --screenshot=$(CURDIR)/screenshot.png

.PHONY: run hotseat test verify smoke check lint format format-check tiles \
	sprites-check unit-sprites-check ground sprites unit-sprites unit-placeholders \
	sfx portraits import \
	screenshot menu-screenshot gallery-screenshot commander-balance difficulty-check \
	balance-sim balance-watch replay replay-report
