import subprocess
from pathlib import Path

repo = Path(__file__).resolve().parents[2]
cli = repo / "scripts/cortetsu"
hypr = (repo / "config/hypr-user.lua").read_text(encoding="utf-8")
keybinds = (repo / "dotfiles/home/.config/hypr/hyprland/keybinds.lua").read_text(encoding="utf-8")
text = cli.read_text(encoding="utf-8")
picker = (repo / "cortetsu/modules/areapicker/AreaPicker.qml").read_text(encoding="utf-8")
picker_content = (repo / "cortetsu/modules/areapicker/Picker.qml").read_text(encoding="utf-8")
capture_helper = (repo / "cortetsu/bin/cortetsu-area-capture").read_text(encoding="utf-8")

assert "screenshot_cmd()" in text
assert 'ipc call picker openFreeze' in text
assert 'ipc call picker open' in text
assert "/usr/bin/caelestia" not in text
assert 'create_bind(vars.kbScreenshot, hl.dsp.exec_cmd("cortetsu screenshot -r -f"))' in keybinds
assert '"Print",\n    hl.dsp.exec_cmd("cortetsu screenshot -r -f")' not in hypr
assert "caelestia screenshot" not in hypr
assert "Leaving them orphaned" not in keybinds
for source in (picker, picker_content):
    for legacy in ("Caelestia", "CUtils", "Colours.", "Tokens.", "StyledRect", "StyledText", "MaterialIcon", "qs.services", "qs.components"):
        assert legacy not in source, legacy
assert 'target: "picker"' in picker
assert "screenshotActive" in picker
assert "CortetsuShellState.screenshotActive = active" in picker
assert "CortetsuShellState.screenshotActive" in (repo / "cortetsu/modules/osd/Wrapper.qml").read_text(encoding="utf-8")
for method in ("open", "openFreeze", "openClip", "openFreezeClip"):
    assert f"function {method}()" in picker
# The picker hands the area to AreaPicker, which captures after the picker
# hides and then shows the preview; the helper never runs through a shell.
assert "root.state.capture(`${x},${y} ${width}x${height}`, root.screen)" in picker_content
assert "captureTimer" in picker and "interval: 120" in picker
assert '"cortetsu-area-capture", request.geometry, path' in picker
for action in ("--copy", "--save", "--edit", "--discard"):
    assert f'root.act("{action}", root.shot)' in picker, action
assert "ScreenshotPreview {" in picker
assert "WlrKeyboardFocus.None" in picker
assert "else if (!root.state.freeze)" in picker_content
assert "dragThreshold" in picker_content
assert "sx = event.x;" in picker_content and "ex = event.x;" in picker_content
assert "root.checkClientRects(event.x, event.y)" in picker_content
assert "Math.min(screen.width, rsx + sw)" in picker_content
for source in (picker, picker_content):
    assert '"sh", "-c"' not in source
assert 'exec "$BUNDLE/cortetsu-desktop-runtime" cortetsu-area-capture "$@"' in capture_helper
result = subprocess.run(["bash", str(cli), "screenshot", "--bad"], text=True, capture_output=True)
assert result.returncode != 0 and "opción de screenshot desconocida" in result.stderr
print("PASS: screenshot keybind targets the Cortetsu runtime IPC")
