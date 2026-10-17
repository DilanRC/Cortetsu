"""The keybind helper the tests run: the Rust `cortetsu-keybinds`.

CORTETSU_KEYBINDS_HELPER overrides it with a command line. Otherwise the
release binary is rebuilt incrementally first, so a test does not run a stale
build; without cargo on PATH the existing binary is used as it is.
"""
from __future__ import annotations

import os
import shlex
import shutil
import subprocess
from pathlib import Path

CRATE = Path(__file__).resolve().parents[2] / "cortetsu/keyboards"
BINARY = CRATE / "target/release/cortetsu-keybinds"


def command() -> list[str]:
    override = os.environ.get("CORTETSU_KEYBINDS_HELPER")
    if override:
        return shlex.split(override)
    if shutil.which("cargo"):
        subprocess.run(["cargo", "build", "--release", "--locked", "--quiet", "--manifest-path",
                        str(CRATE / "Cargo.toml")], check=True)
    if not BINARY.is_file():
        raise SystemExit(f"FAIL: falta {BINARY}; compílalo con cargo build --release --locked")
    return [str(BINARY)]
