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

// The dashboard: one fixed-size sheet hanging from the top edge, with four
// zones (Inicio, Multimedia, Rendimiento, Clima). It speaks the ink
// language: sumi ground washed with the wallpaper colour and grained like
// paper, a vermillion seal for the zone you are in, serif ink for the big
// moments, and space instead of cards. Every zone fills the same frame, so
// switching never moves or resizes the sheet. Only the current zone is
// loaded, so telemetry and lyrics run only while their zone is on screen.
FocusScope {
    id: root

    required property var screenState
    required property var facePicker

    implicitWidth: 1040
    implicitHeight: 580

    readonly property bool open: screenState?.dashboard ?? false
    readonly property var tabs: [
        { key: "home", glyph: "今", label: qsTr("Inicio"), enabled: true },
        { key: "media", glyph: "音", label: qsTr("Multimedia"), enabled: CortetsuConfig.dashboard.showMedia },
        { key: "performance", glyph: "力", label: qsTr("Rendimiento"), enabled: CortetsuConfig.dashboard.showPerformance },
        { key: "weather", glyph: "空", label: qsTr("Clima"), enabled: CortetsuConfig.dashboard.showWeather }
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

    onCurrentChanged: seal.stamp()
    onOpenChanged: if (open) seal.stamp()

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

    CortetsuInkPanel {
        anchors.fill: parent
        radius: CortetsuDesign.radiusSurface
        washX: 0.02
        washY: 0
    }

    // ---------------------------------------------------------------- header

    // The seal of the zone you are in, and its name in ink.
    RowLayout {
        id: title
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.leftMargin: 36
        anchors.topMargin: 30
        spacing: CortetsuDesign.spacingStandard

        CortetsuHanko {
            id: seal
            size: 44
            glyph: root.tabs[root.current]?.glyph ?? "今"
        }
        DashInk {
            text: root.tabs[root.current]?.label ?? ""
            textSize: CortetsuTypography.inkTitlePx
        }
    }

    // The zones as words; a brush stroke lies under the one you are in.
    Row {
        id: tabRow
        anchors.right: parent.right
        anchors.rightMargin: 36
        anchors.verticalCenter: title.verticalCenter
        spacing: CortetsuDesign.spacingCompact

        Repeater {
            id: tabRepeater
            model: root.tabs

            Item {
                id: tab
                required property var modelData
                required property int index
                readonly property bool selected: index === root.current
                width: tabContent.implicitWidth + 24
                height: 40

                Row {
                    id: tabContent
                    anchors.centerIn: parent
                    spacing: 6
                    Text {
                        anchors.baseline: tabLabel.baseline
                        text: tab.modelData.glyph
                        font.family: CortetsuTypography.kanjiFamily
                        font.pixelSize: CortetsuTypography.labelLargePx
                        color: tab.selected ? CortetsuDesign.colorPrimary : CortetsuDesign.colorOnSurfaceVariant
                        opacity: tab.selected ? 1 : 0.6
                    }
                    CortetsuText {
                        id: tabLabel
                        text: tab.modelData.label
                        font.weight: tab.selected ? Font.DemiBold : Font.Normal
                        color: tab.selected ? CortetsuDesign.colorWashi : CortetsuDesign.colorOnSurfaceVariant
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

    CortetsuBrushStroke {
        // count makes the binding re-read once the tabs exist.
        readonly property Item target: tabRepeater.count > 0 ? tabRepeater.itemAt(root.current) : null
        x: tabRow.x + (target?.x ?? 0) + 10
        y: tabRow.y + tabRow.height - 4
        width: (target?.width ?? 0) - 20
        height: 5
        // design-lint: allow motion-layout-property: the stroke travels to the chosen zone
        Behavior on x { NumberAnimation { duration: CortetsuDesign.motionStandardMs; easing.type: Easing.OutQuint } }
        // design-lint: allow motion-layout-property: the stroke takes the chosen zone's width
        Behavior on width { NumberAnimation { duration: CortetsuDesign.motionStandardMs; easing.type: Easing.OutQuint } }
    }

    // ----------------------------------------------------------------- stage

    // The current zone. A switch slides the new one in from the side it
    // comes from; the frame itself never changes size.
    Item {
        id: stage
        anchors.top: title.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: 36
        anchors.rightMargin: 36
        anchors.bottomMargin: 30
        anchors.topMargin: CortetsuDesign.spacingSection
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

    // Inicio: the hour is the subject, large and thin; everything else is a
    // margin note beside it.
    Component {
        id: homeZone

        RowLayout {
            spacing: CortetsuDesign.spacingSection * 2

            Component.onCompleted: Lyrics.consumers += 1
            Component.onDestruction: Lyrics.consumers -= 1

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 0

                DashInk {
                    text: CortetsuRegional.formatDate(Time.date, "longDay", true)
                    textSize: CortetsuTypography.inkLinePx
                    font.italic: true
                    color: CortetsuDesign.colorOnSurfaceVariant
                }
                Item { Layout.fillHeight: true }
                DashInk {
                    text: `${Time.hourStr}:${Time.minuteStr}`
                    textSize: CortetsuTypography.inkHeroPx
                    font.weight: Font.Thin
                    color: CortetsuDesign.colorWashi
                }
                // The line being sung, under the hour.
                DashInk {
                    Layout.fillWidth: true
                    Layout.preferredHeight: implicitHeight
                    visible: CortetsuConfig.dashboard.showMedia
                    text: Lyrics.currentLine ? `— ${Lyrics.currentLine}` : " "
                    textSize: CortetsuTypography.inkLinePx
                    font.italic: true
                    color: CortetsuDesign.colorIndicator
                    elide: Text.ElideRight
                }
            }

            ColumnLayout {
                Layout.preferredWidth: 330
                Layout.maximumWidth: 330
                Layout.fillWidth: false
                Layout.fillHeight: true
                spacing: CortetsuDesign.spacingStandard

                DashWeatherSummary { Layout.fillWidth: true }
                DashRule {}
                Today {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 88
                    screenState: root.screenState
                }
                DashRule {}
                Focus {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 104
                    screenState: root.screenState
                }
                DashRule { visible: CortetsuConfig.dashboard.showMedia }
                DashMediaPlayer {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: CortetsuConfig.dashboard.showMedia
                    compact: true
                    dashboardOpen: root.open
                }
            }
        }
    }

    Component {
        id: mediaZone
        DashMediaPlayer { compact: false; dashboardOpen: root.open }
    }

    // Rendimiento: the processor as a large ensō; the rest smaller, and the
    // network and power as notes.
    Component {
        id: performanceZone

        RowLayout {
            spacing: CortetsuDesign.spacingSection * 2

            Component.onCompleted: { Cpu.consumers += 1; Gpu.consumers += 1; Memory.consumers += 1; Storage.consumers += 1; NetworkUsage.consumers += 1; }
            Component.onDestruction: { Cpu.consumers -= 1; Gpu.consumers -= 1; Memory.consumers -= 1; Storage.consumers -= 1; NetworkUsage.consumers -= 1; }

            DashGauge {
                Layout.alignment: Qt.AlignVCenter
                visible: CortetsuConfig.dashboard.performance.showCpu
                size: 280
                mark: "脳"; label: qsTr("CPU"); value: Cpu.percentage
                detail: Cpu.temperature > 0 ? qsTr("%1 °C").arg(Math.round(Cpu.temperature)) : qsTr("Sin sensor")
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: CortetsuDesign.spacingSection

                RowLayout {
                    Layout.fillWidth: true
                    spacing: CortetsuDesign.spacingSection
                    DashGauge {
                        visible: CortetsuConfig.dashboard.performance.showGpu
                        size: 128
                        mark: "画"; label: qsTr("GPU")
                        value: Gpu.type === Gpu.noneType ? 0 : Gpu.percentage
                        detail: Gpu.type === Gpu.noneType
                            ? (Gpu.dgpuAsleep ? qsTr("En reposo") : qsTr("No disponible"))
                            : qsTr("%1 °C").arg(Math.round(Gpu.temperature))
                    }
                    DashGauge {
                        visible: CortetsuConfig.dashboard.performance.showMemory
                        size: 128
                        mark: "記"; label: qsTr("MEMORIA"); value: Memory.percentage
                        detail: qsTr("%1 de %2 GiB").arg((Memory.used / 1048576).toFixed(1)).arg((Memory.total / 1048576).toFixed(1))
                    }
                    DashGauge {
                        visible: CortetsuConfig.dashboard.performance.showStorage
                        size: 128
                        mark: "蔵"; label: qsTr("DISCO"); value: Storage.percentage
                        detail: Storage.primaryDisk?.mount ?? qsTr("Volumen principal")
                    }
                    Item { Layout.fillWidth: true }
                }

                Item { Layout.fillHeight: true }
                DashRule {}

                RowLayout {
                    Layout.fillWidth: true
                    spacing: CortetsuDesign.spacingSection * 2

                    DashNote {
                        visible: CortetsuConfig.dashboard.performance.showNetwork
                        mark: "網"
                        label: qsTr("RED · %1").arg(CortetsuNetwork.activeEthernet ? qsTr("Ethernet") : CortetsuNetwork.active?.ssid ?? qsTr("Sin conexión"))
                        RowLayout {
                            spacing: CortetsuDesign.spacingSection
                            DashRate { value: NetworkUsage.downloadSpeed; label: qsTr("BAJADA") }
                            DashRate { value: NetworkUsage.uploadSpeed; label: qsTr("SUBIDA") }
                        }
                    }

                    DashNote {
                        Layout.fillWidth: true
                        visible: CortetsuConfig.dashboard.performance.showBattery
                        mark: "電"
                        label: qsTr("ENERGÍA")
                        DashInk {
                            text: CortetsuPower.hasBattery ? qsTr("%1 %").arg(CortetsuPower.percent) : qsTr("Corriente externa")
                        }
                        CortetsuText {
                            text: !CortetsuPower.laptopBattery ? qsTr("Sin batería")
                                : CortetsuPower.charging ? qsTr("Cargando")
                                : CortetsuPower.onBattery ? qsTr("Con batería") : qsTr("Corriente externa")
                            color: CortetsuDesign.colorOnSurfaceVariant
                            textSize: CortetsuTypography.bodySmallPx
                        }
                        Item {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 6
                            visible: CortetsuPower.hasBattery
                            CortetsuBrushStroke { anchors.fill: parent; ink: CortetsuDesign.colorWashi; inkAlpha: 0.08 }
                            CortetsuBrushStroke { height: parent.height; width: Math.max(height * 3, parent.width * CortetsuPower.percent / 100) }
                        }
                    }
                }
            }
        }
    }

    // Clima: the temperature large on the left; the hours as one ink line
    // and the week as brush ranges on the right.
    Component {
        id: weatherZone

        Item {
            ColumnLayout {
                anchors.centerIn: parent
                visible: !Weather.cc
                spacing: CortetsuDesign.spacingCompact
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "空"
                    font.family: CortetsuTypography.kanjiFamily
                    font.pixelSize: CortetsuTypography.inkHeroPx
                    color: CortetsuDesign.colorWashi
                    opacity: 0.08
                }
                DashInk { Layout.alignment: Qt.AlignHCenter; text: qsTr("Tiempo no disponible"); font.italic: true }
                CortetsuText { Layout.alignment: Qt.AlignHCenter; text: qsTr("Aparece cuando hay conexión y una ubicación en Ajustes"); color: CortetsuDesign.colorOnSurfaceVariant }
            }

            RowLayout {
                anchors.fill: parent
                visible: !!Weather.cc
                spacing: CortetsuDesign.spacingSection * 2

                ColumnLayout {
                    Layout.preferredWidth: 300
                    Layout.maximumWidth: 300
                    Layout.fillHeight: true
                    spacing: CortetsuDesign.spacingCompact

                    DashLabel { text: Weather.city.toUpperCase() }
                    Item { Layout.fillHeight: true }
                    RowLayout {
                        spacing: CortetsuDesign.spacingStandard
                        DashInk { text: Weather.temp; textSize: CortetsuTypography.inkHeroPx * 0.78; font.weight: Font.Thin }
                        CortetsuText { Layout.alignment: Qt.AlignTop; text: Weather.icon; textSize: CortetsuTypography.iconHeroPx; color: CortetsuDesign.colorIndicator }
                    }
                    DashInk { text: Weather.description; textSize: CortetsuTypography.inkLinePx; font.italic: true }
                    Item { Layout.preferredHeight: CortetsuDesign.spacingStandard }
                    CortetsuText { text: qsTr("Sensación %1 · Humedad %2 %").arg(Weather.feelsLike).arg(Weather.humidity); color: CortetsuDesign.colorOnSurfaceVariant }
                    CortetsuText { text: qsTr("Amanece %1 · Anochece %2").arg(Weather.sunrise).arg(Weather.sunset); color: CortetsuDesign.colorOnSurfaceVariant }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: CortetsuDesign.spacingStandard

                    DashLabel { text: qsTr("PRÓXIMAS HORAS") }
                    DashHourChart {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 150
                        hours: (Weather.hourlyForecast ?? []).slice(0, 8)
                    }
                    DashRule {}
                    DashLabel { text: qsTr("PRÓXIMOS DÍAS") }

                    ColumnLayout {
                        id: week
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 0
                        readonly property var days: (Weather.forecast ?? []).slice(0, 7)
                        readonly property real lo: days.length ? Math.min(...days.map(d => Number(d.minTempC) || 0)) : 0
                        readonly property real hi: days.length ? Math.max(...days.map(d => Number(d.maxTempC) || 0)) : 1

                        Repeater {
                            model: week.days
                            RowLayout {
                                id: day
                                required property var modelData
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                spacing: CortetsuDesign.spacingStandard
                                readonly property real span: Math.max(1, week.hi - week.lo)
                                CortetsuText { Layout.preferredWidth: 120; text: CortetsuRegional.formatDate(new Date(day.modelData.date), "weekdayDay", true); color: CortetsuDesign.colorOnSurfaceVariant; textSize: CortetsuTypography.bodySmallPx }
                                CortetsuText { Layout.preferredWidth: 28; text: day.modelData.icon; textSize: CortetsuTypography.iconMediumPx; color: CortetsuDesign.colorIndicator }
                                CortetsuText { Layout.preferredWidth: 44; horizontalAlignment: Text.AlignRight; text: CortetsuRegional.formatTemperature(day.modelData.minTempC); color: CortetsuDesign.colorOnSurfaceVariant; textSize: CortetsuTypography.bodySmallPx }
                                // The day's range as a brush stroke on the week's scale.
                                Item {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 6
                                    CortetsuBrushStroke {
                                        height: parent.height
                                        x: parent.width * ((Number(day.modelData.minTempC) || 0) - week.lo) / day.span
                                        width: Math.max(height * 3, parent.width * ((Number(day.modelData.maxTempC) || 0) - (Number(day.modelData.minTempC) || 0)) / day.span)
                                    }
                                }
                                CortetsuText { Layout.preferredWidth: 44; text: CortetsuRegional.formatTemperature(day.modelData.maxTempC); textSize: CortetsuTypography.bodySmallPx; font.weight: Font.DemiBold }
                            }
                        }
                    }
                }
            }
        }
    }
}
