"""Contract tests for the two music loops.

The SFX discipline applied to composition: determinism, the game's
Music.NAMES contract, a seamless loop (the file's end must lead into its
start — the game plays LOOP_FORWARD over the whole file), music sitting
clearly under the combat SFX peaks, and the two marches staying distinct
in both spectrum and tempo.

Run with `.venv/bin/python -m unittest discover tests`.
"""

from __future__ import annotations

import unittest

import numpy as np

from audiogen import measure, music, sequencer, sfx
from audiogen.dsp import seconds

# The game's autoload/music.gd Music.NAMES, verbatim.
CONTRACT = ("parade", "advance")

# One render per track for every gate below; Determinism renders fresh and
# compares against these, which is the render-twice check itself.
RENDERED = {name: music.render(name) for name in CONTRACT}


class Contract(unittest.TestCase):
    def test_roster_is_the_games_music_names(self):
        self.assertEqual(tuple(music.MUSIC), CONTRACT)

    def test_each_loop_fits_the_duration_budget(self):
        # 30-90s per loop: long enough not to wear, short enough to load.
        for name in CONTRACT:
            t = seconds(len(RENDERED[name]))
            with self.subTest(track=name):
                self.assertTrue(30.0 <= t <= 90.0, f"{t:.2f}s outside [30, 90]")


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

    def test_the_texture_holds_across_the_seam(self):
        # No dropout out of the end, no thump into the start.
        for name in CONTRACT:
            with self.subTest(track=name):
                self.assertLess(measure.loop_rms_delta_db(RENDERED[name]), 6.0)


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


if __name__ == "__main__":
    unittest.main()
