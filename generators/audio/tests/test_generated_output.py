"""Contract tests for what the generator actually emits.

Everything here renders sounds and asserts properties of the resulting
samples — the sprite_generator discipline applied to audio: determinism,
the game's Sfx.NAMES contract, loudness bands, click-free edges, and
pairwise spectral distinctness (the silhouette-IoU gate with a Fourier
transform: no two effects may share a tonal fingerprint).

Run with `.venv/bin/python -m unittest discover tests`.
"""

from __future__ import annotations

import unittest

from audiogen import measure, sfx
from audiogen.dsp import seconds

# The game's autoload/sfx.gd Sfx.NAMES, verbatim.
CONTRACT = (
    "select",
    "move",
    "shot",
    "explosion",
    "capture",
    "fanfare",
    "flak",
    "rocket",
    "torpedo",
)

# Per-name duration budgets (seconds): a UI blip must stay a blip and a
# combat sound must not outstay the animation it voices.
BUDGET = {
    "select": (0.03, 0.15),
    "move": (0.06, 0.25),
    "shot": (0.05, 0.25),
    "explosion": (0.25, 0.9),
    "capture": (0.15, 0.5),
    "fanfare": (0.25, 0.7),
    "flak": (0.15, 0.6),
    "rocket": (0.2, 0.7),
    "torpedo": (0.25, 0.9),
}


class Contract(unittest.TestCase):
    def test_roster_is_the_games_sfx_names(self):
        self.assertEqual(tuple(sfx.SFX), CONTRACT)

    def test_durations_fit_their_budgets(self):
        for name in CONTRACT:
            lo, hi = BUDGET[name]
            t = seconds(len(sfx.render(name)))
            with self.subTest(sound=name):
                self.assertTrue(lo <= t <= hi, f"{t:.2f}s outside [{lo}, {hi}]")


class Determinism(unittest.TestCase):
    def test_every_render_is_byte_stable(self):
        for name in CONTRACT:
            with self.subTest(sound=name):
                a, b = sfx.render(name), sfx.render(name)
                self.assertTrue((a == b).all())


class Mix(unittest.TestCase):
    """Loudness is authored per category and held here, never re-argued."""

    def test_peaks_sit_at_their_authored_level(self):
        for name in CONTRACT:
            _b, _c, peak_db = sfx.SFX[name]
            with self.subTest(sound=name):
                self.assertAlmostEqual(
                    measure.peak_db(sfx.render(name)), peak_db, delta=0.2
                )

    def test_ui_sits_under_combat(self):
        # The quietest combat peak stays above the loudest UI peak: a menu
        # never barks louder than a battle.
        ui = [
            measure.peak_db(sfx.render(n)) for n in CONTRACT if sfx.SFX[n][1] == sfx.UI
        ]
        combat = [
            measure.peak_db(sfx.render(n))
            for n in CONTRACT
            if sfx.SFX[n][1] == sfx.COMBAT
        ]
        self.assertGreater(min(combat), max(ui))

    def test_no_clicks_no_dc(self):
        for name in CONTRACT:
            x = sfx.render(name)
            with self.subTest(sound=name):
                self.assertLess(measure.edge_peak(x), 0.05)
                self.assertLess(measure.dc_offset(x), 0.005)


class Distinctness(unittest.TestCase):
    """No two effects may wear the same tonal fingerprint."""

    THRESHOLD = 0.08

    def test_every_pair_separates(self):
        rendered = {name: sfx.render(name) for name in CONTRACT}
        for i, a in enumerate(CONTRACT):
            for b in CONTRACT[i + 1 :]:
                with self.subTest(pair=(a, b)):
                    self.assertGreater(
                        measure.spectral_distance(rendered[a], rendered[b]),
                        self.THRESHOLD,
                    )


if __name__ == "__main__":
    unittest.main()
