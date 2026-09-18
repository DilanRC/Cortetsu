from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
content = (ROOT / "cortetsu/modules/launcher/Content.qml").read_text(encoding="utf-8")
mode = (ROOT / "cortetsu/modules/CortetsuModeSegment.qml").read_text(encoding="utf-8")
assert "CortetsuSearchBar" in content
assert "onAccepted" in content
checks = {
    "launcher delegates mode rendering": "ContentList" in content,
    "idle stays Human": '"Human"' in mode,
    "hover intent reaches Awakening": '"Awakening"' in mode and "launcherButton.hovered" in mode,
    "launcher open reaches Monster": '"Monster"' in mode and "root.launcherActive" in mode,
    "Cosmic is excluded": '"Cosmic"' not in mode,
    "mode button remains functional": "onClicked: root.launcherRequested()" in mode,
}
assert all(checks.values()), [name for name, passed in checks.items() if not passed]
print(f"Launcher identity eval: {sum(checks.values())}/{len(checks)}")
