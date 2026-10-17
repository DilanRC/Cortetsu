#!/usr/bin/env python3
"""Every nested Hyprland a test starts keeps a suspended dGPU asleep.

See scripts/integration/nested_gpu.py for the two measured wake sources.
"""
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / "scripts/integration"))
from nested_gpu import compositor_env  # noqa: E402

with tempfile.TemporaryDirectory() as tmp:
    env = compositor_env({"PATH": os.environ["PATH"]}, Path(tmp))
    found = subprocess.run(["sh", "-c", "command -v lspci; lspci -vnn"], env=env, capture_output=True, text=True)
    assert found.stdout.strip() == str(Path(tmp) / "nested-gpu-bin/lspci"), found.stdout
    assert env["__EGL_VENDOR_LIBRARY_FILENAMES"].endswith("50_mesa.json") or not Path("/usr/share/glvnd").exists()

launches = []
for path in sorted((REPO / "scripts").rglob("*.py")):
    text = path.read_text(encoding="utf-8")
    for match in re.finditer(r'Popen\(\["Hyprland"\][^\n]*', text):
        launches.append(path.relative_to(REPO))
        assert "compositor_env(" in match.group(0), f"{path.relative_to(REPO)}: nested Hyprland without compositor_env"
assert len(launches) >= 5, launches
print(f"PASS: {len(launches)} nested Hyprland launches use the Mesa-only, lspci-free environment")
