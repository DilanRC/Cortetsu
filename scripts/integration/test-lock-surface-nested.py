#!/usr/bin/env python3
"""The real lock surface inside a nested Hyprland: it loads, it locks, it draws.

LockCard is covered without a compositor; LockSurface is not, and a surface
that fails to load under a session lock leaves a locked screen with nothing on
it. This locks only the throwaway nested compositor, never submits a password
(PAM is not exercised, so faillock is not touched) and ends by stopping the
nested session.

    python3 scripts/integration/ws2_run.py --workspace 3 LOG -- \\
        python3 scripts/integration/test-lock-surface-nested.py [--shots DIR]
"""
from __future__ import annotations

import argparse
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time

sys.path.insert(0, str(Path(__file__).resolve().parent))
import launcher_harness as H  # noqa: E402

FAILURES = ("TypeError", "ReferenceError", "Binding loop", "Unable to assign", "is not a type",
            "Required property", "Failed to load", "Type LockSurface unavailable")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--shots", type=Path)
    args = parser.parse_args()
    if not os.environ.get("WAYLAND_DISPLAY"):
        print("SKIP: requiere una sesión Wayland para anidar Hyprland")
        return 0
    if missing := H.missing_tools():
        print(f"SKIP: faltan {', '.join(missing)}")
        return 0
    with tempfile.TemporaryDirectory(prefix="cz30-lock-") as temporary:
        session = H.Session(Path(temporary))
        try:
            session.start(outputs=2)
            name = session.headless()[0]
            assert session.ipc("lock", "isLocked").stdout.strip() == "false"
            session.ipc("lock", "lock")
            H.wait_for(lambda: session.ipc("lock", "isLocked").stdout.strip() == "true", "sesión anidada bloqueada")
            # Hyprland reports the session lock once every output has a surface.
            H.wait_for(lambda: (session.hjson("locked") or {}).get("locked") is True, "bloqueo confirmado por el compositor")
            time.sleep(1.5)
            # Characters reach the buffer and nothing is submitted.
            for key in (30, 31, 32):  # KEY_A, KEY_S, KEY_D
                session.tap(key)
            time.sleep(0.6)
            if args.shots and shutil.which("grim"):
                args.shots.mkdir(parents=True, exist_ok=True)
                subprocess.run(["grim", "-o", name, str(args.shots / "lock-nested.png")],
                               env=session.env(), check=False, timeout=20)
            assert session.ipc("lock", "isLocked").stdout.strip() == "true", "escribir no libera el bloqueo"
            log = (session.logs / "qs.log").read_text(errors="replace")
            bad = [line for line in log.splitlines() if any(marker in line for marker in FAILURES)]
            assert not bad, "\n".join(bad[:12])
        finally:
            session.stop()
    print("PASS: la superficie de bloqueo real carga, bloquea las dos salidas y sigue bloqueada al escribir")
    return 0


if __name__ == "__main__":
    sys.exit(main())
