import QtQuick
import "../../components"
import "../../theme"
import "../CortetsuTypography.js" as CortetsuTypography

// One reading: what it is on the left, its value on the right. A missing
// value says so instead of showing a dash that reads as data.
Item {
    id: root

    property string label: ""
    property string value: ""
    property bool emphasized: false

    implicitHeight: 28

    CortetsuText {
        id: name
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(implicitWidth, parent.width * 0.55)
        text: root.label
        color: CortetsuDesign.colorOnSurfaceVariant
        textSize: CortetsuTypography.bodySmallPx
        elide: Text.ElideRight
    }

    CortetsuText {
        anchors.left: name.right
        anchors.leftMargin: CortetsuDesign.spacingStandard
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: root.value || qsTr("No disponible")
        color: root.value ? CortetsuDesign.colorOnSurface : CortetsuDesign.colorOnSurfaceVariant
        textSize: CortetsuTypography.bodySmallPx
        font.weight: root.emphasized && root.value ? Font.DemiBold : Font.Normal
        horizontalAlignment: Text.AlignRight
        elide: Text.ElideLeft
    }
}
