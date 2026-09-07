import subprocess
from pathlib import Path

repo = Path(__file__).resolve().parents[2]
cli = repo / "scripts/cortetsu"
hypr = (repo / "config/hypr-user.lua").read_text(encoding="utf-8")
text = cli.read_text(encoding="utf-8")
picker = (repo / "cortetsu/modules/areapicker/AreaPicker.qml").read_text(encoding="utf-8")
picker_content = (repo / "cortetsu/modules/areapicker/Picker.qml").read_text(encoding="utf-8")
capture_helper = (repo / "cortetsu/bin/cortetsu-area-capture").read_text(encoding="utf-8")

assert "screenshot_cmd()" in text
assert 'ipc call picker openFreeze' in text
assert 'ipc call picker open' in text
assert "/usr/bin/caelestia" not in text
assert 'cortetsu screenshot -r -f' in hypr
assert "caelestia screenshot" not in hypr
for source in (picker, picker_content):
    for legacy in ("Caelestia", "CUtils", "Colours.", "Tokens.", "StyledRect", "StyledText", "MaterialIcon", "qs.services", "qs.components"):
        assert legacy not in source, legacy
assert 'target: "picker"' in picker
for method in ("open", "openFreeze", "openClip", "openFreezeClip"):
    assert f"function {method}()" in picker
assert '"cortetsu-area-capture", geometry, path' in picker_content
assert '"sh", "-c"' not in picker_content
assert 'subprocess.run(["grim", "-g", args.geometry, str(args.path)])' in capture_helper
assert 'subprocess.run(["swappy", "-f", str(args.path)])' in capture_helper
result = subprocess.run(["bash", str(cli), "screenshot", "--bad"], text=True, capture_output=True)
assert result.returncode != 0 and "opción de screenshot desconocida" in result.stderr
print("PASS: screenshot keybind targets the Cortetsu runtime IPC")
