pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import qs.components
import qs.modules 1.0
import qs.services 1.0
import "../CortetsuDesign.js" as CortetsuDesign
import "../CortetsuTypography.js" as CortetsuTypography

Item {
    id: root
    required property var screenState

    ColumnLayout {
        anchors.fill: parent
        spacing: CortetsuDesign.spacingStandard

        RowLayout {
            Layout.fillWidth: true
            spacing: CortetsuDesign.spacingStandard

            CortetsuIcon { text: "hexagon"; iconSize: CortetsuTypography.iconMediumPx; color: CortetsuDesign.colorPrimary }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                CortetsuText { text: qsTr("Cortetsu"); textSize: CortetsuTypography.titleMediumPx; font.weight: Font.DemiBold }
                CortetsuText { text: qsTr("Quick Settings"); textSize: CortetsuTypography.labelSmallPx; color: CortetsuDesign.colorOnSurfaceVariant }
            }
            CortetsuButton { compact: true; icon: "close"; label: qsTr("Close"); onClicked: root.screenState.qsd = false }
        }

        CortetsuSectionHeader { Layout.fillWidth: true; title: qsTr("Controls"); detail: qsTr("Live system state") }

        GridLayout {
            Layout.fillWidth: true
            columns: 2
            rowSpacing: CortetsuDesign.spacingCompact
            columnSpacing: CortetsuDesign.spacingCompact

            CortetsuSurface {
                Layout.fillWidth: true
                implicitHeight: 74
                radiusValue: CortetsuDesign.radiusMedium
                baseColor: CortetsuAudio.muted ? Qt.alpha(CortetsuDesign.colorWarning, 0.12) : Qt.alpha(CortetsuDesign.colorPrimary, 0.14)
                outlined: true
                CortetsuIcon { anchors.centerIn: parent; text: CortetsuAudio.muted ? "volume_off" : "volume_up"; iconSize: CortetsuTypography.iconMediumPx; color: CortetsuAudio.muted ? CortetsuDesign.colorWarning : CortetsuDesign.colorPrimary }
                MouseArea { anchors.fill: parent; onClicked: if (CortetsuAudio.sink?.audio) CortetsuAudio.sink.audio.muted = !CortetsuAudio.sink.audio.muted }
            }
            CortetsuSurface {
                Layout.fillWidth: true
                implicitHeight: 74
                radiusValue: CortetsuDesign.radiusMedium
                baseColor: CortetsuNotifications.dnd ? Qt.alpha(CortetsuDesign.colorWarning, 0.12) : Qt.alpha(CortetsuDesign.colorSurfaceGlassStrong, 0.84)
                outlined: true
                CortetsuIcon { anchors.centerIn: parent; text: CortetsuNotifications.dnd ? "notifications_off" : "notifications_active"; iconSize: CortetsuTypography.iconMediumPx; color: CortetsuNotifications.dnd ? CortetsuDesign.colorWarning : CortetsuDesign.colorOnSurface }
                MouseArea { anchors.fill: parent; onClicked: CortetsuNotifications.dnd = !CortetsuNotifications.dnd }
            }
        }

        CortetsuSectionHeader { Layout.fillWidth: true; title: qsTr("Levels"); detail: qsTr("Hardware readback") }

        CortetsuText { text: qsTr("Brightness"); textSize: CortetsuTypography.labelMediumPx }
        CortetsuSlider {
            Layout.fillWidth: true
            value: Brightness.getMonitorForScreen(root.screen)?.brightness ?? -1
            disabled: value < 0
            onMoved: Brightness.getMonitorForScreen(root.screen)?.setBrightness(value)
        }
        CortetsuText { text: qsTr("Volume"); textSize: CortetsuTypography.labelMediumPx }
        CortetsuSlider {
            Layout.fillWidth: true
            value: CortetsuAudio.volume
            onMoved: CortetsuAudio.setVolume(value)
        }

        CortetsuSurface {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radiusValue: CortetsuDesign.radiusLarge
            baseColor: Qt.alpha(CortetsuDesign.colorSurfaceGlass, 0.66)
            outlined: true
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: CortetsuDesign.spacingStandard
                spacing: CortetsuDesign.spacingUnit
                CortetsuText { text: qsTr("Network"); textSize: CortetsuTypography.labelMediumPx; font.weight: Font.DemiBold }
                CortetsuText { Layout.fillWidth: true; text: CortetsuNetwork.active?.ssid ?? (CortetsuNetwork.activeEthernet ? qsTr("Ethernet connected") : qsTr("Network unavailable")); textSize: CortetsuTypography.bodySmallPx; color: CortetsuDesign.colorOnSurfaceVariant; elide: Text.ElideRight }
                CortetsuText { Layout.fillWidth: true; text: Bluetooth.defaultAdapter?.enabled ? qsTr("Bluetooth enabled") : qsTr("Bluetooth disabled"); textSize: CortetsuTypography.bodySmallPx; color: CortetsuDesign.colorOnSurfaceVariant }
            }
        }
    }
}
