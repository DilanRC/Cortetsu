#!/usr/bin/env python3
"""Write scripts/features/INDEX.md: which feature checks a suite runs.

Text generator, not a check. A file under scripts/features is "running"
when a runner names it (scripts/cortetsu, scripts/verification/*,
cortetsu/tests/*.sh). The rest are archived contracts of earlier
migrations: the historical oracle runs its own copies from the baseline
commit (scripts/verification/run-legacy-oracle.py), never these.
    scripts/verification/feature-contracts-index.py [--check]
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
FEATURES = ROOT / "scripts/features"
OUT = FEATURES / "INDEX.md"
RUNNERS = [ROOT / "scripts/cortetsu", *sorted((ROOT / "scripts/verification").glob("*")),
           *sorted((ROOT / "cortetsu/tests").glob("*.sh"))]


def render() -> str:
    text = "\n".join(p.read_text(errors="replace") for p in RUNNERS if p.is_file() and p.name != "feature-contracts-index.py")
    checks = sorted(p.name for p in FEATURES.iterdir()
                    if p.is_file() and p.name.startswith(("test-", "eval-")) and p.suffix in (".py", ".sh", ".mjs", ".cjs", ".js"))
    running = [name for name in checks if name in text]
    archived = [name for name in checks if name not in text]
    lines = [
        "# Comprobaciones de funciones",
        "",
        "Generado por `scripts/verification/feature-contracts-index.py`; no editar a mano.",
        "",
        f"{len(running)} comprobaciones se ejecutan en una suite (`cortetsu test`,",
        "`build-regressions.sh`, `nested-regressions.py`, `test-feature-contracts.sh`).",
        f"Las otras {len(archived)} son contratos archivados de migraciones anteriores",
        "(F0–F9): nada las ejecuta en HEAD y muchas describen código que ya pasó al",
        "runtime nativo. El oráculo histórico ejecuta sus propias copias desde el",
        "commit base. Antes de recuperar una, comprobar que sigue describiendo el",
        "comportamiento actual y añadirla a una suite.",
        "",
        "## En una suite",
        "",
        *[f"- `{name}`" for name in running],
        "",
        "## Archivadas",
        "",
        *[f"- `{name}`" for name in archived],
    ]
    return "\n".join(lines) + "\n"


def main() -> int:
    text = render()
    if "--check" in sys.argv:
        return 0 if OUT.exists() and OUT.read_text() == text else 1
    OUT.write_text(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
