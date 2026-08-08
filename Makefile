# The vendored macOS engine (README's setup step) is the default, not the rule:
# CI fetches the Linux build of the same version and points GODOT at it, the way
# tools/check_scripts.sh and tools/smoke_scenarios.sh already allow.
GODOT ?= bin/Godot.app/Contents/MacOS/Godot
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

# The two things a gate can be missing. tools/check_scripts.sh and
# tools/check_determinism.sh already say this for themselves; a target that
# runs the tool directly says it here, so a fresh machine reads the setup line
# instead of a bare "No such file or directory".
require-godot = @test -x "$(GODOT)" || command -v "$(GODOT)" >/dev/null || { \
	echo "$@: Godot binary not found at $(GODOT)" >&2; \
	echo "$@: see README.md for engine setup, or pass GODOT=<path>" >&2; \
	exit 1; }
require-gdtoolkit = @command -v $(1) >/dev/null || { \
	echo "$@: $(1) not found — pipx install \"gdtoolkit==4.*\"" >&2; \
	exit 1; }

run: import
	$(GODOT_GUI) --path .

hotseat: import
	$(GODOT_GUI) --path . $(BATTLE) -- --hotseat

test:
	$(call require-godot)
	$(GODOT) --headless --path . -s res://addons/gut/gut_cmdln.gd

# The merge gate, in one command. Order is cheapest-feedback-first: parsing
# fails fastest, style next, the suite last, then the ~1s determinism replay.
#
# Note on exit noise: every headless run ends with "N ObjectDB instances were
# leaked at exit" and "resources still in use". That is the engine failing to
# tear down a *script* reference cycle — AttackCommand.validate() referring to
# its sibling MoveCommand pins the core script graph — and it reproduces in
# a dozen lines with no GUT involved. No gameplay object leaks. Attempted
# workarounds (static call, split statements) do not avoid it, so the gate
# reads exit status and ignores the diagnostics.
#
# Needs Godot 4.7+ (vendored under bin/, see README) and gdtoolkit 4.x for the
# lint and format steps: pipx install "gdtoolkit==4.*"
verify: check lint format-check test determinism

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
	$(call require-godot)
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
	$(call require-godot)
	$(GODOT) --headless --path . -s res://tools/run_commander_balance.gd -- \
		--difficulty-check $(DIFF)

# The Bulwark fairness measurement (asymmetric-board plan AB3): the win spread
# over N seeds, AI on all four seats, neutral commanders. BalanceMatchEngine
# plays two sides and this board plays four, so it is its own runner rather
# than a third preset over that engine — see tools/run_bulwark_measure.gd.
# A measurement, not a gate: out of `make verify` and `make test`, and it tunes
# nothing — docs/bulwark_balance.md is the committed record, never the
# generated report. Narrow it for iteration, e.g.:
#   make bulwark-measure BULWARK="--seeds=4 --days=40"
BULWARK ?=
bulwark-measure:
	$(call require-godot)
	$(GODOT) --headless --path . -s res://tools/run_bulwark_measure.gd -- $(BULWARK)

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
	$(call require-godot)
	$(GODOT) --headless --path . -s res://tools/run_balance_sim.gd -- $(SIM)

# The same Lab, sharded across processes: one headless engine per shard, several
# at a time, and resumable — a shard whose summary.json exists is skipped, so a
# killed sweep costs the shard in flight and nothing else. The merged matches.csv
# is what the same spec written as one `balance-sim` run produces, byte for byte.
# Not a gate; it is how a long sweep is played:
#   make balance-pool POOL="--maps=ironworks --pairings=none:normal/none:hard --seeds=32"
# docs/balance_sim.md has the flags, the merge bar and the measured scaling curve.
# The pool drives either preset over that engine: `--preset=arena` plays the
# shards with tools/run_ai_arena.gd instead, whose sides are profile paths and
# whose shards merge as JSON.
POOL ?=
balance-pool:
	GODOT="$(GODOT)" tools/balance_pool.py $(POOL)

# The AI Arena's match driver (arena plan AR3): the same one match loop as the
# Lab, given the one input the Lab's <commander>:<tier> grammar cannot state —
# "play *this* AIProfile". Writes one JSON record per match and nothing else, so
# a tournament's telemetry cost is a record rather than a timeline; a pairing
# worth a closer look is re-run through `make balance-sim` with the full
# instruments on. An instrument, not a gate:
#   make ai-arena ARENA="--red-profile=data/ai/default.tres --blue-profile=data/ai/hard.tres --seeds=8"
#   make ai-arena ARENA="--pairings=reports/ai_arena/gen1/shard0.json"
# A whole matrix goes through the pool: make balance-pool POOL="--preset=arena …"
ARENA ?=
ai-arena:
	$(call require-godot)
	$(GODOT) --headless --path . -s res://tools/run_ai_arena.gd -- $(ARENA)

# Score a finished arena run: one row per candidate, in each pool (arena plan
# AR4). Reads records and plays nothing, so re-scoring a run after the fitness
# function moves costs no matches. docs/ai_arena.md is the function it applies.
#   make arena-report REPORT="--matches=reports/ai_arena/anchors_training"
REPORT ?=
arena-report:
	$(call require-godot)
	$(GODOT) --headless --path . -s res://tools/run_arena_report.gd -- $(REPORT)

# The calibration, end to end: play one fixed pool of the anchor round-robin
# across the cores and score it. `ARENA_POOL=training` or `ARENA_POOL=validation`
# — its own knob rather than `POOL`, which balance-pool already defines as the
# empty flag list; the two share no default. The boards, seeds and pairings are
# ArenaPools' and are read out of it rather than spelled here, so the command
# that plays a pool cannot drift from the split the report reads matches back
# against. The engine prints a banner before the argument line, which is what
# the grep is for.
ARENA_POOL ?= training
WORKERS ?= 6
arena-anchors:
	$(call require-godot)
	@plan=$$($(GODOT) --headless --path . -s res://tools/run_arena_plan.gd -- \
		--pool=$(ARENA_POOL) | grep '^--maps=') && \
	echo "arena: $(ARENA_POOL) pool -> $$plan" && \
	GODOT="$(GODOT)" tools/balance_pool.py --preset=arena $$plan \
		--batch=4 --workers=$(WORKERS) --out=ai_arena/anchors_$(ARENA_POOL) && \
	$(GODOT) --headless --path . -s res://tools/run_arena_report.gd -- \
		--matches=reports/ai_arena/anchors_$(ARENA_POOL)

# Search a block of planner dials against the fixed anchors (arena plan AR5).
# The loop over the three instruments above — propose a vector, play it through
# the pool, score it through the report — and nothing else: it edits no data/
# file, and every candidate it writes stays under reports/ so a champion can be
# re-run and explained afterwards. Blocks, never one joint optimisation (R5);
# `tools/arena/arena_blocks.gd` is which dials are in which and why.
# State the cost before spending it:
#   make arena-search SEARCH="--block=all --dry-run"
#   make arena-search SEARCH="--block=combat --train-seeds=6"
# Rerun the same command to resume one; docs/ai_arena.md has the algorithm.
SEARCH ?=
arena-search:
	GODOT="$(GODOT)" tools/arena_search.py $(SEARCH)

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
	$(call require-godot)
	$(GODOT) --headless --path . -s res://tools/run_replay_report.gd -- \
		--replay="$(REPLAY)" $(ARGS)

# Every .gd file that is actually ours: skips the engine cache, vendored addons,
# the engine binary, and .claude/worktrees, which holds whole nested checkouts of
# this same repo and would otherwise be linted as if it were project source.
#
# Deferred, so only the three gdtoolkit targets below pay for the walk — `:=`
# ran it on every invocation, `make run` included.
SOURCES = $(shell find . -name '*.gd' \
	-not -path './.godot/*' -not -path './addons/*' -not -path './bin/*' \
	-not -path './.claude/*')

# Parse/type check plus lightweight architecture invariants without booting the
# scene tree. Rules live in tools/check_scripts.sh.
check:
	tools/check_scripts.sh

# The determinism gate (balance plan D1): one pinned Balance Lab match, byte-
# diffed against the golden report under tests/fixtures/determinism/. About a
# second, so unlike its two full-size siblings it runs on every change and in CI.
# A deliberate rules, data or planner change is supposed to move it:
#   make determinism REFRESH=1   rewrite the golden after reading the diff
REFRESH ?=
determinism:
	tools/check_determinism.sh $(if $(REFRESH),--refresh)

# Style and smells. Rule overrides live in gdlintrc.
lint:
	$(call require-gdtoolkit,gdlint)
	gdlint $(SOURCES)

# Reformat in place; `make format-check` only reports. Both need gdtoolkit:
#   pipx install "gdtoolkit==4.*"
format:
	$(call require-gdtoolkit,gdformat)
	gdformat $(SOURCES)

format-check:
	$(call require-gdtoolkit,gdformat)
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
# .NOTPARALLEL keeps that order under `make -j`, and it is file-scope on
# purpose. The two atlas steps write the same terrain_atlas.png, so run
# concurrently they tear it — and `verify`'s four gates are a sequence rather
# than a set: they share one .godot/ across every engine boot, and their order
# is the cheapest feedback first, so racing them would trade a one-second parse
# failure for the suite's ninety. Scoping it (`.NOTPARALLEL: ground sprites`)
# would be inert here anyway — prerequisites are honoured by GNU make 4.4 and
# up, and macOS ships 3.81, which serialises the whole file regardless.
.NOTPARALLEL:

tiles: sprites-check unit-sprites-check ground sprites unit-sprites unit-placeholders import

sprites-check:
	tools/build_pixvoxel_atlases.sh --check "$(PIXVOXEL)"

# Preflight for `unit-sprites`: proves the vendored per-unit sources exist,
# are the right size, and map onto the roster, without writing anything.
unit-sprites-check:
	$(call require-godot)
	$(GODOT) --headless --path . -s res://tools/paste_unit_sprites.gd -- --check

ground:
	$(call require-godot)
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
	$(call require-godot)
	$(GODOT) --headless --path . -s res://tools/paste_unit_sprites.gd

# Audits the finished atlas cell by cell for one no art reached (none today;
# this drew the Missiles placeholder until real art landed on column 13).
# Must follow `unit-sprites`, whose output it preserves.
unit-placeholders:
	$(call require-godot)
	$(GODOT) --headless --path . -s res://tools/generate_unit_placeholders.gd

sfx:
	$(call require-godot)
	$(GODOT) --headless --path . -s res://tools/generate_sfx.gd

# Regenerates the commander portraits (220x268 busts, drawn as SVG by
# tools/commander_face_svg.gd) and the four faction emblems, then re-imports so
# the new PNGs register. These are committed art, so this only needs rerunning
# when either generator changes or a commander is added.
# Holds every shipped campaign to the bar a playable mission clears: the board
# parses, the seating is one the board deals, every objective names ground that
# exists, and the launch builds. Run it after authoring a mission.
campaigns:
	$(GODOT) --headless --path . -s res://tools/check_campaigns.gd

portraits:
	$(call require-godot)
	$(GODOT) --headless --path . -s res://tools/generate_portraits.gd
	$(GODOT) --headless --path . --import

import:
	$(call require-godot)
	$(GODOT) --headless --path . --import

# The battle scene is launched directly so demos and captures skip the menu.
screenshot: import
	$(GODOT_GUI) --path . $(BATTLE) -- --screenshot=$(CURDIR)/screenshot.png

menu-screenshot: import
	$(GODOT_GUI) --path . -- --screenshot=$(CURDIR)/screenshot.png

# The G1 gate: renders a card for all twenty-three commander records at once, so a
# missing portrait or empty copy field shows up as a crash or a blank card.
gallery-screenshot: import
	$(GODOT_GUI) --path . scenes/menu/commander_gallery.tscn -- --screenshot=$(CURDIR)/screenshot.png

.PHONY: run hotseat test verify smoke check determinism lint format format-check tiles \
	sprites-check unit-sprites-check ground sprites unit-sprites unit-placeholders \
	sfx portraits import \
	screenshot menu-screenshot gallery-screenshot commander-balance difficulty-check \
	balance-sim balance-pool bulwark-measure ai-arena arena-report arena-anchors arena-search \
	balance-watch replay replay-report campaigns
