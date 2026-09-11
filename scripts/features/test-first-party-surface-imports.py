#!/usr/bin/env python3
"""Keep active Cortetsu surfaces on local module boundaries."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MODULES = ROOT / "cortetsu/modules"
sources = {path: path.read_text(encoding="utf-8") for path in MODULES.rglob("*.qml")}

assert sources, "the active Cortetsu module tree is empty"
for path, source in sources.items():
    assert "import qs." not in source, f"{path} reintroduced a compatibility import"
    assert "import Caelestia" not in source, f"{path} reintroduced legacy ownership"

print(f"PASS: {len(sources)} active Cortetsu QML files use local import boundaries")
