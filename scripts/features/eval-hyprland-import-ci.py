#!/usr/bin/env python3
"""Product eval for deterministic, third-party-independent Hyprland CI setup."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
workflow = (ROOT / ".github/workflows/hyprland-import-ci.yml").read_text(encoding="utf-8")

checks = {
    "official Ubuntu source is selected": "ubuntu.sources" in workflow,
    "source parts are disabled": "Dir::Etc::sourceparts=-" in workflow,
    "Lua install remains unchanged": "lua5.4" in workflow,
    "all importer checks remain wired": all(name in workflow for name in (
        "test-hyprland-import.py",
        "test-hyprland-self-contained.py",
        "test-zero-caelestia-gate.py",
        "test-shortcut-namespace.py",
    )),
    "unscoped update is absent": "apt-get update &&" not in workflow,
}

assert all(checks.values()), [name for name, passed in checks.items() if not passed]
print(f"Hyprland import CI eval: {sum(checks.values())}/{len(checks)}")
