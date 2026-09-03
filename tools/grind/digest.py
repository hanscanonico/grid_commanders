#!/usr/bin/env python3
"""Grind digest — what the box has been doing, in one page a person can read.

`tools/grind/grind.sh` plays the instruments; this reads what they left behind.
Three modes, all of them writing under `reports/grind/` and nothing else:

  digest.py --state …    the live state of the supervisor (state.json)
  digest.py --record …   one job's outcome (jobs/<job>.json)
  digest.py              rebuild DIGEST.md and status.json from both

**The reading comes from the instrument's own artifact, never from a second
opinion.** A job's record names the *kind* of reading it left — an arena search
run directory, a section of its log, a merged `matches.csv`, a replay survey —
and each extractor here reads that one thing. Nothing is recomputed: a win rate
is counted off the rows the engine wrote, and a champion vector is the one the
search recorded.

The page is capped on purpose. It is meant to be read whole by a person over
coffee, or by a session that must not open a 200 MB CSV, so every job gets a
handful of lines and the raw artifacts stay where they are.

Flags:
  --dir=DIR             the grind directory (default reports/grind)
  --state               write state.json from --pass/--job/--phase/--started/
                        --queue/--order/--boot, then rebuild
  --record              write jobs/<job>.json from --job/--status/--exit/
                        --started/--ended/--log/--kind/--artifact/--marker
  --champions=RUN       print the champion candidate of each finished block
  --self-check          run the extractors over tests/fixtures/grind/ and stop
"""
import argparse
import csv
import glob
import json
import os
import socket
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DEFAULT_DIR = "reports/grind"
# Per job. The whole page is meant to stay under ~150 lines, and a job that
# reports more than this is one nobody reads to the end of.
MAX_RESULT_LINES = 8


def read_json(path, fallback=None):
    try:
        with open(path) as f:
            return json.load(f)
    except (OSError, ValueError):
        return {} if fallback is None else fallback


def write_json(path, payload):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        json.dump(payload, f, indent="\t", sort_keys=True)
        f.write("\n")


def resolve(path):
    """A repo-relative artifact path, resolved against the project root — the
    supervisor is run from anywhere and every record it writes is repo-relative."""
    return path if os.path.isabs(path) else os.path.join(ROOT, path)


# Every headless run ends with the engine's own exit chatter — the addon banner
# and the documented script-cycle leak, headline and per-object lines alike — and
# a verdict with that under it reads as a failure to somebody skimming. The
# per-object lines matter most to the fallback reading: there are more of them
# than `tail()` shows, so leaving them in costs the job's real last word.
NOISE = (
    "[godot_ai",
    "ObjectDB instances were leaked",
    "resources still in use",
    "Leaked instance:",
    "Orphan StringName:",
    "Hint: Leaked instances",
)


def log_lines(record):
    path = record.get("log", "")
    if not path or not os.path.exists(resolve(path)):
        return []
    with open(resolve(path), errors="replace") as f:
        said = [line.rstrip() for line in f]
    return [line for line in said if not any(noise in line for noise in NOISE)]


def tail(record):
    """The fallback reading: the last few lines the job said anything on."""
    said = [line for line in log_lines(record) if line.strip()]
    return said[-5:] if said else ["(no output)"]


def log_section(record):
    """From the last line matching the job's marker to the end of the log — how
    every headless runner here prints its verdict."""
    marker = record.get("marker", "")
    lines = log_lines(record)
    starts = [i for i, line in enumerate(lines) if marker and marker in line]
    if not starts:
        # Say so, or a reworded banner hands the engine's exit chatter to the page
        # as the instrument's verdict, under a job still reporting `done`.
        return ["(marker %r not found in the log)" % marker] + tail(record)
    return [line for line in lines[starts[-1]:] if line.strip()]


def arena_reading(record):
    """One line per finished block: which dials moved off the base, and what the
    champion scored on the training pool against the held-out one."""
    run = resolve(record.get("artifact", ""))
    lines = []
    for summary_path in sorted(glob.glob(os.path.join(run, "*", "summary.json"))):
        summary = read_json(summary_path)
        if not summary:
            continue
        moved = [
            "%s %s->%s" % (field, summary["base"][field], summary["champion"][field])
            for field in summary.get("dials", [])
            if summary["base"].get(field) != summary["champion"].get(field)
        ]
        best = max(summary.get("rows", []), key=lambda row: row["training"], default=None)
        scored = (
            "train %+.3f / held out %+.3f" % (best["training"], best["validation"])
            if best
            else "not scored yet"
        )
        lines.append("%s: %s — %s" % (summary["block"], ", ".join(moved) or "base held", scored))
    blocks = len(glob.glob(os.path.join(run, "*", "search.json")))
    lines.append("%d block(s) started, %d finished." % (blocks, len(lines)))
    if os.path.exists(os.path.join(run, "report.md")):
        lines.append("report: %s/report.md" % record.get("artifact", ""))
    return lines


SEATS = {"1": "red", "2": "blue"}


def pool_reading(record):
    """Who won, off the rows the engine wrote. Grouped by the pairing, because a
    pool plays a tier against a tier and the whole point is the gap."""
    path = os.path.join(resolve(record.get("artifact", "")), "matches.csv")
    if not os.path.exists(path):
        return ["(no matches.csv yet)"]
    tallies = {}
    with open(path, newline="") as f:
        for row in csv.DictReader(f):
            pairing = "%s:%s vs %s:%s" % (
                row["red_commander"],
                row["red_tier"],
                row["blue_commander"],
                row["blue_tier"],
            )
            tally = tallies.setdefault(pairing, {"red": 0, "blue": 0, "other": 0})
            # `winner` is the team that took the board — 1 red, 2 blue, and
            # anything else (a day cap, a draw) decided nothing.
            tally[SEATS.get(row["winner"], "other")] += 1
    lines = []
    for pairing in sorted(tallies):
        tally = tallies[pairing]
        played = sum(tally.values())
        lines.append(
            "%s — red %.0f%%, blue %.0f%%, undecided %.0f%% over %d"
            % (
                pairing,
                100.0 * tally["red"] / played,
                100.0 * tally["blue"] / played,
                100.0 * tally["other"] / played,
                played,
            )
        )
    return lines or ["(no rows)"]


def survey_reading(record):
    """The replay survey's headline and the detectors that fired most."""
    survey = read_json(os.path.join(resolve(record.get("artifact", "")), "survey.json"))
    if not survey:
        return ["(no survey.json yet)"]
    lines = [
        "%d recordings, %d commands, %d findings"
        % (int(survey["matches"]), int(survey["commands"]), int(survey["findings"]))
    ]
    for entry in survey.get("kinds", [])[:5]:
        lines.append(
            "%s: %d (%.2f per 100 commands)"
            % (entry["kind"], int(entry["count"]), float(entry["per_100_commands"]))
        )
    return lines


def champions(run):
    """The candidate file each finished block ranked first — what `--publish`
    copies, because a champion is re-run months later by naming its file."""
    paths = []
    for summary_path in sorted(glob.glob(os.path.join(run, "*", "summary.json"))):
        rows = read_json(summary_path).get("rows", [])
        best = max(rows, key=lambda row: row["training"], default=None)
        if best:
            paths.append(best["path"])
    return paths


READINGS = {
    "arena": arena_reading,
    "pool": pool_reading,
    "survey": survey_reading,
    "section": log_section,
    "log": tail,
}


def reading(record):
    read = READINGS.get(record.get("kind", "log"), tail)
    try:
        lines = read(record)
    except (OSError, ValueError, KeyError, IndexError, ZeroDivisionError) as err:
        lines = ["(unreadable: %s)" % err]
    lines = [line[:100] for line in lines]
    if len(lines) > MAX_RESULT_LINES:
        # The last line of an instrument's section is its verdict, so a reading
        # is trimmed in the middle rather than at the end.
        lines = lines[: MAX_RESULT_LINES - 2] + ["…", lines[-1]]
    return lines or ["(nothing to read)"]


def ago(stamp):
    if not stamp:
        return "—"
    seconds = max(0, int(time.time()) - int(stamp))
    if seconds < 90:
        return "%ds ago" % seconds
    if seconds < 5400:
        return "%dm ago" % (seconds // 60)
    return "%.1fh ago" % (seconds / 3600.0)


def spell_duration(seconds):
    seconds = int(seconds)
    if seconds < 90:
        return "%ds" % seconds
    if seconds < 5400:
        return "%dm" % (seconds // 60)
    return "%.1fh" % (seconds / 3600.0)


def records(grind_dir):
    """Every job record, in the rotation's own order — a page that reshuffles
    between passes cannot be diffed."""
    state = read_json(os.path.join(grind_dir, "state.json"))
    order = state.get("order", [])
    found = {}
    for path in glob.glob(os.path.join(grind_dir, "jobs", "*.json")):
        record = read_json(path)
        if record:
            found[record.get("job", os.path.basename(path)[:-5])] = record
    ranked = sorted(found, key=lambda job: (order.index(job) if job in order else len(order), job))
    return state, [found[job] for job in ranked]


def digest_lines(state, jobs):
    stamp = time.strftime("%Y-%m-%d %H:%M:%S", time.localtime())
    lines = [
        "# Grind digest",
        "",
        "host `%s` · commit `%s` · pass %s · up %s · written %s"
        % (
            state.get("host", socket.gethostname()),
            state.get("sha", "?"),
            state.get("pass", "?"),
            spell_duration(time.time() - state.get("boot", time.time())),
            stamp,
        ),
        "",
        "now: **%s** — %s, started %s"
        % (
            state.get("job") or "nothing running",
            state.get("phase") or "idle",
            ago(state.get("started")),
        ),
        "",
        "queued this pass: %s" % (", ".join(state.get("queue", [])) or "—"),
        "",
    ]
    for record in jobs:
        wall = float(record.get("ended", 0)) - float(record.get("started", 0))
        lines.append(
            "## %s — %s (%s, %s)"
            % (
                record.get("job", "?"),
                record.get("status", "?"),
                ago(record.get("ended")),
                spell_duration(max(0.0, wall)),
            )
        )
        lines.append("")
        lines += reading(record)
        lines.append("")
    return lines


def rebuild(grind_dir):
    state, jobs = records(grind_dir)
    lines = digest_lines(state, jobs)
    path = os.path.join(grind_dir, "DIGEST.md")
    os.makedirs(grind_dir, exist_ok=True)
    with open(path, "w") as f:
        f.write("\n".join(lines) + "\n")
    write_json(
        os.path.join(grind_dir, "status.json"),
        {
            "written": int(time.time()),
            "state": state,
            "jobs": [dict(record, reading=reading(record)) for record in jobs],
        },
    )
    return path


def parse_args(argv):
    p = argparse.ArgumentParser(add_help=True, description=__doc__)
    p.add_argument("--dir", default=DEFAULT_DIR)
    p.add_argument("--state", action="store_true")
    p.add_argument("--record", action="store_true")
    p.add_argument("--self-check", action="store_true")
    p.add_argument("--champions", default="")
    for field in ("job", "phase", "status", "log", "kind", "artifact", "marker", "sha", "host"):
        p.add_argument("--" + field, default="")
    for field in ("pass", "started", "ended", "boot", "exit"):
        p.add_argument("--" + field, dest=field.replace("pass", "pass_no"), type=int, default=0)
    p.add_argument("--queue", default="")
    p.add_argument("--order", default="")
    return p.parse_args(argv)


def main(argv):
    args = parse_args(argv)
    if args.self_check:
        return self_check()
    if args.champions:
        for path in champions(resolve(args.champions)):
            print(path)
        return 0
    grind_dir = resolve(args.dir)
    if args.state:
        previous = read_json(os.path.join(grind_dir, "state.json"))
        write_json(
            os.path.join(grind_dir, "state.json"),
            {
                "host": args.host or socket.gethostname(),
                "sha": args.sha,
                "pass": args.pass_no,
                "job": args.job,
                "phase": args.phase,
                "started": args.started,
                "boot": args.boot or previous.get("boot", int(time.time())),
                "queue": [j for j in args.queue.split(",") if j],
                "order": [j for j in args.order.split(",") if j] or previous.get("order", []),
            },
        )
    if args.record:
        write_json(
            os.path.join(grind_dir, "jobs", args.job + ".json"),
            {
                "job": args.job,
                "status": args.status,
                "exit": args.exit,
                "started": args.started,
                "ended": args.ended or int(time.time()),
                "log": args.log,
                "kind": args.kind or "log",
                "artifact": args.artifact,
                "marker": args.marker,
            },
        )
    print(rebuild(grind_dir))
    return 0


def self_check():
    """The extractors, over committed fixtures — no engine, no matches, and the
    only part of the supervisor that is pure enough to pin."""
    fixtures = os.path.join(ROOT, "tests/fixtures/grind")
    failures = []

    def case(name, ok):
        if not ok:
            failures.append(name)

    arena = reading({"kind": "arena", "artifact": "tests/fixtures/grind/search"})
    case("arena names the block", arena[0].startswith("combat:"))
    case("arena reports the moved dial", "retreat_bias 0.2->0.4" in arena[0])
    case("arena reports both pools", "train +0.120 / held out +0.080" in arena[0])
    case("arena counts the blocks", "1 block(s) started, 1 finished." in arena)

    pool = reading({"kind": "pool", "artifact": "tests/fixtures/grind/pool"})
    case("pool groups by pairing", pool[0].startswith("none:normal vs none:hard"))
    case("pool counts red wins", "red 50%" in pool[0])
    case("pool counts undecided", "undecided 25%" in pool[0])

    survey = reading({"kind": "survey", "artifact": "tests/fixtures/grind/replay"})
    case("survey leads with the headline", survey[0] == "3 recordings, 120 commands, 7 findings")
    case("survey ranks the kinds", survey[1].startswith("idle_unit: 4"))

    log = os.path.join("tests/fixtures/grind", "difficulty.log")
    section = reading({"kind": "section", "log": log, "marker": "=== difficulty ladder ==="})
    case("section starts at the marker", section[0] == "=== difficulty ladder ===")
    case("section keeps the verdict", "PASS: every higher tier clears the gate." in section)
    case("section drops the noise", "playing 12 matches" not in "\n".join(section))
    case("engine exit chatter is not a verdict", not any("godot_ai" in l for l in section))

    case("a section longer than the cap is capped", len(section) == MAX_RESULT_LINES)
    case("a capped section is elided in the middle", section[-2] == "…")
    case("a job with no reading says so", reading({"kind": "log", "log": ""}) == ["(no output)"])
    case("a missing artifact is not a crash", reading({"kind": "pool", "artifact": "nope"}))

    # reworded.log is difficulty-check with its banner renamed, and it ends on the
    # documented exit leak: the marker misses, so the label has to degrade to the
    # job's real last word rather than to the engine's per-object leak lines.
    reworded = reading(
        {
            "kind": "section",
            "log": "tests/fixtures/grind/reworded.log",
            "marker": "=== difficulty ladder ===",
        }
    )
    case("a missed marker labels the reading a fallback", reworded[0].startswith("(marker "))
    case("a missed marker names the marker it wanted", "difficulty ladder" in reworded[0])
    case(
        "a missed marker falls back to the verdict",
        any("PASS: every higher tier clears the gate." in line for line in reworded),
    )
    case("a missed marker drops the exit leak", not any("Leaked" in line for line in reworded))

    state = {"sha": "abc1234", "pass": 2, "job": "difficulty-check", "phase": "running"}
    page = digest_lines(state, [{"job": "difficulty-check", "status": "done", "kind": "log"}])
    case("the page names the commit", any("abc1234" in line for line in page))
    long_section = reading(
        {"kind": "section", "log": "tests/fixtures/grind/difficulty.log", "marker": "difficulty:"}
    )
    case("a long reading keeps its verdict", long_section[-1].startswith("PASS"))
    case("a long reading drops its middle, not its end", "…" in long_section)
    case("the page has one section per job", "## difficulty-check — done (—, 0s)" in page)

    case("fixtures are where they are said to be", os.path.isdir(fixtures))
    case(
        "the champion of a block is its best-training row, whatever its position",
        champions(os.path.join(fixtures, "search"))
        == ["reports/ai_arena/search/default/combat/c1.tres"],
    )
    for failure in failures:
        print("digest self-check: %s" % failure, file=sys.stderr)
    print("digest self-check: %d case(s) failed" % len(failures))
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
