pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtCore
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import ".."
import "../CortetsuDesign.js" as CortetsuDesign
import "../CortetsuTypography.js" as CortetsuTypography
import "../../components"

Item {
    id: root

    property var entries: []
    property string query: ""
    property string sourceFilter: "all"
    property string enabledFilter: "all"
    property var selected: null
    property string statusText: qsTr("Abre la página para inspeccionar el inicio automático.")
    property bool busy: false
    property string pendingActionError: ""
    property string stopConfirmationId: ""

    property string helperPath: StandardPaths.writableLocation(StandardPaths.HomeLocation) + "/.local/bin/cortetsu-startup"
    readonly property var visibleEntries: entries.filter(entry => {
        const source = String(entry.sourceType ?? "");
        const sourceMatch = sourceFilter === "all"
            || (sourceFilter === "apps" && source.startsWith("xdg-"))
            || (sourceFilter === "user" && source === "systemd-user")
            || (sourceFilter === "session" && ["hyprland", "cortetsu"].includes(source))
            || (sourceFilter === "system" && source === "systemd-system");
        const stateMatch = enabledFilter === "all" || entry.configured === (enabledFilter === "enabled");
        const term = query.trim().toLowerCase();
        const textMatch = !term || `${entry.name} ${entry.command} ${entry.origin} ${entry.description}`.toLowerCase().includes(term);
        return sourceMatch && stateMatch && textMatch;
    })

    function scan(): void {
        if (!busy) {
            busy = true;
            statusText = qsTr("Leyendo fuentes de inicio…");
            scanProcess.running = true;
        }
    }

    function setEnabled(item, enabled): void {
        if (busy || !item?.modifiable)
            return;
        requestedId = String(item.id);
        requestedState = enabled ? "enable" : "disable";
        busy = true;
        statusText = qsTr("Aplicando y verificando el cambio…");
        setProcess.running = true;
    }

    function requestStop(item): void {
        if (busy || item?.sourceType !== "systemd-user" || !item?.modifiable || item?.running !== true)
            return;
        if (stopConfirmationId !== item.id) {
            stopConfirmationId = item.id;
            statusText = qsTr("Pulsa Confirmar detener para detener esta unidad ahora.");
            return;
        }
        requestedId = String(item.id);
        requestedState = "stop";
        stopConfirmationId = "";
        busy = true;
        statusText = qsTr("Deteniendo y verificando la unidad…");
        setProcess.running = true;
    }

    function sourceLabel(item): string {
        return ({
            "xdg-user": qsTr("XDG · usuario"),
            "xdg-system": qsTr("XDG · sistema"),
            "systemd-user": qsTr("systemd · usuario"),
            "systemd-system": qsTr("systemd · sistema"),
            "hyprland": qsTr("Hyprland"),
            "cortetsu": qsTr("Cortetsu")
        })[item?.sourceType] ?? qsTr("Otra fuente");
    }

    function phaseLabel(phase): string {
        return ({
            "boot": qsTr("Sistema"),
            "login": qsTr("Sesión"),
            "shell": qsTr("Hyprland/Cortetsu"),
            "on-demand": qsTr("Bajo demanda")
        })[phase] ?? qsTr("Desconocido");
    }

    function acceptScan(result): void {
        busy = false;
        const actionError = pendingActionError;
        pendingActionError = "";
        if (!result?.ok || !Array.isArray(result.entries)) {
            statusText = (actionError ? `${qsTr("Cambio no aplicado")}: ${actionError} · ` : "")
                + (result?.error ?? qsTr("No se pudo leer el inventario."));
            return;
        }
        entries = result.entries;
        selected = selected ? entries.find(entry => entry.id === selected.id) ?? null : null;
        statusText = (actionError ? `${qsTr("Cambio no aplicado")}: ${actionError} · ` : "")
            + qsTr("Inventario actualizado")
            + ` · ${entries.filter(entry => entry.configured && entry.eligible !== false).length} habilitados`
            + ` · ${entries.filter(entry => entry.configured).length} configurados`
            + ` · ${entries.filter(entry => entry.running === true).length} ejecutándose`
            + ` · ${entries.filter(entry => entry.duplicateCount > 1).length} con inicio duplicado`;
    }

    property string requestedId: ""
    property string requestedState: ""

    Component.onCompleted: scan()

    Process {
        id: scanProcess
        command: [root.helperPath, "scan"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.acceptScan(JSON.parse(text.trim())); }
                catch (error) { root.acceptScan({ ok: false, error: String(error) }); }
            }
        }
    }

    Process {
        id: setProcess
        command: [root.helperPath, "set", root.requestedId, root.requestedState]
        stdout: StdioCollector {
            onStreamFinished: {
                let result;
                try { result = JSON.parse(text.trim()); }
                catch (error) { result = { ok: false, error: String(error) }; }
                root.pendingActionError = result?.ok ? "" : String(result?.error ?? qsTr("No se pudo aplicar el cambio"));
                root.busy = false;
                root.scan();
            }
        }
    }

    Column {
        anchors.fill: parent
        spacing: CortetsuDesign.spacingCompact

        Row {
            width: parent.width
            spacing: CortetsuDesign.spacingCompact

            CortetsuText {
                width: parent.width - refresh.width - parent.spacing
                text: `${qsTr("Inicio automático")} · ${root.statusText}`
                textSize: CortetsuTypography.bodySmallPx
                color: CortetsuDesign.colorOnSurfaceVariant
                elide: Text.ElideRight
            }
            CortetsuButton {
                id: refresh
                label: qsTr("Actualizar")
                disabled: root.busy
                onClicked: root.scan()
            }
        }

        Row {
            width: parent.width
            spacing: CortetsuDesign.spacingCompact
            TextField {
                width: parent.width * 0.39
                height: 44
                placeholderText: qsTr("Buscar nombre, comando, unidad u origen")
                text: root.query
                onTextChanged: root.query = text
                palette.text: CortetsuDesign.colorOnSurface
                palette.placeholderText: CortetsuDesign.colorOnSurfaceVariant
                background: Rectangle {
                    radius: CortetsuDesign.radiusMedium
                    color: CortetsuDesign.colorSurface
                    border.width: 1
                    border.color: CortetsuDesign.colorOutlineVariant
                }
            }
            ComboBox {
                width: parent.width * 0.32
                height: 44
                model: [qsTr("Todas las fuentes"), qsTr("Aplicaciones"), qsTr("Servicios de usuario"), qsTr("Hyprland/Cortetsu"), qsTr("Sistema")]
                onActivated: root.sourceFilter = ["all", "apps", "user", "session", "system"][currentIndex]
                palette.buttonText: CortetsuDesign.colorOnSurface
                palette.button: CortetsuDesign.colorSurface
                background: Rectangle { radius: CortetsuDesign.radiusMedium; color: CortetsuDesign.colorSurface; border.width: 1; border.color: CortetsuDesign.colorOutlineVariant }
            }
            ComboBox {
                width: parent.width * 0.23
                height: 44
                model: [qsTr("Todos los estados"), qsTr("Habilitados"), qsTr("Deshabilitados")]
                onActivated: root.enabledFilter = ["all", "enabled", "disabled"][currentIndex]
                palette.buttonText: CortetsuDesign.colorOnSurface
                palette.button: CortetsuDesign.colorSurface
                background: Rectangle { radius: CortetsuDesign.radiusMedium; color: CortetsuDesign.colorSurface; border.width: 1; border.color: CortetsuDesign.colorOutlineVariant }
            }
        }

        Row {
            width: parent.width
            height: parent.height - 104
            spacing: CortetsuDesign.spacingStandard

            ListView {
                id: list
                width: root.selected ? parent.width * 0.56 : parent.width
                height: parent.height
                clip: true
                spacing: CortetsuDesign.spacingCompact
                model: root.visibleEntries
                ScrollBar.vertical: ScrollBar {}
                Text {
                    anchors.centerIn: parent
                    visible: !root.busy && root.visibleEntries.length === 0
                    text: qsTr("No hay entradas para estos filtros")
                    color: CortetsuDesign.colorOnSurfaceVariant
                }
                delegate: Rectangle {
                    required property var modelData
                    required property int index
                    width: list.width - 8
                    height: 78
                    radius: CortetsuDesign.radiusMedium
                    color: root.selected?.id === modelData.id
                        ? Qt.alpha(CortetsuDesign.colorPrimaryContainer, 0.7)
                        : CortetsuDesign.colorSurface
                    border.width: 1
                    border.color: CortetsuDesign.colorOutlineVariant
                    activeFocusOnTab: true
                    focus: root.selected?.id === modelData.id

                    MouseArea {
                        anchors.fill: parent
                        onClicked: { root.selected = modelData; parent.forceActiveFocus(); }
                    }
                    Keys.onReturnPressed: root.selected = modelData
                    Keys.onEnterPressed: root.selected = modelData
                    Keys.onSpacePressed: root.selected = modelData
                    Row {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 8
                        IconImage {
                            anchors.verticalCenter: parent.verticalCenter
                            implicitSize: 26
                            source: modelData.icon ? Quickshell.iconPath(modelData.icon, "image-missing") : Quickshell.iconPath("application-x-executable", "image-missing")
                        }
                        Column {
                            width: parent.width - toggle.width - parent.spacing - 34
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2
                            CortetsuText { width: parent.width; text: modelData.name; textSize: CortetsuTypography.bodyPx; elide: Text.ElideRight }
                            CortetsuText { width: parent.width; text: `${root.sourceLabel(modelData)} · ${modelData.origin}`; textSize: CortetsuTypography.labelSmallPx; color: CortetsuDesign.colorOnSurfaceVariant; elide: Text.ElideMiddle }
                            CortetsuText {
                                width: parent.width
                                text: `${qsTr("Configuración automática")}: ${modelData.configured ? qsTr("ON") : qsTr("OFF")}${modelData.eligible === false ? ` · ${qsTr("No aplicable en esta sesión")}` : ""} · ${modelData.running === null ? qsTr("Estado: desconocido") : modelData.running ? qsTr("Ejecutándose") : qsTr("Detenido")}${modelData.duplicateCount > 1 ? ` · ${modelData.duplicateCount} fuentes` : ""}`
                                textSize: CortetsuTypography.labelSmallPx
                                color: modelData.duplicateCount > 1 ? CortetsuDesign.colorWarning : CortetsuDesign.colorOnSurfaceVariant
                                elide: Text.ElideRight
                            }
                        }
                        Item {
                            width: 46
                            height: 44
                            CortetsuToggle {
                                id: toggle
                                anchors.centerIn: parent
                                checked: modelData.configured
                                disabled: root.busy || !modelData.modifiable
                                Accessible.name: `${qsTr("Inicio automático para")} ${modelData.name}`
                                Accessible.description: root.sourceLabel(modelData)
                                onToggled: checked => root.setEnabled(modelData, checked)
                            }
                        }
                    }
                }
            }

            Rectangle {
                visible: root.selected !== null
                    width: parent.width - list.width - parent.spacing
                height: parent.height
                radius: CortetsuDesign.radiusMedium
                color: CortetsuDesign.colorSurface
                border.width: 1
                border.color: CortetsuDesign.colorOutlineVariant
                Flickable {
                    anchors.fill: parent
                    anchors.margins: CortetsuDesign.spacingComfortable
                    contentHeight: details.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar {}
                    Column {
                        id: details
                        width: parent.width
                        spacing: CortetsuDesign.spacingCompact
                        CortetsuText { width: parent.width; text: root.selected?.name ?? ""; textSize: CortetsuTypography.titleMediumPx; elide: Text.ElideRight }
                        CortetsuText { width: parent.width; text: qsTr("Por qué se inicia"); textSize: CortetsuTypography.bodyPx; color: CortetsuDesign.colorPrimary }
                        IconImage { implicitSize: 36; source: root.selected?.icon ? Quickshell.iconPath(root.selected.icon, "image-missing") : Quickshell.iconPath("application-x-executable", "image-missing") }
                        CortetsuText { width: parent.width; text: root.selected?.reason ?? ""; textSize: CortetsuTypography.bodySmallPx; wrapMode: Text.WordWrap; color: CortetsuDesign.colorOnSurfaceVariant }
                        CortetsuText { width: parent.width; text: `${qsTr("Origen")}: ${root.selected?.origin ?? ""}`; textSize: CortetsuTypography.labelSmallPx; wrapMode: Text.WrapAnywhere }
                        CortetsuText { width: parent.width; visible: (root.selected?.command ?? "").length > 0; text: `${qsTr("Comando")}: ${root.selected?.command ?? ""}`; textSize: CortetsuTypography.labelSmallPx; wrapMode: Text.WrapAnywhere }
                        CortetsuText { width: parent.width; text: `${qsTr("Tipo")}: ${root.sourceLabel(root.selected)}`; textSize: CortetsuTypography.labelSmallPx }
                        CortetsuText { width: parent.width; visible: root.selected?.eligible !== undefined; text: `${qsTr("Aplicable en esta sesión")}: ${root.selected?.eligible ? qsTr("Sí") : qsTr("No; la especificación XDG excluye esta entrada")}`; textSize: CortetsuTypography.labelSmallPx; color: root.selected?.eligible === false ? CortetsuDesign.colorWarning : CortetsuDesign.colorOnSurfaceVariant; wrapMode: Text.WordWrap }
                        CortetsuText { width: parent.width; text: `${qsTr("Inicio")}: ${root.phaseLabel(root.selected?.startupPhase)}`; textSize: CortetsuTypography.labelSmallPx }
                        CortetsuText { width: parent.width; text: `${qsTr("Estado actual")}: ${root.selected?.activeState ?? (root.selected?.running === null ? qsTr("Desconocido") : root.selected?.running ? qsTr("Ejecutándose") : qsTr("Detenido"))}`; textSize: CortetsuTypography.labelSmallPx }
                        CortetsuText { width: parent.width; visible: !!root.selected?.unitState; text: `${qsTr("Estado systemd")}: ${root.selected?.unitState ?? "—"} · ${qsTr("Activación")}: ${root.selected?.target || "—"}`; textSize: CortetsuTypography.labelSmallPx; wrapMode: Text.WordWrap }
                        CortetsuButton { visible: root.selected?.sourceType === "systemd-user" && root.selected?.modifiable && root.selected?.running === true; label: root.stopConfirmationId === root.selected?.id ? qsTr("Confirmar detener") : qsTr("Detener ahora"); disabled: root.busy; onClicked: root.requestStop(root.selected) }
                        CortetsuText { width: parent.width; visible: root.selected?.sourceType === "systemd-system"; text: qsTr("Servicios del sistema: sólo lectura"); textSize: CortetsuTypography.labelSmallPx; color: CortetsuDesign.colorWarning }
                        CortetsuText { width: parent.width; visible: root.selected?.duplicateCount > 1; text: qsTr("Inicio duplicado: revisa cada origen antes de cambiarlo."); textSize: CortetsuTypography.bodySmallPx; color: CortetsuDesign.colorWarning; wrapMode: Text.WordWrap }
                    }
                }
            }
        }
    }
}
