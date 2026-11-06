#!/usr/bin/env python3
"""Run frozen historical contracts in a disposable baseline source snapshot.

This is developer tooling. Production installation, CLI and verification never
load it. Native differential suites compare this same baseline with Rust.
"""
from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
MANIFEST = ROOT / "tests/reference/python-runtime/MANIFEST.json"


def replace_once(path: Path, old: str, new: str) -> None:
    source = path.read_text()
    if source.count(old) != 1:
        raise SystemExit(f"Expected one historical marker in {path.relative_to(path.parents[2])}; found {source.count(old)}")
    path.write_text(source.replace(old, new, 1))


def adapt_nested_hyprland_tests(work: Path, tests: set[str]) -> None:
    """Adapt only the selected tests that need host-specific socket/key fixes."""
    path = work / "scripts/features/test-gamemode-runtime.py"
    if "scripts/features/test-gamemode-runtime.py" in tests and path.is_file():
        # Keep assertions unchanged while shortening the disposable runtime
        # directory for Linux sun_path (108 bytes).
        replace_once(path, 'TemporaryDirectory(prefix="cortetsu-gamemode-")',
                     'TemporaryDirectory(prefix="gm-")')

    if "scripts/integration/test-hp-keys.py" in tests:
        # In the HP layout Super+Shift+F23 resolves away from the F23 keysym.
        # Update only this test's chord and its disposable config; all other
        # historical dispatch/receiver pairs stay byte-for-byte unchanged.
        replace_once(work / "config/hypr-user.lua", '"SUPER + SHIFT + F23"',
                     '"SUPER + SHIFT + code:201"')
        replace_once(work / "scripts/integration/test-hp-keys.py", '"SUPER + SHIFT + F23"',
                     '"SUPER + SHIFT + code:201"')


def main() -> int:
    if len(sys.argv) < 2:
        raise SystemExit("usage: run-legacy-oracle.py --suite | RELATIVE_TEST...")
    revision = json.loads(MANIFEST.read_text())["source_commit"]
    if subprocess.run(["git", "-C", str(ROOT), "cat-file", "-e", revision],
                      stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode:
        raise SystemExit(f"Historical source {revision} is not in this clone; fetch that commit before running developer oracles.")
    with tempfile.TemporaryDirectory(prefix="cortetsu-historical-oracle-") as directory:
        archive = subprocess.Popen(["git", "-C", str(ROOT), "archive", revision], stdout=subprocess.PIPE)
        extracted = subprocess.run(["tar", "-x", "-C", directory], stdin=archive.stdout)
        archive.stdout.close()
        if archive.wait() or extracted.returncode:
            return 1
        work = Path(directory)
        tests = set(sys.argv[1:])
        if tests == {"--suite"}:
            tests = {"scripts/features/test-gamemode-runtime.py", "scripts/integration/test-hp-keys.py"}
        adapt_nested_hyprland_tests(work, tests)
        # Preserve repository queries made by tests without writing to the real
        # source tree or interpreting the archived runtime as current code.
        subprocess.run(["git", "init", "-q", directory], check=True)
        env = {**os.environ, "CORTETSU_HISTORICAL_ORACLE": revision}
        if sys.argv[1:] == ["--suite"]:
            print(f"HISTORICAL BASELINE: {revision} (current HP key contract)", flush=True)
            return subprocess.run(["bash", str(work / "scripts/cortetsu"), "test"], cwd=work, env=env).returncode
        for relative in sys.argv[1:]:
            path = Path(relative)
            if path.is_absolute() or ".." in path.parts or not relative.startswith((
                    "scripts/features/test-", "scripts/integration/test-", "cortetsu/tests/test-")):
                raise SystemExit("Only relative historical test paths are accepted")
            target = work / path
            if not target.is_file():
                raise SystemExit(f"Historical test is missing: {relative}")
            interpreter = sys.executable if target.suffix == ".py" else "bash"
            print(f"HISTORICAL ORACLE {relative} @ {revision}", flush=True)
            result = subprocess.run([interpreter, str(target)], cwd=work, env=env)
            if result.returncode:
                return result.returncode
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
