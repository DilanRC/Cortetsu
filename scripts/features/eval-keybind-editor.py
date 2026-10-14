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
    "duplicate rejection": "ya es «",
    "atomic writes": "os.replace(temp_name, path)",
    "snapshot before edit": "saved = snapshot()",
    "reload verification": '[HYPRCTL, "binds", "-j"]',
    "automatic rollback": "restore(saved)",
    "delete with confirmation": "if (pendingDeleteId !== identifier)",
    "delete and reset backend": 'for verb in ("delete", "reset")',
    "desktop entry resolution": "DesktopEntries.heuristicLookup(executable)",
    "desktop id fallback": "id.endsWith(`.${query}`)",
    "real application icon": "bindingRow.appEntry.icon",
    "application metadata": '"appId": app[1]',
    "managed files stay read-only": "refuse_symlink(STORE)",
    "verified by description": 'description not in bound.get(chord_parts(chord), [])',
    "balanced Lua parser": "def binding_blocks(text: str)",
}

joined = page + "\n" + helper
missing = [name for name, needle in criteria.items() if needle not in joined]
score = (len(criteria) - len(missing)) / len(criteria)
print(f"Keybind editor eval: {len(criteria) - len(missing)}/{len(criteria)} ({score:.0%})")
if missing:
    raise SystemExit("FAIL: " + ", ".join(missing))
