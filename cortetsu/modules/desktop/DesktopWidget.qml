pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Mpris
import ".."
import "../../components"
import "../../services"
import "../../theme"
import "../CortetsuTypography.js" as CortetsuTypography
import "../calendar/CalendarModel.js" as CalendarModel
import "DesktopLayout.js" as DesktopLayout

// One desktop widget, drawn the same on the desktop and in the editor. It
// reads its data from the shell's services and never invents a value: a
// sample that has not arrived reads "Leyendo…", a source that does not
// exist says so. Sampling services are held only while `live` (the
// desktop is in view, or the editor shows the widget).
Item {
    id: root

    required property var item
    // The desktop of this monitor is visible: sampling may run.
    property bool live: true
    // Shown inside the editor: controls do not take clicks.
    property bool editing: false

    readonly property string type: item?.type ?? ""
    readonly property real ui: DesktopLayout.scales[item?.size] ?? 1
    readonly property var box: DesktopLayout.sizeOf(type, item?.size ?? "m")
    readonly property real pad: Math.round(CortetsuDesign.spacingComfortable * ui)

    function px(value: real): int {
        return Math.round(value * root.ui);
    }

    implicitWidth: box.w
    implicitHeight: box.h
    width: box.w
    height: box.h

    Accessible.role: Accessible.Grouping
    Accessible.name: DesktopWidgets.info(type)?.title ?? type

    // 08-widgets: the clock stands on the wallpaper, the protagonist; every
    // other widget is a card with its icon and name over its content.
    readonly property bool framed: type !== "clock"
    readonly property real headerHeight: framed ? px(30) : 0

    CortetsuSurface {
        visible: root.framed
        anchors.fill: parent
        radiusValue: CortetsuDesign.radiusLarge
        baseColor: Qt.alpha(CortetsuDesign.colorSurfaceGlass, 0.82)
        outlined: true
    }

    RowLayout {
        objectName: "desktopWidgetHeader"
        visible: root.framed
        x: root.pad
        y: root.pad
        width: root.width - root.pad * 2
        height: root.headerHeight
        spacing: root.px(CortetsuDesign.spacingCompact)
        CortetsuIcon {
            text: DesktopWidgets.info(root.type)?.icon ?? ""
            iconSize: root.px(CortetsuTypography.iconSmallPx)
            color: CortetsuDesign.colorPrimary
        }
        CortetsuText {
            Layout.fillWidth: true
            text: DesktopWidgets.info(root.type)?.title ?? ""
            textSize: root.px(CortetsuTypography.bodyPx)
            font.weight: Font.DemiBold
            elide: Text.ElideRight
        }
    }

    Loader {
        anchors.fill: parent
        anchors.margins: root.pad
        anchors.topMargin: root.pad + root.headerHeight
        sourceComponent: ({
            clock: clockView, date: dateView, weather: weatherView, battery: batteryView,
            system: systemView, storage: storageView, network: networkView, media: mediaView, note: noteView
        })[root.type] ?? null
    }

    // --- Clock -------------------------------------------------------------
    Component {
        id: clockView
        ColumnLayout {
            spacing: root.px(2)
            CortetsuText {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                style: Text.Raised
                styleColor: Qt.alpha(CortetsuDesign.colorSumi, 0.5)
                text: CortetsuRegional.useSecondPrecision ? `${Time.hourStr}:${Time.minuteStr}:${Time.secondStr}` : `${Time.hourStr}:${Time.minuteStr}`
                textSize: root.px(CortetsuTypography.displayHeroPx * 1.5)
                font.family: CortetsuDesign.fontHeading
                font.weight: Font.Light
                font.features: ({ "tnum": 1 })
                color: CortetsuDesign.colorOnSurface
                elide: Text.ElideRight
            }
            CortetsuText {
                Layout.fillWidth: true
                visible: root.item?.showDate !== false
                horizontalAlignment: Text.AlignHCenter
                style: Text.Raised
                styleColor: Qt.alpha(CortetsuDesign.colorSumi, 0.5)
                text: CortetsuRegional.formatDate(Time.date, "longDay", true) + (Time.amPmStr ? ` · ${Time.amPmStr}` : "")
                textSize: root.px(CortetsuTypography.bodyLargePx)
                color: CortetsuDesign.colorOnSurfaceVariant
                elide: Text.ElideRight
            }
        }
    }

    // --- Month ------------------------------------------------------------
    Component {
        id: dateView
        ColumnLayout {
            id: month
            readonly property int year: Time.date.getFullYear()
            readonly property int monthIndex: Time.date.getMonth()
            readonly property int today: Time.date.getDate()
            readonly property var cells: CalendarModel.monthCells(year, monthIndex)
            spacing: root.px(6)

            CortetsuText {
                Layout.fillWidth: true
                text: CortetsuRegional.formatDate(Time.date, "monthYear", true)
                textSize: root.px(CortetsuTypography.titleSmallPx)
                font.family: CortetsuDesign.fontHeading
                font.weight: CortetsuDesign.headingWeight
                elide: Text.ElideRight
            }

            Grid {
                Layout.fillWidth: true
                Layout.fillHeight: true
                columns: 7
                readonly property real cell: width / 7

                // Monday first, as the calendar surface.
                Repeater {
                    model: 7
                    delegate: CortetsuText {
                        required property int index
                        width: parent.cell
                        horizontalAlignment: Text.AlignHCenter
                        text: Qt.locale().dayName((index + 1) % 7, Locale.NarrowFormat).toUpperCase()
                        textSize: root.px(CortetsuTypography.labelSmallPx)
                        color: CortetsuDesign.colorOnSurfaceVariant
                    }
                }

                Repeater {
                    model: month.cells
                    delegate: Item {
                        id: day
                        required property int modelData
                        required property int index
                        width: parent.cell
                        height: root.px(26)
                        visible: modelData > 0 || index < 35

                        Rectangle {
                            anchors.centerIn: parent
                            width: Math.min(parent.width, parent.height) - 2
                            height: width
                            radius: CortetsuDesign.radiusSmall
                            visible: day.modelData === month.today
                            color: CortetsuDesign.colorPrimary
                        }

                        CortetsuText {
                            anchors.centerIn: parent
                            visible: day.modelData > 0
                            text: day.modelData
                            textSize: root.px(CortetsuTypography.labelMediumPx)
                            font.features: ({ "tnum": 1 })
                            color: day.modelData === month.today ? CortetsuDesign.colorOnPrimary : CortetsuDesign.colorOnSurface
                        }
                    }
                }
            }
        }
    }

    // --- Weather ----------------------------------------------------------
    Component {
        id: weatherView
        RowLayout {
            spacing: root.px(CortetsuDesign.spacingStandard)

            CortetsuText {
                visible: !!Weather.cc
                text: Weather.icon
                textSize: root.px(CortetsuTypography.iconFeaturePx)
                color: CortetsuDesign.colorIndicator
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: root.px(2)
                CortetsuText {
                    Layout.fillWidth: true
                    text: Weather.cc ? Weather.temp : qsTr("Sin pronóstico")
                    textSize: root.px(Weather.cc ? CortetsuTypography.displaySmallPx : CortetsuTypography.titleSmallPx)
                    font.weight: Weather.cc ? Font.Light : Font.Medium
                    elide: Text.ElideRight
                }
                CortetsuText {
                    Layout.fillWidth: true
                    text: Weather.cc ? Weather.description : qsTr("Elige una ubicación en Ajustes → Clima o espera a la primera consulta")
                    textSize: root.px(CortetsuTypography.bodyPx)
                    color: CortetsuDesign.colorOnSurfaceVariant
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }
                CortetsuText {
                    Layout.fillWidth: true
                    visible: !!Weather.cc && Weather.city.length > 0
                    text: Weather.city
                    textSize: root.px(CortetsuTypography.labelMediumPx)
                    color: CortetsuDesign.colorOnSurfaceVariant
                    elide: Text.ElideRight
                }
            }
        }
    }

    // --- Battery ----------------------------------------------------------
    Component {
        id: batteryView
        ColumnLayout {
            id: battery
            spacing: root.px(CortetsuDesign.spacingCompact)

            function duration(seconds: int): string {
                const hours = Math.floor(seconds / 3600);
                const minutes = Math.round((seconds % 3600) / 60);
                return hours > 0 ? qsTr("%1 h %2 min").arg(hours).arg(minutes) : qsTr("%1 min").arg(minutes);
            }

            RowLayout {
                Layout.fillWidth: true
                CortetsuIcon {
                    text: CortetsuPower.charging ? "battery_charging_full" : CortetsuPower.critical ? "battery_alert" : "battery_full"
                    iconSize: root.px(CortetsuTypography.iconMediumPx)
                    color: CortetsuPower.critical ? CortetsuDesign.colorVermillion : CortetsuDesign.colorPrimary
                }
                CortetsuText {
                    Layout.fillWidth: true
                    text: CortetsuPower.hasBattery ? qsTr("%1 %").arg(CortetsuPower.percent) : qsTr("No disponible")
                    textSize: root.px(CortetsuPower.hasBattery ? CortetsuTypography.displaySmallPx : CortetsuTypography.titleSmallPx)
                    font.weight: Font.Light
                    font.features: ({ "tnum": 1 })
                }
            }
            CortetsuProgressBar {
                Layout.fillWidth: true
                visible: CortetsuPower.hasBattery
                value: CortetsuPower.percent / 100
                fillColor: CortetsuPower.critical ? CortetsuDesign.colorVermillion : CortetsuDesign.colorPrimary
            }
            CortetsuText {
                Layout.fillWidth: true
                text: !CortetsuPower.hasBattery ? qsTr("UPower no informa de la batería")
                    : CortetsuPower.charging ? (CortetsuPower.timeToFull > 0 ? qsTr("Cargando · llena en %1").arg(battery.duration(CortetsuPower.timeToFull)) : qsTr("Cargando"))
                    : CortetsuPower.onBattery ? (CortetsuPower.timeToEmpty > 0 ? qsTr("Quedan %1").arg(battery.duration(CortetsuPower.timeToEmpty)) : qsTr("Con batería"))
                    : qsTr("Conectado, sin cargar")
                textSize: root.px(CortetsuTypography.bodySmallPx)
                color: CortetsuDesign.colorOnSurfaceVariant
                elide: Text.ElideRight
            }
        }
    }

    // --- System -----------------------------------------------------------
    Component {
        id: systemView
        ColumnLayout {
            id: system
            spacing: root.px(CortetsuDesign.spacingCompact)
            // A sample has arrived since this view started: before that the
            // services hold 0, which is not a reading.
            property bool cpuSeen: false
            property bool memorySeen: Memory.total > 0
            Connections { target: Cpu; function onPercentageChanged(): void { system.cpuSeen = true; } }

            ServiceUse { target: Cpu; active: root.live }
            ServiceUse { target: Memory; active: root.live }
            ServiceUse { target: Gpu; active: root.live }

            // One row per metric; the model is the count, so a new sample
            // updates the rows in place instead of rebuilding them.
            function metric(index: int): var {
                if (index === 0)
                    return { label: qsTr("CPU"), seen: system.cpuSeen, value: Cpu.percentage, extra: Cpu.temperature > 0 ? qsTr("%1 °C").arg(Math.round(Cpu.temperature)) : "" };
                if (index === 1)
                    return { label: qsTr("Memoria"), seen: system.memorySeen, value: Memory.percentage, extra: "" };
                return Gpu.type !== Gpu.noneType
                    ? { label: qsTr("GPU"), seen: true, value: Gpu.percentage, extra: Gpu.temperature > 0 ? qsTr("%1 °C").arg(Math.round(Gpu.temperature)) : "" }
                    : { label: qsTr("GPU"), seen: false, value: -1, extra: qsTr("En reposo") };
            }

            Repeater {
                model: Gpu.type !== Gpu.noneType || Gpu.dgpuAsleep ? 3 : 2

                delegate: ColumnLayout {
                    id: metric
                    required property int index
                    readonly property var modelData: system.metric(index)
                    Layout.fillWidth: true
                    spacing: root.px(3)
                    RowLayout {
                        Layout.fillWidth: true
                        CortetsuText {
                            Layout.fillWidth: true
                            text: metric.modelData.label
                            textSize: root.px(CortetsuTypography.bodySmallPx)
                            color: CortetsuDesign.colorOnSurfaceVariant
                        }
                        CortetsuText {
                            readonly property var data: metric.modelData
                            text: data.seen ? `${Math.round(data.value * 100)} %${data.extra ? " · " + data.extra : ""}`
                                : data.extra || qsTr("Leyendo…")
                            textSize: root.px(CortetsuTypography.bodySmallPx)
                            font.features: ({ "tnum": 1 })
                        }
                    }
                    CortetsuProgressBar {
                        Layout.fillWidth: true
                        value: metric.modelData.seen ? metric.modelData.value : -1
                        fillColor: metric.modelData.value > 0.9 ? CortetsuDesign.colorVermillion : CortetsuDesign.colorPrimary
                    }
                }
            }
        }
    }

    // --- Storage ----------------------------------------------------------
    Component {
        id: storageView
        ColumnLayout {
            id: storage
            spacing: root.px(CortetsuDesign.spacingCompact)
            readonly property var disk: Storage.primaryDisk
            ServiceUse { target: Storage; active: root.live }

            RowLayout {
                Layout.fillWidth: true
                CortetsuIcon { text: "hard_drive"; iconSize: root.px(CortetsuTypography.iconSmallPx); color: CortetsuDesign.colorPrimary }
                CortetsuText {
                    Layout.fillWidth: true
                    text: storage.disk ? storage.disk.mount : qsTr("Almacenamiento")
                    textSize: root.px(CortetsuTypography.bodyPx)
                    font.weight: Font.DemiBold
                    elide: Text.ElideMiddle
                }
                CortetsuText {
                    visible: !!storage.disk
                    text: storage.disk ? `${Math.round(storage.disk.perc * 100)} %` : ""
                    textSize: root.px(CortetsuTypography.bodyPx)
                    font.features: ({ "tnum": 1 })
                }
            }
            CortetsuProgressBar {
                Layout.fillWidth: true
                value: storage.disk ? storage.disk.perc : -1
                fillColor: (storage.disk?.perc ?? 0) > 0.9 ? CortetsuDesign.colorVermillion : CortetsuDesign.colorPrimary
            }
            CortetsuText {
                Layout.fillWidth: true
                text: {
                    const disk = storage.disk;
                    if (!disk)
                        return qsTr("Leyendo…");
                    const free = NetworkUsage.formatBytes(disk.free * 1024);
                    return qsTr("%1 %2 libres").arg(free.value.toFixed(1)).arg(free.unit);
                }
                textSize: root.px(CortetsuTypography.bodySmallPx)
                color: (storage.disk?.perc ?? 0) > 0.9 ? CortetsuDesign.colorVermillion : CortetsuDesign.colorOnSurfaceVariant
            }
        }
    }

    // --- Network ----------------------------------------------------------
    Component {
        id: networkView
        ColumnLayout {
            id: network
            spacing: root.px(CortetsuDesign.spacingCompact)
            property bool seen: false
            Connections {
                target: NetworkUsage
                function onDownloadSpeedChanged(): void { network.seen = true; }
                function onUploadSpeedChanged(): void { network.seen = true; }
            }
            ServiceUse { target: NetworkUsage; active: root.live }

            function rate(value: real): string {
                const formatted = NetworkUsage.formatBytesRate(value);
                return qsTr("%1 %2/s").arg(formatted.value.toFixed(formatted.value < 10 ? 1 : 0)).arg(formatted.unit);
            }

            // Two fixed rows; each reads its rate, so samples do not
            // rebuild them.
            Repeater {
                model: 2
                delegate: RowLayout {
                    id: rateRow
                    required property int index
                    readonly property var modelData: index === 0
                        ? { icon: "south", label: qsTr("Descarga"), value: NetworkUsage.downloadSpeed }
                        : { icon: "north", label: qsTr("Subida"), value: NetworkUsage.uploadSpeed }
                    Layout.fillWidth: true
                    spacing: root.px(CortetsuDesign.spacingCompact)
                    CortetsuIcon { text: rateRow.modelData.icon; iconSize: root.px(CortetsuTypography.iconSmallPx); color: CortetsuDesign.colorPrimary }
                    CortetsuText {
                        Layout.fillWidth: true
                        text: rateRow.modelData.label
                        textSize: root.px(CortetsuTypography.bodyPx)
                        color: CortetsuDesign.colorOnSurfaceVariant
                    }
                    CortetsuText {
                        text: network.seen ? network.rate(rateRow.modelData.value) : qsTr("Leyendo…")
                        textSize: root.px(CortetsuTypography.bodyLargePx)
                        font.features: ({ "tnum": 1 })
                    }
                }
            }
        }
    }

    // --- Media ------------------------------------------------------------
    Component {
        id: mediaView
        RowLayout {
            id: media
            readonly property MprisPlayer player: Players.active
            readonly property string art: player ? Players.getArtUrl(player) : ""
            spacing: root.px(CortetsuDesign.spacingStandard)

            CortetsuRoundedImage {
                visible: media.art.length > 0
                Layout.preferredWidth: root.height - root.pad * 2
                Layout.preferredHeight: root.height - root.pad * 2
                source: media.art
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: root.px(2)
                CortetsuText {
                    Layout.fillWidth: true
                    text: media.player ? (media.player.trackTitle || qsTr("Sin título")) : qsTr("Nada suena")
                    textSize: root.px(CortetsuTypography.bodyLargePx)
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }
                CortetsuText {
                    Layout.fillWidth: true
                    text: media.player ? (media.player.trackArtist || Players.getIdentity(media.player)) : qsTr("Reproduce algo en una aplicación de música o vídeo")
                    textSize: root.px(CortetsuTypography.bodySmallPx)
                    color: CortetsuDesign.colorOnSurfaceVariant
                    elide: Text.ElideRight
                }
                RowLayout {
                    visible: !!media.player
                    spacing: CortetsuDesign.spacingUnit
                    CortetsuButton {
                        compact: true; icon: "skip_previous"; label: ""
                        tooltipText: qsTr("Anterior")
                        disabled: root.editing || !media.player?.canGoPrevious
                        onClicked: media.player?.previous()
                    }
                    CortetsuButton {
                        compact: true
                        icon: media.player?.isPlaying ? "pause" : "play_arrow"
                        label: ""
                        tooltipText: media.player?.isPlaying ? qsTr("Pausar") : qsTr("Reproducir")
                        disabled: root.editing || !media.player?.canTogglePlaying
                        onClicked: media.player?.togglePlaying()
                    }
                    CortetsuButton {
                        compact: true; icon: "skip_next"; label: ""
                        tooltipText: qsTr("Siguiente")
                        disabled: root.editing || !media.player?.canGoNext
                        onClicked: media.player?.next()
                    }
                }
            }
        }
    }

    // --- Note -------------------------------------------------------------
    Component {
        id: noteView
        CortetsuText {
            readonly property string body: root.item?.text ?? ""
            text: body.length > 0 ? body : qsTr("Nota vacía. Escríbela en el modo edición del escritorio.")
            textSize: root.px(CortetsuTypography.bodyLargePx)
            color: body.length > 0 ? CortetsuDesign.colorOnSurface : CortetsuDesign.colorOnSurfaceVariant
            wrapMode: Text.Wrap
            elide: Text.ElideRight
            verticalAlignment: Text.AlignTop
        }
    }
}
