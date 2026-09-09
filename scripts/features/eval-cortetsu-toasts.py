from pathlib import Path

repo = Path(__file__).resolve().parents[2]
toaster = (repo / "cortetsu/services/CortetsuToaster.qml").read_text(encoding="utf-8")
view = (repo / "cortetsu/modules/utilities/toasts/Toasts.qml").read_text(encoding="utf-8")
item = (repo / "cortetsu/modules/utilities/toasts/ToastItem.qml").read_text(encoding="utf-8")
bottom_hub = (repo / "cortetsu/modules/BottomHub.qml").read_text(encoding="utf-8")

criteria = {
    "host has an effective width": "width: implicitWidth" in view,
    "host has an effective height": "height: implicitHeight" in view,
    "host tracks repeater children": "implicitHeight: column.childrenRect.height" in view,
    "toast host stays above panels": "z: 100" in view,
    "toast requests active keyboard focus": "forceActiveFocus()" in view,
    "mouse dismissal exists": "MouseArea" in item and "onClicked: root.dismissed()" in item,
    "toast shares the bar layer": 'import "utilities/toasts" as Toasts' in bottom_hub,
    "toast sits above the bar": "anchors.bottom: bottomHubView.top" in bottom_hub,
    "toast window expands for content": "toasts.implicitHeight" in bottom_hub,
    "event watcher deduplicates per host": "property var consumed" in (repo / "cortetsu/modules/BottomHub.qml").read_text(encoding="utf-8"),
    "file changes debounce event reload": "onFileChanged: pomodoroNotificationReload.restart()" in (repo / "cortetsu/modules/BottomHub.qml").read_text(encoding="utf-8"),
    "event reload runs after debounce": "onTriggered: pomodoroNotification.reload()" in (repo / "cortetsu/modules/BottomHub.qml").read_text(encoding="utf-8"),
    "loaded text is consumed": "onTextChanged: consumeEvent(text())" in (repo / "cortetsu/modules/BottomHub.qml").read_text(encoding="utf-8"),
    "event parses after loading": "onLoaded" in (repo / "cortetsu/modules/BottomHub.qml").read_text(encoding="utf-8"),
    "event duplicates are suppressed": "property var consumed" in (repo / "cortetsu/modules/BottomHub.qml").read_text(encoding="utf-8"),
    "toast list is capped": "slice(0, 5)" in view,
    "item has an effective height": "height: implicitHeight" in item,
    "item does not steal initial focus": "focus: false" in item,
    "host focuses first toast": "focus: index === 0" in view,
    "long messages wrap": "wrapMode: Text.Wrap" in item,
    "critical toasts use urgency color": "toast.type === 2" in item,
    "keyboard dismissal exists": "Keys.onEscapePressed" in item,
    "toast window captures Escape": "WlrKeyboardFocus.Exclusive" in bottom_hub,
    "automatic expiration exists": "interval: 5000" in item,
}

failed = [name for name, passed in criteria.items() if not passed]
assert not failed, f"Toast eval failures: {failed}"
print(f"Toast eval: {len(criteria)}/{len(criteria)} (100%)")
