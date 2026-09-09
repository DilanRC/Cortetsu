from pathlib import Path

repo = Path(__file__).resolve().parents[2]
for name in ("Wrapper.qml", "Content.qml"):
    source = (repo / "cortetsu/modules/session" / name).read_text(encoding="utf-8")
    for legacy in ("Caelestia", "GlobalConfig", "SessionManager", "qs.services", "qs.components", "Tokens", "Colours"):
        assert legacy not in source, f"{name}: {legacy}"

content = (repo / "cortetsu/modules/session/Content.qml").read_text(encoding="utf-8")
action_row = (repo / "cortetsu/components/CortetsuActionRow.qml").read_text(encoding="utf-8")

# First-party power commands remain explicit and inspectable.
for marker in (
    '["systemctl", "suspend"]',
    '["systemctl", "hibernate"]',
    '["systemctl", "reboot"]',
    '["systemctl", "poweroff"]',
    '["hyprctl", "dispatch", "exit"]',
    '["hyprctl", "dispatch", "global", "cortetsu:lock"]',
):
    assert marker in content, marker

# Confirmations are keyed by stable action ids. The previous implementation
# accidentally passed modelData.command into run() and then attempted
# action.command, which could never dispatch the selected action correctly.
assert "property string pendingAction" in content
assert "action.confirm && pendingAction !== action.id" in content
assert "Quickshell.execDetached(action.command)" in content
assert "onClicked: root.run(actionRow.modelData)" in content
assert "CortetsuActionRow" in content
assert "activeFocusOnTab" in action_row
assert "required property int index" in action_row
assert "focus: root.index === 0" in action_row
assert "Keys.onEnterPressed" in action_row and "Keys.onSpacePressed" in action_row
assert "onEntered: actionRow.hovered = true" not in content
assert "onExited: actionRow.hovered = false" not in content
assert "root.run(modelData.command)" not in content
assert "Confirm %1" in content and "Press again within 4 seconds" in content

# Suspend locks the shell first and only then hands off to systemd.
assert "action.lockBefore" in content
assert "deferredTimer" in content
assert "interval: 220" in content

print("PASS: session actions dispatch full first-party action records with safe lock/suspend flow and confirmation")
