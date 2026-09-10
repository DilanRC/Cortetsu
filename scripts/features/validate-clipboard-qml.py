#!/usr/bin/env python3
from pathlib import Path
import sys

repo = Path(__file__).resolve().parents[2]
qml_dir = repo / "cortetsu/modules/clipboard"
content = qml_dir / "Content.qml"

errors = []
legacy = ("Caelestia", "qs.components", "qs.services", "Colours.", "Tokens.", "StyledRect", "StyledText", "MaterialIcon")
for path in sorted(qml_dir.glob("*.qml")):
    text = path.read_text(encoding="utf-8")
    for symbol in legacy:
        if symbol in text:
            errors.append(f"{path.relative_to(repo)}: dependencia legacy {symbol}")

content_source = content.read_text(encoding="utf-8")
if "const outsidePanel =" not in content_source:
    errors.append(f"{content.relative_to(repo)}: el dismiss no distingue clic interno de externo")
if 'if (outsidePanel)' not in content_source:
    errors.append(f"{content.relative_to(repo)}: el panel no conserva los clics internos")

if errors:
    print("VALIDATION FAILED")
    for error in errors:
        print(f"  - {error}")
    sys.exit(1)

print("Clipboard QML static validation: OK")
