#!/usr/bin/env python3
"""Regression: launcher scheme listing must expose the shipped catalog."""
import json
import subprocess
import tempfile
import os
from pathlib import Path

root = Path(__file__).resolve().parents[2]
palettes = json.loads((root / 'cortetsu/data/schemes/palettes.json').read_text())
with tempfile.TemporaryDirectory() as state:
    result = subprocess.run([str(root / 'cortetsu/bin/cortetsu-scheme'), 'list'], check=True, capture_output=True, text=True,
                            env={**os.environ, 'XDG_STATE_HOME': state})
listed = json.loads(result.stdout)
expected = {(key.split('/', 1)[0], key.split('/', 1)[1]) for key in palettes}
actual = {(name, flavour) for name, flavours in listed.items() for flavour in flavours}
assert actual == expected, f'scheme catalog mismatch: expected {len(expected)}, got {len(actual)}'
print(f'PASS: scheme catalog exposes all {len(expected)} shipped families/flavours')
