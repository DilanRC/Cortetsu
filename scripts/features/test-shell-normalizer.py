#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
NORMALIZER = REPO / "tests/reference/python-runtime/cortetsu/bin/normalize-shell-24.py"

spec = importlib.util.spec_from_file_location("shell_normalizer", NORMALIZER)
if spec is None or spec.loader is None:
    raise SystemExit(f"No pude cargar {NORMALIZER}")
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

# Do not use str.format() here: QML braces are literal syntax and must not be
# interpreted as Python replacement fields. Only the explicit sentinel below
# is substituted per test case.
BASE = '''import "modules"\n\nShellRoot {\n    id: root\n\n    settings.watchFiles: __WATCH__\n\n    Background {}\n    Drawers {}\n\n    Shortcuts {}\n    BatteryMonitor {}\n}\n'''


def shell_fixture(watch: str) -> str:
    if watch not in {"true", "false"}:
        raise ValueError(f"invalid watchFiles fixture value: {watch}")
    return BASE.replace("__WATCH__", watch, 1)


def case(name: str, watch: str, *, expect_change: bool = True) -> None:
    with tempfile.TemporaryDirectory(prefix="cortetsu-shell-normalizer-") as td:
        root = Path(td)
        path = root / "shell.qml"
        path.write_text(shell_fixture(watch), encoding="utf-8")
        changed = mod.normalize(root)
        if changed != expect_change:
            raise SystemExit(f"FAIL {name}: changed={changed}")
        text = path.read_text(encoding="utf-8")
        for marker in (
            "settings.watchFiles: false",
            "    BottomHub {}",
            "    OverviewController {}",
        ):
            if marker not in text:
                raise SystemExit(f"FAIL {name}: missing {marker}")
        if mod.normalize(root):
            raise SystemExit(f"FAIL {name}: second pass not idempotent")
        print(f"PASS {name}")


def reject_legacy() -> None:
    with tempfile.TemporaryDirectory(prefix="cortetsu-shell-legacy-") as td:
        root = Path(td)
        path = root / "shell.qml"
        path.write_text(
            shell_fixture("false").replace(
                "    Shortcuts {}\n",
                "    ConfigToasts {}\n    Shortcuts {}\n",
            ),
            encoding="utf-8",
        )
        try:
            mod.normalize(root)
        except SystemExit:
            print("PASS legacy-configtoasts-rejected")
            return
        raise SystemExit("FAIL legacy-configtoasts-rejected")


def main() -> None:
    case("upstream-2.4-shell", "true")
    case("aur-watchfiles-variant", "false")
    reject_legacy()
    print("Shell normalizer tests: OK")


if __name__ == "__main__":
    main()
