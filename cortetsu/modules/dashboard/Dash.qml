pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
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

    readonly property bool batteryCharging: CortetsuPower.charging
    readonly property int batteryPercent: CortetsuPower.percent
    readonly property string batterySubtitle: !CortetsuPower.laptopBattery
        ? qsTr("External power")
        : batteryCharging
            ? qsTr("Charging")
            : CortetsuPower.onBattery
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
    // Dashboard composition is controlled by the persisted product settings.
    // Each flag gates the corresponding Loader below, so disabled modules do
    // not keep rendering or subscribing to their live provider.
    readonly property bool showWeather: CortetsuConfig.dashboard.showWeather
    readonly property bool showMedia: CortetsuConfig.dashboard.showMedia
    readonly property bool showPerformance: CortetsuConfig.dashboard.showPerformance
    readonly property bool showCpu: showPerformance && CortetsuConfig.dashboard.performance.showCpu
    readonly property bool showGpu: showPerformance && CortetsuConfig.dashboard.performance.showGpu
    readonly property bool showMemory: showPerformance && CortetsuConfig.dashboard.performance.showMemory
    readonly property bool showStorage: showPerformance && CortetsuConfig.dashboard.performance.showStorage
    readonly property bool showNetwork: showPerformance && CortetsuConfig.dashboard.performance.showNetwork
    readonly property bool showBattery: showPerformance && CortetsuConfig.dashboard.performance.showBattery

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

            Loader {
                active: root.showWeather
                visible: active
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: root.showWeather ? 1.35 : 0
                sourceComponent: weatherCard
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

            Loader {
                active: root.showMedia
                visible: active
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: root.showMedia ? 0.95 : 0
                sourceComponent: mediaCard
            }
        }

        Loader {
            active: root.showPerformance
            visible: active
            Layout.fillWidth: true
            Layout.preferredHeight: active ? 52 : 0
            sourceComponent: systemSummary
        }
    }

    Component {
        id: weatherCard

        CortetsuSurface {
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
    }

    Component {
        id: mediaCard

        CortetsuSurface {
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

    Component {
        id: systemSummary

        RowLayout {
            spacing: CortetsuDesign.spacingCompact

            CortetsuSectionHeader {
                title: qsTr("SYSTEM")
                detail: qsTr("Live context")
                Layout.preferredWidth: 118
            }

            Loader {
                active: root.showCpu
                visible: active
                Layout.fillWidth: true
                sourceComponent: cpuSummary
            }
            Loader {
                active: root.showGpu
                visible: active
                Layout.fillWidth: true
                sourceComponent: gpuSummary
            }
            Loader {
                active: root.showMemory
                visible: active
                Layout.fillWidth: true
                sourceComponent: memorySummary
            }
            Loader {
                active: root.showStorage
                visible: active
                Layout.fillWidth: true
                sourceComponent: storageSummary
            }
            Loader {
                active: root.showBattery
                visible: active
                Layout.fillWidth: true
                sourceComponent: batterySummary
            }
            Loader {
                active: root.showNetwork
                visible: active
                Layout.fillWidth: true
                sourceComponent: networkSummary
            }
        }
    }

    Component {
        id: cpuSummary
        CortetsuListRow {
            icon: "memory"
            title: qsTr("CPU %1%").arg(Math.round(Cpu.percentage * 100))
            subtitle: qsTr("%1°C").arg(Math.round(Cpu.temperature))
            selected: false
        }
    }

    Component {
        id: gpuSummary
        CortetsuListRow {
            icon: "developer_board"
            title: Gpu.name || qsTr("GPU %1%").arg(Math.round(Gpu.percentage * 100))
            subtitle: Gpu.name ? qsTr("%1% · %2°C").arg(Math.round(Gpu.percentage * 100)).arg(Math.round(Gpu.temperature)) : qsTr("Unavailable")
            selected: false
        }
    }

    Component {
        id: memorySummary
        CortetsuListRow {
            icon: "data_usage"
            title: qsTr("Memory %1%").arg(Math.round(Memory.percentage * 100))
            subtitle: qsTr("%1 GB used").arg((Memory.used / 1048576).toFixed(1))
            selected: false
        }
    }

    Component {
        id: storageSummary
        CortetsuListRow {
            icon: "storage"
            title: qsTr("Storage %1%").arg(Math.round(Storage.percentage * 100))
            subtitle: Storage.primaryDisk?.mount ?? qsTr("Primary volume")
            selected: false
        }
    }

    Component {
        id: batterySummary
        CortetsuListRow {
            icon: CortetsuPower.hasBattery ? Icons.getBatteryIcon(CortetsuPower.value, root.batteryCharging) : "power"
            title: CortetsuPower.hasBattery ? qsTr("Battery %1%").arg(root.batteryPercent) : qsTr("Power")
            subtitle: root.batterySubtitle
            selected: false
        }
    }

    Component {
        id: networkSummary
        CortetsuListRow {
            icon: CortetsuNetwork.activeEthernet ? "cable" : (CortetsuNetwork.connecting ? "sync" : (CortetsuNetwork.active ? "wifi" : "wifi_off"))
            title: root.networkTitle
            subtitle: root.networkSubtitle
            selected: false
        }
    }

    Shortcut {
        sequence: "Escape"
        onActivated: root.screenState.dashboard = false
    }
}
