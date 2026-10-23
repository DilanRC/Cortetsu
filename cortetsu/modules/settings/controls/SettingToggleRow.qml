pragma ComponentBehavior: Bound

import QtQuick
import "../../../components"

// A switch with its explanation. The whole row is one target and one Tab
// stop. `checked` is bound by the caller to the real value: the row never
// flips on its own, so a refused change leaves the switch where it was.
SettingRow {
    id: root

    property bool checked: false
    signal toggled(bool checked)

    interactive: true
    // Qt will not drop the flag from the item that holds the focus.
    activeFocusOnTab: !disabled || activeFocus
    enabled: !disabled

    // The entire row is one switch; its visual knob is not a second target.
    Accessible.role: Accessible.Switch
    Accessible.name: root.title
    Accessible.checkable: true
    Accessible.checked: root.checked
    Accessible.focusable: !root.disabled
    Accessible.focused: root.activeFocus
    Accessible.onPressAction: root.request()
    Accessible.onToggleAction: root.request()

    function request(): void {
        if (!root.disabled && root.status !== "busy")
            root.toggled(!root.checked);
    }

    Keys.onEnterPressed: root.request()
    Keys.onReturnPressed: root.request()
    Keys.onSpacePressed: root.request()

    onClicked: {
        root.forceActiveFocus();
        root.request();
    }

    CortetsuToggle {
        objectName: "switch"
        checked: root.checked
        disabled: root.disabled || root.status === "busy"
        // The row is the target for keys and pointer alike; the switch only
        // draws the state. Left enabled it would answer the same click too.
        enabled: false
        activeFocusOnTab: false
        // The parent SettingToggleRow owns the one accessible switch target.
        Accessible.ignored: true
    }
}
