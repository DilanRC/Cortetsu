#!/usr/bin/env python3
"""Write docs/IPC.md from the IpcHandler blocks of the shell's QML.

Text generator, not a check: it reads the source and lists every IPC target
with its functions, so the reference cannot drift from the code. Usage:
    scripts/verification/ipc-inventory.py [--check]
--check exits 1 when docs/IPC.md differs from what the code produces.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SHELL = ROOT / "cortetsu"
OUT = ROOT / "docs" / "IPC.md"
SKIP = ("tests/", "Fixture.qml")


def handlers(text):
    """Yield (target, [signature, ...], enabled_expr) for each IpcHandler."""
    for match in re.finditer(r"\bIpcHandler\s*\{", text):
        depth, i = 1, match.end()
        while depth and i < len(text):
            depth += {"{": 1, "}": -1}.get(text[i], 0)
            i += 1
        body = text[match.end():i - 1]
        target = re.search(r'^\s*target:\s*(?:"([^"]+)"|root\.ipcTarget)\s*$', body, re.M)
        if not target:
            continue
        enabled = re.search(r"^\s*enabled:\s*(.+)$", body, re.M)
        sigs = [f"{m.group(1)}({m.group(2).strip()}){(': ' + m.group(3)) if m.group(3) else ''}"
                for m in re.finditer(r"^\s*function\s+(\w+)\s*\(([^)]*)\)\s*(?::\s*([\w<>]+))?", body, re.M)]
        # None: the target is the component's `ipcTarget`, set by each user.
        yield target.group(1), sigs, enabled.group(1).strip() if enabled else ""


def render():
    rows = {}
    dynamic = {}
    files = [p for p in sorted(SHELL.rglob("*.qml")) if not any(s in p.relative_to(ROOT).as_posix() for s in SKIP)]
    for path in files:
        rel = path.relative_to(ROOT).as_posix()
        for target, sigs, enabled in handlers(path.read_text(encoding="utf-8")):
            if target is None:
                dynamic[path.stem] = (rel, sigs, enabled)
            else:
                rows.setdefault(target, []).append((f"`{rel}`", sigs, enabled))
    # A file whose root object is such a component names the target.
    for path in files:
        text = path.read_text(encoding="utf-8")
        root = re.search(r"^(\w+)\s*\{", text, re.M)
        name = re.search(r'^\s{4}ipcTarget:\s*"([^"]+)"', text, re.M)
        if root and name and root.group(1) in dynamic:
            base, sigs, enabled = dynamic[root.group(1)]
            rel = f"`{path.relative_to(ROOT).as_posix()}` (vía `{base}`)"
            rows.setdefault(name.group(1), []).append((rel, sigs, enabled))
    lines = [
        "# IPC del shell",
        "",
        "Generado por `scripts/verification/ipc-inventory.py` a partir de los",
        "`IpcHandler` del QML. No editar a mano: regenerar tras cambiar un destino.",
        "",
        "Uso: `cortetsu shell ipc <destino> <función> [argumentos]`. Una función",
        "llamada `show` exige `call --` (ver la memoria del proyecto). `qs ipc call`",
        "sale con 0 aunque el destino no exista: comprobar la salida.",
        "",
        f"Destinos: {len(rows)}. Un destino definido en varios archivos aparece una",
        "vez por archivo; si dos están activos a la vez, la llamada llega a uno solo.",
        "",
    ]
    for target in sorted(rows, key=str.lower):
        lines.append(f"## `{target}`")
        lines.append("")
        for rel, sigs, enabled in rows[target]:
            lines.append(f"- {rel}" + (f" (activo si `{enabled}`)" if enabled else ""))
            for sig in sigs:
                lines.append(f"  - `{sig}`")
        lines.append("")
    return "\n".join(lines).rstrip() + "\n"


def main():
    text = render()
    if "--check" in sys.argv:
        return 0 if OUT.exists() and OUT.read_text(encoding="utf-8") == text else 1
    OUT.write_text(text, encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main())
