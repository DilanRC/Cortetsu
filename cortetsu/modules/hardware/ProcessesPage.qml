pragma ComponentBehavior: Bound

import QtQuick
import ".."
import "../CortetsuDesign.js" as CortetsuDesign
import "../CortetsuTypography.js" as CortetsuTypography
import Quickshell

Item {
    id: root

    required property var processes
    property real memoryTotalGb: 0

    property string filterText: ""
    property string sortKey: "cpu"
    property bool sortDescending: true
    property bool paused: false
    property bool numericMode: true
    property var frozenProcesses: []
    property int selectedPid: -1
    property string actionStatus: ""

    readonly property var sourceProcesses: paused ? frozenProcesses : processes
    readonly property var visibleProcesses: buildProcesses(sourceProcesses)
    readonly property var selectedProcess: findSelected()
    readonly property bool selectedStopped: String(selectedProcess?.state ?? "") === "T"

    function buildProcesses(source): var {
        const query = filterText.trim().toLowerCase();
        let result = Array.from(source ?? []);
        if (query.length > 0) {
            const terms = query.split(/\s+/).filter(t => t.length > 0);
            result = result.filter(p => {
                const haystack = `${p?.name ?? ""} ${p?.user ?? ""} ${p?.command ?? ""} ${p?.pid ?? ""}`.toLowerCase();
                return terms.every(term => haystack.includes(term));
            });
        }

        result.sort((a, b) => {
            let left = a?.[sortKey] ?? 0;
            let right = b?.[sortKey] ?? 0;
            if (sortKey === "name" || sortKey === "user") {
                left = String(left).toLowerCase();
                right = String(right).toLowerCase();
                const cmp = left.localeCompare(right);
                return sortDescending ? -cmp : cmp;
            }
            const cmp = Number(left) - Number(right);
            return sortDescending ? -cmp : cmp;
        });
        return result;
    }

    function findSelected(): var {
        const source = visibleProcesses ?? [];
        for (const proc of source) {
            if (Number(proc?.pid) === selectedPid)
                return proc;
        }
        return source.length > 0 ? source[0] : ({});
    }

    function setSort(key): void {
        if (sortKey === key)
            sortDescending = !sortDescending;
        else {
            sortKey = key;
            sortDescending = key !== "name" && key !== "user";
        }
    }

    function togglePause(): void {
        if (!paused)
            frozenProcesses = Array.from(processes ?? []);
        paused = !paused;
    }

    function sendSignal(signal): void {
        const pid = Number(selectedProcess?.pid ?? -1);
        if (pid <= 1)
            return;
        Quickshell.execDetached(["kill", `-${signal}`, String(pid)]);
        actionStatus = `${signal} → PID ${pid}`;
    }

    function toggleSelectedPause(): void {
        sendSignal(selectedStopped ? "CONT" : "STOP");
    }

    function cpuText(proc): string {
        const usage = Number(proc?.cpu ?? 0);
        return numericMode ? `${(usage / 100).toFixed(2)} core` : `${usage.toFixed(1)}%`;
    }

    function ramGiB(proc): real {
        return Math.max(0, Number(memoryTotalGb)) * Math.max(0, Number(proc?.mem ?? 0)) / 100;
    }

    function ramText(proc): string {
        const pct = Number(proc?.mem ?? 0);
        if (!numericMode)
            return `${pct.toFixed(1)}%`;
        const gib = ramGiB(proc);
        return gib < 1 ? `${Math.round(gib * 1024)} MiB` : `${gib.toFixed(2)} GiB`;
    }

    onVisibleProcessesChanged: {
        if (visibleProcesses.length === 0) {
            selectedPid = -1;
            return;
        }
        if (!visibleProcesses.some(p => Number(p?.pid) === selectedPid))
            selectedPid = Number(visibleProcesses[0]?.pid ?? -1);
    }

    Row {
        anchors.fill: parent
        spacing: 12

        Rectangle {
            id: listCard
            width: parent.width * 0.66
            height: parent.height
            radius: CortetsuDesign.radiusLarge
            color: CortetsuDesign.colorSurface
            border.width: 1
            border.color: CortetsuDesign.colorOutlineVariant

            Column {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 10

                Row {
                    width: parent.width
                    height: 42
                    spacing: 9

                    Rectangle {
                        width: parent.width - sortControls.width - pauseButton.width - unitsButton.width - 27
                        height: 42
                        radius: CortetsuDesign.radiusMedium
                        color: CortetsuDesign.colorSurfaceHigh
                        border.width: searchInput.activeFocus ? 1 : 0
                        border.color: CortetsuDesign.colorPrimary

                        CortetsuIcon {
                            anchors.left: parent.left
                            anchors.leftMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            text: "search"
                            color: CortetsuDesign.colorOnSurfaceVariant
                            iconSize: CortetsuTypography.iconMediumPx
                        }

                        CortetsuText {
                            anchors.left: parent.left
                            anchors.leftMargin: 42
                            anchors.verticalCenter: parent.verticalCenter
                            visible: searchInput.text.length === 0
                        text: qsTr("Filtrar procesos…")
                            color: CortetsuDesign.colorOutline
                            textSize: CortetsuTypography.bodyPx
                        }

                        TextInput {
                            id: searchInput
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.leftMargin: 42
                            anchors.rightMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            height: parent.height
                            verticalAlignment: TextInput.AlignVCenter
                            color: CortetsuDesign.colorOnSurface
                            selectionColor: CortetsuDesign.colorPrimary
                            selectedTextColor: CortetsuDesign.colorOnPrimary
                            font.pixelSize: 15
                            text: root.filterText
                            onTextChanged: root.filterText = text
                        }
                    }

                    Row {
                        id: sortControls
                        spacing: 5

                        Repeater {
                            model: [
                                { label: "CPU", key: "cpu" },
                                { label: "RAM", key: "mem" },
                                { label: "PID", key: "pid" }
                            ]

                            delegate: Rectangle {
                                required property var modelData
                                width: 54
                                height: 42
                                radius: CortetsuDesign.radiusMedium
                                color: root.sortKey === modelData.key
                                    ? CortetsuDesign.colorSecondaryContainer
                                    : CortetsuDesign.colorSurfaceHigh

                                CortetsuStateLayer {
                                    radius: parent.radius
                                    onClicked: root.setSort(modelData.key)
                                }

                                CortetsuText {
                                    anchors.centerIn: parent
                                    text: `${modelData.label}${root.sortKey === modelData.key ? (root.sortDescending ? " ↓" : " ↑") : ""}`
                                    color: root.sortKey === modelData.key
                                        ? CortetsuDesign.colorOnSecondaryContainer
                                        : CortetsuDesign.colorOnSurfaceVariant
                                    textSize: CortetsuTypography.labelSmallPx
                                }
                            }
                        }
                    }

                    Rectangle {
                        id: unitsButton
                        width: 48
                        height: 42
                        radius: CortetsuDesign.radiusMedium
                        color: root.numericMode
                            ? CortetsuDesign.colorSecondaryContainer
                            : CortetsuDesign.colorSurfaceHigh

                        CortetsuStateLayer {
                            radius: parent.radius
                            onClicked: root.numericMode = !root.numericMode
                        }

                        CortetsuText {
                            anchors.centerIn: parent
                            text: root.numericMode ? "123" : "%"
                            color: root.numericMode
                                ? CortetsuDesign.colorOnSecondaryContainer
                                : CortetsuDesign.colorOnSurfaceVariant
                            textSize: CortetsuTypography.labelMediumPx
                        }
                    }

                    Rectangle {
                        id: pauseButton
                        width: 44
                        height: 42
                        radius: CortetsuDesign.radiusMedium
                        color: root.paused
                            ? CortetsuDesign.colorSecondaryContainer
                            : CortetsuDesign.colorSurfaceHigh

                        CortetsuStateLayer {
                            radius: parent.radius
                            onClicked: root.togglePause()
                        }

                        CortetsuIcon {
                            anchors.centerIn: parent
                            text: root.paused ? "play_arrow" : "pause"
                            color: root.paused
                                ? CortetsuDesign.colorOnSurface
                                : CortetsuDesign.colorOnSurfaceVariant
                        }
                    }
                }

                Row {
                    width: parent.width
                    height: 26

                    CortetsuText {
                        width: parent.width * 0.43
                        text: qsTr("Proceso")
                        color: CortetsuDesign.colorOutline
                        textSize: CortetsuTypography.labelSmallPx
                    }
                    CortetsuText {
                        width: parent.width * 0.17
                        text: qsTr("Usuario")
                        color: CortetsuDesign.colorOutline
                        textSize: CortetsuTypography.labelSmallPx
                    }
                    CortetsuText {
                        width: parent.width * 0.12
                        text: qsTr("PID")
                        color: CortetsuDesign.colorOutline
                        textSize: CortetsuTypography.labelSmallPx
                        horizontalAlignment: Text.AlignRight
                    }
                    CortetsuText {
                        width: parent.width * 0.14
                        text: root.numericMode ? qsTr("Núcleos de CPU") : qsTr("CPU %")
                        color: CortetsuDesign.colorOutline
                        textSize: CortetsuTypography.labelSmallPx
                        horizontalAlignment: Text.AlignRight
                    }
                    CortetsuText {
                        width: parent.width * 0.14
                        text: root.numericMode ? qsTr("RAM") : qsTr("RAM %")
                        color: CortetsuDesign.colorOutline
                        textSize: CortetsuTypography.labelSmallPx
                        horizontalAlignment: Text.AlignRight
                    }
                }

                ListView {
                    id: processList
                    width: parent.width
                    height: parent.height - 88
                    clip: true
                    spacing: 3
                    boundsBehavior: Flickable.StopAtBounds
                    model: root.visibleProcesses

                    delegate: Rectangle {
                        id: processRow
                        required property var modelData
                        required property int index
                        width: processList.width
                        height: 36
                        radius: CortetsuDesign.radiusSmall
                        color: Number(modelData?.pid) === root.selectedPid
                            ? CortetsuDesign.colorSecondaryContainer
                            : (index % 2 === 0
                                ? CortetsuDesign.colorSurface
                                : CortetsuDesign.colorSurface)

                        CortetsuStateLayer {
                            radius: parent.radius
                            onClicked: root.selectedPid = Number(processRow.modelData?.pid ?? -1)
                        }

                        Row {
                            anchors.fill: parent
                            anchors.leftMargin: 9
                            anchors.rightMargin: 9

                            CortetsuText {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width * 0.43
                                text: processRow.modelData?.name ?? "—"
                                color: CortetsuDesign.colorOnSurface
                                textSize: CortetsuTypography.bodySmallPx
                                elide: Text.ElideRight
                            }
                            CortetsuText {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width * 0.17
                                text: processRow.modelData?.user ?? "—"
                                color: CortetsuDesign.colorOnSurfaceVariant
                                textSize: CortetsuTypography.labelSmallPx
                                elide: Text.ElideRight
                            }
                            CortetsuText {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width * 0.12
                                text: String(processRow.modelData?.pid ?? "—")
                                color: CortetsuDesign.colorOutline
                                textSize: CortetsuTypography.labelSmallPx
                                horizontalAlignment: Text.AlignRight
                            }
                            CortetsuText {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width * 0.14
                                text: root.cpuText(processRow.modelData)
                                color: Number(processRow.modelData?.cpu ?? 0) >= 50
                                    ? CortetsuDesign.colorPrimary
                                    : CortetsuDesign.colorOnSurfaceVariant
                                textSize: CortetsuTypography.labelSmallPx
                                horizontalAlignment: Text.AlignRight
                                elide: Text.ElideLeft
                            }
                            CortetsuText {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width * 0.14
                                text: root.ramText(processRow.modelData)
                                color: CortetsuDesign.colorOnSurfaceVariant
                                textSize: CortetsuTypography.labelSmallPx
                                horizontalAlignment: Text.AlignRight
                                elide: Text.ElideLeft
                            }
                        }
                    }
                }
            }
        }

        Rectangle {
            id: details
            width: parent.width - listCard.width - 12
            height: parent.height
            radius: CortetsuDesign.radiusLarge
            color: CortetsuDesign.colorSurface
            border.width: 1
            border.color: CortetsuDesign.colorOutlineVariant

            Column {
                id: detailsBody
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: actionArea.top
                anchors.margins: 18
                anchors.bottomMargin: 12
                spacing: 12

                Row {
                    width: parent.width
                    spacing: 10

                    Rectangle {
                        width: 44
                        height: 44
                        radius: CortetsuDesign.radiusMedium
                        color: CortetsuDesign.colorPrimaryContainer

                        CortetsuIcon {
                            anchors.centerIn: parent
                            text: "terminal"
                            color: CortetsuDesign.colorOnPrimaryContainer
                            iconSize: CortetsuTypography.iconLargePx
                        }
                    }

                    Column {
                        width: parent.width - 54
                        spacing: 1

                        CortetsuText {
                            width: parent.width
                            text: root.selectedProcess?.name ?? qsTr("No hay proceso seleccionado")
                            color: CortetsuDesign.colorOnSurface
                            textSize: CortetsuTypography.titleMediumPx
                            elide: Text.ElideRight
                        }

                        CortetsuText {
                            width: parent.width
                            text: root.selectedProcess?.pid
                                ? `PID ${root.selectedProcess.pid} · ${root.selectedProcess?.user ?? "—"}`
                                : ""
                            color: CortetsuDesign.colorOnSurfaceVariant
                            textSize: CortetsuTypography.labelMediumPx
                        }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 104
                    radius: CortetsuDesign.radiusMedium
                    color: CortetsuDesign.colorSurfaceHigh

                    CortetsuText {
                        anchors.fill: parent
                        anchors.margins: 12
                        text: root.selectedProcess?.command ?? qsTr("Selecciona un proceso para inspeccionar su línea de comandos.")
                        color: CortetsuDesign.colorOnSurfaceVariant
                        textSize: CortetsuTypography.bodySmallPx
                        wrapMode: Text.WrapAnywhere
                        elide: Text.ElideRight
                        maximumLineCount: 5
                    }
                }

                Repeater {
                    model: [
                        { label: qsTr("CPU"), value: root.cpuText(root.selectedProcess) },
                        { label: qsTr("Memoria"), value: root.ramText(root.selectedProcess) },
                        { label: qsTr("Estado"), value: root.selectedProcess?.state ?? "—" },
                        { label: qsTr("Hilos"), value: String(root.selectedProcess?.threads ?? "—") },
                        { label: qsTr("PID padre"), value: String(root.selectedProcess?.ppid ?? "—") },
                        { label: qsTr("Tiempo transcurrido"), value: root.selectedProcess?.elapsed_sec !== undefined ? `${Math.floor(Number(root.selectedProcess.elapsed_sec) / 60)}m` : "—" }
                    ]

                    delegate: Row {
                        required property var modelData
                        width: parent.width
                        height: 23

                        CortetsuText {
                            width: parent.width * 0.46
                            text: modelData.label
                            color: CortetsuDesign.colorOutline
                            textSize: CortetsuTypography.labelSmallPx
                        }

                        CortetsuText {
                            width: parent.width * 0.54
                            text: modelData.value
                            color: CortetsuDesign.colorOnSurfaceVariant
                            textSize: CortetsuTypography.labelSmallPx
                            horizontalAlignment: Text.AlignRight
                            elide: Text.ElideLeft
                        }
                    }
                }
            }

            Column {
                id: actionArea
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.leftMargin: 18
                anchors.rightMargin: 18
                anchors.bottomMargin: 18
                spacing: 8

                CortetsuText {
                    width: parent.width
                    visible: root.actionStatus.length > 0
                    text: root.actionStatus
                    color: CortetsuDesign.colorPrimary
                    textSize: CortetsuTypography.labelSmallPx
                    elide: Text.ElideRight
                }

                Grid {
                    width: parent.width
                    columns: 2
                    columnSpacing: 8
                    rowSpacing: 8

                    Rectangle {
                        width: (parent.width - 8) / 2
                        height: 40
                        radius: CortetsuDesign.radiusMedium
                        color: CortetsuDesign.colorSecondaryContainer

                        CortetsuStateLayer {
                            radius: parent.radius
                            onClicked: root.toggleSelectedPause()
                        }

                        Row {
                            anchors.centerIn: parent
                            spacing: 6
                            CortetsuIcon {
                                text: root.selectedStopped ? "play_arrow" : "pause"
                                color: CortetsuDesign.colorOnSecondaryContainer
                                iconSize: CortetsuTypography.iconSmallPx
                            }
                            CortetsuText {
                                text: root.selectedStopped ? qsTr("Reanudar") : qsTr("Pausar")
                                color: CortetsuDesign.colorOnSecondaryContainer
                                textSize: CortetsuTypography.labelMediumPx
                            }
                        }
                    }

                    Rectangle {
                        width: (parent.width - 8) / 2
                        height: 40
                        radius: CortetsuDesign.radiusMedium
                        color: CortetsuDesign.colorSurfaceHigh

                        CortetsuStateLayer {
                            radius: parent.radius
                            onClicked: root.sendSignal("INT")
                        }

                        Row {
                            anchors.centerIn: parent
                            spacing: 6
                            CortetsuIcon {
                                text: "cancel"
                                color: CortetsuDesign.colorOnSurfaceVariant
                                iconSize: CortetsuTypography.iconSmallPx
                            }
                            CortetsuText {
                                text: qsTr("Interrumpir")
                                color: CortetsuDesign.colorOnSurfaceVariant
                                textSize: CortetsuTypography.labelMediumPx
                            }
                        }
                    }

                    Rectangle {
                        width: (parent.width - 8) / 2
                        height: 40
                        radius: CortetsuDesign.radiusMedium
                        color: CortetsuDesign.colorSecondaryContainer

                        CortetsuStateLayer {
                            radius: parent.radius
                            onClicked: root.sendSignal("TERM")
                        }

                        Row {
                            anchors.centerIn: parent
                            spacing: 6
                            CortetsuIcon {
                                text: "power_settings_new"
                                color: CortetsuDesign.colorOnSurface
                                iconSize: CortetsuTypography.iconSmallPx
                            }
                            CortetsuText {
                                text: qsTr("Terminar")
                                color: CortetsuDesign.colorOnSurface
                                textSize: CortetsuTypography.labelMediumPx
                            }
                        }
                    }

                    Rectangle {
                        width: (parent.width - 8) / 2
                        height: 40
                        radius: CortetsuDesign.radiusMedium
                        color: Qt.darker(CortetsuDesign.colorVermillion, 1.5)

                        CortetsuStateLayer {
                            radius: parent.radius
                            onClicked: root.sendSignal("KILL")
                        }

                        Row {
                            anchors.centerIn: parent
                            spacing: 6
                            CortetsuIcon {
                                text: "dangerous"
                                color: CortetsuDesign.colorOnSurface
                                iconSize: CortetsuTypography.iconSmallPx
                            }
                            CortetsuText {
                                text: qsTr("Forzar cierre")
                                color: CortetsuDesign.colorOnSurface
                                textSize: CortetsuTypography.labelMediumPx
                            }
                        }
                    }
                }
            }
        }
    }
}
