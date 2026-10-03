pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import ".."
import "../../theme"
import "../../components"
import "../CortetsuTypography.js" as CortetsuTypography
import "KeyCapture.js" as KeyCapture

// Modal listening state for the shortcut editor. It only presents: the page
// owns the capture state, so there is exactly one place that decides whether
// the keyboard is being recorded.
Item {
    id: root

    property bool active: false
    property string actionLabel: ""
    property string currentChord: ""
    property var heldModifiers: []
    property string message: ""
    property bool failed: false
    property bool saving: false
    property real remaining: 1

    signal cancelRequested()

    visible: opacity > 0.001
    opacity: active ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: CortetsuDesign.motionFastMs; easing.type: Easing.OutCubic } }

    Rectangle {
        anchors.fill: parent
        radius: CortetsuDesign.radiusLarge
        color: Qt.alpha(CortetsuDesign.colorSumi, 0.78)
    }

    // Swallow pointer input so nothing behind can be clicked while listening.
    MouseArea { anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.AllButtons; onWheel: wheel => wheel.accepted = true }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: Math.min(parent.width - 48, 460)
        height: column.implicitHeight + CortetsuDesign.spacingSpacious * 2
        radius: CortetsuDesign.radiusLarge
        color: CortetsuDesign.colorSurfaceHigh
        border.width: 2
        border.color: root.failed ? CortetsuDesign.colorVermillion : CortetsuDesign.colorPrimary

        // The pulse is the unambiguous "recording" signal; it runs only while
        // the editor is actually listening.
        SequentialAnimation on border.color {
            running: root.active && !root.failed && !root.saving
            loops: Animation.Infinite
            ColorAnimation { to: Qt.alpha(CortetsuDesign.colorPrimary, 0.35); duration: 700; easing.type: Easing.InOutSine }
            ColorAnimation { to: CortetsuDesign.colorPrimary; duration: 700; easing.type: Easing.InOutSine }
        }

        ColumnLayout {
            id: column
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: CortetsuDesign.spacingSpacious
            spacing: CortetsuDesign.spacingStandard

            RowLayout {
                Layout.fillWidth: true
                spacing: CortetsuDesign.spacingCompact

                Rectangle {
                    Layout.preferredWidth: 10
                    Layout.preferredHeight: 10
                    radius: 5
                    color: root.failed ? CortetsuDesign.colorVermillion : CortetsuDesign.colorPrimary
                }
                CortetsuText {
                    Layout.fillWidth: true
                    text: root.saving ? qsTr("Guardando…") : qsTr("Escuchando el teclado")
                    textSize: CortetsuTypography.labelMediumPx
                    font.weight: Font.DemiBold
                    // The dot carries the accent; the label stays on the text
                    // colour so it is readable under every scheme.
                    color: CortetsuDesign.colorOnSurface
                }
            }

            CortetsuText {
                Layout.fillWidth: true
                text: root.actionLabel
                textSize: CortetsuTypography.titleMediumPx
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }

            CortetsuText {
                Layout.fillWidth: true
                visible: root.currentChord.length > 0
                text: qsTr("Atajo actual: %1").arg(root.currentChord)
                textSize: CortetsuTypography.labelSmallPx
                color: CortetsuDesign.colorOnSurfaceVariant
                elide: Text.ElideRight
            }

            // Live echo of what is being held, in the order Hyprland writes it.
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 64
                radius: CortetsuDesign.radiusMedium
                color: Qt.alpha(CortetsuDesign.colorSumi, 0.55)
                border.width: 1
                border.color: Qt.alpha(CortetsuDesign.colorOutlineVariant, 0.5)

                Row {
                    anchors.centerIn: parent
                    spacing: CortetsuDesign.spacingCompact

                    Repeater {
                        model: KeyCapture.MODIFIER_ORDER
                        delegate: Rectangle {
                            id: chip
                            required property string modelData
                            readonly property bool held: root.heldModifiers.indexOf(modelData) >= 0
                            width: chipText.implicitWidth + 20
                            height: 34
                            radius: CortetsuDesign.radiusSmall
                            color: held ? CortetsuDesign.colorPrimary : "transparent"
                            border.width: 1
                            border.color: held ? CortetsuDesign.colorPrimary : Qt.alpha(CortetsuDesign.colorOutlineVariant, 0.7)
                            Behavior on color { ColorAnimation { duration: CortetsuDesign.motionInstantMs } }

                            CortetsuText {
                                id: chipText
                                anchors.centerIn: parent
                                text: chip.modelData
                                textSize: CortetsuTypography.labelMediumPx
                                font.weight: Font.DemiBold
                                color: chip.held ? CortetsuDesign.colorOnPrimary : CortetsuDesign.colorOnSurfaceVariant
                            }
                        }
                    }

                    CortetsuText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: qsTr("+ tecla")
                        textSize: CortetsuTypography.labelMediumPx
                        color: CortetsuDesign.colorOnSurfaceVariant
                    }
                }
            }

            CortetsuText {
                Layout.fillWidth: true
                text: root.message.length > 0
                    ? root.message
                    : qsTr("Mantén los modificadores y pulsa la tecla. Las combinaciones que ya tienen una acción las recibe Hyprland y no llegan aquí.")
                textSize: CortetsuTypography.labelSmallPx
                color: root.failed ? CortetsuDesign.colorVermillion : CortetsuDesign.colorOnSurfaceVariant
                wrapMode: Text.WordWrap
            }

            CortetsuProgressBar {
                Layout.fillWidth: true
                value: root.remaining
                barHeight: 3
                motionDuration: 0
                fillColor: root.failed ? CortetsuDesign.colorVermillion : CortetsuDesign.colorPrimary
            }

            RowLayout {
                Layout.fillWidth: true
                CortetsuText {
                    Layout.fillWidth: true
                    text: qsTr("Esc cancela · se cierra sola al agotarse el tiempo")
                    textSize: CortetsuTypography.labelSmallPx
                    color: CortetsuDesign.colorOnSurfaceVariant
                }
                CortetsuButton {
                    compact: true
                    label: qsTr("Cancelar")
                    onClicked: root.cancelRequested()
                }
            }
        }
    }
}
