#!/usr/bin/env python3
"""Run existing black-box contracts against the native binary, never real hardware.

Python is only the test driver. The installed runtime and cargo tests need no
interpreter. Original tests stay unchanged; only their executable argv is
substituted in memory. References may live in the migration archive.
"""
from pathlib import Path
import os
import sys
import tempfile

REPO = Path(__file__).resolve().parents[3]
BINARY = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else REPO / "cortetsu/hardware-runtime-rs/target/debug/cortetsu-hardware-runtime"
if not BINARY.is_file():
    raise SystemExit(f"Build the native binary before running contracts: {BINARY}")

def run(relative: str, replacements: list[tuple[str, str]], truncate: str | None = None) -> None:
    path = REPO / relative
    if not path.is_file():
        path = REPO / "tests/reference/python-runtime" / relative
    source = path.read_text()
    for original, replacement in replacements:
        if original not in source:
            raise AssertionError(f"fixture argv changed in {relative}: {original}")
        source = source.replace(original, replacement)
    if truncate:
        if truncate not in source:
            raise AssertionError(f"fixture boundary changed: {relative}")
        source = source[:source.index(truncate)]
    context = {"__file__": str(REPO / relative), "__name__": "__main__", "NATIVE_BINARY": str(BINARY)}
    exec(compile(source, str(path), "exec"), context)
    print(f"PASS native contract: {relative}", flush=True)

with tempfile.TemporaryDirectory(prefix="cortetsu-native-contracts-") as directory:
    home = Path(directory)
    for folder in ("bin", "sys/class/drm", "run"):
        (home / folder).mkdir(parents=True, exist_ok=True)
    for name, contents in {
        "systemctl": "#!/bin/sh\nexit 3\n",
        "powerprofilesctl": "#!/bin/sh\ncase \"$1\" in get) echo balanced;; list) echo balanced:;; *) exit 3;; esac\n",
    }.items():
        path = home / "bin" / name
        path.write_text(contents)
        path.chmod(0o755)
    os.environ.update(HOME=str(home), XDG_CONFIG_HOME=str(home / ".config"),
                      XDG_STATE_HOME=str(home / ".local/state"), XDG_RUNTIME_DIR=str(home / "run"),
                      CORTETSU_SYSFS_ROOT=str(home / "sys"),
                      PATH=f"{home / 'bin'}:{os.environ['PATH']}")
    run("scripts/features/test-gamemode-helper.py", [
        ('["python3", str(HELPER),', '[NATIVE_BINARY, "cortetsu-gamemode",'),
    ])
    run("scripts/features/test-nvibrant.py", [
        ('[str(HELPER),', '[NATIVE_BINARY, "cortetsu-nvibrant",'),
    ], '    # The service the Settings page instantiates')
    run("cortetsu/tests/test-gpu-passive.py", [
        ('["python3", str(BIN / tool),', '[NATIVE_BINARY, tool,'),
    ])
    # The historical size assertion assumes a desktop with many processes.
    # Supply a deterministic procfs fixture instead of depending on the CI host.
    proc = home / "proc"
    proc.mkdir()
    (proc / "uptime").write_text("10000 5000\n")
    (proc / "meminfo").write_text("MemTotal: 8000000 kB\nMemAvailable: 4000000 kB\n")
    for pid in range(50000, 50128):
        folder = proc / str(pid)
        folder.mkdir()
        fields = ["1"] * 22
        fields[0] = "S"
        (folder / "stat").write_text(f"{pid} (fixture-{pid}) " + " ".join(fields))
        (folder / "comm").write_text(f"fixture-{pid}\n")
        (folder / "cmdline").write_text(f"fixture-{pid}\0--read-only\0")
    os.environ["CORTETSU_PROCFS_ROOT"] = str(proc)
    run("cortetsu/tests/test-hardware-probe.py", [
        ('["python3", str(PROBE),', '[NATIVE_BINARY, "cortetsu-hardware-probe",'),
    ])
