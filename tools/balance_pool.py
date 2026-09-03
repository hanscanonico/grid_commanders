#!/usr/bin/env python3
"""Balance pool — the offline matrix played on several cores at once.

One headless Godot process per shard, `--workers` of them at a time, and
**resumable**: a shard whose marker artifact is already on disk is skipped, so a
killed run costs the shard in flight and nothing else. That property is the
reason this exists in the shape it does — a sweep that has to start over is a
sweep nobody dares interrupt.

**Resume is keyed on the content too, not only on the spec.** A shard's
directory name digests the arguments it was played with, and an argument list
cannot tell that `data/ai/default.tres` was retuned underneath it — so a run
also writes `<out>/stamp.json`, the sides' and the match-wide resources' bytes
beside the commit and what is uncommitted under `core/ ai/ data/`. Markers whose
stamp no longer matches are not honoured: the run says what moved and plays them
again. That is the one failure mode a measurement instrument may not have —
re-reporting a previous commit's matches as today's, indistinguishable from a
real sweep.

A shard is one pairing on one board over a contiguous slice of the seed range
(`--batch` seeds, handed to the driver as `--seeds=` plus `--seed-offset=`). That
is the smallest unit of work that both amortises the engine boot (~0.9 s against
~1.6 s a match) and is independently readable: it writes its own artifacts under
`shards/`. Its directory is named for the arguments it was played with, digest
and all, so a shard is reused only for the run it answers — see `Shard`.

**The engine plays every match; this only decides who plays what, and when.**
The merged `matches.csv` is what a single `make balance-sim` run of the same spec
writes, row for row and byte for byte — that diff is the merge bar for any
change to the sharding here. Nothing is aggregated: a merged summary would be a
second opinion about numbers `BalanceRunSummary` already owns.

Two presets sit over the one match loop and this drives either (`--preset=`):
`lab` is `run_balance_sim.gd`, whose side is `<commander>:<tier>` and whose
shards merge as CSV; `arena` is `run_ai_arena.gd`, whose side is a path to an
`AIProfile` and whose shards merge as JSON. Everything else — the shard plan,
the digest resume key, resume, status, `pool.json` — is the same code for both.

Usage:
  tools/balance_pool.py --maps=ironworks --pairings=none:normal/none:hard \\
      --seeds=32 --batch=4 --days=100 --workers=4

  tools/balance_pool.py --preset=arena --maps=ironworks \\
      --pairings=data/ai/default.tres::reports/ai_arena/gen1/c7.tres --seeds=32

Flags:
  --maps=a,b            shipped boards or Lab fixtures (required)
  --pairings=r/b,r/b    `<red side>/<blue side>` in the preset's own side
                        grammar, passed through untouched (required). The arena
                        pairs on `::` rather than `/`, because a side there is a
                        path and paths carry the `/`.
  --preset=lab|arena    which driver plays the shards (default lab)
  --seeds=N             paired seeds per pairing (default 4, the Lab's)
  --seed-offset=N       where in each board's seed range the run starts
                        (default 0) — a held-out pool is the same boards' later
                        seeds, and this is how a run asks for them
  --batch=N             seeds per shard (default 4)
  --days=N              day cap; omitted, the driver's own default stands
  --workers=N           processes at a time (default min(6, cores) — 6 is the
                        measured peak; the curve is in docs/balance_sim.md)
  --out=DIR             run directory, **relative to reports/** and refused if
                        it leaves it (default reports/balance_pool/<spec>; a
                        leading `reports/` is accepted, so both spellings work)
  --timeout=SEC         per shard, default 3600
  --refresh             replay every shard, marker or no marker
  --reuse-stale         report shards whose content stamp moved anyway. The
                        escape hatch for a commit that touched nothing a match
                        reads; it keeps the old stamp, so the run stays loud
                        about what it is reporting
  --dry-run             resolve the spec, print the shard plan and what the
                        stamp says about the markers on disk, and stop
  --self-check          run the out-directory, resume-key, content-stamp and
                        merge rules over their cases and stop (gated by
                        `make check`)

Poll a live run with `cat <out>/status.txt`; `<out>/progress.log` is the record
and `<out>/pool.json` the throughput reading. Exit status is 1 if any shard
failed to write its marker — a shard that wrote one and still exited 1 is the
driver reporting a cap-stall finding, not a failed run.

Everything a run writes lands under `reports/`, and the driver refuses at
startup to be pointed anywhere else. See `resolve_out`: the Lab resolves its own
`--out` against the *project* root, so a path outside the repo is silently
written inside it, where this driver never looks — and resume, which is keyed on
a shard's `summary.json`, would then replay every shard of every run forever
while calling each one failed.

Nice the whole pool if you want the machine back: `nice -n 10 tools/balance_pool.py …`
"""
import argparse
import csv
import hashlib
import json
import os
import subprocess
import sys
import tempfile
import threading
import time
from concurrent.futures import ThreadPoolExecutor, as_completed

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
# Resolved against the project root, because every child is launched with
# cwd=ROOT — a relative GODOT= must mean the same engine to the pre-flight check
# as it does to the shards, whatever directory the driver was invoked from.
GODOT = os.path.join(
    ROOT, os.path.expanduser(os.environ.get("GODOT", "bin/Godot.app/Contents/MacOS/Godot"))
)
REPORTS_ROOT = "reports"
DEFAULT_OUT_ROOT = os.path.join(REPORTS_ROOT, "balance_pool")
# Six is where throughput peaked on the 4-performance-core M1 this was measured
# on — eight regresses — and no machine should be asked for more workers than it
# has cores. docs/balance_sim.md carries the curve.
DEFAULT_WORKERS = max(1, min(6, os.cpu_count() or 4))


def lab_args(map_name, red, blue, offset, count, days):
    """The Balance Lab's flags for one shard. A side is `<commander>:<tier>`."""
    args = [
        "--map=%s" % map_name,
        "--red=%s" % red,
        "--blue=%s" % blue,
        "--seeds=%d" % count,
        "--seed-offset=%d" % offset,
        "--no-commands",
    ]
    if days:
        args.append("--days=%d" % days)
    return args


def arena_args(map_name, red, blue, offset, count, days):
    """The AI Arena's flags for one shard. A side is a path to an AIProfile, and
    the arena writes no telemetry, so there is no `--no-commands` to switch off."""
    args = [
        "--map=%s" % map_name,
        "--red-profile=%s" % red,
        "--blue-profile=%s" % blue,
        "--seeds=%d" % count,
        "--seed-offset=%d" % offset,
    ]
    if days:
        args.append("--days=%d" % days)
    return args


def _slug(spec):
    return spec.replace(":", "-") or "default"


def _profile_slug(path):
    """A candidate is a path, so a shard is named for the file's stem: a slug
    with a separator in it would nest the shard's own directory somewhere resume
    never looks again."""
    return os.path.splitext(os.path.basename(path))[0] or "profile"


def header_mismatch(sources):
    """The one thing a concatenation cannot survive: shards that disagree about
    their columns. Shard 0's header becomes the merged table's, so a shard played
    under different flags would have its values read back under the wrong names,
    and every row count downstream would call the result healthy. Returns the
    refusal text, or "" when they all agree."""
    first = ""
    for index, source in enumerate(sources):
        with open(source, newline="") as f:
            header = f.readline().rstrip("\r\n")
        if index == 0:
            first = header
        elif header != first:
            return "shard %s disagrees about the columns:\n  %s\n  %s" % (
                os.path.basename(os.path.dirname(source)), first, header
            )
    return ""


def merge_csv(dest, sources):
    """Concatenates the shards' rows in plan order, one header. Returns
    (rows, error) — nothing is written unless every shard agrees."""
    error = header_mismatch(sources)
    if error:
        return 0, error
    with open(dest, "w") as merged:
        for index, source in enumerate(sources):
            with open(source) as f:
                header = f.readline()
                if index == 0:
                    merged.write(header)
                for line in f:
                    merged.write(line)
    return count_csv_rows(dest), ""


def merge_json(dest, sources):
    """The same concatenation for a driver whose shard is one JSON array: the
    records are read and re-emitted as one list, in the same plan order."""
    records = []
    for source in sources:
        with open(source) as f:
            records.extend(json.load(f))
    with open(dest, "w") as merged:
        json.dump(records, merged, indent="\t", sort_keys=True)
    return len(records), ""


def count_csv_rows(path):
    """Records, not lines: `BalanceReportWriter._cell` quotes a cell holding a
    separator, a quote or a newline (RFC 4180), so a row is not always a line."""
    with open(path, newline="") as f:
        return max(0, sum(1 for _ in csv.reader(f)) - 1)


def count_json_records(path):
    with open(path) as f:
        return len(json.load(f))


# Which driver plays a shard, what it is handed, and what it leaves behind. The
# marker is what resume reads, so it has to be an artifact its driver writes in
# one go at the end — both of these do, which is what keeps a shard on disk
# either complete or absent rather than half true.
PRESETS = {
    "lab": {
        "script": "res://tools/run_balance_sim.gd",
        "args": lab_args,
        "slug": _slug,
        "pair_sep": "/",
        # `<commander>:<tier>` names no file, so the content stamp takes the
        # commit and the working tree for these sides and nothing more.
        "side_is_path": False,
        "marker": "summary.json",
        "artifacts": [("matches.csv", merge_csv), ("timeline.csv", merge_csv)],
        "count": count_csv_rows,
    },
    "arena": {
        "script": "res://tools/run_ai_arena.gd",
        "args": arena_args,
        "slug": _profile_slug,
        # A side is a path, and paths carry the `/` the Lab pairs on.
        "pair_sep": "::",
        "side_is_path": True,
        "marker": "matches.json",
        "artifacts": [("matches.json", merge_json)],
        "count": count_json_records,
    },
}


class Shard:
    """One pairing on one board over a slice of the seed range — and its own
    resume key.

    That key is the driver's argument list itself, digested into the shard's
    directory name, so a shard on disk is reused only if it was played with the
    arguments this run would hand it — whose *bytes* moved underneath it is the
    content stamp's question, not this key's.

    Naming the spec dimensions by hand is what
    a resume key must never do: the day cap was already missing from one, which
    replayed a 20-day sweep's shards as a 100-day answer, and the next flag added
    to `args` would have fallen off the same list. A digest cannot forget one —
    and because the flags differ per preset, it separates the two presets' shards
    for free.
    """

    def __init__(self, preset, map_name, red, blue, offset, count, days):
        self.preset = PRESETS[preset]
        self.map_name = map_name
        self.red = red
        self.blue = blue
        self.offset = offset
        self.count = count
        self.args = self.preset["args"](map_name, red, blue, offset, count, days)
        slug = self.preset["slug"]
        digest = hashlib.sha1(" ".join(self.args).encode()).hexdigest()[:8]
        self.name = "%s__%s__vs__%s__s%d+%d__%s" % (
            map_name, slug(red), slug(blue), offset, count, digest
        )


def resolve_out(out):
    """The run directory, as a repo-relative path under `reports/`. Returns
    (path, error) and is the one place that decides where a run may write.

    A relative path is taken as relative to `reports/` — a leading `reports/` is
    accepted rather than doubled, since that is how the default and every
    documented example are spelled. Anything that leaves `reports/`, including an
    absolute path, is an error the caller reports before a match is played.

    The rule is not tidiness. Godot's `path_join` concatenates rather than
    resolves, so a leading `/`, a `res://` prefix or a `..` that climbs out each
    lands the artifact inside the repo under a name nobody reads — `--out=/tmp/x`
    writes to `<repo>/tmp/x` while this driver reads `/tmp/x`. Resume is keyed on
    finding a shard's `summary.json`, so it would then find none, ever: every
    shard of every run replayed forever and reported failed, with the results on
    disk the whole time. Containing the path is what makes that unreachable
    instead of documented.

    `BalanceReportWriter.resolve_out` is this same policy said in GDScript, where
    the write actually happens; it is stated twice because this driver has to
    refuse a path *before* it launches a preset. The two share the case table
    below, which `--self-check` and `tests/unit/test_report_writer.gd` pin.
    """
    refusal = "--out is relative to %s/ and may not leave it (got '%s')" % (REPORTS_ROOT, out)
    if os.path.isabs(out):
        return "", refusal
    out = out[len("res://"):] if out.startswith("res://") else out
    if out.startswith("/"):
        return "", refusal
    parts = os.path.normpath(out).split(os.sep)
    if parts[0] != REPORTS_ROOT:
        parts.insert(0, REPORTS_ROOT)
    path = os.path.normpath(os.path.join(*parts))
    if path != REPORTS_ROOT and not path.startswith(REPORTS_ROOT + os.sep):
        return "", refusal
    return path, ""


def parse_args(argv):
    p = argparse.ArgumentParser(add_help=True, description=__doc__)
    p.add_argument("--maps", required=True)
    p.add_argument("--pairings", required=True)
    p.add_argument("--preset", default="lab", choices=sorted(PRESETS))
    p.add_argument("--seeds", type=int, default=4)
    p.add_argument("--seed-offset", dest="seed_offset", type=int, default=0)
    p.add_argument("--batch", type=int, default=4)
    p.add_argument("--days", type=int, default=0)
    p.add_argument("--workers", type=int, default=DEFAULT_WORKERS)
    p.add_argument("--out", default="")
    p.add_argument("--timeout", type=int, default=3600)
    p.add_argument("--refresh", action="store_true")
    p.add_argument("--reuse-stale", dest="reuse_stale", action="store_true")
    p.add_argument("--dry-run", action="store_true")
    args = p.parse_args(argv)
    args.resume = not args.refresh
    maps = [m.strip() for m in args.maps.split(",") if m.strip()]
    if not maps:
        p.error("--maps is a comma list of boards, got '%s'" % args.maps)
    args.maps = maps
    separator = PRESETS[args.preset]["pair_sep"]
    pairings = []
    for text in args.pairings.split(","):
        red, sep, blue = text.strip().partition(separator)
        if not sep:
            p.error(
                "a %s pairing is <red>%s<blue>, got '%s'" % (args.preset, separator, text)
            )
        pairings.append((red.strip(), blue.strip()))
    args.pairings = pairings
    for name, value in (("seeds", args.seeds), ("batch", args.batch), ("workers", args.workers)):
        if value < 1:
            p.error("--%s must be at least 1" % name)
    if args.seed_offset < 0:
        p.error("--seed-offset cannot be negative")
    args.out, error = resolve_out(args.out or os.path.join(DEFAULT_OUT_ROOT, run_name(args)))
    if error:
        p.error(error)
    return args


def run_name(args):
    """Derived from the spec, never a clock — the Lab's rule, and here it is also
    the resume key: rerunning a sweep finds its own directory and skips what it
    already played. The preset joins it only when it is not the default one, so
    every directory a Lab sweep already wrote keeps its name."""
    slug = PRESETS[args.preset]["slug"]
    parts = [] if args.preset == "lab" else [args.preset]
    parts.append("-".join(args.maps))
    parts += ["%s_vs_%s" % (slug(r), slug(b)) for r, b in args.pairings]
    parts.append("s%d_b%d" % (args.seeds, args.batch))
    if args.seed_offset:
        parts.append("o%d" % args.seed_offset)
    if args.days:
        parts.append("d%d" % args.days)
    return "_".join(parts)


def build_shards(args):
    """Map by map, pairing by pairing, seed slice by seed slice — the order the
    driver itself would play them in, which is what makes the merge a
    concatenation."""
    shards = []
    for map_name in args.maps:
        for red, blue in args.pairings:
            for taken in range(0, args.seeds, args.batch):
                count = min(args.batch, args.seeds - taken)
                offset = args.seed_offset + taken
                shards.append(Shard(args.preset, map_name, red, blue, offset, count, args.days))
    return shards


def shard_dir(out, shard):
    return os.path.join(out, "shards", shard.name)


def marker_path(out, shard):
    """What resume reads: the artifact its driver writes last and in one go."""
    return os.path.join(ROOT, shard_dir(out, shard), shard.preset["marker"])


STAMP = "stamp.json"
# Read by every match whatever the pairing: a shard played before either of them
# moved is a shard about other rules.
STAMPED_DATA = ("data/rules.tres", "data/damage_chart.tres")


def _sha1_file(path):
    try:
        with open(path, "rb") as f:
            return hashlib.sha1(f.read()).hexdigest()
    except OSError:
        return "(missing)"


def _git(argv):
    """Best effort: a checkout without git is not a reason to refuse to play,
    only a reason for the stamp to say less."""
    try:
        done = subprocess.run(
            ["git", "-C", ROOT, *argv], capture_output=True, text=True, timeout=30
        )
    except (OSError, subprocess.SubprocessError):
        return ""
    return done.stdout.strip() if done.returncode == 0 else ""


def stamped_files(preset, pairings, root=ROOT):
    """Every file this run's rows are a statement about: the sides, where a side
    is a path, and the two match-wide resources. A `<commander>:<tier>` side
    names none, which is what the commit and the working tree below are for."""
    paths = list(STAMPED_DATA)
    if PRESETS[preset]["side_is_path"]:
        paths += [side for pairing in pairings for side in pairing]
    return {path: _sha1_file(os.path.join(root, path)) for path in sorted(set(paths))}


def content_stamp(args):
    """What the shards in an out-directory answer for."""
    return {
        "files": stamped_files(args.preset, args.pairings),
        "head": _git(["rev-parse", "HEAD"]) or "(no git)",
        # A dirty tree must not resume a clean one's shards, nor the other way
        # round: what is uncommitted under these three is part of the content.
        "dirty": _git(["status", "--porcelain", "--", "core", "ai", "data"]),
    }


def read_stamp(out):
    try:
        with open(os.path.join(ROOT, out, STAMP)) as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def write_stamp(out, stamp):
    with open(os.path.join(ROOT, out, STAMP), "w") as f:
        json.dump(stamp, f, indent="\t", sort_keys=True)


def stamp_changes(previous, current):
    """What moved since the shards on disk were played, one line each — and
    empty when nothing did, which is the only case resume may honour.

    A file only *this* run names is not a change: the arena search plays wave
    after wave of content-addressed candidates into one pool directory, and the
    earlier waves' shards are still true about their own files. An out-directory
    with no stamp at all is not a change either — it predates the stamp, and
    replaying a sweep somebody is watching is not how this arrives.
    """
    if not previous:
        return []
    lines = []
    for path, before in sorted(previous.get("files", {}).items()):
        now = current["files"].get(path)
        if now is not None and now != before:
            lines.append("%s changed" % path)
    if previous.get("head") != current["head"]:
        lines.append("HEAD moved: %s -> %s" % (previous.get("head"), current["head"]))
    if previous.get("dirty", "") != current["dirty"]:
        lines.append("core/ ai/ data/ hold different uncommitted work")
    return lines


def resumes(refresh, changes, reuse_stale):
    """Whether a marker already on disk still answers for this run. `--refresh`
    is the caller saying replay regardless; `--reuse-stale` is the caller taking
    the stamp that moved on themselves."""
    if refresh:
        return False
    return not changes or reuse_stale


def pool_resume(args, shards, log):
    """Decides whether this run may skip the shards already on disk, says out
    loud when it is throwing markers away — or keeping ones it should not — and
    leaves the stamp those shards answer for behind."""
    current = content_stamp(args)
    previous = read_stamp(args.out)
    changes = stamp_changes(previous, current)
    played = any(os.path.exists(marker_path(args.out, shard)) for shard in shards)

    def say(line):
        print("balance-pool: %s" % line, file=sys.stderr)
        log.write(line + "\n")

    if played and not previous:
        say("%s has no content stamp; trusting its shards and writing one" % args.out)
    for line in changes:
        say("!! %s" % line)
    resume = resumes(args.refresh, changes, args.reuse_stale)
    if changes and resume:
        say("!! --reuse-stale: reporting shards that were played against other content")
    elif changes:
        say("!! the shards on disk answer for the content above — replaying every one")
        say("!! pass --reuse-stale to report them anyway")
    elif args.refresh and played:
        say("--refresh: replaying every shard on disk")
    # Honouring stale markers leaves the run mixed, so the stamp stays the one
    # those shards were played under and the next run is loud about it too.
    if not (changes and resume):
        write_stamp(args.out, current)
    return resume


class Children:
    """The engines this run has in flight, so an interrupt can end them.

    Worker threads are not daemons and `concurrent.futures` joins them at exit,
    so a driver that only cancels its futures waits out every running shard —
    up to `--timeout` — before the process dies. It survives interactively
    because the terminal signals the whole process group; launched from a script
    or a runner, nothing else would reach the children.
    """

    def __init__(self):
        self._lock = threading.Lock()
        self._live = set()
        self._stopping = False

    def start(self, cmd):
        with self._lock:
            if self._stopping:
                return None
            proc = subprocess.Popen(
                cmd, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
            )
            self._live.add(proc)
        return proc

    def finished(self, proc):
        with self._lock:
            self._live.discard(proc)

    def stopping(self):
        with self._lock:
            return self._stopping

    def stop(self):
        with self._lock:
            self._stopping = True
            live = list(self._live)
        for proc in live:
            proc.terminate()


CHILDREN = Children()


def run_shard(shard, args):
    out_rel = shard_dir(args.out, shard)
    marker = marker_path(args.out, shard)
    if os.path.exists(marker):
        if args.resume:
            return ("skip", shard, 0.0, 0, 0)
        # The marker is the whole of "this shard is finished", so a replay that
        # left the old one in place would report the old artifacts as its own.
        os.remove(marker)
    cmd = [
        GODOT, "--headless", "--path", ".", "-s", shard.preset["script"], "--",
        *shard.args, "--out=%s" % out_rel,
    ]
    started = time.time()
    proc = CHILDREN.start(cmd)
    if proc is None:
        return ("cancel", shard, 0.0, 0, 0)
    try:
        stdout, stderr = proc.communicate(timeout=args.timeout)
        rc = proc.returncode
    except subprocess.TimeoutExpired:
        proc.kill()
        stdout, stderr = proc.communicate()
        rc = -9
    finally:
        CHILDREN.finished(proc)
    elapsed = time.time() - started
    if CHILDREN.stopping():
        return ("cancel", shard, elapsed, rc, 0)
    if not os.path.exists(marker):
        failures = os.path.join(ROOT, args.out, "failures")
        os.makedirs(failures, exist_ok=True)
        with open(os.path.join(failures, shard.name + ".log"), "w") as f:
            f.write("rc=%d elapsed=%.1fs\ncmd=%s\n\n" % (rc, elapsed, " ".join(cmd)))
            f.write(stdout[-4000:] + "\n--- stderr ---\n" + stderr[-4000:])
        return ("FAIL", shard, elapsed, rc, 0)
    primary = shard.preset["artifacts"][0][0]
    played = shard.preset["count"](os.path.join(ROOT, out_rel, primary))
    return ("done", shard, elapsed, rc, played)


def merge(out, shards, name, merger):
    """Concatenates the shards' records in plan order, and returns (rows, error).
    A shard that is missing means the run is incomplete and the caller does not
    get here."""
    sources = [os.path.join(ROOT, shard_dir(out, shard), name) for shard in shards]
    return merger(os.path.join(ROOT, out, name), sources)


## The arena's sides in the resume-key cases: two paths, which is the shape the
## key has to survive — a candidate is a file, not a `<commander>:<tier>` spec.
AR_SIDES = ("data/ai/default.tres", "reports/arena/gen1/c7.tres")

## Every shape `resolve_out` has had to refuse or contain, and the plain relative
## path that must keep working. `tests/unit/test_report_writer.gd` runs this same
## table against the GDScript half, so the two cannot drift apart quietly.
OUT_CASES = [
    ("reports/balance_pool/run", "reports/balance_pool/run"),
    ("verify_equiv", "reports/verify_equiv"),
    ("./nested/run", "reports/nested/run"),
    ("reports", "reports"),
    ("res://reports/ai_arena/run", "reports/ai_arena/run"),
    ("/tmp/pooltest", ""),
    ("res:///tmp/pooltest", ""),
    ("../escape", ""),
    ("reports/../../escape", ""),
]


def _stamp(files, head="c0", dirty=""):
    return {"files": dict(files), "head": head, "dirty": dirty}


## A stamp on disk, this run's, and the first line the refusal has to say — or ""
## when the markers still answer. Every case is a day this would have mattered: a
## retuned anchor, a retuned chart, a new commit, an uncommitted edit. The last
## two are what it must *not* refuse — the arena search names a new wave of
## candidates in the same pool directory, and a directory written before the
## stamp existed is not evidence that anything moved.
STAMP_CASES = [
    ("the same content resumes", _stamp({"data/rules.tres": "r1"}),
     _stamp({"data/rules.tres": "r1"}), ""),
    ("a retuned side replays", _stamp({"data/ai/default.tres": "a1"}),
     _stamp({"data/ai/default.tres": "a2"}), "data/ai/default.tres changed"),
    ("a retuned damage chart replays", _stamp({"data/damage_chart.tres": "d1"}),
     _stamp({"data/damage_chart.tres": "d2"}), "data/damage_chart.tres changed"),
    ("a new commit replays", _stamp({}, head="c0"), _stamp({}, head="c1"), "HEAD moved: c0 -> c1"),
    ("a dirty tree does not resume a clean one's shards", _stamp({}),
     _stamp({}, dirty=" M core/grid.gd"), "uncommitted work"),
    ("the next wave's candidates are not a change", _stamp({"reports/s/c1.tres": "1"}),
     _stamp({"reports/s/c1.tres": "1", "reports/s/c2.tres": "2"}), ""),
    ("an unstamped run is not a change", {}, _stamp({"data/rules.tres": "r1"}), ""),
]

## What a caller can ask for over a stamp that moved: (refresh, changes,
## reuse-stale) -> may this run honour the markers on disk.
RESUME_CASES = [
    ("a matching stamp resumes", False, [], False, True),
    ("--refresh replays a matching stamp", True, [], False, False),
    ("a moved stamp replays", False, ["x"], False, False),
    ("--reuse-stale keeps a moved stamp's shards", False, ["x"], True, True),
    ("--refresh beats --reuse-stale", True, ["x"], True, False),
]

## Two headers that disagree and the merge that must refuse them. The columns are
## the Lab's own, shortened: what makes a pair legal is that the text matches, so
## the names only have to be recognisable.
LAB_HEADER = "seed,map,red,blue,winner,day\n"
MERGE_CASES = [
    ("shards agreeing merge", [LAB_HEADER + "1,a,x,y,1,7\n", LAB_HEADER + "2,a,x,y,2,9\n"], True),
    ("a shard with a column more", [LAB_HEADER, "seed,map,red,blue,winner,day,turns\n"], False),
    ("a shard with the columns reordered", [LAB_HEADER, "map,seed,red,blue,winner,day\n"], False),
]

## What a row is when a cell is quoted the way `BalanceReportWriter._cell` quotes
## it (RFC 4180) — the embedded newline is the case a line count reads as two.
ROW_CASES = [
    ("plain rows", LAB_HEADER + "1,a,x,y,1,7\n2,a,x,y,2,9\n", 2),
    ("header only", LAB_HEADER, 0),
    ("a quoted separator", LAB_HEADER + '1,a,"x,y",y,1,7\n', 1),
    ("a quoted newline", LAB_HEADER + '1,a,"x\ny",y,1,7\n2,a,x,y,2,9\n', 2),
]


def self_check():
    """The out-directory, resume-key, content-stamp and merge rules, over the
    cases that made them.
    Run by `tools/check_scripts.sh`, and so by `make check` and `make verify`,
    which otherwise reach GDScript only — these are the decisions in here that
    are pure and worth pinning, and an ungated check is one that rots."""
    cases = OUT_CASES
    failures = 0
    for out, expected in cases:
        path, error = resolve_out(out)
        ok = path == expected and bool(error) == (expected == "")
        failures += 0 if ok else 1
        print("%-4s --out=%-22s -> %s" % (
            "ok" if ok else "FAIL", out, error or path))

    def key(days, preset="lab", red=None, blue=None, offset=0):
        sides = {"lab": ("none:normal", "none:hard"), "arena": AR_SIDES}[preset]
        return Shard(preset, "ironworks", red or sides[0], blue or sides[1], offset, 4, days).name

    for label, ok in (
        ("same spec, same key", key(20) == key(20)),
        ("different day cap, different key", key(20) != key(100)),
        ("driver default day cap, different key", key(0) != key(100)),
        ("a held-out slice of the range, different key", key(100) != key(100, offset=12)),
        ("a preset's shards are its own", key(100) != key(100, "arena")),
        (
            "a candidate's path slugs to a bare name",
            os.sep not in key(100, "arena"),
        ),
        (
            "two candidates of the same name stay apart",
            key(100, "arena", red="reports/g1/c1.tres")
            != key(100, "arena", red="reports/g2/c1.tres"),
        ),
    ):
        failures += 0 if ok else 1
        print("%-4s resume key: %s" % ("ok" if ok else "FAIL", label))

    for label, previous, current, expected in STAMP_CASES:
        changes = stamp_changes(previous, current)
        first = changes[0] if changes else ""
        ok = expected in first if expected else not changes
        failures += 0 if ok else 1
        print("%-4s stamp: %-46s -> %s" % (
            "ok" if ok else "FAIL", label, first or "resumes"))

    for label, refresh, changes, reuse_stale, expected in RESUME_CASES:
        ok = resumes(refresh, changes, reuse_stale) == expected
        failures += 0 if ok else 1
        print("%-4s resume: %s" % ("ok" if ok else "FAIL", label))

    with tempfile.TemporaryDirectory() as scratch:
        ## Which files a stamp is taken over, over a scratch tree: a side is a
        ## path only in the arena, and a named side that is not there has to read
        ## as absent rather than as a digest that happens to match.
        for path in (*STAMPED_DATA, *AR_SIDES):
            os.makedirs(os.path.join(scratch, os.path.dirname(path)), exist_ok=True)
            with open(os.path.join(scratch, path), "w") as f:
                f.write(path)
        gone = "data/ai/gone.tres"
        for label, ok in (
            (
                "a lab side names no file",
                sorted(stamped_files("lab", [("none:normal", "none:hard")], scratch))
                == sorted(STAMPED_DATA),
            ),
            (
                "an arena side is stamped with the resources",
                sorted(stamped_files("arena", [AR_SIDES], scratch))
                == sorted(set(STAMPED_DATA + AR_SIDES)),
            ),
            (
                "a side that is not there is not a silent match",
                stamped_files("arena", [(gone, AR_SIDES[0])], scratch)[gone] == "(missing)",
            ),
            ("an out-directory with no stamp reads empty", read_stamp(scratch) == {}),
        ):
            failures += 0 if ok else 1
            print("%-4s stamped files: %s" % ("ok" if ok else "FAIL", label))

    with tempfile.TemporaryDirectory() as scratch:
        for index, (label, shards, agree) in enumerate(MERGE_CASES):
            sources = []
            for number, text in enumerate(shards):
                shard = os.path.join(scratch, "m%d" % index, "shard_%d" % number)
                os.makedirs(shard)
                path = os.path.join(shard, "matches.csv")
                with open(path, "w") as f:
                    f.write(text)
                sources.append(path)
            dest = os.path.join(scratch, "m%d" % index, "matches.csv")
            rows, error = merge_csv(dest, sources)
            if agree:
                ok = not error and rows == len(sources) and os.path.exists(dest)
            else:
                ## The refusal has to name the shard and both headers, or the
                ## reader cannot tell which run to throw away.
                ok = (
                    rows == 0
                    and not os.path.exists(dest)
                    and "shard_1" in error
                    and shards[0].strip() in error
                    and shards[1].strip() in error
                )
            failures += 0 if ok else 1
            print("%-4s merge: %s" % ("ok" if ok else "FAIL", label))

        for index, (label, text, expected) in enumerate(ROW_CASES):
            path = os.path.join(scratch, "r%d.csv" % index)
            with open(path, "w", newline="") as f:
                f.write(text)
            counted = count_csv_rows(path)
            ok = counted == expected
            failures += 0 if ok else 1
            print("%-4s rows: %s -> %d" % ("ok" if ok else "FAIL", label, counted))

    print("self-check: %d case(s) failed" % failures if failures else "self-check: all cases pass")
    return 1 if failures else 0


def main(argv):
    if "--self-check" in argv:
        return self_check()
    args = parse_args(argv)
    shards = build_shards(args)
    matches_hint = sum(s.count for s in shards)
    if args.dry_run:
        for shard in shards:
            print("%-70s %s" % (shard.name, " ".join(shard.args)))
        print("%d shards, %d seeds, %d workers, writing to %s"
              % (len(shards), matches_hint, args.workers, args.out))
        for line in stamp_changes(read_stamp(args.out), content_stamp(args)):
            print("balance-pool: !! %s" % line)
        return 0

    if not os.access(GODOT, os.X_OK):
        print("balance-pool: Godot not found at %s" % GODOT, file=sys.stderr)
        print("balance-pool: see README.md for engine setup, or set GODOT=<path>", file=sys.stderr)
        return 2

    out_abs = os.path.join(ROOT, args.out)
    os.makedirs(out_abs, exist_ok=True)
    log = open(os.path.join(out_abs, "progress.log"), "a", buffering=1)
    args.resume = pool_resume(args, shards, log)
    status_path = os.path.join(out_abs, "status.txt")
    started = time.time()
    loads = [os.getloadavg()[0]]
    counts = {"done": 0, "skip": 0, "FAIL": 0, "cancel": 0}
    played = 0
    log.write("=== pool start: %d shards, %d workers, load %.2f ===\n" % (
        len(shards), args.workers, loads[0]))

    def write_status():
        elapsed = time.time() - started
        finished = sum(counts.values())
        rate = 60.0 * played / elapsed if elapsed > 0 else 0.0
        with open(status_path, "w") as f:
            f.write(
                "%d/%d shards (%d pre-done, %d failed) | %d matches played | "
                "elapsed %.1f s | %.1f matches/min | load %.2f\n"
                % (finished, len(shards), counts["skip"], counts["FAIL"],
                   played, elapsed, rate, loads[-1])
            )

    pool = ThreadPoolExecutor(max_workers=args.workers)
    futures = [pool.submit(run_shard, shard, args) for shard in shards]
    try:
        for future in as_completed(futures):
            state, shard, elapsed, rc, rows = future.result()
            counts[state] += 1
            played += rows
            loads.append(os.getloadavg()[0])
            if state not in ("skip", "cancel"):
                log.write("%s %s %.1fs rc=%d %d matches\n" % (state, shard.name, elapsed, rc, rows))
            write_status()
    except KeyboardInterrupt:
        pool.shutdown(wait=False, cancel_futures=True)
        CHILDREN.stop()
        log.write("=== pool interrupted: %d done, %d skipped, %d failed ===\n"
                  % (counts["done"], counts["skip"], counts["FAIL"]))
        print("balance-pool: interrupted; rerun the same command to resume", file=sys.stderr)
        return 130
    pool.shutdown()

    wall = time.time() - started
    if counts["FAIL"]:
        log.write("=== pool end: %d FAILED ===\n" % counts["FAIL"])
        print("balance-pool: %d shard(s) failed; see %s/failures" % (counts["FAIL"], args.out))
        return 1
    preset = PRESETS[args.preset]
    matches = 0
    for index, (name, merger) in enumerate(preset["artifacts"]):
        rows, error = merge(args.out, shards, name, merger)
        if error:
            log.write("=== pool end: %s not merged ===\n" % name)
            print("balance-pool: %s: %s" % (name, error), file=sys.stderr)
            return 1
        if index == 0:
            matches = rows
    separator = preset["pair_sep"]
    reading = {
        "spec": {
            "preset": args.preset,
            "maps": args.maps,
            "pairings": [separator.join((r, b)) for r, b in args.pairings],
            "seeds": args.seeds,
            "seed_offset": args.seed_offset,
            "batch": args.batch,
            "days": args.days or "(driver default)",
        },
        "workers": args.workers,
        "shards": len(shards),
        "shards_skipped": counts["skip"],
        "matches": matches,
        "matches_played": played,
        "wall_s": round(wall, 1),
        "matches_per_min": round(60.0 * played / wall, 1) if wall > 0 else 0.0,
        "load_start": round(loads[0], 2),
        "load_end": round(loads[-1], 2),
        "load_mean": round(sum(loads) / len(loads), 2),
    }
    with open(os.path.join(out_abs, "pool.json"), "w") as f:
        json.dump(reading, f, indent="\t")
    write_status()
    log.write("=== pool end: %d done, %d skipped, %.1f matches/min ===\n"
              % (counts["done"], counts["skip"], reading["matches_per_min"]))
    print("balance-pool: %d matches in %s (%d shards, %d resumed) in %.1f s"
          % (matches, args.out, len(shards), counts["skip"], wall))
    if played:
        print("balance-pool: %.1f matches/min at %d workers, load %.2f -> %.2f"
              % (reading["matches_per_min"], args.workers, loads[0], loads[-1]))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
