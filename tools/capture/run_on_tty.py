"""Run a command with a pty on all three descriptors, and return its status.

tools/test_godot_gui.sh needs a launch that looks interactive, and `make` gives
it pipes. `pty.spawn` would be the short spelling and is not usable: on macOS's
system python it never returns from a child that exited without printing, which
hangs the gate rather than failing it.

Usage: python3 tools/capture/run_on_tty.py <command> [args...]
"""

import os
import pty
import subprocess
import sys
import threading

TIMEOUT_SECONDS = 60


def main() -> int:
    master, slave = pty.openpty()
    child = subprocess.Popen(sys.argv[1:], stdin=slave, stdout=slave, stderr=slave)
    os.close(slave)

    def drain() -> None:
        try:
            while os.read(master, 1024):
                pass
        except OSError:
            pass

    threading.Thread(target=drain, daemon=True).start()
    try:
        return child.wait(TIMEOUT_SECONDS)
    except subprocess.TimeoutExpired:
        child.kill()
        return 124


if __name__ == "__main__":
    sys.exit(main())
