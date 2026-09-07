pragma ComponentBehavior: Bound

import QtQuick
import ".."
import "../CortetsuDesign.js" as CortetsuDesign
import "../CortetsuTypography.js" as CortetsuTypography
import QtCore
import Quickshell
import Quickshell.Io

FocusScope {
    id: root

    required property ShellScreen screen
    required property var screenState
    required property bool hardwareVisible

    property var snapshot: ({})
    property string statusText: qsTr("Waiting for first sample…")
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
        root.statusText = qsTr("Refreshing…");
        probe.running = true;
    }

    function openHardware(): void {
        forceActiveFocus();
        refresh();
    }

    function closeHardware(): void {
        root.screenState.cortetsuState?.setRetained("hardware", false);
    }

    Keys.onEscapePressed: root.closeHardware()

    Keys.onPressed: event => {
        if (event.key === Qt.Key_R) {
            root.refresh();
            event.accepted = true;
            return;
        }
        if (event.key >= Qt.Key_1 && event.key <= Qt.Key_9) {
            root.currentPage = event.key - Qt.Key_1;
            event.accepted = true;
        }
    }

    Timer {
        interval: 1500
        repeat: true
        running: root.hardwareVisible
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

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
                    root.statusText = qsTr("Live");
                } catch (error) {
                    root.statusText = qsTr("Probe unavailable");
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

            Row {
                id: tabs
                width: parent.width
                height: 40
                spacing: CortetsuDesign.spacingUnit

                Repeater {
                    model: [
                        { label: qsTr("Overview"), icon: "dashboard" },
                        { label: qsTr("Performance"), icon: "monitoring" },
                        { label: qsTr("Processes"), icon: "account_tree" },
                        { label: qsTr("Sensors"), icon: "device_thermostat" },
                        { label: qsTr("I/O"), icon: "lan" },
                        { label: qsTr("Power"), icon: "bolt" },
                        { label: qsTr("Auto"), icon: "auto_mode" },
                        { label: qsTr("Energy"), icon: "electric_bolt" },
                        { label: qsTr("Keys"), icon: "keyboard" }
                    ]

                    delegate: Item {
                        required property var modelData
                        required property int index
                        width: (tabs.width - tabs.spacing * 8) / 9
                        height: tabs.height

                        CortetsuSurface {
                            anchors.fill: parent
                            radiusValue: CortetsuDesign.radiusMedium
                            baseColor: root.currentPage === index
                                ? Qt.alpha(CortetsuDesign.colorPrimaryContainer, 0.76)
                                : tabLayer.containsMouse
                                    ? CortetsuDesign.colorSurfaceGlass
                                    : "transparent"
                            outlined: false
                        }

                        CortetsuStateLayer {
                            id: tabLayer
                            anchors.fill: parent
                            radius: CortetsuDesign.radiusMedium
                            onClicked: root.currentPage = index
                        }

                        Row {
                            anchors.centerIn: parent
                            spacing: 5

                            CortetsuIcon {
                                text: modelData.icon
                                color: root.currentPage === index
                                    ? CortetsuDesign.colorOnPrimaryContainer
                                    : CortetsuDesign.colorOnSurfaceVariant
                                iconSize: CortetsuTypography.iconSmallPx
                            }

                            CortetsuText {
                                text: modelData.label
                                color: root.currentPage === index
                                    ? CortetsuDesign.colorOnPrimaryContainer
                                    : CortetsuDesign.colorOnSurfaceVariant
                                textSize: CortetsuTypography.labelSmallPx
                                font.weight: root.currentPage === index ? Font.DemiBold : Font.Normal
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
                                                : keybindsComponent
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
}
