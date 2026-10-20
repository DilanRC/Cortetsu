"""Read the canonical surface registry by evaluating it, not by pattern matching.

`cortetsu/modules/SurfaceRegistry.js` is a Qt `.pragma library`. Node runs the
same JavaScript once the pragma line is dropped, so the gates compare the QML
sources with the groups the shell actually computes.
"""
from __future__ import annotations

import functools
import json
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
REGISTRY = ROOT / "cortetsu/modules/SurfaceRegistry.js"
GROUPS = ("names", "retained", "transient", "exclusive", "competingWithWallpaper", "keyboardOwners", "ipcExclusive")


@functools.cache
def load() -> dict:
    source = REGISTRY.read_text(encoding="utf-8")
    assert source.startswith(".pragma library\n"), "SurfaceRegistry.js must stay a QML library"
    assert ".import" not in source, "SurfaceRegistry.js must not import anything (no init cycles)"
    program = source.removeprefix(".pragma library\n") + (
        "\nprocess.stdout.write(JSON.stringify({surfaces, "
        + ", ".join(GROUPS)
        + "}));\n"
    )
    result = subprocess.run(["node", "--input-type=commonjs", "-"], input=program, text=True,
                            capture_output=True, check=True, timeout=30)
    return json.loads(result.stdout)


def group(name: str) -> list[str]:
    return list(load()[name])


def declared_bools(qml: str, readonly: bool = False) -> list[str]:
    prefix = r"readonly\s+property\s+bool" if readonly else r"(?<!readonly )property\s+bool"
    return re.findall(rf"^\s*{prefix}\s+(\w+)\b", qml, flags=re.M)
