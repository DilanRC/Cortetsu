#!/usr/bin/env python3
"""Gate contract for an isolated Ubuntu package update in Hyprland CI."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
workflow = (ROOT / ".github/workflows/hyprland-import-ci.yml").read_text(encoding="utf-8")

assert "ubuntu_sources=" in workflow
assert "-name 'ubuntu.sources'" in workflow
assert "Dir::Etc::sourcelist" in workflow
assert "Dir::Etc::sourceparts=-" in workflow
assert "sudo apt-get install -y --no-install-recommends lua5.4" in workflow
assert "sudo apt-get update &&" not in workflow

print("PASS: Hyprland CI isolates Ubuntu package indexes from third-party runner repos")
