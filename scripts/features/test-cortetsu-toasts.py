from pathlib import Path

repo = Path(__file__).resolve().parents[2]
toaster = (repo / "cortetsu/services/CortetsuToaster.qml").read_text(encoding="utf-8")
view = (repo / "cortetsu/modules/utilities/toasts/Toasts.qml").read_text(encoding="utf-8")
item = (repo / "cortetsu/modules/utilities/toasts/ToastItem.qml").read_text(encoding="utf-8")
bottom_hub = (repo / "cortetsu/modules/BottomHub.qml").read_text(encoding="utf-8")
panels = (repo / "cortetsu/modules/drawers/Panels.qml").read_text(encoding="utf-8")
hub = (repo / "cortetsu/modules/BottomHub.qml").read_text(encoding="utf-8")

for source in (toaster, view, item, panels, hub):
    for legacy in ("Caelestia", "GlobalConfig", "qs.services", "qs.components"):
        assert legacy not in source, legacy

assert "pragma Singleton" in toaster
assert "function toast" in toaster
assert "function toast(title, message, icon, type = 0)" in toaster
assert "function dismiss" in toaster
assert "CortetsuToaster.toasts" in view
assert "onDismissed: CortetsuToaster.dismiss" in view
assert "visibleToasts" in view
assert "toast: root.visibleToasts[index]" in view
assert "width: implicitWidth" in view
assert "height: implicitHeight" in view
assert "implicitHeight: column.childrenRect.height" in view
assert "z: 100" in view
assert "onVisibleToastsChanged" in view
assert "forceActiveFocus()" in view
assert "Keys.onEscapePressed" in view
assert "CortetsuToaster.dismiss(root.visibleToasts[0].id)" in view
assert "height: implicitHeight" in item
assert "focus: false" in item
assert "pressed: toastMouse.pressed" in item
assert "scale: 1" in item
assert "running: !root.hovered && !root.activeFocus" in item
assert "focus: index === 0" in view
assert "pomodoroNotification" in hub
assert "property var consumed" in hub
assert "CortetsuToaster.toast(event.title, event.message, \"timer\")" in hub
assert "onFileChanged: pomodoroNotificationReload.restart()" in hub
assert "onTriggered: pomodoroNotification.reload()" in hub
assert "onTextChanged: consumeEvent(text())" in hub
assert "onLoaded" in hub
assert 'import "utilities/toasts" as Toasts' in bottom_hub
assert "anchors.bottom: bottomHubView.top" in bottom_hub
assert "toasts.implicitHeight" in bottom_hub
assert "toasts.spacing" in bottom_hub
assert "x: toasts.x" in bottom_hub
assert "WlrLayershell.keyboardFocus" in bottom_hub
assert "WlrKeyboardFocus.Exclusive" in bottom_hub
assert 'import "../utilities/toasts" as Toasts' not in panels
print("PASS: Cortetsu owns toast state, rendering, and event calls")
