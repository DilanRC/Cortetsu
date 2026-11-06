#!/usr/bin/env python3
"""Gate test for the remaining active Bottom Hub patches."""
from __future__ import annotations

from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
MANIFEST = REPO / "cortetsu/contracts/patch-debt.tsv"
CHECKER = REPO / "tests/reference/python-runtime/cortetsu/bin/check-bottom-hub-target.py"
V4_TEST = REPO / "scripts/features/test-bottom-hub-v4.py"

# patch file -> (manifest target path, at least one real consumer to grep for)
AUDITED_ACTIVE_PATCHES = {
}

# The semantic checker is frozen with the Python baseline; Cortetsu's active
# implementation is native, while this test preserves the historical oracle.
REQUIRED_CHECKER_TARGETS = (
    "modules/Shortcuts.qml",
    "modules/sidebar/Wrapper.qml",
    "modules/bar/BarWrapper.qml",
    "modules/bar/popouts/Wrapper.qml",
    "modules/bar/popouts/ClipWrapper.qml",
    "modules/utilities/Wrapper.qml",
)


def main() -> None:
    manifest_text = MANIFEST.read_text(encoding="utf-8")
    checker_text = CHECKER.read_text(encoding="utf-8")
    v4_text = V4_TEST.read_text(encoding="utf-8")

    for patch_name, (target_path, consumer_needles) in AUDITED_ACTIVE_PATCHES.items():
        patch_file = REPO / "cortetsu/contracts/patches" / patch_name
        assert patch_file.is_file(), f"missing patch: {patch_name}"

        assert f"{patch_name}\t{target_path}" in manifest_text, (
            f"MANIFEST.tsv missing entry for active patch {patch_name}"
        )

        matched = any(
            needle in checker_text or needle in v4_text or _grep_repo(needle)
            for needle in consumer_needles
        )
        assert matched, f"{patch_name}: no real consumer found for {consumer_needles}"

    for target in REQUIRED_CHECKER_TARGETS:
        assert f'"{target}"' in checker_text, (
            f"check-bottom-hub-target.py must keep validating {target} "
            "(it is the Bottom Hub v4 contract, not dead code)"
        )

    print(f"PASS: {len(AUDITED_ACTIVE_PATCHES)} remaining audited patches confirmed ACTIVE")


def _grep_repo(needle: str) -> bool:
    for path in (REPO / "cortetsu/modules").rglob("*.qml"):
        if needle in path.read_text(encoding="utf-8", errors="ignore"):
            return True
    return False


if __name__ == "__main__":
    main()
