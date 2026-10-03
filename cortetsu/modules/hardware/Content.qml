pragma ComponentBehavior: Bound

import QtQuick
import ".."
import "../../theme"
import "../CortetsuTypography.js" as CortetsuTypography
import "Navigation.js" as HardwareNavigation
import "Format.js" as Format
import Quickshell
import Quickshell.Services.UPower
import "../../components"

FocusScope {
    id: root

    required property ShellScreen screen
    required property var screenState
    required property bool hardwareVisible

    property int currentPage: 0

    readonly property var pageTabs: [
        { label: qsTr("Resumen"), icon: "dashboard" },
        { label: qsTr("Rendimiento"), icon: "monitoring" },
        { label: qsTr("Procesos"), icon: "account_tree" },
        { label: qsTr("Sensores"), icon: "device_thermostat" },
        { label: qsTr("E/S"), icon: "lan" },
        { label: qsTr("Energía"), icon: "bolt" },
        { label: qsTr("Automatización"), icon: "auto_mode" },
        { label: qsTr("Consumo"), icon: "electric_bolt" },
        { label: qsTr("Atajos"), icon: "keyboard" },
        { label: qsTr("Arranque"), icon: "play_circle" }
    ]
    // The summary names its destinations with the tab labels themselves.
    readonly property var pageLabels: {
        const labels = {};
        for (const target in HardwareNavigation.pages)
            labels[target] = root.pageTabs[HardwareNavigation.pages[target]].label;
        return labels;
    }

    readonly property alias telemetry: telemetry
    readonly property string statusText: telemetry.status === "live"
        ? qsTr("Lectura de las %1").arg(Format.clock(telemetry.sampleTime, CortetsuConfig.useTwelveHourClock))
        : telemetry.status === "stale"
            ? qsTr("Lecturas detenidas")
            : telemetry.status === "error" ? qsTr("Sonda no disponible") : qsTr("Leyendo…")
    readonly property string powerProfile: PowerProfiles.profile === PowerProfile.PowerSaver
        ? "power-saver"
        : PowerProfiles.profile === PowerProfile.Performance ? "performance" : "balanced"

    function refresh(): void {
        telemetry.refresh();
    }

    // The telemetry timer takes a reading as soon as the panel is visible.
    function openHardware(): void {
        forceActiveFocus();
    }

    function closeHardware(): void {
        root.screenState.cortetsuState?.setRetained("hardware", false);
    }

    Keys.onPressed: event => {
        if (HardwareNavigation.isEscape(event.key, Qt.Key_Escape)) {
            root.closeHardware();
            event.accepted = true;
            return;
        }
        if (event.key === Qt.Key_R) {
            root.refresh();
            event.accepted = true;
            return;
        }
        if (HardwareNavigation.handlesPageKey(event.key, Qt.Key_1, Qt.Key_9, Qt.Key_0)) {
            root.currentPage = HardwareNavigation.pageForKey(
                event.key, root.currentPage, Qt.Key_1, Qt.Key_9, Qt.Key_0);
            event.accepted = true;
        }
    }

    function selectAdjacentTab(delta): void {
        root.currentPage = Math.max(0, Math.min(9, root.currentPage + delta));
    }

    function revealPageTab(index): void {
        const tab = tabRepeater.itemAt(index);
        if (tab)
            tabs.contentX = Math.max(0, Math.min(tab.x, tabs.contentWidth - tabs.width));
    }

    onCurrentPageChanged: Qt.callLater(() => root.revealPageTab(root.currentPage))

    HardwareTelemetry {
        id: telemetry
        active: root.hardwareVisible
        fullProcessList: root.currentPage === HardwareNavigation.pages.processes
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onClicked: mouse => {
            const outsidePanel =
                mouse.x < panel.x ||
                mouse.x >= panel.x + panel.width ||
                mouse.y < panel.y ||
                mouse.y >= panel.y + panel.height;

            if (outsidePanel)
                root.closeHardware();
        }
    }

    Rectangle {
        id: panel

        width: Math.min(1120, parent.width - 96)
        height: Math.min(820, parent.height - 72)
        x: Math.round((parent.width - width) / 2)
        y: Math.round((parent.height - height) / 2)
        radius: 24
        color: Qt.alpha(CortetsuDesign.colorTetsu, 0.97)
        border.width: 1
        border.color: Qt.alpha(CortetsuDesign.colorOutlineVariant, 0.22)
        clip: true

        Column {
            anchors.fill: parent
            anchors.margins: CortetsuDesign.spacingComfortable
            spacing: CortetsuDesign.spacingStandard

            Row {
                id: header
                width: parent.width
                height: 50
                spacing: CortetsuDesign.spacingStandard

                CortetsuIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "monitor_heart"
                    color: CortetsuDesign.colorPrimary
                    iconSize: CortetsuTypography.iconLargePx
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.max(120, parent.width - x - status.width - refreshButton.width - closeButton.width - 36)
                    spacing: 1

                    CortetsuText {
                        width: parent.width
                        text: qsTr("Hardware")
                        color: CortetsuDesign.colorOnSurface
                        textSize: CortetsuTypography.titleLargePx
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }

                    CortetsuText {
                        width: parent.width
                        text: Format.join([
                            telemetry.snapshot?.host ?? "",
                            telemetry.snapshot?.kernel ?? "",
                            Format.duration(telemetry.snapshot?.uptime_sec) ? qsTr("encendido %1").arg(Format.duration(telemetry.snapshot.uptime_sec)) : ""
                        ])
                        color: CortetsuDesign.colorOnSurfaceVariant
                        textSize: CortetsuTypography.labelSmallPx
                        elide: Text.ElideRight
                    }
                }

                CortetsuText {
                    id: status
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.statusText
                    color: telemetry.status === "stale" || telemetry.status === "error"
                        ? CortetsuDesign.colorWarning
                        : CortetsuDesign.colorOnSurfaceVariant
                    textSize: CortetsuTypography.labelSmallPx
                }

                CortetsuButton {
                    id: refreshButton
                    objectName: "hardwareRefresh"
                    anchors.verticalCenter: parent.verticalCenter
                    compact: true
                    icon: "refresh"
                    tooltipText: qsTr("Actualizar (R)")
                    Accessible.name: qsTr("Actualizar")
                    onClicked: root.refresh()
                }

                CortetsuButton {
                    id: closeButton
                    objectName: "hardwareClose"
                    anchors.verticalCenter: parent.verticalCenter
                    compact: true
                    icon: "close"
                    tooltipText: qsTr("Cerrar (Esc)")
                    Accessible.name: qsTr("Cerrar")
                    onClicked: root.closeHardware()
                }
            }

            Flickable {
                id: tabs
                width: parent.width
                height: 40
                contentWidth: tabRow.implicitWidth
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                Row {
                    id: tabRow
                    spacing: CortetsuDesign.spacingUnit
                    height: parent.height

                    Repeater {
                        id: tabRepeater
                        model: root.pageTabs

                        delegate: Item {
                            id: tabDelegate
                            required property var modelData
                            required property int index
                            // Each tab is as wide as its label, so a long name
                            // is never squeezed into an equal share.
                            width: tab.implicitWidth
                            height: tabRow.height

                            CortetsuTab {
                                id: tab
                                anchors.fill: parent
                                index: tabDelegate.index
                                count: 10
                                label: tabDelegate.modelData.label
                                icon: tabDelegate.modelData.icon
                                selected: root.currentPage === tabDelegate.index
                                onActivated: root.currentPage = tabDelegate.index
                                onPreviousRequested: root.selectAdjacentTab(-1)
                                onNextRequested: root.selectAdjacentTab(1)
                            }
                        }
                    }
                }
            }

            Loader {
                id: pageLoader
                width: parent.width
                height: parent.height - header.height - tabs.height - CortetsuDesign.spacingStandard * 2
                sourceComponent: root.currentPage === 0
                    ? overviewComponent
                    : root.currentPage === 1
                        ? performanceComponent
                        : root.currentPage === 2
                            ? processesComponent
                            : root.currentPage === 3
                                ? sensorsComponent
                                : root.currentPage === 4
                                    ? ioComponent
                                    : root.currentPage === 5
                                        ? powerComponent
                                        : root.currentPage === 6
                                            ? automationComponent
                                            : root.currentPage === 7
                                                ? energyComponent
                                                : root.currentPage === 8
                                                    ? keybindsComponent
                                                    : startupComponent
            }
        }
    }

    Component {
        id: overviewComponent
        OverviewPage {
            snapshot: telemetry.snapshot
            status: telemetry.status
            sampleTime: telemetry.sampleTime
            cpuHistory: telemetry.cpuHistory
            historyLength: telemetry.historyLength
            historySeconds: telemetry.historySeconds
            powerProfile: root.powerProfile
            pageLabels: root.pageLabels
            onPageRequested: target => root.currentPage = HardwareNavigation.pages[target]
            onRetryRequested: telemetry.refresh()
        }
    }

    Component {
        id: performanceComponent
        PerformancePage {
            snapshot: telemetry.snapshot
            cpuHistory: telemetry.cpuHistory
            cpuCoreHistories: telemetry.cpuCoreHistories
            memoryUsedHistory: telemetry.memoryUsedHistory
            memoryCacheHistory: telemetry.memoryCacheHistory
            swapUsedHistory: telemetry.swapUsedHistory
            networkRxHistory: telemetry.networkRxHistory
            networkTxHistory: telemetry.networkTxHistory
            diskReadHistory: telemetry.diskReadHistory
            diskWriteHistory: telemetry.diskWriteHistory
            gpu0History: telemetry.gpu0History
            gpu1History: telemetry.gpu1History
            historyLength: telemetry.historyLength
        }
    }

    Component {
        id: processesComponent
        ProcessesPage {
            processes: telemetry.snapshot?.processes ?? []
            memoryTotalGb: Number(telemetry.snapshot?.memory?.total_gb ?? 0)
        }
    }

    Component { id: sensorsComponent; SensorsPage { snapshot: telemetry.snapshot } }
    Component { id: ioComponent; IOPage { snapshot: telemetry.snapshot } }
    Component { id: powerComponent; PowerPage {} }
    Component { id: automationComponent; PowerAutomationPage {} }
    Component { id: energyComponent; EnergyPage {} }
    Component { id: keybindsComponent; KeybindsPage {} }
    Component { id: startupComponent; StartupPage {} }
}
