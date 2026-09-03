# The grind box

A spare Linux machine, running this repo's offline instruments around the clock,
leaving behind one page somebody reads in the morning. Nothing here measures
anything new: every job is a `make` target that already exists — the AI arena
search, the difficulty ladder, the commander matrix, the campaign ladder, the
legibility ratchet, the balance pool and the replay survey — played at seed
counts a laptop cannot afford.

The entry point is `make grind`; `tools/grind/grind.sh` is the supervisor and
`tools/grind/digest.py` writes the page.

## Install on a fresh Ubuntu/Debian box

```sh
sudo apt-get update
sudo apt-get install -y git make python3 unzip curl \
  libgl1 libx11-6 libxcursor1 libxinerama1 libxi6 libxrandr2
git clone <this repo> ~/grid_commanders
cd ~/grid_commanders
make grind GRIND="--once --dry-run"      # fetches the engine, imports, prints the plan
```

The first run fetches the Godot build the CI workflow pins into `bin/godot` and
imports the project once — a checkout that skipped the import looks like broken
assets rather than a cold cache, so it is part of the bootstrap. `gdtoolkit` is
not needed: the box plays matches, it does not run `make verify`.

Then install the service:

```sh
sudo cp tools/grind/grid-commanders-grind.service /etc/systemd/system/
sudoedit /etc/systemd/system/grid-commanders-grind.service   # User, WorkingDirectory
sudo systemctl daemon-reload
sudo systemctl enable --now grid-commanders-grind
```

The unit runs `make grind GRIND="--publish"` at `Nice=10` with `Restart=always`.
A crash costs the job in flight and nothing else: `arena-search` and
`balance-pool` resume from their own artifacts — the pool's run directory carries
the pass's commit, so a new commit re-measures instead of picking up yesterday's
shards — and the runners that cannot resume are marked done per commit under
`reports/grind/done/`.

## Where is it at?

Two answers, one live and one after the fact.

- **`make grind-status`** — right now: which job, since when, which pass, what is
  still queued, and the running job's own progress. For a search it delegates to
  `tools/arena_status.sh`, for a pool it reads the pool's `status.txt`, and for a
  single-process runner it tails the job log.
  `make grind-status STATUS=--watch` redraws every 10s.
- **`journalctl -u grid-commanders-grind -f`** — the supervisor prints a
  timestamped line at every state change (pass start, job start with its full
  command, job end with exit code and wall time, a skip and why, sleep) plus a
  heartbeat at most every five minutes quoting the running job's progress. The
  same facts are in `reports/grind/state.json`.

## Reading the digest

`reports/grind/DIGEST.md` is rewritten after every job: a header (host, commit,
pass, uptime), then one short section per job with its status, when it ran, how
long it took and a handful of lines of the *result* — the champion vector and
its training-vs-held-out scores per arena base, the difficulty ladder's verdict,
the cells the legibility ratchet says regressed, win rates per pool, the replay
survey's top detectors. `reports/grind/status.json` is the same facts for a
program. The raw CSVs stay under `reports/` and are not meant to be opened.

`reports/` is gitignored, so with `--publish` the box pushes `DIGEST.md`,
`status.json`, each search's `report.md` and champion `.tres`, and the replay
surveys to the orphan branch `grind-results`. It never commits to `main`.

## Stopping it

```sh
sudo systemctl stop grid-commanders-grind     # or ctrl-c a foreground run
```

The supervisor traps the signal, stops the running job's whole process group and
exits at that job's boundary. Nothing is left half-written: every instrument
here writes its artifacts in one go at the end, and the job it interrupted is
`stopped` in the digest rather than `failed` — a restart is not a finding.

## Adopting an arena champion

The search never edits `data/` (arena plan D8), and neither does the box. A
champion is a judged human step:

1. Read the block's section in `reports/grind/DIGEST.md`, then the run's own
   `report.md` — a candidate that beats the base on training and gives it back on
   the held-out pool is not a champion.
2. Play it against the shipped tier yourself:
   `make ai-arena ARENA="--red-profile=data/ai/default.tres --blue-profile=<candidate>.tres --seeds=16"`.
3. If it holds, copy the dial values into `data/ai/<tier>.tres` by hand, and say
   in the commit which run and which candidate they came from.
4. Re-run `make difficulty-check` — the tiers must still order Easy < Normal <
   Difficult, and that gate is the whole claim that the AI plays smarter rather
   than cheating.

## Knobs

`make grind GRIND="…"` takes `--once`, `--dry-run`, `--jobs=a,b` (prefix match),
`--refresh`, `--sleep=SECONDS`, `--workers=N` and `--publish`. The seed counts
are `GRIND_DIFF_SEEDS`, `GRIND_POOL_SEEDS` and `GRIND_SIM_SEEDS`, and
`GRIND_EXTRA_DIFF`, `GRIND_EXTRA_BAL`, `GRIND_EXTRA_CAMPAIGN`,
`GRIND_EXTRA_SEARCH`, `GRIND_EXTRA_POOL` and `GRIND_EXTRA_SIM` are appended to
their job's flags — which is how one job is played end to end in a minute before
the box is trusted with a week:

```sh
GRIND_EXTRA_DIFF="--seeds=1 --days=6" make grind GRIND="--once --jobs=difficulty-check"
```
