#!/usr/bin/env python3
"""Gate test for Task 8 (design system reduction, cortetsu/modules scope).

Audit result: cortetsu/modules/ already has zero references to the legacy
Colours./Tokens./StyledRect/StyledText/MaterialIcon vocabulary. Every module
already uses the first-party primitives (CortetsuSurface, CortetsuText,
CortetsuIcon) driven by CortetsuDesign.js. This test locks that in as a
regression gate: if a future change reintroduces a legacy token into an
owned module, this fails instead of silently regressing the design debt.

Legacy usage still exists in caelestia/patches/*.patch (diffs against the
upstream caelestia-shell tree) -- that is out of scope for Task 8, which
targets cortetsu/modules/ only, and is not audited here.
"""
from __future__ import annotations

import re
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
MODULES = REPO / "cortetsu/modules"
RUNTIME = REPO / "cortetsu"

LEGACY_TOKENS = ("Colours.", "Tokens.", "StyledRect", "StyledText", "MaterialIcon")

REQUIRED_FIRST_PARTY_PRIMITIVES = (
    "CortetsuSurface.qml",
    "CortetsuText.qml",
    "CortetsuIcon.qml",
    "CortetsuDesign.js",
    "../services/CortetsuTokens.qml",
)


def main() -> None:
    for name in REQUIRED_FIRST_PARTY_PRIMITIVES:
        path = MODULES / name if not name.startswith("../") else REPO / "cortetsu/modules" / name
        assert path.is_file(), f"missing first-party primitive: {name}"

    offenders: list[str] = []
    for path in MODULES.rglob("*.qml"):
        text = path.read_text(encoding="utf-8", errors="ignore")
        # CortetsuColours is the owned reactive palette bridge; only the
        # inherited bare Colours. namespace belongs to the retired vocabulary.
        text_for_audit = text.replace("CortetsuColours.", "")
        for token in LEGACY_TOKENS:
            if token in text_for_audit:
                offenders.append(f"{path.relative_to(REPO)}: {token}")

    assert not offenders, (
        "cortetsu/modules/ regressed to legacy design tokens: " + ", ".join(offenders)
    )

    runtime_offenders: list[str] = []
    for path in RUNTIME.rglob("*.qml"):
        text = path.read_text(encoding="utf-8", errors="ignore")
        for token in ("StyledRect", "StyledText", "MaterialIcon", "StateLayer"):
            if re.search(rf"\b{token}\b", text):
                runtime_offenders.append(f"{path.relative_to(REPO)}: {token}")
    assert not runtime_offenders, (
        "runtime reintroduced inherited design component names: "
        + ", ".join(runtime_offenders)
    )

    consumers = sum(
        1
        for path in MODULES.rglob("*.qml")
        if "CortetsuDesign" in path.read_text(encoding="utf-8", errors="ignore")
    )
    assert consumers > 0, "no module consumes CortetsuDesign.js -- design system not wired"

    print(
        f"PASS: cortetsu/modules/ has 0 legacy design tokens, "
        f"{consumers} files on CortetsuDesign.js first-party primitives"
    )


if __name__ == "__main__":
    main()
