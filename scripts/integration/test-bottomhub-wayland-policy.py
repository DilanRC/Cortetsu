#!/usr/bin/env python3
"""Per-monitor Bottom Hub identity with fullscreen and reversible GameMode."""
from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

sys.path.insert(0, str(Path(__file__).resolve().parent))
import launcher_harness as H  # noqa: E402

OPTIONS = (
    "animations:enabled", "decoration:blur:enabled", "decoration:shadow:enabled",
    "general:gaps_in", "general:gaps_out", "decoration:rounding", "general:allow_tearing",
)


def main() -> int:
    if not os.environ.get("WAYLAND_DISPLAY"):
        print("SKIP: requiere una sesión Wayland para anidar Hyprland")
        return 0
    if missing := H.missing_tools():
        print(f"SKIP: faltan {', '.join(missing)}")
        return 0
    binary = H.REPO / "dist/native/cortetsu-hardware-runtime"
    assert binary.is_file(), "construye primero scripts/build-native.sh"
    with tempfile.TemporaryDirectory(prefix="cz22-policy-") as temporary:
        session = H.Session(Path(temporary))
        try:
            session.start(outputs=3)
            session.start_client()
            session.focus_monitor(session.headless()[0])
            H.wait_for(lambda: (session.hjson("activewindow") or {}).get("class") == "cortetsu-probe",
                       "foco del cliente")
            dispatch = 'hl.dsp.window.fullscreen({ mode = "fullscreen" })'
            assert session.hyprctl("dispatch", dispatch).strip() == "ok"
            H.wait_for(lambda: (session.hjson("activewindow") or {}).get("fullscreen") == 2,
                       "cliente fullscreen")
            layers = session.hjson("layers")
            for monitor in session.headless()[:2]:
                namespaces = [layer.get("namespace") for level in layers[monitor]["levels"].values()
                              for layer in level]
                assert namespaces.count("cortetsu-bottom-hub") == 1, (monitor, namespaces)
            initial = {option: session.hyprctl("-j", "getoption", option) for option in OPTIONS}
            for action, state in (("enable", "ACTIVE"), ("disable", "INACTIVE")):
                result = subprocess.run([str(binary), "cortetsu-gamemode", action],
                                        env=session.env(), capture_output=True, text=True, timeout=15)
                assert result.returncode == 0, (action, result.stdout, result.stderr)
                assert json.loads(result.stdout)["state"] == state, result.stdout
            restored = {option: session.hyprctl("-j", "getoption", option) for option in OPTIONS}
            assert initial == restored, (initial, restored)
            assert session.hyprctl("dispatch", dispatch).strip() == "ok"
            H.wait_for(lambda: (session.hjson("activewindow") or {}).get("fullscreen") == 0,
                       "salida de fullscreen")
        finally:
            session.stop()
    print("PASS: fullscreen conserva namespaces por monitor; GameMode restaura siete opciones")
    return 0


if __name__ == "__main__":
    sys.exit(main())
