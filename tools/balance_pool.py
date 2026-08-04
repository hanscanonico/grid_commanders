#!/usr/bin/env python3
"""Balance pool — the Lab's matrix played on several cores at once.

One headless Godot process per shard, `--workers` of them at a time, and
**resumable**: a shard whose `summary.json` is already on disk is skipped, so a
killed run costs the shard in flight and nothing else. That property is the
reason this exists in the shape it does — a sweep that has to start over is a
sweep nobody dares interrupt.

A shard is one pairing on one board over a contiguous slice of the seed range
(`--batch` seeds, handed to the Lab as `--seeds=` plus `--seed-offset=`). That
is the smallest unit of work that both amortises the engine boot (~0.9 s against
~1.6 s a match) and is independently readable: it writes its own `matches.csv`
and `summary.json` under `shards/`.

**The Lab plays every match; this only decides who plays what, and when.** The
merged `matches.csv` is what a single `make balance-sim` run of the same spec
writes, row for row and byte for byte — that diff is the merge bar for any
change to the sharding here. Nothing is aggregated: a merged summary would be a
second opinion about numbers `BalanceRunSummary` already owns.

Usage:
  tools/balance_pool.py --maps=ironworks --pairings=none:normal/none:hard \\
      --seeds=32 --batch=4 --days=100 --workers=4

Flags:
  --maps=a,b            shipped boards or Lab fixtures (required)
  --pairings=r/b,r/b    `<red spec>/<blue spec>`, the Lab's own side grammar,
                        passed through untouched (required)
  --seeds=N             paired seeds per pairing (default 4, the Lab's)
  --batch=N             seeds per shard (default 4)
  --days=N              day cap; omitted, the Lab's own default stands
  --workers=N           processes at a time (default 6 — the measured peak; the
                        curve it comes from is in docs/balance_sim.md)
  --out=DIR             run directory, **relative to reports/** and refused if
                        it leaves it (default reports/balance_pool/<spec>; a
                        leading `reports/` is accepted, so both spellings work)
  --timeout=SEC         per shard, default 3600
  --dry-run             resolve the spec, print the shard plan, and stop
  --self-check          run the out-directory rules over their cases and stop

Poll a live run with `cat <out>/status.txt`; `<out>/progress.log` is the record
and `<out>/pool.json` the throughput reading. Exit status is 1 if any shard
failed to write a summary — a shard that wrote one and still exited 1 is the
Lab reporting a cap-stall finding, not a failed run.

Everything a run writes lands under `reports/`, and the driver refuses at
startup to be pointed anywhere else. See `resolve_out`: the Lab resolves its own
`--out` against the *project* root, so a path outside the repo is silently
written inside it, where this driver never looks — and resume, which is keyed on
a shard's `summary.json`, would then replay every shard of every run forever
while calling each one failed.

Nice the whole pool if you want the machine back: `nice -n 10 tools/balance_pool.py …`
"""
import argparse
import json
import os
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GODOT = os.environ.get("GODOT", os.path.join(ROOT, "bin/Godot.app/Contents/MacOS/Godot"))
REPORTS_ROOT = "reports"
DEFAULT_OUT_ROOT = os.path.join(REPORTS_ROOT, "balance_pool")
# Six is where throughput peaked on the 4-performance-core M1 this was measured
# on — eight regresses — and no machine should be asked for more workers than it
# has cores. docs/balance_sim.md carries the curve.
DEFAULT_WORKERS = max(1, min(6, os.cpu_count() or 4))


class Shard:
    def __init__(self, map_name, red, blue, offset, count):
        self.map_name = map_name
        self.red = red
        self.blue = blue
        self.offset = offset
        self.count = count
        self.name = "%s__%s__vs__%s__s%d+%d" % (
            map_name, _slug(red), _slug(blue), offset, count
        )

    def args(self, days):
        args = [
            "--map=%s" % self.map_name,
            "--red=%s" % self.red,
            "--blue=%s" % self.blue,
            "--seeds=%d" % self.count,
            "--seed-offset=%d" % self.offset,
            "--no-commands",
        ]
        if days:
            args.append("--days=%d" % days)
        return args


def _slug(spec):
    return spec.replace(":", "-") or "default"


def resolve_out(out):
    """The run directory, as a repo-relative path under `reports/`. Returns
    (path, error) and is the one place that decides where a run may write.

    A relative path is taken as relative to `reports/` — a leading `reports/` is
    accepted rather than doubled, since that is how the default and every
    documented example are spelled. Anything that leaves `reports/`, including an
    absolute path, is an error the caller reports before a match is played.

    The rule is not tidiness. `BalanceReportWriter.prepare_dir` resolves the
    Lab's own `--out` against the *project* root, and Godot's `path_join`
    re-roots an absolute path under it — so `--out=/tmp/x` writes to `<repo>/tmp/x`
    while this driver reads `/tmp/x`. Resume is keyed on finding a shard's
    `summary.json`, so it would then find none, ever: every shard of every run
    replayed forever and reported failed, with the results on disk the whole time.
    Containing the path is what makes that unreachable instead of documented.
    """
    refusal = "--out is relative to %s/ and may not leave it (got '%s')" % (REPORTS_ROOT, out)
    if os.path.isabs(out):
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
    p.add_argument("--seeds", type=int, default=4)
    p.add_argument("--batch", type=int, default=4)
    p.add_argument("--days", type=int, default=0)
    p.add_argument("--workers", type=int, default=DEFAULT_WORKERS)
    p.add_argument("--out", default="")
    p.add_argument("--timeout", type=int, default=3600)
    p.add_argument("--dry-run", action="store_true")
    args = p.parse_args(argv)
    args.maps = [m.strip() for m in args.maps.split(",") if m.strip()]
    pairings = []
    for text in args.pairings.split(","):
        red, sep, blue = text.strip().partition("/")
        if not sep:
            p.error("a pairing is <red spec>/<blue spec>, got '%s'" % text)
        pairings.append((red.strip(), blue.strip()))
    args.pairings = pairings
    for name, value in (("seeds", args.seeds), ("batch", args.batch), ("workers", args.workers)):
        if value < 1:
            p.error("--%s must be at least 1" % name)
    args.out, error = resolve_out(args.out or os.path.join(DEFAULT_OUT_ROOT, run_name(args)))
    if error:
        p.error(error)
    return args


def run_name(args):
    """Derived from the spec, never a clock — the Lab's rule, and here it is also
    the resume key: rerunning a sweep finds its own directory and skips what it
    already played."""
    parts = ["-".join(args.maps)]
    parts += ["%s_vs_%s" % (_slug(r), _slug(b)) for r, b in args.pairings]
    parts.append("s%d_b%d" % (args.seeds, args.batch))
    if args.days:
        parts.append("d%d" % args.days)
    return "_".join(parts)


def build_shards(args):
    """Map by map, pairing by pairing, seed slice by seed slice — the order the
    Lab itself would play them in, which is what makes the merge a concatenation."""
    shards = []
    for map_name in args.maps:
        for red, blue in args.pairings:
            for offset in range(0, args.seeds, args.batch):
                count = min(args.batch, args.seeds - offset)
                shards.append(Shard(map_name, red, blue, offset, count))
    return shards


def shard_dir(out, shard):
    return os.path.join(out, "shards", shard.name)


def match_rows(path):
    with open(path) as f:
        return max(0, sum(1 for _ in f) - 1)


def run_shard(shard, args):
    out_rel = shard_dir(args.out, shard)
    summary = os.path.join(ROOT, out_rel, "summary.json")
    if os.path.exists(summary):
        return ("skip", shard, 0.0, 0, 0)
    cmd = [
        GODOT, "--headless", "--path", ".", "-s", "res://tools/run_balance_sim.gd", "--",
        *shard.args(args.days), "--out=%s" % out_rel,
    ]
    started = time.time()
    proc = None
    try:
        proc = subprocess.run(
            cmd, cwd=ROOT, capture_output=True, text=True, timeout=args.timeout
        )
        rc = proc.returncode
    except subprocess.TimeoutExpired:
        rc = -9
    elapsed = time.time() - started
    if not os.path.exists(summary):
        failures = os.path.join(ROOT, args.out, "failures")
        os.makedirs(failures, exist_ok=True)
        with open(os.path.join(failures, shard.name + ".log"), "w") as f:
            f.write("rc=%d elapsed=%.1fs\ncmd=%s\n\n" % (rc, elapsed, " ".join(cmd)))
            if proc is not None:
                f.write(proc.stdout[-4000:] + "\n--- stderr ---\n" + proc.stderr[-4000:])
        return ("FAIL", shard, elapsed, rc, 0)
    played = match_rows(os.path.join(ROOT, out_rel, "matches.csv"))
    return ("done", shard, elapsed, rc, played)


def merge(out, shards, name):
    """Concatenates the shards' rows in plan order, one header. A shard that is
    missing means the run is incomplete and the caller does not get here."""
    dest = os.path.join(ROOT, out, name)
    rows = 0
    with open(dest, "w") as merged:
        for index, shard in enumerate(shards):
            with open(os.path.join(ROOT, shard_dir(out, shard), name)) as f:
                header = f.readline()
                if index == 0:
                    merged.write(header)
                for line in f:
                    merged.write(line)
                    rows += 1
    return rows


def self_check():
    """The out-directory rules, over the cases that made them. Run it with
    `--self-check`: `make verify` reaches GDScript only, so this is where the
    one decision in here that is pure and worth pinning gets exercised."""
    cases = [
        ("reports/balance_pool/run", "reports/balance_pool/run"),
        ("verify_equiv", "reports/verify_equiv"),
        ("./nested/run", "reports/nested/run"),
        ("reports", "reports"),
        ("/tmp/pooltest", ""),
        ("../escape", ""),
        ("reports/../../escape", ""),
    ]
    failures = 0
    for out, expected in cases:
        path, error = resolve_out(out)
        ok = path == expected and bool(error) == (expected == "")
        failures += 0 if ok else 1
        print("%-4s --out=%-22s -> %s" % (
            "ok" if ok else "FAIL", out, error or path))
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
            print("%-60s %s" % (shard.name, " ".join(shard.args(args.days))))
        print("%d shards, %d seeds, %d workers, writing to %s"
              % (len(shards), matches_hint, args.workers, args.out))
        return 0

    if not os.access(GODOT, os.X_OK):
        print("balance-pool: Godot not found at %s" % GODOT, file=sys.stderr)
        print("balance-pool: see README.md for engine setup, or set GODOT=<path>", file=sys.stderr)
        return 2

    out_abs = os.path.join(ROOT, args.out)
    os.makedirs(out_abs, exist_ok=True)
    log = open(os.path.join(out_abs, "progress.log"), "a", buffering=1)
    status_path = os.path.join(out_abs, "status.txt")
    started = time.time()
    loads = [os.getloadavg()[0]]
    counts = {"done": 0, "skip": 0, "FAIL": 0}
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
            if state != "skip":
                log.write("%s %s %.1fs rc=%d %d matches\n" % (state, shard.name, elapsed, rc, rows))
            write_status()
    except KeyboardInterrupt:
        pool.shutdown(wait=False, cancel_futures=True)
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
    matches = merge(args.out, shards, "matches.csv")
    merge(args.out, shards, "timeline.csv")
    reading = {
        "spec": {
            "maps": args.maps,
            "pairings": ["%s/%s" % (r, b) for r, b in args.pairings],
            "seeds": args.seeds,
            "batch": args.batch,
            "days": args.days or "(lab default)",
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
