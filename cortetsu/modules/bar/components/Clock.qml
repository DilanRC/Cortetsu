import QtQuick
import QtQuick.Layouts
import "../.."
import "../../../services"
import "../../../theme"
import "../../CortetsuTypography.js" as CortetsuTypography

Rectangle {
    id: root

    readonly property color colour: CortetsuDesign.colorTertiary
    implicitWidth: 72
    implicitHeight: layout.implicitHeight + 16
    radius: height / 2
    color: Qt.alpha(CortetsuDesign.colorSurfaceHigh, 0.82)
    border.color: CortetsuDesign.colorOutlineVariant
    border.width: 1

    ColumnLayout {
        id: layout
        anchors.centerIn: parent
        spacing: 0

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: Time.hourStr + ":" + Time.minuteStr
            color: root.colour
            font.family: CortetsuTypography.uiFamily
            font.pixelSize: CortetsuTypography.labelLargePx
            font.weight: Font.DemiBold
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: Time.format("ddd d")
            color: CortetsuDesign.colorOnSurfaceVariant
            font.family: CortetsuTypography.uiFamily
            font.pixelSize: CortetsuTypography.labelSmallPx
        }
    }
}
