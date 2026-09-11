from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
content = (ROOT / "cortetsu/modules/launcher/Content.qml").read_text(encoding="utf-8")
assert "Search-first" in content
assert "Prefix mode" in content
assert "onAccepted" in content
checks = {
    "launcher renders the shared mark": "CortetsuEvolvingMark" in content,
    "idle stays Human": '"Human"' in content,
    "focus intent reaches Awakening": 'search.activeFocus' in content and '"Awakening"' in content,
    "launcher open reaches Monster": '"Monster"' in content and "root.screenState?.launcher" in content,
    "wallpaper lifecycle stays out of Launcher mark": "markPhase: CortetsuWallpapers.applying" not in content,
    "Cosmic is excluded": '"Cosmic"' not in content,
    "mode icon remains functional": "root.modeIcon()" in content,
    "slot stays fixed": "width: 20" in content and "height: 20" in content,
}
assert all(checks.values()), [name for name, passed in checks.items() if not passed]
print(f"Launcher identity eval: {sum(checks.values())}/{len(checks)}")
