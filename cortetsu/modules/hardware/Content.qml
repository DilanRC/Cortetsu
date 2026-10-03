pragma ComponentBehavior: Bound

import QtQuick
import ".."
import "../CortetsuDesign.js" as CortetsuDesign
import "../CortetsuTypography.js" as CortetsuTypography
import "Navigation.js" as HardwareNavigation
import QtCore
import Quickshell
import Quickshell.Io
import "../../components"

FocusScope {
    id: root

    required property ShellScreen screen
    required property var screenState
    required property bool hardwareVisible

    property var snapshot: ({})
    property string statusText: qsTr("Esperando la primera lectura…")
    property int sampleCount: 0
    property int currentPage: 0

    property var cpuHistory: []
    property var cpuCoreHistories: []
    property var memoryUsedHistory: []
    property var memoryCacheHistory: []
    property var swapUsedHistory: []
    property var networkRxHistory: []
    property var networkTxHistory: []
    property var diskReadHistory: []
    property var diskWriteHistory: []
    property var gpu0History: []
    property var gpu1History: []

    readonly property string probePath:
        StandardPaths.writableLocation(StandardPaths.HomeLocation) +
        "/.local/bin/cortetsu-hardware-probe"

    readonly property var processes: snapshot?.processes ?? []

    function number(value, digits = 1): string {
        if (value === null || value === undefined || isNaN(Number(value)))
            return "—";
        return Number(value).toFixed(digits);
    }

    function uptimeText(seconds): string {
        const total = Math.max(0, Number(seconds ?? 0));
        const days = Math.floor(total / 86400);
        const hours = Math.floor((total % 86400) / 3600);
        const mins = Math.floor((total % 3600) / 60);
        if (days > 0)
            return `${days}d ${hours}h ${mins}m`;
        if (hours > 0)
            return `${hours}h ${mins}m`;
        return `${mins}m`;
    }

    function pushHistory(source, value): var {
        const next = Array.from(source ?? []);
        next.push(Number(value ?? 0));
        return next.slice(-72);
    }

    function recordHistory(parsed): void {
        root.cpuHistory = pushHistory(root.cpuHistory, parsed?.cpu?.usage);

        const coreValues = parsed?.cpu?.per_core ?? [];
        const coreHistories = Array.from(root.cpuCoreHistories ?? []);
        while (coreHistories.length < coreValues.length)
            coreHistories.push([]);
        for (let i = 0; i < coreValues.length; ++i)
            coreHistories[i] = pushHistory(coreHistories[i], coreValues[i]);
        root.cpuCoreHistories = coreHistories;

        root.memoryUsedHistory = pushHistory(root.memoryUsedHistory, parsed?.memory?.used_gb);
        root.memoryCacheHistory = pushHistory(root.memoryCacheHistory, parsed?.memory?.cache_gb);
        root.swapUsedHistory = pushHistory(root.swapUsedHistory, parsed?.memory?.swap_used_gb);
        root.networkRxHistory = pushHistory(root.networkRxHistory, parsed?.network?.rx_mbps);
        root.networkTxHistory = pushHistory(root.networkTxHistory, parsed?.network?.tx_mbps);
        root.diskReadHistory = pushHistory(root.diskReadHistory, parsed?.disk_io?.read_mib_s);
        root.diskWriteHistory = pushHistory(root.diskWriteHistory, parsed?.disk_io?.write_mib_s);
        root.gpu0History = pushHistory(root.gpu0History, parsed?.gpus?.[0]?.usage);
        root.gpu1History = pushHistory(root.gpu1History, parsed?.gpus?.[1]?.usage);
    }

    function refresh(): void {
        if (!root.hardwareVisible || probe.running)
            return;
        root.statusText = qsTr("Actualizando…");
        probe.running = true;
    }

    function openHardware(): void {
        forceActiveFocus();
        refresh();
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

    Timer {
        interval: 1500
        repeat: true
        running: root.hardwareVisible
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    // startup inventory: cortetsu:hardware-probe
    Process {
        id: probe
        command: [root.probePath]

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const parsed = JSON.parse(text.trim());
                    root.snapshot = parsed;
                    root.recordHistory(parsed);
                    root.sampleCount += 1;
                    root.statusText = qsTr("En vivo");
                } catch (error) {
                    root.statusText = qsTr("Sonda no disponible");
                    console.warn(`Hardware Center: invalid probe JSON: ${error}`);
                }
            }
        }
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
                        text: `${root.snapshot?.host ?? "Cortetsu"} · ${root.snapshot?.kernel ?? ""} · ${root.uptimeText(root.snapshot?.uptime_sec)}`
                        color: CortetsuDesign.colorOnSurfaceVariant
                        textSize: CortetsuTypography.labelSmallPx
                        elide: Text.ElideRight
                    }
                }

                CortetsuText {
                    id: status
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.statusText
                    color: probe.running ? CortetsuDesign.colorPrimary : CortetsuDesign.colorOnSurfaceVariant
                    textSize: CortetsuTypography.labelSmallPx
                }

                Item {
                    id: refreshButton
                    anchors.verticalCenter: parent.verticalCenter
                    width: 38
                    height: 38

                    CortetsuSurface {
                        anchors.fill: parent
                        radiusValue: CortetsuDesign.radiusPill
                        baseColor: refreshLayer.containsMouse ? CortetsuDesign.colorSurfaceGlassStrong : "transparent"
                        outlined: false
                    }
                    CortetsuStateLayer {
                        id: refreshLayer
                        anchors.fill: parent
                        radius: CortetsuDesign.radiusPill
                        onClicked: root.refresh()
                    }
                    CortetsuIcon {
                        anchors.centerIn: parent
                        text: probe.running ? "progress_activity" : "refresh"
                        color: CortetsuDesign.colorOnSurfaceVariant
                        iconSize: CortetsuTypography.iconMediumPx
                    }
                }

                Item {
                    id: closeButton
                    anchors.verticalCenter: parent.verticalCenter
                    width: 38
                    height: 38

                    CortetsuSurface {
                        anchors.fill: parent
                        radiusValue: CortetsuDesign.radiusPill
                        baseColor: closeLayer.containsMouse ? CortetsuDesign.colorSurfaceGlassStrong : "transparent"
                        outlined: false
                    }
                    CortetsuStateLayer {
                        id: closeLayer
                        anchors.fill: parent
                        radius: CortetsuDesign.radiusPill
                        onClicked: root.closeHardware()
                    }
                    CortetsuIcon {
                        anchors.centerIn: parent
                        text: "close"
                        color: CortetsuDesign.colorOnSurfaceVariant
                        iconSize: CortetsuTypography.iconMediumPx
                    }
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
                        model: [
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

                        delegate: Item {
                            id: tabDelegate
                            required property var modelData
                            required property int index
                            width: Math.max(92, (tabs.width - tabRow.spacing * 9) / 10)
                            height: tabRow.height

                            CortetsuTab {
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
        OverviewPage { snapshot: root.snapshot }
    }

    Component {
        id: performanceComponent
        PerformancePage {
            snapshot: root.snapshot
            cpuHistory: root.cpuHistory
            cpuCoreHistories: root.cpuCoreHistories
            memoryUsedHistory: root.memoryUsedHistory
            memoryCacheHistory: root.memoryCacheHistory
            swapUsedHistory: root.swapUsedHistory
            networkRxHistory: root.networkRxHistory
            networkTxHistory: root.networkTxHistory
            diskReadHistory: root.diskReadHistory
            diskWriteHistory: root.diskWriteHistory
            gpu0History: root.gpu0History
            gpu1History: root.gpu1History
        }
    }

    Component {
        id: processesComponent
        ProcessesPage {
            processes: root.processes
            memoryTotalGb: Number(root.snapshot?.memory?.total_gb ?? 0)
        }
    }

    Component { id: sensorsComponent; SensorsPage { snapshot: root.snapshot } }
    Component { id: ioComponent; IOPage { snapshot: root.snapshot } }
    Component { id: powerComponent; PowerPage {} }
    Component { id: automationComponent; PowerAutomationPage {} }
    Component { id: energyComponent; EnergyPage {} }
    Component { id: keybindsComponent; KeybindsPage {} }
    Component { id: startupComponent; StartupPage {} }
}
