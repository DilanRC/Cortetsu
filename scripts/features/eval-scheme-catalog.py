#!/usr/bin/env python3
import json
import subprocess
import tempfile
import os
from pathlib import Path

root = Path(__file__).resolve().parents[2]
expected = json.loads((root / 'cortetsu/data/schemes/palettes.json').read_text())
with tempfile.TemporaryDirectory() as state:
    actual = json.loads(subprocess.check_output([str(root / 'cortetsu/bin/cortetsu-scheme'), 'list'], text=True,
                                                env={**os.environ, 'XDG_STATE_HOME': state}))
assert sum(len(v) for v in actual.values()) == len(expected)
print(f'Scheme catalog eval: {len(expected)}/{len(expected)} (100%)')
