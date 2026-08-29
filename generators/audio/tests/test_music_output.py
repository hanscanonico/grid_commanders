"""Contract tests for the two music loops.

The SFX discipline applied to composition: determinism, the game's
Music.NAMES contract, a seamless loop (the file's end must lead into its
start — the game plays LOOP_FORWARD over the whole file), music sitting
clearly under the combat SFX peaks, every authored voice being heard in
the mix it plays in, and the two marches staying distinct in both spectrum
and tempo.

Run with `make audio-test` from the repository root.
"""

from __future__ import annotations

import dataclasses
import io
import unittest
from pathlib import Path

import numpy as np
import soundfile as sf

from audiogen import measure, music, sequencer, sfx
from audiogen.dsp import RATE, seconds
from audiogen.ogg import ogg_bytes, vendor_string

# The checkout this generator sits in, for the audio the game actually ships.
GAME_ROOT = Path(__file__).resolve().parents[3]

# The game's autoload/music.gd Music.NAMES, verbatim.
CONTRACT = ("parade", "advance")

# One render per track for every gate below; Determinism renders fresh and
# compares against these, which is the render-twice check itself.
RENDERED = {name: music.render(name) for name in CONTRACT}

# One encode and one decode per track: the shipped bytes, and the samples the
# game actually loops. Encoding is the suite's most expensive step, so the
# gates below read these rather than re-encoding per assertion.
ENCODED = {name: ogg_bytes(RENDERED[name]) for name in CONTRACT}
DECODED = {
    name: sf.read(io.BytesIO(ENCODED[name]), dtype="float64")[0] for name in CONTRACT
}


class Contract(unittest.TestCase):
    def test_roster_is_the_games_music_names(self):
        self.assertEqual(tuple(music.MUSIC), CONTRACT)

    def test_each_loop_fits_the_duration_budget(self):
        # 30-90s per loop: long enough not to wear, short enough to load.
        for name in CONTRACT:
            t = seconds(len(RENDERED[name]))
            with self.subTest(track=name):
                self.assertTrue(30.0 <= t <= 90.0, f"{t:.2f}s outside [30, 90]")

    def test_each_loop_runs_exactly_the_score(self):
        # The file is the loop, so its length must be the score's to the
        # sample: a render that padded or trimmed the tail would move the
        # seam every loop gate below measures.
        for name in CONTRACT:
            builder, _peak = music.MUSIC[name]
            song = builder()
            authored = song.beats * 60.0 / song.bpm
            with self.subTest(track=name):
                self.assertAlmostEqual(
                    seconds(len(RENDERED[name])), authored, delta=seconds(1)
                )


class Determinism(unittest.TestCase):
    def test_every_render_is_byte_stable(self):
        for name in CONTRACT:
            with self.subTest(track=name):
                self.assertTrue((music.render(name) == RENDERED[name]).all())


class Loop(unittest.TestCase):
    """The seam gates: a click at the loop point is a build failure."""

    def test_tails_wrap_from_the_end_to_the_start(self):
        # The sequencer invariant the songs rely on, held on a fixture:
        # whatever rings past the last sample continues at sample zero.
        out = np.zeros(100)
        x = np.arange(1.0, 31.0)
        sequencer.add_wrapped(out, x, 85)
        self.assertTrue((out[85:] == x[:15]).all())
        self.assertTrue((out[:15] == x[15:]).all())
        self.assertEqual(float(np.sum(out != 0.0)), 30.0)

    def test_seam_amplitude_and_slope_stay_inside_the_texture(self):
        # The end-to-start step and kink must hide inside the track's own
        # sample-to-sample motion — a seam louder than the music clicks.
        for name in CONTRACT:
            x = RENDERED[name]
            typical = measure.typical_step(x)
            with self.subTest(track=name):
                self.assertLess(measure.loop_step(x), typical)
                self.assertLess(measure.loop_slope(x), 2.0 * typical)

    def test_the_decoded_seam_stays_inside_the_texture(self):
        # The same seam on the samples the game loops: the encoder rounds
        # the last and first samples, and the seam must survive that too.
        for name in CONTRACT:
            x = DECODED[name]
            typical = measure.typical_step(x)
            with self.subTest(track=name):
                self.assertLess(measure.loop_step(x), typical)
                self.assertLess(measure.loop_slope(x), 2.0 * typical)

    def test_the_texture_holds_across_the_seam(self):
        # No dropout out of the end, no thump into the start — read over a
        # beat, and again over the 20 ms a gasp used to hide in.
        for name in CONTRACT:
            for source, x in (("render", RENDERED[name]), ("ogg", DECODED[name])):
                with self.subTest(track=name, source=source):
                    self.assertLess(measure.loop_rms_delta_db(x), 6.0)
                    self.assertLess(measure.loop_rms_delta_db(x, 0.020), 4.0)

    def test_the_band_is_still_playing_at_the_last_sample(self):
        # Two windows either side of the seam both pass over a hole between
        # them, and the hole is what the loop audibly gasped on: every
        # instrument used to shorten its slot and nothing was authored past
        # the last bar, so the file decayed out before its final sample.
        for name in CONTRACT:
            for source, x in (("render", RENDERED[name]), ("ogg", DECODED[name])):
                with self.subTest(track=name, source=source):
                    self.assertGreater(measure.quietest_window_db(x), -30.0)


class Mix(unittest.TestCase):
    """Loudness is authored and held here, never re-argued."""

    # Music must sit clearly under every combat effect: a battle track may
    # never bury the shot it underscores.
    MARGIN_DB = 6.0

    def test_peaks_sit_at_their_authored_level(self):
        for name in CONTRACT:
            _builder, peak_db = music.MUSIC[name]
            with self.subTest(track=name):
                self.assertAlmostEqual(
                    measure.peak_db(RENDERED[name]), peak_db, delta=0.2
                )

    def test_music_rms_sits_under_the_combat_peaks(self):
        quietest_combat = min(
            peak for _b, category, peak in sfx.SFX.values() if category == sfx.COMBAT
        )
        for name in CONTRACT:
            with self.subTest(track=name):
                self.assertLessEqual(
                    measure.rms_db(RENDERED[name]), quietest_combat - self.MARGIN_DB
                )

    def test_no_dc(self):
        for name in CONTRACT:
            with self.subTest(track=name):
                self.assertLess(measure.dc_offset(RENDERED[name]), 0.005)


class Distinctness(unittest.TestCase):
    """The menu and the battle may not wear the same march."""

    SPECTRAL_THRESHOLD = 0.05  # measured 0.099 between the two as authored
    TEMPO_TOLERANCE_BPM = 3.0

    def test_the_two_tracks_separate_spectrally(self):
        self.assertGreater(
            measure.spectral_distance(RENDERED["parade"], RENDERED["advance"]),
            self.SPECTRAL_THRESHOLD,
        )

    def test_each_track_pulses_at_its_authored_tempo(self):
        for name in CONTRACT:
            builder, _peak = music.MUSIC[name]
            with self.subTest(track=name):
                self.assertAlmostEqual(
                    measure.tempo_bpm(RENDERED[name]),
                    builder().bpm,
                    delta=self.TEMPO_TOLERANCE_BPM,
                )

    def test_the_two_tempos_are_far_apart(self):
        a = measure.tempo_bpm(RENDERED["parade"])
        b = measure.tempo_bpm(RENDERED["advance"])
        self.assertGreater(abs(a - b) / min(a, b), 0.15)


class Arrangement(unittest.TestCase):
    """Every authored voice is in the band, and heard once it is there."""

    # The band each march plays with: (instrument, gain), in score order.
    ROSTER = {
        "parade": (
            ("brass_lead", 0.34),
            ("stab", 0.12),
            ("tuba_bass", 0.30),
            ("pad", 0.15),
            ("kick", 0.50),
            ("snare", 0.34),
            ("hat", 0.32),
            ("roll", 0.60),
        ),
        "advance": (
            ("edge_lead", 0.32),
            ("stab", 0.11),
            ("drive_bass", 0.26),
            ("kick", 0.50),
            ("snare", 0.34),
            ("hat", 0.30),
            ("roll", 1.30),
        ),
    }

    # Measured level each voice carries in its mix, dB relative to the whole.
    # A pad at gain 0.15 can never read like a kick at 0.50, so the bar is
    # per voice; the slack is uniform because it is the same claim each time.
    CONTRIBUTION_DB = {
        "parade": {
            "brass_lead": -0.9,
            "stab": -17.8,
            "tuba_bass": -8.4,
            "pad": -19.2,
            "kick": -10.8,
            "snare": -21.5,
            "hat": -27.8,
            "roll": -21.2,
        },
        "advance": {
            "edge_lead": -2.4,
            "stab": -17.6,
            "drive_bass": -6.4,
            "kick": -9.0,
            "snare": -19.0,
            "hat": -28.6,
            "roll": -12.2,
        },
    }

    # 6 dB is half the amplitude: a voice turned down to half its authored
    # weight sits exactly on the bar, and anything quieter is a mix bug.
    SLACK_DB = 6.0

    def test_the_roster_of_voices_is_the_authored_one(self):
        for name in CONTRACT:
            builder, _peak = music.MUSIC[name]
            with self.subTest(track=name):
                self.assertEqual(
                    tuple((t.instrument, t.gain) for t in builder().tracks),
                    self.ROSTER[name],
                )

    def test_every_voice_is_audible_in_the_mix(self):
        for name in CONTRACT:
            builder, peak_db = music.MUSIC[name]
            song = builder()
            for voice in song.tracks:
                rest = tuple(t for t in song.tracks if t is not voice)
                without = sequencer.render(
                    dataclasses.replace(song, tracks=rest), peak_db
                )
                carried = measure.voice_contribution_db(RENDERED[name], without)
                floor = self.CONTRIBUTION_DB[name][voice.instrument] - self.SLACK_DB
                with self.subTest(track=name, voice=voice.instrument):
                    self.assertGreater(carried, floor)


class OggEncoding(unittest.TestCase):
    """The shipped format: mono Ogg Vorbis, pinned so a re-render is stable."""

    def test_the_encode_is_byte_identical_across_runs(self):
        for name in CONTRACT:
            self.assertEqual(
                ogg_bytes(RENDERED[name]),
                ogg_bytes(RENDERED[name]),
                f"{name} should encode to the same bytes twice",
            )

    def test_the_encode_keeps_every_sample_frame(self):
        # The loop is the whole file, so a codec that padded or trimmed the
        # stream would move the seam the gates above measure.
        for name in CONTRACT:
            decoded, rate = sf.read(io.BytesIO(ENCODED[name]), dtype="float64")
            self.assertEqual(rate, RATE)
            self.assertEqual(len(decoded), len(RENDERED[name]), name)

    def test_the_encode_is_far_smaller_than_the_pcm_it_replaces(self):
        for name in CONTRACT:
            pcm = 2 * len(RENDERED[name])
            self.assertLess(len(ENCODED[name]), pcm / 5, name)

    def test_the_decoded_track_measures_like_the_source(self):
        for name in CONTRACT:
            decoded, source = DECODED[name], RENDERED[name]
            self.assertAlmostEqual(
                measure.peak_db(decoded), measure.peak_db(source), delta=0.5, msg=name
            )
            self.assertAlmostEqual(
                measure.rms_db(decoded), measure.rms_db(source), delta=0.5, msg=name
            )
            self.assertAlmostEqual(
                measure.loop_rms_delta_db(decoded),
                measure.loop_rms_delta_db(source),
                delta=0.5,
                msg=name,
            )

    def test_the_encoder_matches_the_one_that_made_the_committed_ogg(self):
        # Every gate above holds over samples; the repository ships bytes. A
        # different libVorbis encodes the same march into different bytes, so
        # the snapshot gate can only byte-compare while the encoders agree.
        installed = GAME_ROOT / "assets/music/parade.ogg"
        self.assertEqual(
            vendor_string(ogg_bytes(RENDERED["parade"])),
            vendor_string(installed.read_bytes()),
            "this soundfile encodes a different Vorbis than the committed "
            "music: regenerate with `make audio`, or install the soundfile "
            "requirements.txt pins",
        )


if __name__ == "__main__":
    unittest.main()
