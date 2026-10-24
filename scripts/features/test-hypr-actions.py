from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]
ACTION_MODULE = ROOT / "cortetsu/modules/CortetsuHyprActions.js"

leaks = []
for directory in (ROOT / "cortetsu/modules", ROOT / "cortetsu/base"):
    for suffix in ("*.qml", "*.js"):
        for path in sorted(directory.rglob(suffix)):
            if path == ACTION_MODULE:
                continue
            for line_number, line in enumerate(path.read_text().splitlines(), start=1):
                if re.search(r"\bhl\.dsp(?:\.|\b)", line):
                    leaks.append(f"{path.relative_to(ROOT)}:{line_number}")

assert not leaks, "Hyprland Lua dispatch literals escaped the action module: " + ", ".join(leaks)
assert ACTION_MODULE.is_file(), "typed Hyprland action module is missing"
module = ACTION_MODULE.read_text()
for action in (
    "luaString", "focusWorkspace", "toggleSpecialWorkspace", "focusWindow", "closeWindow",
    "toggleFloat", "togglePin", "killWindow", "moveWindow", "moveCursor", "dpms", "exit",
):
    assert re.search(rf"function\s+{action}\s*\(", module), action

build = (ROOT / "cortetsu/bin/build-runtime.sh").read_text()
cli = (ROOT / "scripts/cortetsu").read_text()
assert "modules/CortetsuHyprActions.js" in build
assert '"scripts/features/test-hypr-actions.py"' in cli
assert 'for directory in focus components hardware hypr keyboards settings surfaces calendar pomodoro bottomhub' in cli

print("PASS: all generated Hyprland Lua actions use CortetsuHyprActions.js")
