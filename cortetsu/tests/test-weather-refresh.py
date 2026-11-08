#!/usr/bin/env python3
"""Exercise the real Weather singleton with an isolated, deterministic Requests mock."""
from __future__ import annotations

import json
from pathlib import Path
import shutil
import select
import subprocess
import tempfile
import time

REPO = Path(__file__).resolve().parents[2]
FIXTURE = REPO / "cortetsu/tests/qml/services/fixture_WeatherRefresh.qml"
MOCK_REQUESTS = REPO / "cortetsu/tests/qml/services/mock_Requests.qml"
RUNTIME_FILES = (
    "services/Weather.qml",
    "modules/CortetsuConfig.qml",
    "modules/ThemePreferences.js",
    "theme/ThemeProfiles.js",
    "modules/CortetsuRegional.qml",
    "modules/CortetsuRegional.js",
)
EXPECTED = "WEATHER_REFRESH_PASS"
FAILED = "WEATHER_REFRESH_FAIL"


def run_fixture(home: Path) -> str:
    runtime = home / "runtime"
    for relative in RUNTIME_FILES:
        target = runtime / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(REPO / "cortetsu" / relative, target)

    shutil.copyfile(MOCK_REQUESTS, runtime / "services/Requests.qml")
    shutil.copyfile(FIXTURE, runtime / "shell.qml")

    first_location = "12.5,-70.25"
    second_location = "12.6,-70.3"
    preferences = home / "config/cortetsu/preferences.json"
    preferences.write_text(json.dumps({"schema": 1, "weatherLocation": first_location}), encoding="utf-8")
    cities = home / "cache/cortetsu/cities.json"
    cities.write_text(json.dumps({first_location: "Test City", second_location: "Next City"}), encoding="utf-8")

    env = {
        "PATH": "/usr/bin:/bin",
        "HOME": str(home),
        "XDG_CONFIG_HOME": str(home / "config"),
        "XDG_CACHE_HOME": str(home / "cache"),
        "XDG_RUNTIME_DIR": str(home / "run"),
        "QT_QPA_PLATFORM": "offscreen",
        "DBUS_SESSION_BUS_ADDRESS": "unix:path=/nonexistent",
        "LANG": "C.UTF-8",
    }
    process = subprocess.Popen(
        ["qs", "-p", str(runtime), "--no-color"],
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
    )
    output: list[str] = []
    deadline = time.monotonic() + 15
    try:
        assert process.stdout is not None
        while time.monotonic() < deadline:
            if process.poll() is not None:
                output.extend(process.stdout.readlines())
                break
            ready, _, _ = select.select([process.stdout], [], [], 0.1)
            if not ready:
                continue
            line = process.stdout.readline()
            if not line:
                continue
            output.append(line)
            if EXPECTED in line or FAILED in line:
                break
    finally:
        if process.poll() is None:
            process.terminate()
        try:
            remaining, _ = process.communicate(timeout=2)
        except subprocess.TimeoutExpired:
            process.kill()
            remaining, _ = process.communicate()
        output.append(remaining)

    result = "".join(output)
    print(result, end="")
    if EXPECTED not in result:
        raise AssertionError("Weather fixture did not pass" if FAILED not in result else "Weather fixture failed")
    warnings = [line for line in result.splitlines() if " WARN" in line or "ERROR" in line]
    if warnings:
        raise AssertionError(f"unexpected Quickshell warnings: {warnings}")
    return result


def main() -> int:
    if not shutil.which("qs"):
        raise RuntimeError("qs is required; no system packages were installed")
    with tempfile.TemporaryDirectory(prefix="cortetsu-weather-") as temporary:
        home = Path(temporary)
        for directory in (home / "config/cortetsu", home / "cache/cortetsu", home / "run"):
            directory.mkdir(parents=True, exist_ok=True)
        (home / "run").chmod(0o700)
        run_fixture(home)
    print("PASS: Weather refreshes the same location once per reload and rejects stale responses")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
