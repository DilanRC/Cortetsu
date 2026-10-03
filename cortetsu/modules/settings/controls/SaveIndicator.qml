pragma ComponentBehavior: Bound

import QtQuick
import "../../../components"
import "../../../theme"
import "../.."
import "../../CortetsuTypography.js" as CortetsuTypography

// Whether the preferences reached the disk. Quiet while nothing happens, a
// short confirmation after a write, and a message that stays if it failed.
Row {
    id: root

    readonly property string state: CortetsuConfig.saveState
    readonly property bool failed: state === "failed"
    property bool recent: false

    spacing: CortetsuDesign.spacingUnit
    visible: opacity > 0
    opacity: root.failed || root.state === "pending" || root.state === "saving" || root.recent ? 1 : 0

    onStateChanged: {
        if (root.state === "saved") {
            root.recent = true;
            fade.restart();
        }
    }

    Behavior on opacity {
        NumberAnimation { duration: CortetsuDesign.motionStandardMs; easing.type: Easing.OutCubic }
    }

    Timer {
        id: fade
        interval: 2000
        onTriggered: root.recent = false
    }

    CortetsuIcon {
        anchors.verticalCenter: parent.verticalCenter
        text: root.failed ? "error_outline" : root.state === "saved" ? "check" : "sync"
        iconSize: CortetsuTypography.labelLargePx
        color: root.failed ? CortetsuDesign.colorVermillion : CortetsuDesign.colorOnSurfaceVariant
    }

    CortetsuText {
        objectName: "saveText"
        anchors.verticalCenter: parent.verticalCenter
        text: root.failed
            ? qsTr("No se pudo guardar: %1").arg(CortetsuConfig.saveError)
            : root.state === "saved" ? qsTr("Guardado") : qsTr("Guardando…")
        textSize: CortetsuTypography.labelSmallPx
        color: root.failed ? CortetsuDesign.colorVermillion : CortetsuDesign.colorOnSurfaceVariant
    }
}
