import QtQuick
import QtQuick.Layouts
import "../../components"
import "../CortetsuDesign.js" as Design

RowLayout {
    id: root
    property string label
    property string value
    spacing: Design.spacingStandard
    CortetsuText {
        Layout.fillWidth: true
        text: root.label
        textSize: Design.bodySmallPx
        color: Design.colorOnSurfaceVariant
    }
    CortetsuText {
        Layout.fillWidth: true
        Layout.preferredWidth: 300
        text: root.value || qsTr("No disponible")
        textSize: Design.bodySmallPx
        elide: Text.ElideMiddle
        horizontalAlignment: Text.AlignRight
    }
}
