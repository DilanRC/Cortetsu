pragma ComponentBehavior: Bound

import QtQuick
import ".."
import "../../components"
import "../../theme"
import "../CortetsuTypography.js" as CortetsuTypography
import "summary"
import "Format.js" as Format
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
    // A forced close needs a second press within a few seconds.
    property bool killArmed: false

    readonly property bool hasSelection: Number(selectedProcess?.pid ?? -1) > 1
    readonly property var stateLabels: ({
        "R": qsTr("En ejecución"),
        "S": qsTr("En espera"),
        "D": qsTr("Esperando al disco"),
        "I": qsTr("Inactivo"),
        "T": qsTr("Detenido"),
        "t": qsTr("Detenido por depurador"),
        "Z": qsTr("Zombi")
    })

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
        actionStatus = qsTr("Señal %1 enviada al proceso %2").arg(signal).arg(pid);
    }

    function forceClose(): void {
        if (!root.killArmed) {
            root.killArmed = true;
            disarm.restart();
            return;
        }
        root.killArmed = false;
        sendSignal("KILL");
    }

    function moveSelection(delta): void {
        const list = root.visibleProcesses;
        if (list.length === 0)
            return;
        const at = list.findIndex(p => Number(p?.pid) === root.selectedPid);
        const next = Math.max(0, Math.min(list.length - 1, (at < 0 ? 0 : at) + delta));
        root.selectedPid = Number(list[next].pid);
        processList.positionViewAtIndex(next, ListView.Contain);
    }

    onSelectedPidChanged: root.killArmed = false

    Timer {
        id: disarm
        interval: 4000
        onTriggered: root.killArmed = false
    }

    function toggleSelectedPause(): void {
        sendSignal(selectedStopped ? "CONT" : "STOP");
    }

    function cpuText(proc): string {
        const usage = Number(proc?.cpu ?? 0);
        return numericMode ? (usage / 100).toFixed(2) : `${usage.toFixed(1)} %`;
    }

    function ramGiB(proc): real {
        return Math.max(0, Number(memoryTotalGb)) * Math.max(0, Number(proc?.mem ?? 0)) / 100;
    }

    function ramText(proc): string {
        const pct = Number(proc?.mem ?? 0);
        if (!numericMode)
            return `${pct.toFixed(1)} %`;
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
        spacing: CortetsuDesign.spacingStandard

        Panel {
            id: listCard
            width: Math.round((parent.width - parent.spacing) * 0.66)
            height: parent.height

            Row {
                id: toolbar
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: 38
                spacing: CortetsuDesign.spacingCompact

                CortetsuSearchBar {
                    id: search
                    objectName: "processSearch"
                    width: parent.width - units.width - freeze.width - parent.spacing * 2
                    compact: true
                    placeholderText: qsTr("Filtrar por nombre, usuario, comando o PID")
                    text: root.filterText
                    onTextChanged: root.filterText = text
                }

                CortetsuButton {
                    id: units
                    compact: true
                    height: parent.height
                    icon: "swap_horiz"
                    label: root.numericMode ? qsTr("Núcleos y MiB") : qsTr("Porcentaje")
                    tooltipText: qsTr("Cambiar entre cantidades y porcentaje")
                    onClicked: root.numericMode = !root.numericMode
                }

                CortetsuButton {
                    id: freeze
                    compact: true
                    height: parent.height
                    active: root.paused
                    icon: root.paused ? "play_arrow" : "pause"
                    label: root.paused ? qsTr("Reanudar lista") : qsTr("Congelar lista")
                    tooltipText: qsTr("Detiene la actualización de la lista, no los procesos")
                    onClicked: root.togglePause()
                }
            }

            Item {
                id: columns
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: toolbar.bottom
                anchors.topMargin: CortetsuDesign.spacingCompact
                anchors.leftMargin: CortetsuDesign.spacingCompact
                anchors.rightMargin: CortetsuDesign.spacingCompact
                height: 28

                ColumnHeader { x: 0; width: parent.width * 0.42; label: qsTr("Proceso"); key: "name" }
                ColumnHeader { x: parent.width * 0.42; width: parent.width * 0.16; label: qsTr("Usuario"); key: "user" }
                ColumnHeader { x: parent.width * 0.58; width: parent.width * 0.12; label: qsTr("PID"); key: "pid"; alignRight: true }
                ColumnHeader { x: parent.width * 0.70; width: parent.width * 0.15; label: root.numericMode ? qsTr("Núcleos") : qsTr("CPU"); key: "cpu"; alignRight: true }
                ColumnHeader { x: parent.width * 0.85; width: parent.width * 0.15; label: qsTr("Memoria"); key: "mem"; alignRight: true }
            }

            ListView {
                id: processList
                objectName: "processList"
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: columns.bottom
                anchors.bottom: parent.bottom
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                activeFocusOnTab: true
                // Rows are matched by PID, so a new reading moves and updates
                // them in place and the scroll position stays where it was.
                model: ScriptModel {
                    values: root.visibleProcesses
                    objectProp: "pid"
                }

                Keys.onUpPressed: root.moveSelection(-1)
                Keys.onDownPressed: root.moveSelection(1)
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_PageUp) { root.moveSelection(-10); event.accepted = true; }
                    else if (event.key === Qt.Key_PageDown) { root.moveSelection(10); event.accepted = true; }
                }

                delegate: Item {
                    id: processRow
                    required property var modelData
                    readonly property bool selected: Number(processRow.modelData?.pid) === root.selectedPid

                    width: processList.width
                    height: 32

                    CortetsuSurface {
                        anchors.fill: parent
                        radiusValue: CortetsuDesign.radiusSmall
                        outlined: false
                        active: processRow.selected
                        hovered: rowMouse.containsMouse
                        focused: processRow.selected && processList.activeFocus
                        baseColor: Qt.alpha(CortetsuDesign.colorSurfaceGlass, 0)
                        hoverColor: CortetsuDesign.colorSurfaceGlassStrong
                        activeColor: Qt.alpha(CortetsuDesign.colorPrimaryContainer, 0.76)
                        outlineColor: Qt.alpha(CortetsuDesign.colorWashi, 0.86)
                    }

                    MouseArea {
                        id: rowMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            processList.forceActiveFocus();
                            root.selectedPid = Number(processRow.modelData?.pid ?? -1);
                        }
                    }

                    Item {
                        anchors.fill: parent
                        anchors.leftMargin: CortetsuDesign.spacingCompact
                        anchors.rightMargin: CortetsuDesign.spacingCompact

                        Cell { x: 0; width: parent.width * 0.42; text: processRow.modelData?.name ?? ""; strong: true }
                        Cell { x: parent.width * 0.42; width: parent.width * 0.16; text: processRow.modelData?.user ?? "" }
                        Cell { x: parent.width * 0.58; width: parent.width * 0.12; text: String(processRow.modelData?.pid ?? ""); alignRight: true }
                        Cell { x: parent.width * 0.70; width: parent.width * 0.15; text: root.cpuText(processRow.modelData); alignRight: true; strong: Number(processRow.modelData?.cpu ?? 0) >= 50 }
                        Cell { x: parent.width * 0.85; width: parent.width * 0.15; text: root.ramText(processRow.modelData); alignRight: true }
                    }
                }
            }

            CortetsuStateMessage {
                anchors.centerIn: processList
                visible: root.visibleProcesses.length === 0
                width: 320
                kind: "empty"
                icon: root.filterText.length > 0 ? "search_off" : "hourglass_empty"
                title: root.filterText.length > 0 ? qsTr("Ningún proceso coincide") : qsTr("Leyendo procesos…")
                detail: root.filterText.length > 0 ? qsTr("Prueba con menos términos o con el PID.") : ""
            }
        }

        Panel {
            width: parent.width - listCard.width - parent.spacing
            height: parent.height

            Column {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                spacing: CortetsuDesign.spacingCompact

                SummaryLabel {
                    icon: "terminal"
                    text: root.hasSelection ? (root.selectedProcess.name ?? "") : qsTr("Sin selección")
                    detail: root.hasSelection ? qsTr("PID %1 · %2").arg(root.selectedProcess.pid).arg(root.selectedProcess.user ?? "") : ""
                    anchors.rightMargin: 0
                }

                CortetsuText {
                    width: parent.width
                    text: root.hasSelection
                        ? (root.selectedProcess.command ?? "")
                        : qsTr("Elige un proceso de la lista para ver su comando y actuar sobre él.")
                    color: CortetsuDesign.colorOnSurfaceVariant
                    textSize: CortetsuTypography.bodySmallPx
                    wrapMode: Text.WrapAnywhere
                    elide: Text.ElideRight
                    maximumLineCount: 5
                }

                Item { width: 1; height: CortetsuDesign.spacingUnit }

                Column {
                    visible: root.hasSelection
                    width: parent.width

                    FactRow { width: parent.width; label: root.numericMode ? qsTr("Núcleos en uso") : qsTr("CPU"); value: root.cpuText(root.selectedProcess); emphasized: true }
                    FactRow { width: parent.width; label: qsTr("Memoria"); value: root.ramText(root.selectedProcess); emphasized: true }
                    FactRow { width: parent.width; label: qsTr("Estado"); value: root.stateLabels[root.selectedProcess?.state] ?? String(root.selectedProcess?.state ?? "") }
                    FactRow { width: parent.width; label: qsTr("Hilos"); value: Format.fixed(root.selectedProcess?.threads, 0) }
                    FactRow { width: parent.width; label: qsTr("Proceso padre"); value: Format.fixed(root.selectedProcess?.ppid, 0) }
                    FactRow { width: parent.width; label: qsTr("Tiempo activo"); value: Format.duration(root.selectedProcess?.elapsed_sec) }
                }
            }

            Column {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                spacing: CortetsuDesign.spacingCompact

                CortetsuText {
                    width: parent.width
                    text: root.killArmed
                        ? qsTr("Pulsa otra vez para forzar el cierre. Se pierden los datos sin guardar.")
                        : root.actionStatus
                    visible: text.length > 0
                    color: CortetsuDesign.colorOnSurfaceMuted
                    textSize: CortetsuTypography.labelSmallPx
                    wrapMode: Text.WordWrap
                }

                Grid {
                    id: actions
                    width: parent.width
                    columns: 2
                    columnSpacing: CortetsuDesign.spacingCompact
                    rowSpacing: CortetsuDesign.spacingCompact

                    readonly property real cell: (width - columnSpacing) / 2

                    CortetsuButton {
                        width: actions.cell
                        disabled: !root.hasSelection
                        icon: root.selectedStopped ? "play_arrow" : "pause"
                        label: root.selectedStopped ? qsTr("Reanudar") : qsTr("Pausar")
                        onClicked: root.toggleSelectedPause()
                    }

                    CortetsuButton {
                        width: actions.cell
                        disabled: !root.hasSelection
                        icon: "cancel"
                        label: qsTr("Interrumpir")
                        tooltipText: qsTr("Envía SIGINT, como Ctrl+C")
                        onClicked: root.sendSignal("INT")
                    }

                    CortetsuButton {
                        width: actions.cell
                        disabled: !root.hasSelection
                        icon: "power_settings_new"
                        label: qsTr("Terminar")
                        tooltipText: qsTr("Envía SIGTERM: el proceso puede cerrar con orden")
                        onClicked: root.sendSignal("TERM")
                    }

                    CortetsuButton {
                        objectName: "forceClose"
                        width: actions.cell
                        disabled: !root.hasSelection
                        danger: true
                        icon: "dangerous"
                        label: root.killArmed ? qsTr("Confirmar") : qsTr("Forzar cierre")
                        tooltipText: qsTr("Envía SIGKILL: cierre inmediato")
                        onClicked: root.forceClose()
                    }
                }
            }
        }
    }

    // A column title that sorts by its column.
    component ColumnHeader: Item {
        id: columnHeader

        property string label: ""
        property string key: ""
        property bool alignRight: false
        readonly property bool current: root.sortKey === columnHeader.key

        height: parent.height
        activeFocusOnTab: true
        Accessible.role: Accessible.Button
        Accessible.name: qsTr("Ordenar por %1").arg(columnHeader.label)
        Accessible.onPressAction: root.setSort(columnHeader.key)

        Row {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: columnHeader.alignRight ? undefined : parent.left
            anchors.right: columnHeader.alignRight ? parent.right : undefined
            spacing: 2

            CortetsuText {
                anchors.verticalCenter: parent.verticalCenter
                text: columnHeader.label
                color: columnHeader.current || columnHeader.activeFocus || headerMouse.containsMouse
                    ? CortetsuDesign.colorOnSurface
                    : CortetsuDesign.colorOnSurfaceVariant
                textSize: CortetsuTypography.labelMediumPx
                font.weight: columnHeader.current ? Font.DemiBold : Font.Normal
                font.underline: columnHeader.activeFocus
            }

            CortetsuIcon {
                anchors.verticalCenter: parent.verticalCenter
                visible: columnHeader.current
                text: root.sortDescending ? "arrow_downward" : "arrow_upward"
                color: CortetsuDesign.colorOnSurface
                iconSize: 14
            }
        }

        MouseArea {
            id: headerMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.setSort(columnHeader.key)
        }

        Keys.onEnterPressed: root.setSort(columnHeader.key)
        Keys.onReturnPressed: root.setSort(columnHeader.key)
        Keys.onSpacePressed: root.setSort(columnHeader.key)
    }

    component Cell: CortetsuText {
        property bool alignRight: false
        property bool strong: false

        anchors.verticalCenter: parent.verticalCenter
        color: strong ? CortetsuDesign.colorOnSurface : CortetsuDesign.colorOnSurfaceMuted
        textSize: CortetsuTypography.bodySmallPx
        horizontalAlignment: alignRight ? Text.AlignRight : Text.AlignLeft
        elide: Text.ElideRight
    }
}
