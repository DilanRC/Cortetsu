#!/usr/bin/env python3
from pathlib import Path

repo = Path(__file__).resolve().parents[2]
page = (repo / "cortetsu/modules/hardware/KeybindsPage.qml").read_text(encoding="utf-8")
helper = (repo / "cortetsu/bin/cortetsu-keybinds").read_text(encoding="utf-8")

criteria = {
    "native app catalogue": "DesktopEntries.applications.values",
    "app metadata": "selectedApp.execString",
    "keyboard capture": "Keys.onPressed: event =>",
    "click-to-rebind": "root.beginCapture",
    "duplicate rejection": "is already assigned to",
    "atomic writes": "os.replace(temp_name, path)",
    "snapshot before edit": "snapshot = backup()",
    "reload verification": '["hyprctl", "binds", "-j"]',
    "automatic rollback": "shutil.copy2(snapshot / OVERRIDES.name, OVERRIDES)",
    "delete with confirmation": "if (pendingDeleteId !== identifier)",
    "delete backend": 'sub.add_parser("delete")',
    "desktop entry resolution": "DesktopEntries.heuristicLookup(executable)",
    "desktop id fallback": "id.endsWith(`.${query}`)",
    "real application icon": "bindingRow.appEntry.icon",
    "application metadata": '"appId": app[1]',
    "balanced Lua parser": "def binding_blocks(text: str)",
}

joined = page + "\n" + helper
missing = [name for name, needle in criteria.items() if needle not in joined]
score = (len(criteria) - len(missing)) / len(criteria)
print(f"Keybind editor eval: {len(criteria) - len(missing)}/{len(criteria)} ({score:.0%})")
if missing:
    raise SystemExit("FAIL: " + ", ".join(missing))
