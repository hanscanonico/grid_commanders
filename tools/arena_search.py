#!/usr/bin/env python3
"""AI Arena search — one block of dials, walked against the fixed anchors.

The arena's three instruments already exist and none of them is rebuilt here:
`run_ai_arena.gd` plays candidates, `tools/balance_pool.py` plays them across the
cores and resumes, and `run_arena_report.gd` scores the records through
`ArenaFitness` / `ArenaLeaderboard`. What was missing is the loop over them —
propose a vector, play it, keep it or drop it — and that is all this is.

**Blocks, never one joint optimisation** (plan R5). A run searches one block at a
time and holds every other dial at the base vector, so a result is attributable
to the dials that moved. Which dials are in which block, what their ranges are
and which of them are borrowed from another block because they cannot be
searched apart from it is `tools/arena/arena_blocks.gd`'s — printed by
`run_arena_blocks.gd` and never restated here.

**The opponent is the fixed anchor set** (D7): `easy`, `default`, `hard`, never
re-tuned mid-run, so a wave's numbers are comparable with every other wave's and
with the shipped tiers in the same table. A pattern search keeps one incumbent
rather than a population, so there is no champion for a successor to beat in
isolation and no ladder for an intransitive triple to walk around.

**Training and validation are both reported** (R1). Every wave is played on the
training pool alone; at the end of a block the candidates it kept plus the base
vector are replayed on the held-out pool, and the gap between the two numbers is
the headline of the block's report.

**No `data/` edit, ever** (D8). Every candidate is written under `reports/`,
named for a digest of the vector it carries, and left there: a champion can be
re-run months later by naming its file.

**Resumable at every level.** The pool skips a shard whose records are on disk,
and because a candidate's filename is a digest of its vector, an incumbent that
survives a wave is replayed for free. Above that, a block's `search.json` records
every finished wave, so an interrupted run re-reads its own decisions instead of
replaying them. Rerun the same command to pick a search up.

Usage:
  tools/arena_search.py --block=combat --train-seeds=4 --max-waves=4
  tools/arena_search.py --block=all --dry-run          # the budget, and stop

Flags:
  --block=NAME[,NAME]   which blocks to search, or `all` (required)
  --dials=a,b           narrow a block to these dials (one block at a time)
  --base=PATH           the vector the search starts from
                        (default data/ai/default.tres)
  --out=DIR             run directory, relative to reports/
                        (default ai_arena/search/<base>)
  --train-seeds=N       seeds per training board, capped at the pool's own
  --val-seeds=N         seeds per validation board, capped the same way
  --max-waves=N         proposal rounds per block (default 8)
  --contractions=N      step halvings allowed after a wave finds nothing
                        (default 2)
  --keep=N              candidates carried into the held-out run (default 2)
  --workers=N           engines at a time (default 6, the measured peak)
  --batch=N             seeds per shard (default 4)
  --rate=N              matches/min the budget is estimated at (default 65)
  --dry-run             print the compute budget and stop
  --self-check          run the search arithmetic over its cases and stop

Poll a live run with `cat reports/<out>/pool/status.txt`. Everything a run writes
lands under `reports/`, which is gitignored.
"""
import argparse
import hashlib
import json
import math
import os
import shutil
import subprocess
import sys
import time

# The shard plan, the resume key and the out-directory rule are the pool's, and a
# per-board reading has to name the shards it already played — so they are
# imported rather than restated. No bytecode: the one import here would otherwise
# leave a `tools/__pycache__` behind for a module that runs once.
sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import balance_pool  # noqa: E402

ROOT = balance_pool.ROOT
GODOT = balance_pool.GODOT
BLOCKS_SCRIPT = "res://tools/run_arena_blocks.gd"
CANDIDATES_SCRIPT = "res://tools/run_arena_candidates.gd"
REPORT_SCRIPT = "res://tools/run_arena_report.gd"
# Measured on this machine at six workers: 79 matches/min on `ironworks`, the
# heaviest board in the roster, and 60-70 on the pools' lighter ones. Only ever
# an estimate printed before a run, never a number a result is derived from.
DEFAULT_RATE = 65.0
# An improvement smaller than this is noise in a mean over a few hundred matches,
# and moving the incumbent onto it would walk the search sideways forever.
EPSILON = 1e-6


class Dial:
    """One searchable weight and the lattice it moves on — `ArenaBlocks`', read
    off the plan rather than declared here."""

    def __init__(self, field, spec):
        self.field = field
        self.low = float(spec["low"])
        self.high = float(spec["high"])
        self.step = float(spec["step"])
        self.min_step = float(spec["min_step"])
        self.integer = bool(spec["int"])

    def snap(self, value):
        """The nearest value the lattice holds, inside the range. Every base
        value is already on it (the suite pins that), so snapping a proposal is
        what keeps two waves that reach the same vector reaching the same file."""
        steps = math.floor((float(value) - self.low) / self.min_step + 0.5)
        snapped = min(self.high, max(self.low, self.low + steps * self.min_step))
        return int(round(snapped)) if self.integer else round(snapped, 6)

    def contract(self, step):
        """Half the step, rounded onto the lattice and strictly smaller, until it
        is the precision itself. Strictly, because a step that halved to the same
        number would propose the same two neighbours forever."""
        halved = max(1, math.floor(step / 2.0 / self.min_step + 0.5)) * self.min_step
        if halved >= step:
            halved = step - self.min_step
        return round(max(self.min_step, halved), 6)


def canonical(vector):
    """A vector as one line of text, for the digest that names its profile. Fixed
    precision and sorted keys, so the same vector reached by two different paths
    through the search names the same file — which is what lets the pool hand
    back its matches instead of replaying them."""
    parts = ["%s=%s" % (field, format(vector[field], ".6g")) for field in sorted(vector)]
    return ";".join(parts)


def digest(base, vector):
    return hashlib.sha1(("%s|%s" % (base, canonical(vector))).encode()).hexdigest()[:10]


def neighbours(vector, dials, steps):
    """The 2D compass around a vector: each dial up and down by its own step,
    everything else held. A probe that lands back on the vector it came from — a
    dial already at a bound — is dropped: it is the incumbent, it would be named
    by the same digest and so the same file, and the wave would then play and
    tally one candidate's matches twice."""
    proposals = []
    for dial in dials:
        for direction in (1, -1):
            moved = dict(vector)
            moved[dial.field] = dial.snap(vector[dial.field] + direction * steps[dial.field])
            if moved[dial.field] != vector[dial.field]:
                proposals.append(moved)
    return proposals


def matches_per_candidate(plan, pool, seeds):
    """Every board of the pool, at both seatings, against every anchor."""
    return len(plan["pools"][pool]["boards"]) * seeds * 2 * len(plan["anchors"])


def block_budget(plan, block, args):
    """The worst case, stated before a match is played: a wave that improves
    proposes a full compass again, so nothing is saved by the incumbent being
    free except the incumbent itself."""
    width = len(block["fields"])
    train = matches_per_candidate(plan, "training", args.train_seeds)
    held = matches_per_candidate(plan, "validation", args.val_seeds)
    candidates = (1 + 2 * width) + 2 * width * (args.max_waves - 1)
    validated = min(args.keep + 1, candidates)
    return {
        "block": block["name"],
        "dials": width,
        "waves": args.max_waves,
        "candidates": candidates,
        "training_matches": candidates * train,
        "validation_matches": validated * held,
        "matches": candidates * train + validated * held,
    }


def print_budget(plan, blocks, args):
    """What the run may cost, up front. The estimate is deliberately the worst
    case: every wave improving is what keeps a search proposing, and a budget
    that assumed otherwise would be an underestimate exactly when the search is
    working."""
    print("=== arena search: compute budget ===")
    print(
        "base %s | anchors %d | training %d boards x %d seeds | held out %d boards x %d seeds"
        % (
            plan["base"],
            len(plan["anchors"]),
            len(plan["pools"]["training"]["boards"]),
            args.train_seeds,
            len(plan["pools"]["validation"]["boards"]),
            args.val_seeds,
        )
    )
    print(
        "  %-14s %5s %6s %11s %11s %9s %8s"
        % ("block", "dials", "cands", "train", "held-out", "matches", "hours")
    )
    total = 0
    for block in blocks:
        budget = block_budget(plan, block, args)
        total += budget["matches"]
        print(
            "  %-14s %5d %6d %11d %11d %9d %8.1f"
            % (
                budget["block"],
                budget["dials"],
                budget["candidates"],
                budget["training_matches"],
                budget["validation_matches"],
                budget["matches"],
                budget["matches"] / args.rate / 60.0,
            )
        )
    print(
        "  %-14s %5s %6s %11s %11s %9d %8.1f  (at %.0f matches/min, %d workers)"
        % ("TOTAL", "", "", "", "", total, total / args.rate / 60.0, args.rate, args.workers)
    )


class Search:
    """One run: the engine calls, the archive, and the compute it spent."""

    def __init__(self, plan, args):
        self.plan = plan
        self.args = args
        self.out = args.out
        self.pool_dir = os.path.join(self.out, "pool")
        self.archive = os.path.join(self.out, "candidates")
        self.matches_merged = 0
        self.matches_played = 0
        self.pool_seconds = 0.0
        self.started = time.time()

    # --- the three engine calls ------------------------------------------------

    def write_candidates(self, vectors):
        """Materialises a wave's profiles and hands back their paths, in the order
        they were proposed. Named for a digest of the vector, so a candidate the
        search reaches twice is one file and one set of played matches."""
        spec = {"base": self.plan["base"], "candidates": []}
        paths = []
        for vector in vectors:
            path = os.path.join(self.archive, "c%s.tres" % digest(self.plan["base"], vector))
            paths.append(path)
            spec["candidates"].append({"path": path, "overrides": vector})
        spec_path = os.path.join(ROOT, self.out, "candidates.json")
        os.makedirs(os.path.dirname(spec_path), exist_ok=True)
        with open(spec_path, "w") as f:
            json.dump(spec, f, indent="\t")
        self.godot(CANDIDATES_SCRIPT, ["--spec=%s" % os.path.join(self.out, "candidates.json")])
        self.record_archive(vectors, paths)
        return paths

    def play(self, pool, candidates, wave_dir):
        """Plays every candidate against every anchor over one pool, through the
        existing process pool. Returns the shard plan, so a per-board reading can
        be scored off the shards the same run already wrote."""
        spec = self.plan["pools"][pool]
        seeds = self.args.train_seeds if pool == "training" else self.args.val_seeds
        pairings = [
            "%s::%s" % (candidate, anchor)
            for candidate in candidates
            for anchor in self.plan["anchors"]
        ]
        argv = [
            "--preset=arena",
            "--maps=%s" % ",".join(spec["boards"]),
            "--pairings=%s" % ",".join(pairings),
            "--seeds=%d" % seeds,
            "--seed-offset=%d" % spec["seed_offset"],
            "--days=%d" % self.plan["days"],
            "--batch=%d" % self.args.batch,
            "--workers=%d" % self.args.workers,
            "--out=%s" % self.pool_dir,
        ]
        status = subprocess.call(
            [sys.executable, os.path.join(ROOT, "tools", "balance_pool.py")] + argv, cwd=ROOT
        )
        if status != 0:
            raise SystemExit("arena-search: the pool failed (see %s/failures)" % self.pool_dir)
        self.count_pool()
        os.makedirs(os.path.join(ROOT, wave_dir), exist_ok=True)
        shutil.copyfile(
            os.path.join(ROOT, self.pool_dir, "matches.json"),
            os.path.join(ROOT, wave_dir, "matches.json"),
        )
        return balance_pool.build_shards(balance_pool.parse_args(argv))

    def score(self, matches, out_dir):
        """The leaderboard, through the arena's own scorer. A run it refuses to
        read — a pairing seen from one seat, a candidate short of a pool, a match
        the AI and the rules disagreed about — stops the search, because every
        one of those is a measurement that is not there rather than a bad one.

        The report exits 1 on exactly those and writes the leaderboard anyway, so
        that status is read rather than trusted: it is what names which of them
        it was."""
        self.godot(REPORT_SCRIPT, ["--matches=%s" % matches, "--out=%s" % out_dir], allow=(0, 1))
        with open(os.path.join(ROOT, out_dir, "leaderboard.json")) as f:
            board = json.load(f)
        for key in ("unpaired", "uncovered"):
            if board[key]:
                raise SystemExit("arena-search: %s: %s" % (key, ", ".join(board[key][:3])))
        if board["invalid"]:
            raise SystemExit(
                "arena-search: %d match(es) rejected a command or would not resolve"
                % board["invalid"]
            )
        return board

    def godot(self, script, argv, allow=(0,)):
        status = subprocess.call(
            [GODOT, "--headless", "--path", ".", "-s", script, "--"] + argv,
            cwd=ROOT,
            stdout=subprocess.DEVNULL,
        )
        if status not in allow:
            raise SystemExit("arena-search: %s exited %d" % (script, status))

    # --- bookkeeping -----------------------------------------------------------

    def count_pool(self):
        with open(os.path.join(ROOT, self.pool_dir, "pool.json")) as f:
            reading = json.load(f)
        self.matches_merged += reading["matches"]
        self.matches_played += reading["matches_played"]
        self.pool_seconds += reading["wall_s"]

    def record_archive(self, vectors, paths):
        """One line per profile ever written, so a champion read out of a report
        months later can be traced back to the block and the vector that made it."""
        path = os.path.join(ROOT, self.archive, "index.json")
        index = {}
        if os.path.exists(path):
            with open(path) as f:
                index = json.load(f)
        for vector, candidate in zip(vectors, paths):
            index.setdefault(
                os.path.basename(candidate), {"base": self.plan["base"], "vector": vector}
            )
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w") as f:
            json.dump(index, f, indent="\t", sort_keys=True)

    def spent(self):
        wall = time.time() - self.started
        return {
            "matches_played": self.matches_played,
            "matches_read": self.matches_merged,
            "wall_s": round(wall, 1),
            "pool_wall_s": round(self.pool_seconds, 1),
            "matches_per_min": (
                round(60.0 * self.matches_played / self.pool_seconds, 1)
                if self.pool_seconds > 0
                else 0.0
            ),
        }


def means_of(board, pool):
    """Mean score per candidate in one pool, as the leaderboard tallied it."""
    found = {}
    for row in board["candidates"]:
        if pool in row["pools"]:
            found[row["candidate"]] = row["pools"][pool]["mean"]
    return found


def search_block(search, block, dials):
    """The pattern search itself: an incumbent, a compass of neighbours around it,
    and a step that contracts when the compass finds nothing better.

    Chosen over anything cleverer for three reasons, in this order. It is
    **explainable** — every move is one dial, one step, and the wave that bought
    it is in the record, which is what AR5's acceptance criterion asks of a
    champion. It is **cheap per improvement**: 2D probes buy a move, where a grid
    over five dials at three levels each costs 243. And it is **robust to a noisy
    evaluation**, because it only ever asks which of a handful of vectors scored
    best over a few hundred matches, never for a gradient a mean of noisy matches
    cannot give.
    """
    args = search.args
    block_dir = os.path.join(search.out, block["name"])
    state = load_state(search, block, dials, block_dir)
    if state["waves"] and "stopped" in state["waves"][-1]:
        return finish_block(search, block, dials, state, block_dir)
    incumbent = state["incumbent"]
    steps = state["steps"]
    contractions = state["contractions"]
    for wave in range(len(state["waves"]) + 1, args.max_waves + 1):
        vectors = [incumbent] + neighbours(incumbent, dials, steps)
        wave_dir = os.path.join(block_dir, "w%d" % wave)
        paths = search.write_candidates(vectors)
        search.play("training", paths, wave_dir)
        board = search.score(os.path.join(wave_dir, "matches.json"), wave_dir)
        means = means_of(board, "training")
        scored = sorted(zip(paths, vectors), key=lambda pair: -means[pair[0]])
        best_path, best_vector = scored[0]
        improved = means[best_path] > means[paths[0]] + EPSILON
        state["waves"].append(
            {
                "wave": wave,
                "steps": dict(steps),
                "incumbent": incumbent,
                "improved": improved,
                "candidates": [
                    {"path": path, "vector": vector, "training": means[path]}
                    for path, vector in zip(paths, vectors)
                ],
                # The anchors play every wave too, and their score is the point of
                # them (D7): "as strong as the best shipped tier" is a comparison
                # inside one table, not against a number quoted from another run.
                "anchors": {
                    anchor: means[anchor] for anchor in search.plan["anchors"] if anchor in means
                },
            }
        )
        outcome = "moved"
        if improved:
            incumbent = best_vector
            contractions = 0
        else:
            contracted = {d.field: d.contract(steps[d.field]) for d in dials}
            if contracted == steps:
                outcome = "stopping, the step is already the precision"
            elif contractions >= args.contractions:
                outcome = "stopping, %d contraction(s) bought nothing" % contractions
            else:
                outcome = "contracting"
                steps = contracted
                contractions += 1
        print(
            "  wave %d: %d candidates, incumbent %+.3f, best %+.3f -> %s"
            % (wave, len(paths), means[paths[0]], means[best_path], outcome)
        )
        state["incumbent"] = incumbent
        state["steps"] = steps
        state["contractions"] = contractions
        if outcome.startswith("stopping"):
            state["waves"][-1]["stopped"] = outcome
            save_state(state, block_dir)
            break
        save_state(state, block_dir)
    return finish_block(search, block, dials, state, block_dir)


def finish_block(search, block, dials, state, block_dir):
    """The held-out run: what the block kept, plus the vector it started from,
    replayed on boards and seeds no wave could see (R1). The gap between a
    candidate's two numbers is the diagnostic; a champion that leads on training
    and not here has fitted the pool rather than the game."""
    done = already_validated(state, block_dir, search.args.keep)
    if done:
        return done
    ranked = ranked_candidates(state)
    kept = [vector for _, vector in ranked[: search.args.keep]]
    base_vector = state["waves"][0]["incumbent"]
    if base_vector not in kept:
        kept.append(base_vector)
    held_dir = os.path.join(block_dir, "held_out")
    paths = search.write_candidates(kept)
    shards = search.play("validation", paths, held_dir)
    board = search.score(os.path.join(held_dir, "matches.json"), held_dir)
    held = means_of(board, "validation")
    training = training_means(state)
    summary = {
        "block": block["name"],
        "spec": state["spec"],
        "keep": search.args.keep,
        "note": block["note"],
        "dials": [d.field for d in dials],
        "couples": block["couples"],
        "base": state["waves"][0]["incumbent"],
        "waves": len(state["waves"]),
        "champion": kept[0],
        "rows": [
            {
                "path": path,
                "vector": vector,
                "training": training.get(path),
                "validation": held.get(path),
                "gap": round(training.get(path, 0.0) - held.get(path, 0.0), 3),
            }
            for path, vector in zip(paths, kept)
        ],
        "anchors": {
            anchor: {"training": training.get(anchor), "validation": held.get(anchor)}
            for anchor in search.plan["anchors"]
        },
    }
    if block.get("per_board"):
        summary["per_board"] = per_board_reading(
            search, shards, held_dir, paths + search.plan["anchors"]
        )
    with open(os.path.join(ROOT, block_dir, "summary.json"), "w") as f:
        json.dump(summary, f, indent="\t")
    return summary


def per_board_reading(search, shards, held_dir, candidates):
    """The held-out run scored one board at a time, off the shards it already
    played. `capture_units_per_property` counts what is left to take, so a number
    read over a pool of boards is partly a statement about which boards were in
    it — this is how a block declaring `per_board` gets the property-rich and
    property-poor readings the coupling asks for, at no extra match."""
    readings = {}
    boards = {}
    for shard in shards:
        boards.setdefault(shard.map_name, []).append(
            balance_pool.shard_dir(search.pool_dir, shard)
        )
    for board, dirs in boards.items():
        out_dir = os.path.join(held_dir, "by_board", board)
        table = search.score(",".join(dirs), out_dir)
        means = means_of(table, "validation")
        readings[board] = {name: means.get(name) for name in candidates}
    return readings


def already_validated(state, block_dir, keep):
    """A block whose held-out run has already been played, or nothing. Keyed on
    the same spec digest the waves are, plus the two facts that run depends on —
    how many waves fed it and how many candidates it kept — so a rerun that
    changed either replays it rather than reporting a stale answer."""
    path = os.path.join(ROOT, block_dir, "summary.json")
    if not os.path.exists(path):
        return {}
    with open(path) as f:
        summary = json.load(f)
    matches = (
        summary.get("spec") == state["spec"]
        and summary.get("waves") == len(state["waves"])
        and summary.get("keep") == keep
    )
    if matches:
        print("  held-out run already played")
    return summary if matches else {}


def ranked_candidates(state):
    """Every vector the search evaluated, best training score first. Read across
    the whole run rather than off the last wave, because a wave that found
    nothing still measured its own probes."""
    best = {}
    for wave in state["waves"]:
        for entry in wave["candidates"]:
            best[entry["path"]] = (entry["training"], entry["vector"])
    ordered = sorted(best.items(), key=lambda item: -item[1][0])
    return [(path, value[1]) for path, value in ordered]


def training_means(state):
    """Every training score the run took, and the two halves are not the same kind
    of number.

    A **candidate** is scored against the three fixed anchors, so its mean is the
    same in every wave it appears in and comparable with every other candidate's —
    which is the whole of why the opponent set is fixed (D7). An **anchor** is
    scored against whatever candidates shared its wave, so its mean moves as the
    search does; the last wave's is the one that sits beside the champion, and it
    is context rather than a reference.
    """
    found = {}
    for wave in state["waves"]:
        for entry in wave["candidates"]:
            found[entry["path"]] = entry["training"]
    found.update(state["waves"][-1].get("anchors", {}))
    return found


def spec_digest(search, block, dials):
    """What a resumed run has to agree with before it continues one: the base —
    its path and its bytes, so a retuned base cannot silently reuse a stale
    search — the block's dials and their lattices, and the pools it was measured
    on. A search resumed under a different spec would be two searches in one
    record."""
    with open(os.path.join(ROOT, search.plan["base"]), "rb") as f:
        base_bytes = hashlib.sha1(f.read()).hexdigest()
    spec = {
        "base": search.plan["base"],
        "base_sha1": base_bytes,
        "block": block["name"],
        "dials": [(d.field, d.low, d.high, d.step, d.min_step) for d in dials],
        "seeds": [search.args.train_seeds, search.args.val_seeds],
        "anchors": search.plan["anchors"],
        "pools": {
            name: [pool["boards"], pool["seed_offset"]]
            for name, pool in search.plan["pools"].items()
        },
    }
    return hashlib.sha1(json.dumps(spec, sort_keys=True).encode()).hexdigest()[:12]


def load_state(search, block, dials, block_dir):
    path = os.path.join(ROOT, block_dir, "search.json")
    fresh = {
        "spec": spec_digest(search, block, dials),
        "incumbent": {d.field: search.plan["vector"][d.field] for d in dials},
        "steps": {d.field: d.step for d in dials},
        "contractions": 0,
        "waves": [],
    }
    if not os.path.exists(path):
        return fresh
    with open(path) as f:
        state = json.load(f)
    if state["spec"] != fresh["spec"]:
        raise SystemExit(
            "arena-search: %s holds a search of a different spec; name another --out" % path
        )
    print("  resuming after wave %d" % len(state["waves"]))
    return state


def save_state(state, block_dir):
    os.makedirs(os.path.join(ROOT, block_dir), exist_ok=True)
    with open(os.path.join(ROOT, block_dir, "search.json"), "w") as f:
        json.dump(state, f, indent="\t")


def write_report(search, summaries):
    """One markdown page per run: what each block moved, what it scored where, and
    what it cost. The archive is what a champion is re-run from; this is what it
    is read from."""
    lines = ["# AI Arena search", ""]
    lines.append(
        "Base `%s`, anchors %s." % (search.plan["base"], ", ".join(search.plan["anchors"]))
    )
    spent = search.spent()
    lines.append("")
    lines.append(
        "Compute spent: **%d matches played**, %d read, %.1f min of pool wall clock, %.1f "
        "matches/min at %d workers. Total wall clock %.1f min."
        % (
            spent["matches_played"],
            spent["matches_read"],
            spent["pool_wall_s"] / 60.0,
            spent["matches_per_min"],
            search.args.workers,
            spent["wall_s"] / 60.0,
        )
    )
    for summary in summaries:
        lines += block_section(summary)
    path = os.path.join(ROOT, search.out, "report.md")
    with open(path, "w") as f:
        f.write("\n".join(lines) + "\n")
    return path


def block_section(summary):
    """One block's page: why those dials were on the table, what moved, and what
    it scored in each pool."""
    lines = ["", "## %s" % summary["block"], "", summary["note"], ""]
    if summary["couples"]:
        borrowed = sorted(summary["couples"].items())
        lines.append("Coupled in: %s." % ", ".join("`%s` (%s)" % pair for pair in borrowed))
        lines.append("")
    lines += [
        "%d wave(s). Champion against the vector it started from:" % summary["waves"],
        "",
        "| dial | base | champion |",
        "|---|---|---|",
    ]
    for field in summary["dials"]:
        lines.append(
            "| `%s` | %s | %s |" % (field, summary["base"][field], summary["champion"][field])
        )
    lines += [
        "",
        "A candidate's score is against the three fixed anchors and reads the same in every"
        " wave; an anchor's is against whatever shared its table, so it is context rather"
        " than a reference.",
        "",
        "| candidate | training | held out | gap |",
        "|---|---|---|---|",
    ]
    for row in summary["rows"]:
        lines.append(
            "| `%s` | %+.3f | %+.3f | %+.3f |"
            % (os.path.basename(row["path"]), row["training"], row["validation"], row["gap"])
        )
    for anchor, scores in sorted(summary["anchors"].items()):
        lines.append(
            "| `%s` (anchor) | %s | %+.3f | |"
            % (anchor, score_cell(scores["training"]), scores["validation"])
        )
    return lines + board_table(summary.get("per_board", {}))


def board_table(readings):
    """The held-out run one board at a time, when the block asked for it."""
    if not readings:
        return []
    boards = sorted(readings)
    lines = [
        "",
        "Held out, board by board:",
        "",
        "| candidate | %s |" % " | ".join(boards),
        "|---%s|" % ("|---" * len(boards)),
    ]
    for name in readings[boards[0]]:
        cells = [score_cell(readings[board].get(name)) for board in boards]
        lines.append("| `%s` | %s |" % (os.path.basename(name), " | ".join(cells)))
    return lines


def score_cell(mean):
    """A score, or a dash where there is no measurement — never a zero, which
    would read as a candidate that drew rather than one that never played."""
    return "-" if mean is None else "%+.3f" % mean


def load_plan(base):
    """Everything the search needs to state a wave, asked of the engine once: the
    blocks, the lattices, the pools, the anchors and the base vector."""
    output = subprocess.run(
        [GODOT, "--headless", "--path", ".", "-s", BLOCKS_SCRIPT, "--", "--base=%s" % base],
        cwd=ROOT,
        capture_output=True,
        text=True,
    )
    for line in output.stdout.splitlines():
        if line.startswith("{"):
            return json.loads(line)
    raise SystemExit("arena-search: could not read the block table:\n%s" % output.stderr[-2000:])


def parse_args(argv):
    p = argparse.ArgumentParser(add_help=True, description=__doc__)
    p.add_argument("--block", required=True)
    p.add_argument("--dials", default="")
    p.add_argument("--base", default="data/ai/default.tres")
    p.add_argument("--out", default="")
    p.add_argument("--train-seeds", dest="train_seeds", type=int, default=0)
    p.add_argument("--val-seeds", dest="val_seeds", type=int, default=0)
    p.add_argument("--max-waves", dest="max_waves", type=int, default=8)
    p.add_argument("--contractions", type=int, default=2)
    p.add_argument("--keep", type=int, default=2)
    p.add_argument("--workers", type=int, default=balance_pool.DEFAULT_WORKERS)
    p.add_argument("--batch", type=int, default=4)
    p.add_argument("--rate", type=float, default=DEFAULT_RATE)
    p.add_argument("--dry-run", action="store_true")
    args = p.parse_args(argv)
    for name, value in (("max-waves", args.max_waves), ("keep", args.keep)):
        if value < 1:
            p.error("--%s must be at least 1" % name)
    if args.contractions < 0:
        p.error("--contractions cannot be negative")
    args.out, error = balance_pool.resolve_out(
        args.out or os.path.join("ai_arena", "search", os.path.basename(args.base).split(".")[0])
    )
    if error:
        p.error(error)
    return args


def resolve_blocks(plan, args):
    """The blocks this run searches, and the dials inside them. `--dials=` narrows
    one block for a cheap rehearsal of the harness; it is refused across several,
    because a dial list means nothing spread over blocks that do not share one."""
    wanted = [name.strip() for name in args.block.split(",") if name.strip()]
    known = {block["name"]: block for block in plan["blocks"]}
    if wanted == ["all"]:
        wanted = [block["name"] for block in plan["blocks"]]
    blocks = []
    for name in wanted:
        if name not in known:
            raise SystemExit(
                "arena-search: unknown block '%s'. Known: %s, all" % (name, ", ".join(known))
            )
        blocks.append(dict(known[name]))
    if args.dials:
        if len(blocks) != 1:
            raise SystemExit("arena-search: --dials narrows one block, not %d" % len(blocks))
        narrowed = [field.strip() for field in args.dials.split(",") if field.strip()]
        for field in narrowed:
            if field not in blocks[0]["fields"]:
                raise SystemExit(
                    "arena-search: '%s' is not a dial of block '%s' (%s)"
                    % (field, blocks[0]["name"], ", ".join(blocks[0]["fields"]))
                )
        blocks[0]["fields"] = narrowed
        # The couples are what the report says was on the table and why, so a
        # narrowing that drops a borrowed dial has to drop its reason with it.
        blocks[0]["couples"] = {
            field: home for field, home in blocks[0]["couples"].items() if field in narrowed
        }
    return blocks


def cap_seeds(plan, args):
    """A run may take fewer seeds than a pool holds — the ranges are a prefix of
    the pool's own, so a reduced run still lands inside the split `pool_of` reads
    matches back against — but never more, which would reach seeds the other pool
    owns."""
    for pool, attribute in (("training", "train_seeds"), ("validation", "val_seeds")):
        available = plan["pools"][pool]["seeds"]
        asked = getattr(args, attribute) or available
        setattr(args, attribute, max(1, min(available, asked)))


def main(argv):
    if "--self-check" in argv:
        return self_check()
    args = parse_args(argv)
    plan = load_plan(args.base)
    cap_seeds(plan, args)
    blocks = resolve_blocks(plan, args)
    print_budget(plan, blocks, args)
    if args.dry_run:
        return 0
    if not os.access(GODOT, os.X_OK):
        print("arena-search: Godot not found at %s" % GODOT, file=sys.stderr)
        return 2
    search = Search(plan, args)
    summaries = []
    for block in blocks:
        print("\n=== block %s ===" % block["name"])
        dials = [Dial(field, plan["dials"][field]) for field in block["fields"]]
        summaries.append(search_block(search, block, dials))
    path = write_report(search, summaries)
    spent = search.spent()
    print("\n=== arena search: compute spent ===")
    print(
        "%d matches played (%d read), %.1f matches/min at %d workers, %.1f min wall clock"
        % (
            spent["matches_played"],
            spent["matches_read"],
            spent["matches_per_min"],
            args.workers,
            spent["wall_s"] / 60.0,
        )
    )
    print("arena-search: wrote %s" % os.path.relpath(path, ROOT))
    return 0


def self_check():
    """The search arithmetic, over the cases that shaped it. Run by
    `tools/check_scripts.sh`, and so by `make check` and `make verify`, which
    otherwise reach GDScript only — the lattice, the compass and the contraction
    are pure, and an ungated check is one that rots."""
    failures = 0

    def case(label, ok):
        nonlocal failures
        failures += 0 if ok else 1
        print("%-4s %s" % ("ok" if ok else "FAIL", label))

    whole = Dial("cohesion_radius", {"low": 1, "high": 8, "step": 2, "min_step": 1, "int": True})
    fine = Dial("kill_bonus", {"low": 0.6, "high": 3.0, "step": 0.4, "min_step": 0.1, "int": False})
    coarse = Dial(
        "capture_progress_bonus",
        {"low": 0.0, "high": 360.0, "step": 45.0, "min_step": 15.0, "int": False},
    )
    case("an integer dial snaps to an int", isinstance(whole.snap(3.4), int))
    case("a value below the range clamps up", whole.snap(-4) == 1)
    case("a value above the range clamps down", whole.snap(99) == 8)
    case("a float snaps onto the lattice", fine.snap(1.63) == 1.6)
    case("the lattice is the precision, not the step", fine.snap(1.7) == 1.7)
    case("contraction halves onto the lattice", fine.contract(0.4) == 0.2)
    case("contraction bottoms out at the precision", fine.contract(0.1) == 0.1)
    once = coarse.contract(45.0)
    case(
        "contraction is strictly decreasing off a lattice half",
        once < 45.0 and coarse.contract(once) < once,
    )
    dials = [fine, whole]
    steps = {"kill_bonus": 0.4, "cohesion_radius": 2}
    middle = {"kill_bonus": 1.6, "cohesion_radius": 4}
    case("the compass is two probes a dial", len(neighbours(middle, dials, steps)) == 4)
    case(
        "a probe never moves two dials at once",
        all(
            sum(1 for field in middle if probe[field] != middle[field]) == 1
            for probe in neighbours(middle, dials, steps)
        ),
    )
    edge = {"kill_bonus": 3.0, "cohesion_radius": 8}
    case("a dial at its bound proposes one side only", len(neighbours(edge, dials, steps)) == 2)
    case(
        "the digest is the vector, not the order it was written in",
        digest("b", {"a": 1.0, "b": 2.0}) == digest("b", {"b": 2.0, "a": 1.0}),
    )
    case("the digest separates two bases", digest("x", {"a": 1.0}) != digest("y", {"a": 1.0}))
    case(
        "the digest separates two vectors", digest("b", {"a": 1.0}) != digest("b", {"a": 1.1})
    )
    plan = {
        "anchors": ["a", "b", "c"],
        "pools": {
            "training": {"boards": ["m1", "m2"], "seeds": 12, "seed_offset": 0},
            "validation": {"boards": ["m3"], "seeds": 8, "seed_offset": 12},
        },
    }
    args = argparse.Namespace(train_seeds=4, val_seeds=2, max_waves=3, keep=2)
    budget = block_budget(plan, {"name": "b", "fields": ["x", "y"]}, args)
    case("a wave is the incumbent plus a compass", budget["candidates"] == 5 + 4 + 4)
    case(
        "a candidate plays every anchor on every board, both seats",
        budget["training_matches"] == 13 * 2 * 4 * 2 * 3,
    )
    case("only what a block keeps is validated", budget["validation_matches"] == 3 * 1 * 2 * 2 * 3)
    print("self-check: %d case(s) failed" % failures if failures else "self-check: all cases pass")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
