pragma ComponentBehavior: Bound

import QtQuick
import "../../../components"

// Something to do, named on its button. With `confirm`, the first press arms
// the action and the second one, within four seconds, runs it.
SettingRow {
    id: root

    property string actionLabel: ""
    property string accessibleName: actionLabel
    property string actionIcon: ""
    property bool danger: false
    property bool confirm: false
    property bool armed: false
    signal activated()

    // A confirmation must never survive a changed or unavailable action.
    function cancelConfirmation(): void {
        disarm.stop();
        root.armed = false;
    }

    onDisabledChanged: if (root.disabled && root.armed) root.cancelConfirmation()
    onStatusChanged: if (root.armed) root.cancelConfirmation()
    onVisibleChanged: if (!root.visible && root.armed) root.cancelConfirmation()
    onConfirmChanged: if (root.armed) root.cancelConfirmation()
    onActionLabelChanged: if (root.armed) root.cancelConfirmation()
    onTitleChanged: if (root.armed) root.cancelConfirmation()

    function request(): void {
        if (!root.visible || root.disabled || root.status === "busy")
            return;
        if (root.confirm && !root.armed) {
            root.armed = true;
            disarm.restart();
            return;
        }
        root.cancelConfirmation();
        root.activated();
    }

    Timer {
        id: disarm
        interval: 4000
        onTriggered: root.armed = false
    }

    CortetsuButton {
        objectName: "action"
        compact: true
        icon: root.armed ? "warning" : root.actionIcon
        label: root.armed ? qsTr("Confirmar") : root.actionLabel
        danger: root.danger || root.armed
        disabled: root.disabled || root.status === "busy"
        Accessible.name: root.armed ? qsTr("Confirmar: %1").arg(root.title) : root.accessibleName
        onClicked: root.request()
    }
}
