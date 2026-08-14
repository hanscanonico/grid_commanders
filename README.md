# Audio Generator

Deterministic sound pipeline for [`../grid_commanders`](../grid_commanders):
it renders the game's complete sound-effect roster — the nine names
`autoload/sfx.gd`'s `Sfx.NAMES` plays — as authored synthesis recipes over a
small numpy DSP toolkit. The direction is 16-bit-era chiptune-plus: layered
synthesis with punchy envelopes and filtered noise, built to sit beside the
game's dimetric pixel art (whose pipeline this repo deliberately mirrors —
see [`../sprite_generator`](../sprite_generator)).

There is **no RNG outside per-sound seeds**: noise comes from seeded PCG64
generators, so every run reproduces the same bytes on every platform.
Regenerating after an edit changes exactly the sounds you edited.

## The roster

| Category | Sounds | Peak |
| --- | --- | --- |
| UI | select, move, capture, fanfare | −8…−5 dBFS |
| Combat | shot, explosion, flak, rocket, torpedo | −4…−1.5 dBFS |

UI sits a step under combat by contract — a menu never barks louder than a
battle — and the `Mix` gate holds the bands apart. Output is 44100 Hz mono
16-bit (the shipped placeholders were 22050 Hz; Godot reimports transparently).

## Usage

```sh
python3 -m venv .venv && .venv/bin/pip install -r requirements.txt

# render everything + the A/B soundboard into ./out
.venv/bin/python audio_generator.py

# audition: open out/soundboard.html — every sound, the game's current
# take beside this run's, with the measurements

# install into a game checkout — the path is REQUIRED, never defaulted
.venv/bin/python audio_generator.py --install /path/to/grid_commanders
```

`--install` requiring an explicit path is a scar, not an oversight: a
defaulted destination in the sprite pipeline once overwrote uncommitted work
in the game checkout.

## The gates

`.venv/bin/python -m unittest discover tests` — the merge bar:

- **Contract** — the roster is `Sfx.NAMES` verbatim; every duration fits its
  authored budget (a UI blip stays a blip).
- **Determinism** — every render is byte-stable.
- **Mix** — peaks sit at their authored per-sound level; UI under combat;
  no clicks at the edges (first/last ~0.4 ms near-silent); no DC offset.
- **Distinctness** — pairwise spectral distance over log-band fingerprints:
  no two effects may sound like the same event. The silhouette-IoU gate
  with a Fourier transform.

The measurements live in `audiogen/measure.py`; the tests only assert over
them, so the tool and the suite cannot disagree about what "loud" means.

## Adoption

The game still generates its placeholders (`make sfx` →
`tools/generate_sfx.gd`). The route-C switch — `make sfx` calling this repo —
happens **after** human ears approve the soundboard, not before: the gates
hold consistency and technical quality, but whether an explosion feels right
is not measurable here.

Music (`parade`, `advance`) is milestone 2: a deterministic sequencer playing
authored song data, the voxel-model analogue for composition. Not started.
