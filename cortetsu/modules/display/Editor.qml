pragma ComponentBehavior: Bound

import QtQuick
import QtCore
import Quickshell
import Quickshell.Io
import ".."
import "../../components"
import "../CortetsuDesign.js" as CortetsuDesign
import "../CortetsuTypography.js" as CortetsuTypography

FocusScope {
    id: root

    required property ShellScreen screen
    required property var screenState
    required property bool displayVisible

    property var snapshot: ({})
    property var candidateOutputs: []
    property int selectedIndex: 0
    property var planResult: ({})
    property string statusText: qsTr("Esperando inventario de pantallas…")
    property string planStatus: qsTr("Aún no se ha probado la propuesta")

    readonly property string probePath:
        StandardPaths.writableLocation(StandardPaths.HomeLocation) + "/.local/bin/cortetsu-display-probe"
    readonly property string plannerPath:
        StandardPaths.writableLocation(StandardPaths.HomeLocation) + "/.local/bin/cortetsu-display-plan"
    readonly property var monitors: snapshot?.hyprland ?? []
    readonly property var selectedCandidate:
        selectedIndex >= 0 && selectedIndex < candidateOutputs.length ? candidateOutputs[selectedIndex] : ({})
    readonly property var selectedLive: liveByName(selectedCandidate?.name ?? "")
    readonly property int enabledCount: candidateOutputs.filter(item => item?.enabled ?? true).length

    function liveByName(name): var {
        for (const monitor of monitors) {
            if (monitor?.name === name)
                return monitor;
        }
        return ({});
    }

    function currentMode(monitor): string {
        const modes = monitor?.available_modes ?? [];
        const width = Number(monitor?.width ?? 0);
        const height = Number(monitor?.height ?? 0);
        const refresh = Number(monitor?.refresh_hz ?? 0);
        let nearest = "";
        let nearestDelta = 9999;
        for (const mode of modes) {
            const match = String(mode).match(/^(\d+)x(\d+)@([0-9.]+)/);
            if (!match)
                continue;
            if (Number(match[1]) !== width || Number(match[2]) !== height)
                continue;
            const delta = Math.abs(Number(match[3]) - refresh);
            if (delta < nearestDelta) {
                nearestDelta = delta;
                nearest = String(mode);
            }
        }
        if (nearest.length)
            return nearest;
        return modes.length ? String(modes[0]) : "preferred";
    }

    function resetCandidate(): void {
        const next = [];
        for (const monitor of monitors) {
            next.push({
                name: monitor?.name ?? "",
                enabled: !(monitor?.disabled ?? false),
                mode: currentMode(monitor),
                x: Number(monitor?.x ?? 0),
                y: Number(monitor?.y ?? 0),
                scale: Number(monitor?.scale ?? 1),
                transform: Number(monitor?.transform ?? 0)
            });
        }
        candidateOutputs = next;
        selectedIndex = Math.max(0, Math.min(selectedIndex, next.length - 1));
        planResult = ({});
        planStatus = qsTr("Propuesta restablecida al diseño actual");
    }

    function updateSelected(field, value): void {
        if (selectedIndex < 0 || selectedIndex >= candidateOutputs.length)
            return;
        const next = candidateOutputs.map(item => Object.assign({}, item));
        next[selectedIndex][field] = value;
        candidateOutputs = next;
        planResult = ({});
        planStatus = qsTr("La propuesta cambió · vuelve a probarla");
    }

    function toggleSelectedEnabled(): void {
        if (selectedIndex < 0 || selectedIndex >= candidateOutputs.length)
            return;
        const current = candidateOutputs[selectedIndex];
        if ((current?.enabled ?? true) && enabledCount <= 1) {
            planStatus = qsTr("Bloqueado: al menos una salida debe permanecer activa");
            return;
        }
        updateSelected("enabled", !(current?.enabled ?? true));
    }

    function cycleMode(delta): void {
        const modes = selectedLive?.available_modes ?? [];
        if (!modes.length)
            return;
        const current = String(selectedCandidate?.mode ?? "");
        let index = modes.indexOf(current);
        if (index < 0)
            index = 0;
        index = (index + delta + modes.length) % modes.length;
        updateSelected("mode", String(modes[index]));
    }

    function cycleTransform(delta): void {
        const current = Number(selectedCandidate?.transform ?? 0);
        updateSelected("transform", (current + delta + 8) % 8);
    }

    function parseMode(mode): var {
        const match = String(mode ?? "").match(/^(\d+)x(\d+)@?([0-9.]*)/);
        if (!match)
            return ({ width: 1920, height: 1080 });
        return ({ width: Number(match[1]), height: Number(match[2]) });
    }

    function logicalWidth(output): real {
        const size = parseMode(output?.mode);
        return size.width / Math.max(0.5, Number(output?.scale ?? 1));
    }

    function applyLaptopPreset(): void {
        const next = candidateOutputs.map(item => Object.assign({}, item));
        let found = false;
        for (const item of next) {
            const internal = String(item?.name ?? "").startsWith("eDP-");
            item.enabled = internal;
            if (internal) {
                item.x = 0;
                item.y = 0;
                found = true;
            }
        }
        if (!found) {
            planStatus = qsTr("La distribución portátil no está disponible: no hay una salida eDP activa");
            return;
        }
        candidateOutputs = next;
        selectedIndex = Math.max(0, next.findIndex(item => String(item?.name ?? "").startsWith("eDP-")));
        planResult = ({});
        planStatus = qsTr("Distribución: solo portátil · prueba la propuesta");
    }

    function applyDualPreset(): void {
        const next = candidateOutputs.map(item => Object.assign({}, item));
        const internalIndex = next.findIndex(item => String(item?.name ?? "").startsWith("eDP-"));
        const externalIndex = next.findIndex(item => !String(item?.name ?? "").startsWith("eDP-"));
        if (internalIndex < 0 || externalIndex < 0) {
            planStatus = qsTr("La distribución doble no está disponible: conecta primero una salida externa");
            return;
        }
        for (let i = 0; i < next.length; ++i)
            next[i].enabled = i === internalIndex || i === externalIndex;
        next[externalIndex].x = 0;
        next[externalIndex].y = 0;
        next[internalIndex].x = Math.round(logicalWidth(next[externalIndex]));
        next[internalIndex].y = 0;
        candidateOutputs = next;
        selectedIndex = externalIndex;
        planResult = ({});
        planStatus = qsTr("Distribución: doble · externa a la izquierda, portátil a la derecha · prueba la propuesta");
    }

    function applyExternalPreset(): void {
        const next = candidateOutputs.map(item => Object.assign({}, item));
        const externalIndex = next.findIndex(item => !String(item?.name ?? "").startsWith("eDP-"));
        if (externalIndex < 0) {
            planStatus = qsTr("La distribución externa no está disponible: no hay una salida externa conectada");
            return;
        }
        for (let i = 0; i < next.length; ++i)
            next[i].enabled = i === externalIndex;
        next[externalIndex].x = 0;
        next[externalIndex].y = 0;
        candidateOutputs = next;
        selectedIndex = externalIndex;
        planResult = ({});
        planStatus = qsTr("Distribución: solo externa · prueba la propuesta");
    }

    function layoutBounds(): var {
        if (!candidateOutputs.length)
            return ({ minX: 0, minY: 0, width: 1920, height: 1080 });
        let minX = 1e9;
        let minY = 1e9;
        let maxX = -1e9;
        let maxY = -1e9;
        let found = false;
        for (const output of candidateOutputs) {
            if (!output?.enabled)
                continue;
            const size = parseMode(output?.mode);
            const scale = Math.max(0.5, Number(output?.scale ?? 1));
            const width = size.width / scale;
            const height = size.height / scale;
            minX = Math.min(minX, Number(output?.x ?? 0));
            minY = Math.min(minY, Number(output?.y ?? 0));
            maxX = Math.max(maxX, Number(output?.x ?? 0) + width);
            maxY = Math.max(maxY, Number(output?.y ?? 0) + height);
            found = true;
        }
        if (!found)
            return ({ minX: 0, minY: 0, width: 1920, height: 1080 });
        return ({ minX, minY, width: Math.max(1, maxX - minX), height: Math.max(1, maxY - minY) });
    }

    function topologyScale(width, height): real {
        const bounds = layoutBounds();
        return Math.min((width - 36) / bounds.width, (height - 36) / bounds.height);
    }

    function refresh(): void {
        if (!displayVisible || probe.running)
            return;
        statusText = qsTr("Actualizando salidas…");
        probe.running = true;
    }

    function runPlan(): void {
        if (planner.running || !candidateOutputs.length)
            return;
        planStatus = qsTr("Validando propuesta…");
        planner.command = [plannerPath, "--candidate", JSON.stringify({ outputs: candidateOutputs })];
        planner.running = true;
    }

    function openDisplayManager(): void {
        forceActiveFocus();
        refresh();
    }

    function closeDisplayManager(): void {
        screenState.cortetsuState?.setRetained("displayManager", false);
    }

    Keys.onEscapePressed: closeDisplayManager()
    Keys.onPressed: event => {
        if (event.key === Qt.Key_R) {
            refresh();
            event.accepted = true;
        } else if (event.key === Qt.Key_P) {
            runPlan();
            event.accepted = true;
        }
    }

    Process {
        id: probe
        command: [root.probePath]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const parsed = JSON.parse(text.trim());
                    root.snapshot = parsed;
                    root.statusText = qsTr("%1 salida(s) · %2 enfocada(s)")
                        .arg(parsed?.summary?.connected ?? 0)
                        .arg(parsed?.summary?.focused ?? qsTr("ninguna"));
                    if (!root.candidateOutputs.length)
                        root.resetCandidate();
                } catch (error) {
                    root.statusText = qsTr("La consulta de pantallas devolvió JSON no válido");
                    console.warn(`Display Manager probe JSON: ${error}`);
                }
            }
        }
    }

    Process {
        id: planner
        command: []
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const parsed = JSON.parse(text.trim());
                    root.planResult = parsed;
                    root.planStatus = parsed?.ok
                        ? qsTr("Propuesta válida · %1 comando(s) de monitor").arg(parsed?.commands?.length ?? 0)
                        : qsTr("Propuesta bloqueada · %1 error(es)").arg(parsed?.errors?.length ?? 0);
                } catch (error) {
                    root.planResult = ({ ok: false, errors: [String(error)] });
                    root.planStatus = qsTr("El planificador devolvió JSON no válido");
                }
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onClicked: mouse => {
            const outsidePanel = mouse.x < panel.x || mouse.x >= panel.x + panel.width ||
                mouse.y < panel.y || mouse.y >= panel.y + panel.height;
            if (outsidePanel)
                root.closeDisplayManager();
        }
    }

    Rectangle {
        id: panel
        width: Math.min(1260, parent.width - 96)
        height: Math.min(900, parent.height - 64)
        x: Math.round((parent.width - width) / 2)
        y: Math.round((parent.height - height) / 2)
        radius: 30
        color: CortetsuDesign.colorSurfaceHigh
        border.width: 1
        border.color: CortetsuDesign.colorOutlineVariant
        clip: true

        Column {
            anchors.fill: parent
            anchors.margins: 22
            spacing: 12

            Row {
                width: parent.width
                height: 58
                spacing: 12

                Rectangle {
                    width: 52
                    height: 52
                    radius: CortetsuDesign.radiusLarge
                    color: CortetsuDesign.colorPrimaryContainer
                    CortetsuIcon {
                        anchors.centerIn: parent
                        text: "desktop_windows"
                        color: CortetsuDesign.colorOnPrimaryContainer
                        iconSize: CortetsuTypography.iconExtraLargePx
                    }
                }

                Column {
                    width: parent.width - 52 - refreshButton.width - resetButton.width - closeButton.width - 48
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 0
                    CortetsuText {
                        width: parent.width
                        text: qsTr("Gestor de pantallas")
                        color: CortetsuDesign.colorOnSurface
                        textSize: CortetsuTypography.titleLargePx
                    }
                    CortetsuText {
                        width: parent.width
                        text: root.statusText
                        color: CortetsuDesign.colorOnSurfaceVariant
                        textSize: CortetsuTypography.labelMediumPx
                        elide: Text.ElideRight
                    }
                    CortetsuText {
                        width: parent.width
                        text: qsTr("Edita con seguridad · P valida · Previsualizar es temporal · Conservar confirma · Guardar persiste")
                        color: CortetsuDesign.colorOutline
                        textSize: CortetsuTypography.labelSmallPx
                        elide: Text.ElideRight
                    }
                }

                CortetsuButton {
                    id: refreshButton
                    width: 44
                    height: 44
                    compact: true
                    label: ""
                    icon: probe.running ? "progress_activity" : "refresh"
                    tooltipText: qsTr("Actualizar pantallas")
                    anchors.verticalCenter: parent.verticalCenter
                    focus: false
                    onClicked: root.refresh()
                }
                CortetsuButton {
                    id: resetButton
                    width: 44
                    height: 44
                    compact: true
                    label: ""
                    icon: "restart_alt"
                    tooltipText: qsTr("Restablecer propuesta")
                    anchors.verticalCenter: parent.verticalCenter
                    focus: false
                    onClicked: root.resetCandidate()
                }
                CortetsuButton {
                    id: closeButton
                    width: 44
                    height: 44
                    compact: true
                    label: ""
                    icon: "close"
                    tooltipText: qsTr("Cerrar gestor de pantallas")
                    anchors.verticalCenter: parent.verticalCenter
                    focus: false
                    onClicked: root.closeDisplayManager()
                }
            }

            Row {
                width: parent.width
                height: 320
                spacing: 12

                Rectangle {
                    id: topologyCard
                    width: parent.width * 0.60
                    height: parent.height
                    radius: CortetsuDesign.radiusLarge
                    color: CortetsuDesign.colorSurface
                    border.width: 1
                    border.color: CortetsuDesign.colorOutlineVariant

                    CortetsuText {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.margins: 14
                        text: qsTr("Propuesta de topología")
                        color: CortetsuDesign.colorOnSurface
                        textSize: CortetsuTypography.titleSmallPx
                    }

                    Item {
                        id: topologyCanvas
                        anchors.fill: parent
                        anchors.margins: 18
                        anchors.topMargin: 48
                        readonly property var bounds: root.layoutBounds()
                        readonly property real factor: root.topologyScale(width, height)

                        Repeater {
                            model: root.candidateOutputs
                            delegate: Rectangle {
                                id: outputRect
                                required property var modelData
                                required property int index
                                readonly property var modeSize: root.parseMode(modelData?.mode)
                                readonly property real logicalWidth: modeSize.width / Math.max(0.5, Number(modelData?.scale ?? 1))
                                readonly property real logicalHeight: modeSize.height / Math.max(0.5, Number(modelData?.scale ?? 1))
                                x: 18 + (Number(modelData?.x ?? 0) - topologyCanvas.bounds.minX) * topologyCanvas.factor
                                y: 18 + (Number(modelData?.y ?? 0) - topologyCanvas.bounds.minY) * topologyCanvas.factor
                                width: Math.max(90, logicalWidth * topologyCanvas.factor)
                                height: Math.max(54, logicalHeight * topologyCanvas.factor)
                                visible: modelData?.enabled ?? true
                                radius: CortetsuDesign.radiusMedium
                                color: root.selectedIndex === index ? CortetsuDesign.colorSecondaryContainer : CortetsuDesign.colorSurfaceHigh
                                border.width: root.selectedIndex === index ? 2 : 1
                                border.color: root.selectedIndex === index ? CortetsuDesign.colorPrimary : CortetsuDesign.colorOutlineVariant
                                CortetsuStateLayer { radius: parent.radius; onClicked: root.selectedIndex = outputRect.index }
                                Column {
                                    anchors.centerIn: parent
                                    width: parent.width - 16
                                    spacing: 2
                                    CortetsuText {
                                        width: parent.width
                                        text: outputRect.modelData?.name ?? ""
                                        color: root.selectedIndex === outputRect.index ? CortetsuDesign.colorOnSecondaryContainer : CortetsuDesign.colorOnSurface
                                        textSize: CortetsuTypography.labelMediumPx
                                        horizontalAlignment: Text.AlignHCenter
                                        elide: Text.ElideRight
                                    }
                                    CortetsuText {
                                        width: parent.width
                                        text: String(outputRect.modelData?.mode ?? "")
                                        color: CortetsuDesign.colorOnSurfaceVariant
                                        textSize: CortetsuTypography.labelSmallPx
                                        horizontalAlignment: Text.AlignHCenter
                                        elide: Text.ElideRight
                                    }
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    width: parent.width - topologyCard.width - 12
                    height: parent.height
                    radius: CortetsuDesign.radiusLarge
                    color: CortetsuDesign.colorSurface
                    border.width: 1
                    border.color: CortetsuDesign.colorOutlineVariant

                    Column {
                        anchors.fill: parent
                        anchors.margins: 15
                        spacing: 7

                        Row {
                            width: parent.width
                            CortetsuText {
                                width: parent.width * 0.70
                                text: root.selectedCandidate?.name ?? qsTr("Sin salida")
                                color: CortetsuDesign.colorOnSurface
                                textSize: CortetsuTypography.titleMediumPx
                            }
                            CortetsuText {
                                width: parent.width * 0.30
                                text: root.selectedLive?.gpu_vendor ?? "—"
                                color: CortetsuDesign.colorPrimary
                                textSize: CortetsuTypography.labelMediumPx
                                horizontalAlignment: Text.AlignRight
                            }
                        }
                        CortetsuText {
                            width: parent.width
                            text: root.selectedLive?.description ?? ""
                            color: CortetsuDesign.colorOutline
                            textSize: CortetsuTypography.labelSmallPx
                            elide: Text.ElideRight
                        }

                        Row {
                            width: parent.width
                            height: 34
                            spacing: 7
                            Repeater {
                                model: [
                                    { label: qsTr("Portátil"), action: () => root.applyLaptopPreset() },
                                    { label: qsTr("Doble"), action: () => root.applyDualPreset() },
                                    { label: qsTr("Externa"), action: () => root.applyExternalPreset() }
                                ]
                                delegate: CortetsuButton {
                                    required property var modelData
                                    width: (parent.width - 14) / 3
                                    height: 34
                                    compact: true
                                    label: modelData.label
                                    focus: false
                                    onClicked: modelData.action()
                                }
                            }
                        }

                        Row {
                            width: parent.width; height: 42; spacing: 8
                            CortetsuButton {
                                width: 42; height: 42
                                compact: true
                                label: ""
                                icon: "chevron_left"
                                tooltipText: qsTr("Modo de pantalla anterior")
                                focus: false
                                onClicked: root.cycleMode(-1)
                            }
                            Rectangle {
                                width: parent.width - 92; height: 42; radius: CortetsuDesign.radiusMedium; color: CortetsuDesign.colorSurfaceHigh
                                CortetsuText { anchors.centerIn: parent; width: parent.width - 12; text: root.selectedCandidate?.mode ?? "—"; color: CortetsuDesign.colorOnSurface; textSize: CortetsuTypography.labelMediumPx; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideMiddle }
                            }
                            CortetsuButton {
                                width: 42; height: 42
                                compact: true
                                label: ""
                                icon: "chevron_right"
                                tooltipText: qsTr("Modo de pantalla siguiente")
                                focus: false
                                onClicked: root.cycleMode(1)
                            }
                        }

                        Repeater {
                            model: [
                                { label: qsTr("Escala"), value: Number(root.selectedCandidate?.scale ?? 1).toFixed(2), minus: () => root.updateSelected("scale", Math.max(0.5, Number(root.selectedCandidate?.scale ?? 1) - 0.25)), plus: () => root.updateSelected("scale", Math.min(3, Number(root.selectedCandidate?.scale ?? 1) + 0.25)) },
                                { label: qsTr("Posición X"), value: String(root.selectedCandidate?.x ?? 0), minus: () => root.updateSelected("x", Number(root.selectedCandidate?.x ?? 0) - 100), plus: () => root.updateSelected("x", Number(root.selectedCandidate?.x ?? 0) + 100) },
                                { label: qsTr("Posición Y"), value: String(root.selectedCandidate?.y ?? 0), minus: () => root.updateSelected("y", Number(root.selectedCandidate?.y ?? 0) - 100), plus: () => root.updateSelected("y", Number(root.selectedCandidate?.y ?? 0) + 100) },
                                { label: qsTr("Transformación"), value: String(root.selectedCandidate?.transform ?? 0), minus: () => root.cycleTransform(-1), plus: () => root.cycleTransform(1) }
                            ]
                            delegate: Row {
                                required property var modelData
                                width: parent.width; height: 31; spacing: 7
                                CortetsuText { width: parent.width * 0.36; anchors.verticalCenter: parent.verticalCenter; text: modelData.label; color: CortetsuDesign.colorOutline; textSize: CortetsuTypography.labelSmallPx }
                                CortetsuButton {
                                    width: 30; height: 30
                                    compact: true
                                    label: ""
                                    icon: "remove"
                                    tooltipText: qsTr("Reducir %1").arg(modelData.label)
                                    focus: false
                                    onClicked: modelData.minus()
                                }
                                CortetsuText { width: parent.width * 0.28; anchors.verticalCenter: parent.verticalCenter; text: modelData.value; color: CortetsuDesign.colorOnSurface; textSize: CortetsuTypography.labelMediumPx; horizontalAlignment: Text.AlignHCenter }
                                CortetsuButton {
                                    width: 30; height: 30
                                    compact: true
                                    label: ""
                                    icon: "add"
                                    tooltipText: qsTr("Aumentar %1").arg(modelData.label)
                                    focus: false
                                    onClicked: modelData.plus()
                                }
                            }
                        }

                        CortetsuButton {
                            width: parent.width
                            height: 32
                            compact: true
                            icon: (root.selectedCandidate?.enabled ?? true) ? "toggle_on" : "toggle_off"
                            label: (root.selectedCandidate?.enabled ?? true) ? qsTr("Salida activa") : qsTr("Salida desactivada")
                            active: root.selectedCandidate?.enabled ?? true
                            focus: false
                            onClicked: root.toggleSelectedEnabled()
                        }
                    }
                }
            }

            Row {
                width: parent.width
                height: 168
                spacing: 10

                Repeater {
                    model: root.candidateOutputs
                    delegate: Rectangle {
                        id: outputCard
                        required property var modelData
                        required property int index
                        width: Math.max(220, (parent.width - 10 * Math.max(0, root.candidateOutputs.length - 1)) / Math.max(1, root.candidateOutputs.length))
                        height: parent.height
                        radius: CortetsuDesign.radiusLarge
                        color: root.selectedIndex === index ? CortetsuDesign.colorSecondaryContainer : CortetsuDesign.colorSurface
                        border.width: root.selectedIndex === index ? 1 : 0
                        border.color: CortetsuDesign.colorPrimary
                        opacity: outputCard.modelData?.enabled ?? true ? 1 : 0.58
                        CortetsuStateLayer { radius: parent.radius; onClicked: root.selectedIndex = outputCard.index }
                        Column {
                            anchors.fill: parent; anchors.margins: 13; spacing: 5
                            CortetsuText { text: outputCard.modelData?.name ?? ""; color: root.selectedIndex === outputCard.index ? CortetsuDesign.colorOnSecondaryContainer : CortetsuDesign.colorOnSurface; textSize: CortetsuTypography.titleSmallPx }
                            CortetsuText { width: parent.width; text: String(outputCard.modelData?.mode ?? ""); color: CortetsuDesign.colorOnSurfaceVariant; textSize: CortetsuTypography.labelSmallPx; elide: Text.ElideRight }
                            CortetsuText { text: `${outputCard.modelData?.x ?? 0} × ${outputCard.modelData?.y ?? 0} · scale ${Number(outputCard.modelData?.scale ?? 1).toFixed(2)} · transform ${outputCard.modelData?.transform ?? 0}`; color: CortetsuDesign.colorOutline; textSize: CortetsuTypography.labelSmallPx }
                            CortetsuText { text: `${root.liveByName(outputCard.modelData?.name)?.gpu_vendor ?? "—"} · ${root.liveByName(outputCard.modelData?.name)?.drm_card ?? "—"}`; color: CortetsuDesign.colorPrimary; textSize: CortetsuTypography.labelSmallPx }
                        CortetsuText { text: `${root.liveByName(outputCard.modelData?.name)?.workspace?.name ?? qsTr("sin espacio de trabajo")} · ${(outputCard.modelData?.enabled ?? true) ? qsTr("activa") : qsTr("desactivada")}`; color: CortetsuDesign.colorOnSurfaceVariant; textSize: CortetsuTypography.labelSmallPx }
                        }
                    }
                }
            }

            Rectangle {
                width: parent.width
                // Content.qml overlays the three footer controls at the bottom
                // of this panel. Reserve that area so the dry-run card never
                // sits underneath "Apply safely" at 1920x1080.
                height: parent.height - 58 - 320 - 168 - 36 - 150
                radius: CortetsuDesign.radiusLarge
                color: CortetsuDesign.colorSurface
                border.width: 1
                border.color: CortetsuDesign.colorOutlineVariant

                Row {
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 14

                    Column {
                        width: parent.width * 0.66
                        height: parent.height
                        spacing: 5
                        CortetsuText { text: qsTr("Plan de prueba"); color: CortetsuDesign.colorOnSurface; textSize: CortetsuTypography.titleSmallPx }
                        CortetsuText { width: parent.width; text: root.planStatus; color: root.planResult?.ok ? CortetsuDesign.colorPrimary : CortetsuDesign.colorOutline; textSize: CortetsuTypography.labelMediumPx; elide: Text.ElideRight }
                        CortetsuText {
                            width: parent.width
                            height: parent.height - 46
                            text: root.planResult?.ok
                                ? (root.planResult?.hypr_lines ?? []).join("\n")
                                : ((root.planResult?.errors ?? []).concat(root.planResult?.warnings ?? [])).join("\n")
                            color: CortetsuDesign.colorOnSurfaceVariant
                            textSize: CortetsuTypography.bodySmallPx
                            wrapMode: Text.WrapAnywhere
                            elide: Text.ElideRight
                        }
                    }

                    Column {
                        width: parent.width * 0.34 - 14
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 9
                        CortetsuButton {
                            width: parent.width; height: 46
                            compact: true
                            icon: "fact_check"
                            label: planner.running ? qsTr("Validando…") : qsTr("Probar propuesta")
                            active: true
                            disabled: planner.running || !root.candidateOutputs.length
                            focus: false
                            onClicked: root.runPlan()
                        }
                        CortetsuText {
                            width: parent.width
                            text: qsTr("La prueba no cambia las salidas. Usa Previsualizar para una prueba temporal, Conservar para confirmarla y Guardar para persistirla con respaldo y reversión.")
                            color: CortetsuDesign.colorOutline
                            textSize: CortetsuTypography.bodySmallPx
                            wrapMode: Text.WordWrap
                            horizontalAlignment: Text.AlignHCenter
                        }
                    }
                }
            }
        }
    }
}
