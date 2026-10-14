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
    signal moved(real value)

    Layout.fillWidth: true
    implicitHeight: 76

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: CortetsuDesign.spacingStandard
        anchors.rightMargin: CortetsuDesign.spacingStandard
        visible: root.y > 0
        height: 1
        color: Qt.alpha(CortetsuDesign.colorOutlineVariant, 0.36)
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
            opacity: root.disabled ? 0.52 : 1

            CortetsuText {
                Layout.fillWidth: true
                text: root.title
                textSize: CortetsuTypography.bodyPx
                elide: Text.ElideRight
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
            Layout.fillWidth: true
            disabled: root.disabled
            Accessible.name: root.title
            onMoved: next => root.moved(next)
        }
    }
}
