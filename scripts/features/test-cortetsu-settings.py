from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
settings = ROOT / "cortetsu/modules/settings"
content = (settings / "Content.qml").read_text(encoding="utf-8")
host = (ROOT / "cortetsu/modules/SettingsHost.qml").read_text(encoding="utf-8")
state = (ROOT / "cortetsu/components/ScreenState.qml").read_text(encoding="utf-8")
shortcuts = (ROOT / "cortetsu/modules/Shortcuts.qml").read_text(encoding="utf-8")
hypr = (ROOT / "dotfiles/home/.config/hypr/hyprland/keybinds.lua").read_text(encoding="utf-8")
runtime_builder = (ROOT / "cortetsu/bin/build-runtime.sh").read_text(encoding="utf-8")

for filename in ("SettingsController.qml", "Wrapper.qml", "Content.qml"):
    assert (settings / filename).is_file(), filename
for marker in ("Scheme gallery", "Schemes.list", "CortetsuConfig.smartScheme", "CortetsuConfig.wallpaperEnabled", "CortetsuConfig.save()", "Search settings"):
    assert marker in content, marker
for marker in ("name: \"settings\"", "WlrLayer.Overlay", "Exclusive", "Wrapper"):
    assert marker in host, marker
assert "property bool settings" in state and "|| settings" in state
assert 'name: "settings"' in shortcuts
assert 'hl.dsp.global("cortetsu:settings")' in hypr
assert 'cortetsu/assets/branding' in runtime_builder and 'STAGING/assets/branding' in runtime_builder
print("PASS: first-party Settings Center exposes real CortetsuConfig and scheme discovery")
