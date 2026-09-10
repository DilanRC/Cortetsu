pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.UPower
import "../../components"
import "../../services"
import "../../utils"
import ".."
import "../CortetsuDesign.js" as CortetsuDesign
import "../CortetsuTypography.js" as CortetsuTypography

Item {
    id: root
    required property var screenState
    required property var facePicker
    implicitWidth: 1180
    implicitHeight: 620

    readonly property bool batteryCharging: [
        UPowerDeviceState.Charging,
        UPowerDeviceState.FullyCharged,
        UPowerDeviceState.PendingCharge
    ].includes(UPower.displayDevice.state)
    readonly property int batteryPercent: Math.round(UPower.displayDevice.percentage * 100)
    readonly property string batterySubtitle: !UPower.displayDevice?.isLaptopBattery
        ? qsTr("External power")
        : batteryCharging
            ? qsTr("Charging")
            : UPower.onBattery
                ? qsTr("On battery")
                : qsTr("External power")
    readonly property string networkTitle: CortetsuNetwork.connecting
        ? qsTr("Connecting")
        : CortetsuNetwork.activeEthernet
            ? qsTr("Ethernet")
            : CortetsuNetwork.active?.ssid ?? qsTr("Offline")
    readonly property string networkSubtitle: CortetsuNetwork.connecting
        ? qsTr("Negotiating link")
        : CortetsuNetwork.activeEthernet
            ? qsTr("Wired connection")
            : CortetsuNetwork.active
                ? qsTr("Signal %1%").arg(Math.round(CortetsuNetwork.active.strength ?? 0))
                : qsTr("No network connection")

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

            CortetsuEvolvingMark {
                phase: "Ascended"
                animated: false
                monochrome: true
                monochromeColor: CortetsuDesign.colorWashi
                Layout.preferredWidth: 38
                Layout.preferredHeight: 38
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1
                CortetsuText {
                    text: qsTr("Cortetsu")
                    textSize: CortetsuTypography.titleMediumPx
                    font.weight: Font.DemiBold
                }
                CortetsuText {
                    text: qsTr("Desktop context")
                    textSize: CortetsuTypography.labelSmallPx
                    color: CortetsuDesign.colorOnSurfaceVariant
                }
            }

            ColumnLayout {
                spacing: 0
                Layout.alignment: Qt.AlignRight
                CortetsuText {
                    text: `${Time.hourStr}:${Time.minuteStr}`
                    textSize: CortetsuTypography.displayClockPx
                    font.weight: Font.DemiBold
                    Layout.alignment: Qt.AlignRight
                }
                CortetsuText {
                    text: Qt.formatDate(Time.date, "dddd, d MMMM")
                    textSize: CortetsuTypography.bodySmallPx
                    color: CortetsuDesign.colorOnSurfaceVariant
                    Layout.alignment: Qt.AlignRight
                }
            }

            CortetsuButton {
                compact: true
                icon: "close"
                label: ""
                tooltipText: qsTr("Close Dashboard")
                onClicked: root.screenState.dashboard = false
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: CortetsuDesign.spacingStandard

            CortetsuSurface {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: 1.35
                radiusValue: CortetsuDesign.radiusLarge
                baseColor: Qt.alpha(CortetsuDesign.colorPrimaryContainer, 0.38)
                outlined: true

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: CortetsuDesign.spacingSpacious
                    spacing: CortetsuDesign.spacingCompact

                    CortetsuText {
                        text: qsTr("NOW")
                        textSize: CortetsuTypography.labelSmallPx
                        color: CortetsuDesign.colorPrimary
                        font.weight: Font.DemiBold
                    }

                    CortetsuText {
                        Layout.fillWidth: true
                        text: Weather.city || qsTr("Your desktop")
                        textSize: CortetsuTypography.displayClockPx
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }

                    CortetsuText {
                        Layout.fillWidth: true
                        text: Weather.description || qsTr("A focused space for the next thing")
                        textSize: CortetsuTypography.bodyPx
                        color: CortetsuDesign.colorOnSurfaceVariant
                        elide: Text.ElideRight
                    }

                    Item { Layout.fillHeight: true }

                    RowLayout {
                        Layout.fillWidth: true

                        CortetsuText {
                            text: Weather.icon
                            textSize: CortetsuTypography.displayHeroPx
                            color: CortetsuDesign.colorWashi
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            CortetsuText {
                                text: Weather.temp || "--"
                                textSize: CortetsuTypography.displayLargePx
                                font.weight: Font.DemiBold
                            }
                            CortetsuText {
                                text: qsTr("Ambient conditions")
                                textSize: CortetsuTypography.labelSmallPx
                                color: CortetsuDesign.colorOnSurfaceVariant
                            }
                        }
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: 1.1
                spacing: CortetsuDesign.spacingStandard

                Today {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredHeight: 1.15
                    screenState: root.screenState
                }

                Focus {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredHeight: 0.85
                    screenState: root.screenState
                }
            }

            CortetsuSurface {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: 0.95
                radiusValue: CortetsuDesign.radiusLarge
                baseColor: Qt.alpha(CortetsuDesign.colorSurfaceGlass, 0.82)
                outlined: true

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: CortetsuDesign.spacingSpacious
                    spacing: CortetsuDesign.spacingStandard

                    CortetsuText {
                        text: qsTr("NOW PLAYING")
                        textSize: CortetsuTypography.labelSmallPx
                        color: CortetsuDesign.colorPrimary
                        font.weight: Font.DemiBold
                    }

                    Item {
                        Layout.preferredHeight: 32
                        Layout.fillWidth: true
                        CortetsuIcon {
                            anchors.centerIn: parent
                            text: Players.active ? "music_note" : "radio"
                            iconSize: CortetsuTypography.iconFeaturePx
                            color: CortetsuDesign.colorPrimary
                        }
                    }

                    CortetsuText {
                        Layout.fillWidth: true
                        text: Players.active?.trackTitle || qsTr("No active media")
                        textSize: CortetsuTypography.titleMediumPx
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }

                    CortetsuText {
                        Layout.fillWidth: true
                        text: Players.active?.trackArtist || qsTr("The shell is ready")
                        textSize: CortetsuTypography.bodySmallPx
                        color: CortetsuDesign.colorOnSurfaceVariant
                        elide: Text.ElideRight
                    }

                    Item { Layout.fillHeight: true }

                    RowLayout {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: CortetsuDesign.spacingSpacious
                        CortetsuButton {
                            compact: true
                            icon: "skip_previous"
                            label: ""
                            tooltipText: qsTr("Previous track")
                            disabled: !Players.active
                            onClicked: Players.active?.previous()
                        }
                        CortetsuButton {
                            compact: true
                            icon: Players.active?.isPlaying ? "pause" : "play_arrow"
                            label: ""
                            tooltipText: Players.active?.isPlaying ? qsTr("Pause") : qsTr("Play")
                            active: true
                            disabled: !Players.active
                            onClicked: Players.active?.togglePlaying()
                        }
                        CortetsuButton {
                            compact: true
                            icon: "skip_next"
                            label: ""
                            tooltipText: qsTr("Next track")
                            disabled: !Players.active
                            onClicked: Players.active?.next()
                        }
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: CortetsuDesign.spacingCompact

            CortetsuSectionHeader {
                title: qsTr("SYSTEM")
                detail: qsTr("Live context")
                Layout.preferredWidth: 118
            }

            CortetsuListRow {
                Layout.fillWidth: true
                icon: "memory"
                title: qsTr("CPU %1%").arg(Math.round(Cpu.percentage * 100))
                subtitle: qsTr("%1°C").arg(Math.round(Cpu.temperature))
                selected: false
            }

            CortetsuListRow {
                Layout.fillWidth: true
                icon: "data_usage"
                title: qsTr("Memory %1%").arg(Math.round(Memory.percentage * 100))
                subtitle: qsTr("%1 GB used").arg((Memory.used / 1048576).toFixed(1))
                selected: false
            }

            CortetsuListRow {
                Layout.fillWidth: true
                icon: Icons.getBatteryIcon(UPower.displayDevice?.percentage ?? 0, root.batteryCharging)
                title: UPower.displayDevice?.isLaptopBattery ? qsTr("Battery %1%").arg(root.batteryPercent) : qsTr("Power")
                subtitle: root.batterySubtitle
                selected: false
            }

            CortetsuListRow {
                Layout.fillWidth: true
                icon: CortetsuNetwork.activeEthernet ? "cable" : (CortetsuNetwork.connecting ? "sync" : (CortetsuNetwork.active ? "wifi" : "wifi_off"))
                title: root.networkTitle
                subtitle: root.networkSubtitle
                selected: false
            }
        }
    }

    Shortcut {
        sequence: "Escape"
        onActivated: root.screenState.dashboard = false
    }
}
