pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import Quickshell.Services.Mpris
import "../../components"
import "../../services"
import "../../utils"
import ".."
import "../../theme"
import "../CortetsuTypography.js" as CortetsuTypography

Item {
    CortetsuStateMessage {
        anchors.centerIn: parent
        width: parent.width
        visible: !Weather.cc
        icon: "cloud_off"
        title: qsTr("Tiempo no disponible")
        detail: qsTr("Aparece cuando hay conexión y una ubicación en Ajustes")
    }
    ColumnLayout {
        anchors.fill: parent
        visible: !!Weather.cc
        spacing: 2
        DashLabel { text: qsTr("TIEMPO") }
        CortetsuText { text: Weather.city; textSize: CortetsuTypography.titleMediumPx; font.weight: Font.DemiBold; elide: Text.ElideRight; Layout.fillWidth: true }
        CortetsuText { text: Weather.description; color: CortetsuDesign.colorOnSurfaceVariant }
        Item { Layout.fillHeight: true }
        RowLayout {
            spacing: CortetsuDesign.spacingStandard
            CortetsuText { text: Weather.icon; textSize: CortetsuTypography.iconExtraLargePx; color: CortetsuDesign.colorPrimary }
            ColumnLayout {
                spacing: 0
                CortetsuText { text: Weather.temp; textSize: CortetsuTypography.displayLargePx; font.weight: Font.DemiBold }
                CortetsuText { text: qsTr("Sensación %1").arg(Weather.feelsLike); color: CortetsuDesign.colorOnSurfaceVariant; textSize: CortetsuTypography.bodySmallPx }
            }
        }
    }
}
