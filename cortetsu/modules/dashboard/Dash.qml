pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.UPower
import "../../components"
import "../../services"
import ".."
import "../CortetsuDesign.js" as CortetsuDesign
import "../CortetsuTypography.js" as CortetsuTypography

Item {
    id: root
    required property var screenState
    required property var facePicker
    implicitWidth: 1080
    implicitHeight: 520

    CortetsuSurface {
        anchors.fill: parent
        baseColor: Qt.alpha(CortetsuDesign.colorSumi, 0.985)
        radiusValue: CortetsuDesign.radiusSurface
        outlined: true
        outlineColor: Qt.alpha(CortetsuDesign.colorOutlineVariant, 0.82)
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: CortetsuDesign.spacingSection
        spacing: CortetsuDesign.spacingSpacious

        RowLayout {
            Layout.fillWidth: true
            spacing: CortetsuDesign.spacingStandard
            Image {
                source: Quickshell.shellPath("assets/branding/cortetsu-mark.svg")
                sourceSize.width: 38
                sourceSize.height: 38
                Layout.preferredWidth: 38
                Layout.preferredHeight: 38
                fillMode: Image.PreserveAspectFit
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1
                CortetsuText { text: qsTr("Cortetsu"); textSize: CortetsuTypography.titleMediumPx; font.weight: Font.DemiBold }
                CortetsuText { text: qsTr("Desktop context"); textSize: CortetsuTypography.labelSmallPx; color: CortetsuDesign.colorOnSurfaceVariant }
            }
            ColumnLayout {
                spacing: 0
                Layout.alignment: Qt.AlignRight
                CortetsuText { text: `${Time.hourStr}:${Time.minuteStr}`; textSize: 30; font.weight: Font.DemiBold; Layout.alignment: Qt.AlignRight }
                CortetsuText { text: Qt.formatDate(Time.date, "dddd, d MMMM"); textSize: CortetsuTypography.bodySmallPx; color: CortetsuDesign.colorOnSurfaceVariant; Layout.alignment: Qt.AlignRight }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: CortetsuDesign.spacingStandard
            CortetsuSurface {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: 1.65
                radiusValue: CortetsuDesign.radiusLarge
                baseColor: Qt.alpha(CortetsuDesign.colorPrimaryContainer, 0.38)
                outlined: true
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: CortetsuDesign.spacingSpacious
                    spacing: CortetsuDesign.spacingCompact
                    CortetsuText { text: qsTr("NOW"); textSize: CortetsuTypography.labelSmallPx; color: CortetsuDesign.colorPrimary; font.weight: Font.DemiBold }
                    CortetsuText { Layout.fillWidth: true; text: Weather.city || qsTr("Your desktop"); textSize: 30; font.weight: Font.DemiBold; elide: Text.ElideRight }
                    CortetsuText { Layout.fillWidth: true; text: Weather.description || qsTr("A focused space for the next thing"); textSize: CortetsuTypography.bodyPx; color: CortetsuDesign.colorOnSurfaceVariant; elide: Text.ElideRight }
                    Item { Layout.fillHeight: true }
                    RowLayout {
                        Layout.fillWidth: true
                        CortetsuText { text: Weather.icon; textSize: 52; color: CortetsuDesign.colorWashi }
                        ColumnLayout {
                            Layout.fillWidth: true
                            CortetsuText { text: Weather.temp || "--"; textSize: 34; font.weight: Font.DemiBold }
                            CortetsuText { text: qsTr("Ambient conditions"); textSize: CortetsuTypography.labelSmallPx; color: CortetsuDesign.colorOnSurfaceVariant }
                        }
                    }
                }
            }
            CortetsuSurface {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: 1
                radiusValue: CortetsuDesign.radiusLarge
                baseColor: Qt.alpha(CortetsuDesign.colorSurfaceGlass, 0.82)
                outlined: true
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: CortetsuDesign.spacingSpacious
                    spacing: CortetsuDesign.spacingStandard
                    CortetsuText { text: qsTr("NOW PLAYING"); textSize: CortetsuTypography.labelSmallPx; color: CortetsuDesign.colorPrimary; font.weight: Font.DemiBold }
                    Item { Layout.preferredHeight: 32; Layout.fillWidth: true; CortetsuIcon { anchors.centerIn: parent; text: Players.active ? "music_note" : "radio"; iconSize: 32; color: CortetsuDesign.colorPrimary } }
                    CortetsuText { Layout.fillWidth: true; text: Players.active?.trackTitle || qsTr("No active media"); textSize: CortetsuTypography.titleMediumPx; font.weight: Font.DemiBold; elide: Text.ElideRight }
                    CortetsuText { Layout.fillWidth: true; text: Players.active?.trackArtist || qsTr("The shell is ready"); textSize: CortetsuTypography.bodySmallPx; color: CortetsuDesign.colorOnSurfaceVariant; elide: Text.ElideRight }
                    Item { Layout.fillHeight: true }
                    RowLayout {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: CortetsuDesign.spacingSpacious
                        CortetsuButton { compact: true; icon: "skip_previous"; label: ""; disabled: !Players.active; onClicked: Players.active?.previous() }
                        CortetsuButton { compact: true; icon: Players.active?.isPlaying ? "pause" : "play_arrow"; label: ""; active: true; disabled: !Players.active; onClicked: Players.active?.togglePlaying() }
                        CortetsuButton { compact: true; icon: "skip_next"; label: ""; disabled: !Players.active; onClicked: Players.active?.next() }
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: CortetsuDesign.spacingCompact
            CortetsuSectionHeader { title: qsTr("SYSTEM"); detail: qsTr("Live context"); Layout.preferredWidth: 140 }
            CortetsuListRow { Layout.fillWidth: true; icon: "memory"; title: qsTr("CPU %1%").arg(Math.round(Cpu.percentage * 100)); subtitle: qsTr("%1°C").arg(Math.round(Cpu.temperature)); selected: false }
            CortetsuListRow { Layout.fillWidth: true; icon: "data_usage"; title: qsTr("Memory %1%").arg(Math.round(Memory.percentage * 100)); subtitle: qsTr("%1 GB used").arg((Memory.used / 1048576).toFixed(1)); selected: false }
            CortetsuListRow { Layout.fillWidth: true; icon: "battery_5_bar"; title: UPower.displayDevice?.isLaptopBattery ? qsTr("Battery %1%").arg(Math.round(UPower.displayDevice.percentage * 100)) : qsTr("AC power"); subtitle: CortetsuNetwork.active?.ssid ?? qsTr("Network unavailable"); selected: false }
        }
    }

    Shortcut { sequence: "Escape"; onActivated: root.screenState.dashboard = false }
}
