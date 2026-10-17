pragma ComponentBehavior: Bound

import QtQuick
import ".."
import "../../components"
import "../../theme"
import "../CortetsuTypography.js" as CortetsuTypography

// «Probar teclas»: the key test of one keyboard's spare keys. While it runs,
// those keys only record that they were pressed; a pressed key becomes
// «Comprobada» once the test ends.
Rectangle {
    id: root

    property var keyboard: null
    property var probe: null
    property string error: ""
    property string summary: ""
    property bool disabled: false

    signal startRequested()
    signal endRequested()

    readonly property bool running: probe !== null
    readonly property int hits: probe?.hits?.length ?? 0
    readonly property int total: probe?.codes?.length ?? 0

    implicitHeight: content.implicitHeight + CortetsuDesign.spacingStandard * 2
    radius: CortetsuDesign.radiusMedium
    color: Qt.alpha(running ? CortetsuDesign.colorPrimary : CortetsuDesign.colorSumi, running ? 0.12 : 0.35)
    border.width: running ? 1 : 0
    border.color: Qt.alpha(CortetsuDesign.colorPrimary, 0.45)

    Row {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.margins: CortetsuDesign.spacingStandard
        spacing: CortetsuDesign.spacingStandard

        CortetsuIcon {
            anchors.verticalCenter: parent.verticalCenter
            text: root.running ? "touch_app" : "fact_check"
            color: CortetsuDesign.colorPrimary
            iconSize: CortetsuTypography.iconMediumPx
        }

        CortetsuText {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - x - action.width - parent.spacing
            wrapMode: Text.WordWrap
            textSize: CortetsuTypography.labelSmallPx
            color: root.error ? CortetsuDesign.colorWarning : CortetsuDesign.colorOnSurface
            text: root.error ? root.error
                : root.summary && !root.running ? root.summary
                : root.running ? qsTr("Pulsa las teclas libres de %1. Ahora solo registran la pulsación · pulsadas %2 de %3")
                    .arg(root.keyboard?.label ?? "").arg(root.hits).arg(root.total)
                : root.keyboard ? qsTr("Comprueba qué teclas libres existen de verdad en %1: el controlador declara más de las que hay.")
                    .arg(root.keyboard.label)
                : qsTr("Elige un teclado para probar sus teclas libres.")
        }

        CortetsuButton {
            id: action
            objectName: root.running ? "endProbe" : "startProbe"
            anchors.verticalCenter: parent.verticalCenter
            active: root.running
            disabled: root.disabled || (!root.running && !root.keyboard?.hyprlandLinked)
            icon: root.running ? "check" : "play_arrow"
            label: root.running ? qsTr("Terminar") : qsTr("Probar teclas")
            tooltipText: !root.running && root.keyboard && !root.keyboard.hyprlandLinked
                ? qsTr("Hyprland no distingue este teclado de otro igual") : ""
            onClicked: root.running ? root.endRequested() : root.startRequested()
        }
    }
}
