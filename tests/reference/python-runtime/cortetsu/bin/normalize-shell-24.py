#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path


def insert_after_once(text: str, anchor: str, line: str) -> str:
    if line in text:
        return text
    count = text.count(anchor)
    if count != 1:
        raise SystemExit(f"ERROR: esperado un único anchor {anchor!r}, encontré {count}")
    return text.replace(anchor, anchor + line, 1)


def normalize(root: Path) -> bool:
    path = root / "shell.qml"
    if not path.is_file():
        raise SystemExit(f"ERROR: no existe {path}")

    before = path.read_text(encoding="utf-8")

    required = (
        "ShellRoot {",
        "    Background {}\n",
        "    Shortcuts {}\n",
    )
    missing = [marker for marker in required if marker not in before]
    if missing:
        raise SystemExit("ERROR: shell.qml no parece Caelestia 2.4 compatible; faltan: " + ", ".join(missing))

    if "    ConfigToasts {}" in before:
        raise SystemExit("ERROR: shell.qml contiene ConfigToasts legacy; no normalizo automáticamente")

    after = before
    if "    settings.watchFiles: true" in after:
        after = after.replace("    settings.watchFiles: true", "    settings.watchFiles: false", 1)
    elif "    settings.watchFiles: false" not in after:
        raise SystemExit("ERROR: no encontré settings.watchFiles en un estado reconocido")

    after = insert_after_once(after, "    Background {}\n", "    BottomHub {}\n")
    after = insert_after_once(after, "    Shortcuts {}\n", "    OverviewController {}\n")

    if after == before:
        return False

    path.write_text(after, encoding="utf-8")
    return True


def main() -> None:
    parser = argparse.ArgumentParser(description="Normaliza shell.qml para Cortetsu sobre Caelestia 2.4")
    parser.add_argument("root", type=Path)
    args = parser.parse_args()
    changed = normalize(args.root.resolve())
    print("NORMALIZED shell.qml" if changed else "ALREADY shell.qml")


if __name__ == "__main__":
    main()
