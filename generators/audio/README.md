# Audio Generator

Deterministic sound pipeline for this game, living in the repository it feeds
(`generators/audio`, an offline instrument the engine never sees — the sibling
`generators/.gdignore` keeps Godot out of it). It renders the game's complete
sound-effect roster — the nine names `autoload/sfx.gd`'s `Sfx.NAMES` plays —
as authored synthesis recipes over a small numpy DSP toolkit, and its two
looping music tracks — `autoload/music.gd`'s `Music.NAMES` — as authored song
data played by a deterministic sequencer. The direction is 16-bit-era
chiptune-plus: layered synthesis with punchy envelopes and filtered noise,
built to sit beside the game's dimetric pixel art (whose pipeline this one
deliberately mirrors — see [`generators/sprites`](../sprites), which moved
in beside it).

There is **no RNG outside per-sound seeds**: noise comes from seeded PCG64
generators, so every run reproduces the same bytes on every platform.
Regenerating after an edit changes exactly the sounds you edited.

## The roster

| Category | Sounds | Peak |
| --- | --- | --- |
| UI | select, move, capture, fanfare | −8…−5 dBFS |
| Combat | shot, explosion, flak, rocket, torpedo | −4…−1.5 dBFS |
| Music | parade, advance | −7…−6 dBFS |

UI sits a step under combat by contract — a menu never barks louder than a
battle — and the `Mix` gate holds the bands apart. Output is 44100 Hz mono
(the shipped placeholders were 22050 Hz; Godot reimports transparently): the
nine effects as 16-bit PCM `.wav`, the two music loops as Ogg Vorbis `.ogg`.

## The music

Two strictly original marches, composed as hand-written note data in
`audiogen/music.py` — melodies note by note, harmony as a bar chart, drums
as patterns plus authored fills — rendered by `audiogen/sequencer.py`, the
voxel-model analogue for composition:

- **parade** (main menu): a proud C-major march at 104 BPM, AABA over 32
  bars (74 s). Oom-pah tuba, afterbeat horns, parade snare, singable lead;
  the last bar's pickup lifts the loop back to its downbeat.
- **advance** (battle): an A-minor quickstep at 132 BPM, ABAC over 32 bars
  (58 s). Driving eighth-note bass, syncopated stabs, a thin urgent lead;
  a descending E7 run resolves across the seam onto the loop's opening note.

The game loops the whole file (`LOOP_FORWARD`), so each track is rendered as
one seamless loop: every tail that rings past the end wraps back to beat
zero, and the loop gates measure the seam.

The music ships as Ogg Vorbis (`audiogen/ogg.py`), because 132 seconds of
44100 Hz PCM is 11.6 MB of package and of resident RAM on a phone and about
an eighth of that encoded. libsndfile stamps each Ogg stream with a random
serial number, so the serial is pinned and the page CRCs recomputed — this
repo's promise is bytes, not just samples. The effects stay PCM: all nine
together are 264 KB, where the codec's own overhead would be most of the
file.

## Usage

`make audio` from the repository root is the whole of it: it renders and
installs in one step, and `make generators-venv` is the one-off interpreter
setup it needs. The venv is deliberately kept **outside** the checkout
(`~/.cache/grid_commanders/venv-audio` by default, overridable as
`AUDIOGEN_PY=<python>`), because a git worktree shares no ignored files with
the main checkout and a per-worktree venv is a per-worktree reinstall.

To drive the script directly:

```sh
py=~/.cache/grid_commanders/venv-audio/bin/python

# render everything + the A/B boards into ./out
"$py" audio_generator.py

# audition: open out/soundboard.html (effects) and out/musicboard.html
# (music, both players loop) — the game's current take beside this run's,
# with the measurements

# install into a game checkout — the path is REQUIRED, never defaulted
"$py" audio_generator.py --install /path/to/grid_commanders
```

`--game`, which the boards read the current sounds from, defaults to the
repository this generator sits in.

`--install` requiring an explicit path is a scar, not an oversight: a
defaulted destination in the sprite pipeline once overwrote uncommitted work
in the game checkout. It removes a same-named file in a format this repo no
longer emits, because the game imports everything under `assets/` and a
leftover would ship beside its replacement.

## The gates

`make audio-test` from the repository root — the merge bar:

- **Contract** — the rosters are `Sfx.NAMES` and `Music.NAMES` verbatim;
  every duration fits its authored budget (a UI blip stays a blip, a music
  loop is 30–90 s).
- **Determinism** — every render is byte-stable.
- **Mix** — peaks sit at their authored per-sound level; UI under combat;
  music RMS clearly under every combat peak (a battle track never buries
  the shot it underscores); no clicks at the edges (first/last ~0.4 ms
  near-silent); no DC offset.
- **Loop** — the music seam is measured: end-to-start amplitude and slope
  stay inside the track's own motion, the texture holds across the seam,
  and the sequencer's tail-wrap invariant is pinned on a fixture. A click
  at the loop point is a build failure.
- **Distinctness** — pairwise spectral distance over log-band fingerprints:
  no two effects may sound like the same event (the silhouette-IoU gate
  with a Fourier transform). The two marches must also separate — spectrally
  and in measured tempo, each of which must land on its authored BPM.

The measurements live in `audiogen/measure.py`; the tests only assert over
them, so the tool and the suite cannot disagree about what "loud" means.

## Adoption

The game ships this pipeline's exact output: `make audio` installs the nine
effects into `assets/sfx/` and the two marches into `assets/music/`, and
those bytes are what is committed. The gates above hold consistency and
technical quality; whether an explosion feels right or a march is worth
humming stays a human verdict on the soundboard.
