import os
import shutil
import subprocess
import unittest
from pathlib import Path

SCENARIOS = Path(__file__).with_name("page_script.js")


# A missing node skips on a laptop, but must not quietly skip in CI, where this is
# the only thing that runs the page's script.
@unittest.skipUnless(
    shutil.which("node") or os.environ.get("CI"), "node is not installed"
)
class PageScriptTests(unittest.TestCase):
    def test_only_the_latest_load_draws(self):
        result = subprocess.run(
            ["node", str(SCENARIOS)],
            capture_output=True,
            text=True,
            timeout=30,
        )
        self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == "__main__":
    unittest.main()
