import QtQuick
import QtQuick.Layouts
import "../../"
import "../../../services"

CortetsuSurface {
    id: root
    outlined: false
    baseColor: CortetsuDesign.colorSurfaceHigh
    radiusValue: CortetsuDesign.radiusLarge
    implicitHeight: header.implicitHeight + content.implicitHeight + CortetsuDesign.spacingSpacious * 2
    RowLayout {
        id: header
        anchors.left: parent.left; anchors.top: parent.top; anchors.margins: CortetsuDesign.spacingComfortable
        spacing: CortetsuDesign.spacingCompact
        CortetsuIcon { text: "schedule"; iconSize: 20 }
        CortetsuText { text: qsTr("Pronóstico por hora"); textSize: 20; font.weight: Font.DemiBold }
    }
    RowLayout {
        id: content
        anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.margins: CortetsuDesign.spacingComfortable
        spacing: CortetsuDesign.spacingCompact
        Repeater {
            model: Math.min(8, Weather.hourlyForecast.length)
            ColumnLayout {
                required property int index
                readonly property var condition: Weather.hourlyForecast[index]
                Layout.fillWidth: true; spacing: 4
                Rectangle {
                    Layout.alignment: Qt.AlignHCenter; implicitWidth: 48; implicitHeight: 38; radius: 12
                    color: index === 0 ? CortetsuDesign.colorPrimary : "transparent"
                    CortetsuText { anchors.centerIn: parent; text: Weather.formatTemp(condition.tempC).slice(0, -1); textSize: 16; color: index === 0 ? CortetsuDesign.colorOnPrimary : CortetsuDesign.colorOnSurface }
                }
                CortetsuIcon { Layout.alignment: Qt.AlignHCenter; text: condition.icon; iconSize: 22; color: CortetsuDesign.colorSecondary }
                CortetsuText { Layout.alignment: Qt.AlignHCenter; text: `${condition.precipChance}%`; textSize: 12; color: CortetsuDesign.colorPrimary }
                CortetsuText { Layout.alignment: Qt.AlignHCenter; text: index === 0 ? qsTr("Ahora") : Qt.formatDateTime(new Date(condition.timestamp.replace("T", " ")), CortetsuRegional.hourPattern); textSize: 12; color: CortetsuDesign.colorOnSurfaceVariant }
            }
        }
    }
}
