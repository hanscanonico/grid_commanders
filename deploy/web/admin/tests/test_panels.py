import tempfile
import unittest
from datetime import datetime, timezone
from pathlib import Path

from admin import panels
from admin.store import Store
from tests.test_store import a_hit

NOW = datetime(2026, 9, 14, 12, 0, tzinfo=timezone.utc)


class RegistryTests(unittest.TestCase):
    def test_traffic_is_registered(self):
        self.assertEqual(panels.listing(), [{"slug": "traffic", "name": "Traffic"}])

    def test_lookup_by_slug(self):
        self.assertIs(panels.by_slug("traffic"), panels.traffic)
        self.assertIsNone(panels.by_slug("nope"))

    def test_every_panel_has_the_three_names(self):
        for panel in panels.PANELS:
            with self.subTest(panel=panel.__name__):
                self.assertTrue(panel.name)
                self.assertTrue(panel.slug)
                self.assertTrue(callable(panel.query))

    def test_the_traffic_panel_answers_the_store(self):
        with tempfile.TemporaryDirectory() as folder:
            store = Store(str(Path(folder) / "admin.sqlite"))
            self.addCleanup(store.close)
            store.record(a_hit(), NOW)
            self.assertEqual(panels.traffic.query(store, "7d", NOW)["views"], 1)

    def test_the_traffic_panel_carries_the_duration_keys(self):
        with tempfile.TemporaryDirectory() as folder:
            store = Store(str(Path(folder) / "admin.sqlite"))
            self.addCleanup(store.close)
            answer = panels.traffic.query(store, "7d", NOW)
            for key in (
                "engaged_visitors",
                "engaged_seconds",
                "avg_seconds",
                "session_length",
                "time_on_path",
                "landing_uniques",
                "played_uniques",
            ):
                self.assertIn(key, answer)
            self.assertIn("engaged_seconds", answer["daily"][-1])


if __name__ == "__main__":
    unittest.main()
