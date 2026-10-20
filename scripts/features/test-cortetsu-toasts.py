from pathlib import Path

repo = Path(__file__).resolve().parents[2]
toaster = (repo / "cortetsu/services/CortetsuToaster.qml").read_text(encoding="utf-8")
view = (repo / "cortetsu/modules/utilities/toasts/Toasts.qml").read_text(encoding="utf-8")
item = (repo / "cortetsu/modules/utilities/toasts/ToastItem.qml").read_text(encoding="utf-8")
bottom_hub = (repo / "cortetsu/modules/BottomHub.qml").read_text(encoding="utf-8")
pomodoro = (repo / "cortetsu/modules/pomodoro/Pomodoro.qml").read_text(encoding="utf-8")
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
assert "required property var modelData" in view
assert "toast: modelData" in view
assert "CortetsuToaster.dismiss(modelData.id)" in view
assert "width: implicitWidth" in view
assert "height: implicitHeight" in view
assert "implicitHeight: column.childrenRect.height" in view
assert "z: 100" in view
assert "focus: false" in view
assert "onVisibleToastsChanged" not in view
assert "function focusToast(id: int): bool" in view
assert "item.forceActiveFocus(Qt.TabFocusReason)" in view
assert "Keys.onEscapePressed" in view
assert "CortetsuToaster.dismiss(root.visibleToasts[0].id)" in view
assert "height: implicitHeight" in item
assert "focus: false" in item
assert "pressed: toastMouse.pressed" in item
assert "scale: 1" in item
assert "running: !root.hovered && !root.activeFocus" in item
assert 'objectProp: "id"' in view
assert "onPressed: root.forceActiveFocus()" in item
# Pomodoro announcements are read by the Pomodoro service (one per shell).
# Writes are atomic renames, so each change is reloaded at once; the sequence
# and the shell start time keep a reload from repeating a toast.
assert "property FileView announcements" in pomodoro
assert "property real consumed" in pomodoro
assert "CortetsuToaster.toast(event.title, event.message, \"timer\")" in pomodoro
assert "onFileChanged: reload()" in pomodoro
assert "Model.announcement(event, consumed, root.startedNs)" in pomodoro
assert "onLoaded" in pomodoro
assert "pomodoro" not in hub.lower(), "Bottom Hub no longer owns Pomodoro"
assert 'import "utilities/toasts" as Toasts' in bottom_hub
assert "anchors.bottom: bottomHubView.top" in bottom_hub
assert "toasts.implicitHeight" in bottom_hub
assert "toasts.spacing" in bottom_hub
assert "x: toasts.x" in bottom_hub
assert "WlrLayershell.keyboardFocus" in bottom_hub
assert "WlrKeyboardFocus.OnDemand" in bottom_hub
assert "hubRoot.shown" in bottom_hub and "WlrKeyboardFocus.None" in bottom_hub
assert "function onFocusRequested(id: int)" in bottom_hub
assert "Qt.callLater(() => toasts.focusToast(id))" in bottom_hub
assert "function requestFocusNewest(): void" in toaster
assert 'name: "focusToast"' in (repo / "cortetsu/modules/Shortcuts.qml").read_text(encoding="utf-8")
keybinds = (repo / "dotfiles/home/.config/hypr/hyprland/keybinds.lua").read_text(encoding="utf-8")
variables = (repo / "dotfiles/home/.config/hypr/variables.lua").read_text(encoding="utf-8")
assert 'kbFocusToast               = "SUPER + ALT + N"' in variables
assert 'create_bind(vars.kbFocusToast, hl.dsp.global("cortetsu:focusToast"))' in keybinds
assert "visible: hubRoot.shown || toasts.visibleToasts.length > 0" in bottom_hub
assert 'import "../utilities/toasts" as Toasts' not in panels
print("PASS: Cortetsu owns toast state, rendering, and event calls")
