pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../../../components"
import "../../../theme"
import "../../CortetsuTypography.js" as CortetsuTypography

// A value on a scale. The figure has a reserved width so the row does not
// shift while it changes.
Item {
    id: root

    property string title: ""
    property string valueText: ""
    property alias value: slider.value
    property alias from: slider.from
    property alias to: slider.to
    property alias step: slider.step
    property bool disabled: false
    property string status: ""
    property string statusText: ""
    // A level that can be silenced (an app's stream) carries its own mute
    // button, so silencing it never leaves the row with no way back.
    property bool mutable: false
    property bool muted: false
    signal moved(real value)
    signal muteToggled()

    Layout.fillWidth: true
    implicitHeight: CortetsuDesign.rowHeight + CortetsuDesign.spacingSpacious

    CortetsuDivider {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: CortetsuDesign.spacingStandard
        anchors.rightMargin: CortetsuDesign.spacingStandard
        visible: root.y > 0
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: CortetsuDesign.spacingStandard
        anchors.rightMargin: CortetsuDesign.spacingStandard
        anchors.topMargin: CortetsuDesign.spacingCompact
        anchors.bottomMargin: CortetsuDesign.spacingCompact
        spacing: 2

        RowLayout {
            Layout.fillWidth: true
            spacing: CortetsuDesign.spacingStandard
            opacity: root.disabled && !root.mutable ? 0.52 : 1

            CortetsuText {
                Layout.fillWidth: true
                text: root.title
                textSize: CortetsuTypography.bodyLargePx
                elide: Text.ElideRight
            }

            CortetsuButton {
                objectName: "sliderMute"
                visible: root.mutable
                compact: true
                active: root.muted
                icon: root.muted ? "volume_off" : "volume_up"
                label: ""
                tooltipText: root.muted ? qsTr("Activar el sonido de %1").arg(root.title)
                    : qsTr("Silenciar %1").arg(root.title)
                onClicked: root.muteToggled()
            }

            CortetsuText {
                objectName: "sliderValue"
                Layout.minimumWidth: 64
                horizontalAlignment: Text.AlignRight
                text: root.status === "error" && root.statusText.length > 0 ? root.statusText : root.valueText
                textSize: CortetsuTypography.labelMediumPx
                color: root.status === "error"
                    ? CortetsuDesign.colorVermillion
                    : CortetsuDesign.colorOnSurfaceVariant
            }
        }

        CortetsuSlider {
            id: slider
            objectName: "slider"
            accessibleName: root.title
            accessibleValue: root.valueText || Math.round(slider.progress * 100) + " %"
            Layout.fillWidth: true
            disabled: root.disabled
            Accessible.name: root.title
            onMoved: next => root.moved(next)
        }
    }
}
