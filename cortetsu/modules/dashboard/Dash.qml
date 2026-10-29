pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../components"
import "../../services"
import "../../utils"
import ".."
import "../../theme"
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
        ? qsTr("Corriente externa")
        : batteryCharging
            ? qsTr("Cargando")
            : CortetsuPower.onBattery
                ? qsTr("Con batería")
                : qsTr("Corriente externa")
    readonly property string networkTitle: CortetsuNetwork.connecting
        ? qsTr("Conectando")
        : CortetsuNetwork.activeEthernet
            ? qsTr("Ethernet")
            : CortetsuNetwork.active?.ssid ?? qsTr("Sin conexión")
    readonly property string networkSubtitle: CortetsuNetwork.connecting
        ? qsTr("Estableciendo enlace")
        : CortetsuNetwork.activeEthernet
            ? qsTr("Conexión por cable")
            : CortetsuNetwork.active
                ? qsTr("Señal %1 %").arg(Math.round(CortetsuNetwork.active.strength ?? 0))
                : qsTr("Sin conexión de red")
    // Dashboard composition is controlled by the persisted product settings.
    // Each flag gates the corresponding Loader below, so disabled modules do
    // not keep rendering or subscribing to their live provider.
    readonly property bool showWeather: CortetsuConfig.dashboard.showWeather
    readonly property bool showMedia: CortetsuConfig.dashboard.showMedia
    // The system rail exists only while the Dashboard is open, so its
    // telemetry services stop sampling when it closes.
    readonly property bool open: screenState?.dashboard ?? false
    readonly property bool showPerformance: open && CortetsuConfig.dashboard.showPerformance
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

            CortetsuText {
                Layout.fillWidth: true
                text: "Cortetsu"
                textSize: CortetsuTypography.titleMediumPx
                font.weight: Font.DemiBold
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
                    text: CortetsuRegional.formatDate(Time.date, "longDay", true)
                    textSize: CortetsuTypography.bodySmallPx
                    color: CortetsuDesign.colorOnSurfaceVariant
                    Layout.alignment: Qt.AlignRight
                }
            }

            CortetsuButton {
                compact: true
                icon: "close"
                label: ""
                tooltipText: qsTr("Cerrar panel")
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

            CortetsuText {
                id: weatherLabel
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.margins: CortetsuDesign.spacingSpacious
                text: qsTr("TIEMPO")
                textSize: CortetsuTypography.labelSmallPx
                color: CortetsuDesign.colorOnSurfaceVariant
                font.weight: Font.DemiBold
            }

            // Without a reading there is no temperature to show, not "--".
            CortetsuStateMessage {
                anchors.centerIn: parent
                width: parent.width - CortetsuDesign.spacingSpacious * 2
                visible: !Weather.cc
                icon: "cloud_off"
                title: qsTr("Tiempo no disponible")
                detail: qsTr("Aparece cuando hay conexión y una ubicación en Ajustes")
            }

            ColumnLayout {
                visible: !!Weather.cc
                anchors.fill: parent
                anchors.margins: CortetsuDesign.spacingSpacious
                anchors.topMargin: CortetsuDesign.spacingSpacious * 2 + weatherLabel.height
                spacing: CortetsuDesign.spacingCompact

                CortetsuText {
                    Layout.fillWidth: true
                    visible: text.length > 0
                    text: Weather.city
                    textSize: CortetsuTypography.displayClockPx
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }

                CortetsuText {
                    Layout.fillWidth: true
                    text: Weather.cc?.weatherDesc ?? ""
                    textSize: CortetsuTypography.bodyPx
                    color: CortetsuDesign.colorOnSurfaceVariant
                    elide: Text.ElideRight
                }

                Item { Layout.fillHeight: true }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: CortetsuDesign.spacingStandard

                    CortetsuText {
                        text: Weather.icon
                        textSize: CortetsuTypography.displayHeroPx
                        color: CortetsuDesign.colorWashi
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        CortetsuText {
                            text: Weather.temp
                            textSize: CortetsuTypography.displayLargePx
                            font.weight: Font.DemiBold
                        }
                        CortetsuText {
                            text: qsTr("Sensación %1").arg(Weather.feelsLike)
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

            CortetsuText {
                id: mediaLabel
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.margins: CortetsuDesign.spacingSpacious
                text: qsTr("REPRODUCIENDO")
                textSize: CortetsuTypography.labelSmallPx
                color: CortetsuDesign.colorOnSurfaceVariant
                font.weight: Font.DemiBold
            }

            CortetsuStateMessage {
                anchors.centerIn: parent
                width: parent.width - CortetsuDesign.spacingSpacious * 2
                visible: !Players.active
                icon: "music_off"
                title: qsTr("Nada en reproducción")
                detail: qsTr("Los controles aparecen al reproducir en una app con MPRIS")
            }

            ColumnLayout {
                visible: !!Players.active
                anchors.fill: parent
                anchors.margins: CortetsuDesign.spacingSpacious
                anchors.topMargin: CortetsuDesign.spacingSpacious * 2 + mediaLabel.height
                spacing: CortetsuDesign.spacingStandard

                CortetsuText {
                    Layout.fillWidth: true
                    text: Players.active?.trackTitle || qsTr("Pista sin título")
                    textSize: CortetsuTypography.titleMediumPx
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                    maximumLineCount: 2
                    wrapMode: Text.Wrap
                }

                CortetsuText {
                    Layout.fillWidth: true
                    visible: text.length > 0
                    text: Players.active?.trackArtist ?? ""
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
                        tooltipText: qsTr("Pista anterior")
                        onClicked: Players.active?.previous()
                    }
                    CortetsuButton {
                        compact: true
                        icon: Players.active?.isPlaying ? "pause" : "play_arrow"
                        label: ""
                        tooltipText: Players.active?.isPlaying ? qsTr("Pausar") : qsTr("Reproducir")
                        active: true
                        onClicked: Players.active?.togglePlaying()
                    }
                    CortetsuButton {
                        compact: true
                        icon: "skip_next"
                        label: ""
                        tooltipText: qsTr("Pista siguiente")
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

            CortetsuText {
                text: qsTr("SISTEMA")
                textSize: CortetsuTypography.labelSmallPx
                color: CortetsuDesign.colorOnSurfaceVariant
                font.weight: Font.DemiBold
                Layout.preferredWidth: 88
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
        SystemFact {
            Component.onCompleted: Cpu.consumers += 1
            Component.onDestruction: Cpu.consumers -= 1
            icon: "memory"
            title: qsTr("CPU %1 %").arg(Math.round(Cpu.percentage * 100))
            subtitle: Cpu.temperature > 0 ? qsTr("%1 °C").arg(Math.round(Cpu.temperature)) : qsTr("Sin sensor de temperatura")
        }
    }

    Component {
        id: gpuSummary
        SystemFact {
            Component.onCompleted: Gpu.consumers += 1
            Component.onDestruction: Gpu.consumers -= 1
            icon: "developer_board"
            title: Gpu.name || qsTr("GPU %1 %").arg(Math.round(Gpu.percentage * 100))
            subtitle: Gpu.type === Gpu.noneType
                ? (Gpu.dgpuAsleep ? qsTr("En reposo") : qsTr("No disponible"))
                : qsTr("%1 % · %2 °C").arg(Math.round(Gpu.percentage * 100)).arg(Math.round(Gpu.temperature))
                    + (Gpu.dgpuAsleep ? qsTr(" · dGPU en reposo") : "")
        }
    }

    Component {
        id: memorySummary
        SystemFact {
            Component.onCompleted: Memory.consumers += 1
            Component.onDestruction: Memory.consumers -= 1
            icon: "data_usage"
            title: qsTr("Memoria %1 %").arg(Math.round(Memory.percentage * 100))
            subtitle: qsTr("%1 GiB en uso").arg((Memory.used / 1048576).toFixed(1))
        }
    }

    Component {
        id: storageSummary
        SystemFact {
            Component.onCompleted: Storage.consumers += 1
            Component.onDestruction: Storage.consumers -= 1
            icon: "storage"
            title: qsTr("Disco %1 %").arg(Math.round(Storage.percentage * 100))
            subtitle: Storage.primaryDisk?.mount ?? qsTr("Volumen principal")
        }
    }

    Component {
        id: batterySummary
        SystemFact {
            icon: CortetsuPower.hasBattery ? Icons.getBatteryIcon(CortetsuPower.value, root.batteryCharging) : "power"
            title: CortetsuPower.hasBattery ? qsTr("Batería %1 %").arg(root.batteryPercent) : qsTr("Energía")
            subtitle: root.batterySubtitle
        }
    }

    Component {
        id: networkSummary
        SystemFact {
            icon: CortetsuNetwork.activeEthernet ? "cable" : (CortetsuNetwork.connecting ? "sync" : (CortetsuNetwork.active ? "wifi" : "wifi_off"))
            title: root.networkTitle
            subtitle: root.networkSubtitle
        }
    }
}
