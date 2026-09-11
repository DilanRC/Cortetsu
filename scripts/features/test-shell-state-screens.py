from pathlib import Path

repo = Path(__file__).resolve().parents[2]
service = (repo / "cortetsu/services/ShellState.qml").read_text(encoding="utf-8")
pam = (repo / "cortetsu/base/modules/lock/Pam.qml").read_text(encoding="utf-8")
assert "onLockEnableFprintChanged" in pam and "onLockEnableHowdyChanged" in pam
assert "function onEnableFprintChanged" not in pam and "function onEnableHowdyChanged" not in pam

assert 'import "../modules"' in service
assert "CortetsuShellState.forScreen(screen)" in service
assert "CortetsuShellState.forActive()" in service
assert "states.instances[0]" not in service
assert "?? CortetsuShellState.forActive();" not in service.split("function forScreen", 1)[1].split("function forActive", 1)[0]
assert "id: legacyComponents" in service
assert "function compatibilityComponentsFor(screen): var" in service
assert "readonly property var target: ShellState.compatibilityComponentsFor(screen)" in service
assert "readonly property var target: ShellState.componentsFor(screen)" not in service
assert "import Caelestia" not in service
assert "import qs.services" not in service
print("PASS: ShellState compatibility service delegates to Cortetsu state")
