#!/usr/bin/env python3
"""Eval the screenshot path for structured process execution."""

from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
picker = (ROOT / "cortetsu/modules/areapicker/Picker.qml").read_text(encoding="utf-8")
helper = (ROOT / "cortetsu/bin/cortetsu-area-capture").read_text(encoding="utf-8")

checks = {
    "picker uses the owned capture helper": '"cortetsu-area-capture", geometry, path' in picker,
    "picker does not construct a shell command": '"sh", "-c"' not in picker,
    "helper validates geometry": "GEOMETRY = re.compile" in helper,
    "helper executes grim with argv": 'subprocess.run(["grim", "-g", args.geometry, str(args.path)])' in helper,
    "helper executes clipboard without a shell": 'subprocess.run(\n                ["wl-copy", "--type", "image/png"]' in helper,
    "helper executes preview with argv": 'subprocess.run(["swappy", "-f", str(args.path)])' in helper,
}

missing = [name for name, passed in checks.items() if not passed]
if missing:
    raise SystemExit("FAIL: screenshot eval missing " + ", ".join(missing))

print(f"Screenshot eval: {len(checks)}/{len(checks)} (100%)")
