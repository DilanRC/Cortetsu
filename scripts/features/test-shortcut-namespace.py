from pathlib import Path

repo = Path(__file__).resolve().parents[2]
shortcut = (repo / "cortetsu/components/misc/CustomShortcut.qml").read_text()
hypr = (repo / "config/hypr-user.lua").read_text()

assert 'appid: "cortetsu"' in shortcut
assert 'appid: "caelestia"' not in shortcut
assert 'hl.dsp.global("caelestia:' not in hypr
assert 'hl.dsp.global("cortetsu:' in hypr
assert 'hl.dsp.exec_cmd("/home/dilan/.local/bin/cortetsu shell ipc clipboard toggle")' in hypr
assert 'qs -p ~/.config/quickshell/cortetsu/current ipc call clipboard toggle' not in hypr

print("PASS: global shortcuts use the Cortetsu application namespace")
