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

// The dashboard: one fixed-size panel hanging from the top edge, with four
// zones (Inicio, Multimedia, Rendimiento, Clima) in the manner of caelestia.
// Every zone fills the same frame, so switching never moves or resizes the
// panel. Only the current zone is loaded, so telemetry samples only while
// its zone is on screen.
FocusScope {
    id: root

    required property var screenState
    required property var facePicker

    implicitWidth: 1040
    implicitHeight: 580

    readonly property bool open: screenState?.dashboard ?? false
    readonly property var tabs: [
        { key: "home", icon: "space_dashboard", label: qsTr("Inicio"), enabled: true },
        { key: "media", icon: "queue_music", label: qsTr("Multimedia"), enabled: CortetsuConfig.dashboard.showMedia },
        { key: "performance", icon: "speed", label: qsTr("Rendimiento"), enabled: CortetsuConfig.dashboard.showPerformance },
        { key: "weather", icon: "partly_cloudy_day", label: qsTr("Clima"), enabled: CortetsuConfig.dashboard.showWeather }
    ].filter(tab => tab.enabled)
    readonly property int current: Math.max(0, Math.min(tabs.length - 1, screenState?.dashboardTab ?? 0))
    readonly property string currentKey: tabs[current]?.key ?? "home"
    property int direction: 1

    function select(index: int): void {
        if (!screenState || index < 0 || index >= tabs.length || index === current)
            return;
        direction = index > current ? 1 : -1;
        screenState.dashboardTab = index;
    }

    function cycle(step: int): void {
        select((current + step + tabs.length) % tabs.length);
    }

    Keys.onLeftPressed: root.cycle(-1)
    Keys.onRightPressed: root.cycle(1)
    Keys.onTabPressed: root.cycle(1)
    Keys.onBacktabPressed: root.cycle(-1)
    Keys.onPressed: event => {
        const n = event.key - Qt.Key_1;
        if (n >= 0 && n < root.tabs.length) {
            root.select(n);
            event.accepted = true;
        }
    }

    // Panel body: the same material as the BottomHub islands, opaque enough
    // to read on any wallpaper.
    Rectangle {
        anchors.fill: parent
        radius: CortetsuDesign.radiusSurface
        color: Qt.alpha(CortetsuDesign.colorSumi, 0.94)
        border.width: 1
        border.color: Qt.alpha(CortetsuDesign.colorWashi, 0.08)
    }

    // Static brand mark at the panel's corner, level with the zone switcher.
    RowLayout {
        anchors.left: parent.left
        anchors.leftMargin: CortetsuDesign.spacingSpacious
        anchors.verticalCenter: tabBar.verticalCenter
        CortetsuEvolvingMark {
            phase: "Ascended"
            animated: false
            monochrome: true
            monochromeColor: CortetsuDesign.colorWashi
            opacity: 0.85
            Layout.preferredWidth: 38
            Layout.preferredHeight: 38
        }
    }

    // Zone switcher: a segmented pill with a sliding highlight.
    Rectangle {
        id: tabBar
        anchors.top: parent.top
        anchors.topMargin: CortetsuDesign.spacingComfortable
        anchors.horizontalCenter: parent.horizontalCenter
        width: tabRow.width + 8
        height: 44
        radius: height / 2
        color: Qt.alpha(CortetsuDesign.colorSurfaceHigh, 0.7)

        Rectangle {
            readonly property Item target: tabRepeater.itemAt(root.current)
            x: 4 + (target?.x ?? 0)
            y: 4
            width: target?.width ?? 0
            height: parent.height - 8
            radius: height / 2
            color: CortetsuDesign.colorPrimary
            // design-lint: allow motion-layout-property: the highlight travels to the chosen zone
            Behavior on x { NumberAnimation { duration: CortetsuDesign.motionStandardMs; easing.type: Easing.OutCubic } }
            // design-lint: allow motion-layout-property: the highlight takes the chosen zone's width
            Behavior on width { NumberAnimation { duration: CortetsuDesign.motionStandardMs; easing.type: Easing.OutCubic } }
        }

        Row {
            id: tabRow
            x: 4
            anchors.verticalCenter: parent.verticalCenter

            Repeater {
                id: tabRepeater
                model: root.tabs

                Item {
                    id: tab
                    required property var modelData
                    required property int index
                    readonly property bool selected: index === root.current
                    width: tabContent.implicitWidth + 32
                    height: 36

                    Row {
                        id: tabContent
                        anchors.centerIn: parent
                        spacing: 6
                        CortetsuIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            text: tab.modelData.icon
                            iconSize: CortetsuTypography.iconSmallPx
                            fill: tab.selected ? 1 : 0
                            color: tab.selected ? CortetsuDesign.colorOnPrimary : CortetsuDesign.colorOnSurfaceVariant
                        }
                        CortetsuText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: tab.modelData.label
                            font.weight: tab.selected ? Font.DemiBold : Font.Normal
                            color: tab.selected ? CortetsuDesign.colorOnPrimary : CortetsuDesign.colorOnSurfaceVariant
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.select(tab.index)
                    }
                }
            }
        }
    }

    // The current zone. A switch slides the new one in from the side it
    // comes from; the frame itself never changes size.
    Item {
        id: stage
        anchors.top: tabBar.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: CortetsuDesign.spacingComfortable
        anchors.topMargin: CortetsuDesign.spacingComfortable
        clip: true

        Loader {
            id: zone
            width: stage.width
            height: stage.height
            active: root.open
            sourceComponent: root.currentKey === "media" ? mediaZone
                : root.currentKey === "performance" ? performanceZone
                : root.currentKey === "weather" ? weatherZone
                : homeZone
            onLoaded: enter.restart()
        }

        ParallelAnimation {
            id: enter
            NumberAnimation { target: zone; property: "x"; from: 28 * root.direction; to: 0; duration: CortetsuDesign.motionStandardMs * 1.3; easing.type: Easing.OutQuint }
            NumberAnimation { target: zone; property: "opacity"; from: 0; to: 1; duration: CortetsuDesign.motionStandardMs; easing.type: Easing.OutCubic }
        }
    }

    // ---------------------------------------------------------------- zones

    Component {
        id: homeZone

        RowLayout {
            spacing: CortetsuDesign.spacingStandard

            ColumnLayout {
                Layout.preferredWidth: 300
                Layout.maximumWidth: 300
                Layout.fillWidth: false
                Layout.fillHeight: true
                spacing: CortetsuDesign.spacingStandard

                DashCard {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 190
                    tint: CortetsuDesign.colorPrimaryContainer

                    ColumnLayout {
                        anchors.left: parent.left
                        anchors.bottom: parent.bottom
                        anchors.margins: CortetsuDesign.spacingSpacious
                        spacing: 2
                        CortetsuText {
                            text: `${Time.hourStr}:${Time.minuteStr}`
                            textSize: CortetsuTypography.displayHeroPx
                            font.weight: Font.DemiBold
                            color: CortetsuDesign.colorOnPrimaryContainer
                        }
                        CortetsuText {
                            text: CortetsuRegional.formatDate(Time.date, "longDay", true)
                            color: CortetsuDesign.colorOnPrimaryContainer
                            opacity: 0.8
                        }
                    }
                }

                DashCard {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    DashWeatherSummary { anchors.fill: parent; anchors.margins: CortetsuDesign.spacingSpacious }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: CortetsuDesign.spacingStandard

                Today {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredHeight: 1.2
                    screenState: root.screenState
                }

                Focus {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredHeight: 0.8
                    screenState: root.screenState
                }
            }

            DashCard {
                Layout.preferredWidth: 290
                Layout.maximumWidth: 290
                Layout.fillHeight: true
                visible: CortetsuConfig.dashboard.showMedia
                DashMediaPlayer { anchors.fill: parent; anchors.margins: CortetsuDesign.spacingSpacious; compact: true; dashboardOpen: root.open }
            }
        }
    }

    Component {
        id: mediaZone

        DashCard {
            DashMediaPlayer { anchors.fill: parent; anchors.margins: CortetsuDesign.spacingSection; compact: false; dashboardOpen: root.open }
        }
    }

    Component {
        id: performanceZone

        GridLayout {
            columns: 4
            rowSpacing: CortetsuDesign.spacingStandard
            columnSpacing: CortetsuDesign.spacingStandard

            Component.onCompleted: { Cpu.consumers += 1; Gpu.consumers += 1; Memory.consumers += 1; Storage.consumers += 1; NetworkUsage.consumers += 1; }
            Component.onDestruction: { Cpu.consumers -= 1; Gpu.consumers -= 1; Memory.consumers -= 1; Storage.consumers -= 1; NetworkUsage.consumers -= 1; }

            DashGauge {
                visible: CortetsuConfig.dashboard.performance.showCpu
                icon: "memory"; label: qsTr("CPU"); value: Cpu.percentage
                detail: Cpu.temperature > 0 ? qsTr("%1 °C").arg(Math.round(Cpu.temperature)) : qsTr("Sin sensor")
            }
            DashGauge {
                visible: CortetsuConfig.dashboard.performance.showGpu
                icon: "developer_board"; label: qsTr("GPU")
                value: Gpu.type === Gpu.noneType ? 0 : Gpu.percentage
                detail: Gpu.type === Gpu.noneType
                    ? (Gpu.dgpuAsleep ? qsTr("En reposo") : qsTr("No disponible"))
                    : qsTr("%1 °C").arg(Math.round(Gpu.temperature))
            }
            DashGauge {
                visible: CortetsuConfig.dashboard.performance.showMemory
                icon: "data_usage"; label: qsTr("Memoria"); value: Memory.percentage
                detail: qsTr("%1 de %2 GiB").arg((Memory.used / 1048576).toFixed(1)).arg((Memory.total / 1048576).toFixed(1))
            }
            DashGauge {
                visible: CortetsuConfig.dashboard.performance.showStorage
                icon: "storage"; label: qsTr("Disco"); value: Storage.percentage
                detail: Storage.primaryDisk?.mount ?? qsTr("Volumen principal")
            }

            DashCard {
                Layout.columnSpan: 2
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: CortetsuConfig.dashboard.performance.showNetwork
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: CortetsuDesign.spacingSpacious
                    spacing: CortetsuDesign.spacingCompact
                    DashLabel { text: qsTr("RED") }
                    CortetsuText {
                        text: CortetsuNetwork.activeEthernet ? qsTr("Ethernet") : CortetsuNetwork.active?.ssid ?? qsTr("Sin conexión")
                        textSize: CortetsuTypography.titleMediumPx
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                    Item { Layout.fillHeight: true }
                    RowLayout {
                        spacing: CortetsuDesign.spacingSection
                        DashRate { icon: "arrow_downward"; rate: NetworkUsage.downloadSpeed; label: qsTr("Bajada") }
                        DashRate { icon: "arrow_upward"; rate: NetworkUsage.uploadSpeed; label: qsTr("Subida") }
                    }
                }
            }

            DashCard {
                Layout.columnSpan: 2
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: CortetsuConfig.dashboard.performance.showBattery
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: CortetsuDesign.spacingSpacious
                    spacing: CortetsuDesign.spacingCompact
                    DashLabel { text: qsTr("ENERGÍA") }
                    CortetsuText {
                        text: CortetsuPower.hasBattery ? qsTr("%1 %").arg(CortetsuPower.percent) : qsTr("Corriente externa")
                        textSize: CortetsuTypography.titleMediumPx
                        font.weight: Font.DemiBold
                    }
                    CortetsuText {
                        text: !CortetsuPower.laptopBattery ? qsTr("Sin batería")
                            : CortetsuPower.charging ? qsTr("Cargando")
                            : CortetsuPower.onBattery ? qsTr("Con batería") : qsTr("Corriente externa")
                        color: CortetsuDesign.colorOnSurfaceVariant
                    }
                    Item { Layout.fillHeight: true }
                    CortetsuProgressBar {
                        Layout.fillWidth: true
                        visible: CortetsuPower.hasBattery
                        value: CortetsuPower.percent / 100
                        barHeight: 8
                    }
                }
            }
        }
    }

    Component {
        id: weatherZone

        DashCard {
            CortetsuStateMessage {
                anchors.centerIn: parent
                width: parent.width - CortetsuDesign.spacingSection * 2
                visible: !Weather.cc
                icon: "cloud_off"
                title: qsTr("Tiempo no disponible")
                detail: qsTr("Aparece cuando hay conexión y una ubicación en Ajustes")
            }

            ColumnLayout {
                visible: !!Weather.cc
                anchors.fill: parent
                anchors.margins: CortetsuDesign.spacingSection
                spacing: CortetsuDesign.spacingSpacious

                RowLayout {
                    Layout.fillWidth: true
                    spacing: CortetsuDesign.spacingSection
                    CortetsuText {
                        text: Weather.icon
                        textSize: CortetsuTypography.iconHeroPx
                        color: CortetsuDesign.colorPrimary
                    }
                    ColumnLayout {
                        spacing: 0
                        CortetsuText { text: Weather.temp; textSize: CortetsuTypography.displayHeroPx; font.weight: Font.DemiBold }
                        CortetsuText { text: Weather.description; color: CortetsuDesign.colorOnSurfaceVariant }
                    }
                    Item { Layout.fillWidth: true }
                    ColumnLayout {
                        spacing: CortetsuDesign.spacingCompact
                        CortetsuText { Layout.alignment: Qt.AlignRight; text: Weather.city; textSize: CortetsuTypography.titleMediumPx; font.weight: Font.DemiBold }
                        CortetsuText { Layout.alignment: Qt.AlignRight; text: qsTr("Sensación %1 · Humedad %2 %").arg(Weather.feelsLike).arg(Weather.humidity); color: CortetsuDesign.colorOnSurfaceVariant }
                        CortetsuText { Layout.alignment: Qt.AlignRight; text: qsTr("Amanece %1 · Anochece %2").arg(Weather.sunrise).arg(Weather.sunset); color: CortetsuDesign.colorOnSurfaceVariant }
                    }
                }

                DashLabel { text: qsTr("PRÓXIMAS HORAS") }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: CortetsuDesign.spacingCompact
                    Repeater {
                        model: (Weather.hourlyForecast ?? []).slice(0, 8)
                        Rectangle {
                            id: hour
                            required property var modelData
                            Layout.fillWidth: true
                            Layout.preferredHeight: 104
                            radius: CortetsuDesign.radiusMedium
                            color: Qt.alpha(CortetsuDesign.colorSurfaceHigh, 0.6)
                            Column {
                                anchors.centerIn: parent
                                spacing: 4
                                CortetsuText { anchors.horizontalCenter: parent.horizontalCenter; text: `${String(hour.modelData.hour).padStart(2, "0")}:00`; color: CortetsuDesign.colorOnSurfaceVariant; textSize: CortetsuTypography.labelMediumPx }
                                CortetsuText { anchors.horizontalCenter: parent.horizontalCenter; text: hour.modelData.icon; textSize: CortetsuTypography.iconLargePx }
                                CortetsuText { anchors.horizontalCenter: parent.horizontalCenter; text: CortetsuRegional.formatTemperature(hour.modelData.tempC); font.weight: Font.DemiBold }
                            }
                        }
                    }
                }

                DashLabel { text: qsTr("PRÓXIMOS DÍAS") }
                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: CortetsuDesign.spacingCompact
                    Repeater {
                        model: (Weather.forecast ?? []).slice(0, 7)
                        Rectangle {
                            id: day
                            required property var modelData
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            radius: CortetsuDesign.radiusMedium
                            color: Qt.alpha(CortetsuDesign.colorSurfaceHigh, 0.6)
                            Column {
                                anchors.centerIn: parent
                                spacing: 4
                                CortetsuText { anchors.horizontalCenter: parent.horizontalCenter; text: CortetsuRegional.formatDate(new Date(day.modelData.date), "weekdayDay", true); color: CortetsuDesign.colorOnSurfaceVariant; textSize: CortetsuTypography.labelMediumPx }
                                CortetsuText { anchors.horizontalCenter: parent.horizontalCenter; text: day.modelData.icon; textSize: CortetsuTypography.iconLargePx }
                                CortetsuText { anchors.horizontalCenter: parent.horizontalCenter; text: `${CortetsuRegional.formatTemperature(day.modelData.maxTempC)} / ${CortetsuRegional.formatTemperature(day.modelData.minTempC)}`; textSize: CortetsuTypography.bodySmallPx }
                            }
                        }
                    }
                }
            }
        }
    }

}
