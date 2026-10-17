#!/usr/bin/env python3
from pathlib import Path

repo = Path(__file__).resolve().parents[2]
page = "\n".join(path.read_text(encoding="utf-8") for path in sorted((repo / "cortetsu/modules/keyboards").glob("*.[qj]*")))
helper = "\n".join((repo / "cortetsu/keyboards/src" / name).read_text(encoding="utf-8") for name in ("legacy.rs", "lua.rs", "store.rs"))

criteria = {
    "native app catalogue": "DesktopEntries.applications.values",
    "app metadata": "app.execString",
    "keyboard capture": "Keys.onPressed: event =>",
    "click-to-rebind": "onEditRequested: root.startCapture()",
    "duplicate rejection": "ya es «",
    "atomic writes": "fs::rename(&temp, path)",
    "snapshot before edit": "let saved = snapshot(paths)?;",
    "reload verification": "hypr::binds().ok_or(",
    "automatic rollback": "restore(paths, &saved);",
    "delete with confirmation": "function armDelete(): void",
    "delete and reset backend": '("reset", 2) => reset_binding',
    "desktop entry resolution": "DesktopEntries.heuristicLookup(match.executable)",
    "desktop id fallback": "idOf(app).endsWith(\".\" + query)",
    "real application icon": "row.appEntry.icon",
    "application metadata": "entry.app_id = Some(id);",
    "managed files stay read-only": "refuse_symlink(&paths.store)?;",
    "verified by description": ".is_some_and(|d| d.contains(description))",
    "balanced Lua parser": "pub fn binding_blocks(text: &str)",
}

joined = page + "\n" + helper
missing = [name for name, needle in criteria.items() if needle not in joined]
score = (len(criteria) - len(missing)) / len(criteria)
print(f"Keybind editor eval: {len(criteria) - len(missing)}/{len(criteria)} ({score:.0%})")
if missing:
    raise SystemExit("FAIL: " + ", ".join(missing))
