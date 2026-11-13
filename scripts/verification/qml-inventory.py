#!/usr/bin/env python3
"""Inventory every QML file of the shell: owner class, surface, services, tests.

Cortetsu 3.0 (phase 0) needs to know which files are first-party, which are
generated or compatibility, and which nothing references any more, before a
visual change touches them. The answer is computed from the tree, so it can be
regenerated and diffed instead of maintained by hand.

    qml-inventory.py            Markdown table on stdout
    qml-inventory.py --json     the same rows as JSON
    qml-inventory.py --check F  fail if F differs from the current tree
"""
import argparse
import json
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
ROOT = REPO / "cortetsu"
TEST_ROOTS = (ROOT / "tests", REPO / "scripts", REPO / "tests")
GENERATED = {"theme/CortetsuDesign.qml"}
# Instantiated by Quickshell or by path, never by type name.
ENTRYPOINTS = {"shell.qml"}
INTERACTION = (
    ("teclado", re.compile(r"activeFocusOnTab|Keys\.on|forceActiveFocus")),
    ("ratón", re.compile(r"MouseArea|TapHandler|HoverHandler|DragHandler|WheelHandler|onClicked|CortetsuStateLayer")),
)
STATES = (
    ("vacío/error", re.compile(r"CortetsuStateMessage")),
    ("deshabilitado", re.compile(r"\bdisabled\b|enabled:")),
    ("movimiento", re.compile(r"Behavior on|Animation\b|Anim \{|CAnim|CortetsuAnim")),
)


def qml_files() -> list[Path]:
    return sorted(path for path in ROOT.rglob("*.qml") if "target" not in path.parts)


def classify(relative: str) -> str:
    if relative in GENERATED:
        return "generated"
    if relative.startswith("base/"):
        return "compat/upstream"
    if "tests/" in relative or relative.endswith("Fixture.qml"):
        return "harness/test"
    return "owned-first-party"


def surface_of(relative: str) -> str:
    parts = relative.split("/")
    if parts[0] == "modules" and len(parts) > 2:
        return "/".join(parts[:3]) if parts[1] in ("bar", "settings") and len(parts) > 3 else "/".join(parts[:2])
    return parts[0] if len(parts) > 1 else "(raíz)"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--check", type=Path)
    args = parser.parse_args()

    files = qml_files()
    sources = {path: path.read_text(encoding="utf-8", errors="replace") for path in files}
    singletons = sorted({path.stem for path in files
                         if path.parent.name == "services" and "pragma Singleton" in sources[path]})
    tests = [(path, path.read_text(encoding="utf-8", errors="replace"))
             for root in TEST_ROOTS if root.exists()
             for path in root.rglob("*") if path.is_file() and path.suffix in (".qml", ".py", ".js", ".mjs", ".cjs", ".sh")]
    qmldirs = "\n".join(path.read_text() for path in ROOT.rglob("qmldir") if "target" not in path.parts)
    javascript = "\n".join(path.read_text(encoding="utf-8", errors="replace")
                           for path in ROOT.rglob("*.js") if "target" not in path.parts and "tests" not in path.parts)

    rows = []
    for path in files:
        relative = path.relative_to(ROOT).as_posix()
        text = sources[path]
        owner = classify(relative)
        name = re.compile(rf"\b{re.escape(path.stem)}\b")
        users = sum(1 for other, body in sources.items()
                    if other != path and classify(other.relative_to(ROOT).as_posix()) != "harness/test" and name.search(body))
        by_path = f"{path.name}\"" in javascript or f"{path.name}'" in javascript or any(
            f"{path.name}\"" in body for other, body in sources.items() if other != path)
        referenced = users > 0 or by_path or relative in ENTRYPOINTS or bool(name.search(qmldirs)) and "singleton" in qmldirs
        if owner == "owned-first-party" and not referenced:
            owner = "dead"
        rows.append({
            "file": relative,
            "owner": owner,
            "surface": surface_of(relative),
            "lines": text.count("\n") + 1,
            "users": users,
            "services": [service for service in singletons if service != path.stem and re.search(rf"\b{service}\.", text)],
            "interaction": [label for label, pattern in INTERACTION if pattern.search(text)],
            "states": [label for label, pattern in STATES if pattern.search(text)],
            "tests": sum(1 for _, body in tests if name.search(body)),
        })

    if args.json:
        output = json.dumps(rows, indent=1, ensure_ascii=False) + "\n"
    else:
        counts: dict[str, int] = {}
        for row in rows:
            counts[row["owner"]] = counts.get(row["owner"], 0) + 1
        lines = ["# Inventario de QML de Cortetsu", "",
                 "Generado por `scripts/verification/qml-inventory.py`; no se edita a mano.",
                 "`usos` cuenta los QML que no son pruebas y nombran el tipo; `pruebas`, los archivos de",
                 "prueba que lo nombran. `dead` es un QML propio que nada referencia.", "",
                 "| Clase | Archivos |", "| --- | --- |"]
        lines += [f"| {owner} | {count} |" for owner, count in sorted(counts.items())]
        lines += ["", "| Archivo | Clase | Superficie | Líneas | Usos | Servicios | Interacción | Estados | Pruebas |",
                  "| --- | --- | --- | --- | --- | --- | --- | --- | --- |"]
        for row in rows:
            lines.append("| `{file}` | {owner} | {surface} | {lines} | {users} | {services} | {interaction} | {states} | {tests} |".format(
                **{**row, "services": ", ".join(row["services"]) or "-",
                   "interaction": ", ".join(row["interaction"]) or "-",
                   "states": ", ".join(row["states"]) or "-"}))
        output = "\n".join(lines) + "\n"

    if args.check:
        if args.check.read_text(encoding="utf-8") != output:
            print(f"qml-inventory: {args.check} no coincide con el árbol; regenéralo", file=sys.stderr)
            return 1
        return 0
    sys.stdout.write(output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
