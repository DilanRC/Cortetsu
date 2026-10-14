pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtCore
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import ".."
import "../../theme"
import "../CortetsuTypography.js" as CortetsuTypography
import "../../components"
import "summary"
import "Format.js" as Format

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
        const state = root.stateCategory(entry);
        const stateMatch = enabledFilter === "all" || state === enabledFilter;
        const term = query.trim().toLowerCase();
        const textMatch = !term || `${entry.name} ${entry.command} ${entry.origin} ${entry.description}`.toLowerCase().includes(term);
        return sourceMatch && stateMatch && textMatch;
    })

    function stateCategory(entry): string {
        return entry.startupState ?? (entry.configured ? "persistent" : "disabled");
    }

    function stateLabel(entry): string {
        if (!entry)
            return qsTr("Desconocido");
        return entry.startupLabel ?? (entry.configured ? qsTr("Configurada") : qsTr("Deshabilitada"));
    }

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
            "always-on": qsTr("Cortetsu · siempre activo"),
            "conditional": qsTr("Cortetsu · condicional"),
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
            + ` · ${entries.filter(entry => root.stateCategory(entry) === "persistent").length} ${qsTr("persistentes")}`
            + ` · ${entries.filter(entry => root.stateCategory(entry) === "runtime").length} ${qsTr("temporales")}`
            + ` · ${entries.filter(entry => root.stateCategory(entry) === "disabled").length} ${qsTr("deshabilitados")}`
            + ` · ${entries.filter(entry => root.stateCategory(entry) === "special").length} ${qsTr("no administrables")}`
            + ` · ${entries.filter(entry => root.stateCategory(entry) === "always-on").length} ${qsTr("siempre activos")}`
            + ` · ${entries.filter(entry => root.stateCategory(entry) === "conditional").length} ${qsTr("condicionales")}`
            + ` · ${entries.filter(entry => root.stateCategory(entry) === "on-demand").length} ${qsTr("bajo demanda")}`
            + ` · ${entries.filter(entry => entry.running === true).length} ejecutándose`
            + ` · ${entries.filter(entry => entry.duplicateCount > 1).length} con inicio duplicado`;
    }

    property string requestedId: ""
    property string requestedState: ""

    Component.onCompleted: scan()

    // startup inventory: cortetsu:hardware-startup-scan
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

    readonly property var sourceFilters: [
        { key: "all", label: qsTr("Todo") },
        { key: "apps", label: qsTr("Aplicaciones") },
        { key: "user", label: qsTr("Servicios de usuario") },
        { key: "session", label: qsTr("Hyprland y Cortetsu") },
        { key: "system", label: qsTr("Sistema") }
    ]
    readonly property var stateFilters: [
        { key: "all", label: qsTr("Cualquier estado") },
        { key: "persistent", label: qsTr("Persistentes") },
        { key: "runtime", label: qsTr("Temporales") },
        { key: "disabled", label: qsTr("Deshabilitados") },
        { key: "special", label: qsTr("No administrables") },
        { key: "always-on", label: qsTr("Siempre activos") },
        { key: "conditional", label: qsTr("Condicionales") },
        { key: "on-demand", label: qsTr("Bajo demanda") }
    ]

    // What qualifies an entry beyond its state, as short notes.
    function notes(entry): string {
        return Format.join([
            entry.running === true ? qsTr("en ejecución") : entry.running === false ? qsTr("detenido") : "",
            entry.runtimeOnly ? qsTr("solo esta sesión") : "",
            entry.eligible === false ? qsTr("no aplica en esta sesión") : "",
            entry.duplicateCount > 1 ? qsTr("%1 orígenes").arg(entry.duplicateCount) : ""
        ]);
    }

    Column {
        anchors.fill: parent
        spacing: CortetsuDesign.spacingCompact

        Row {
            id: toolbar
            width: parent.width
            height: 38
            spacing: CortetsuDesign.spacingCompact

            CortetsuSearchBar {
                objectName: "startupSearch"
                width: parent.width - refresh.width - parent.spacing
                compact: true
                placeholderText: qsTr("Buscar por nombre, comando, unidad u origen")
                text: root.query
                onTextChanged: root.query = text
            }

            CortetsuButton {
                id: refresh
                compact: true
                height: parent.height
                icon: "refresh"
                label: qsTr("Volver a leer")
                disabled: root.busy
                onClicked: root.scan()
            }
        }

        FilterRow {
            id: sourceRow
            width: parent.width
            options: root.sourceFilters
            current: root.sourceFilter
            onPicked: key => root.sourceFilter = key
        }

        FilterRow {
            id: stateRow
            width: parent.width
            options: root.stateFilters
            current: root.enabledFilter
            onPicked: key => root.enabledFilter = key
        }

        CortetsuText {
            id: status
            width: parent.width
            height: 20
            verticalAlignment: Text.AlignVCenter
            text: root.statusText
            textSize: CortetsuTypography.labelSmallPx
            color: root.pendingActionError ? CortetsuDesign.colorWarning : CortetsuDesign.colorOnSurfaceVariant
            elide: Text.ElideRight
        }

        Row {
            width: parent.width
            height: parent.height - toolbar.height - sourceRow.height - stateRow.height - status.height - parent.spacing * 4
            spacing: CortetsuDesign.spacingStandard

            ListView {
                id: list
                width: root.selected ? Math.round(parent.width * 0.58) : parent.width
                height: parent.height
                clip: true
                spacing: CortetsuDesign.spacingUnit
                boundsBehavior: Flickable.StopAtBounds
                model: root.visibleEntries

                CortetsuStateMessage {
                    anchors.centerIn: parent
                    visible: root.visibleEntries.length === 0
                    width: 320
                    kind: root.busy ? "loading" : "empty"
                    icon: root.busy ? "sync" : "filter_alt_off"
                    title: root.busy ? qsTr("Leyendo el inicio automático…") : qsTr("Nada coincide con estos filtros")
                }

                delegate: Item {
                    id: entryRow
                    required property var modelData
                    required property int index
                    readonly property bool current: root.selected?.id === entryRow.modelData.id
                    readonly property string iconSource: entryRow.modelData.icon ? Quickshell.iconPath(entryRow.modelData.icon, true) : ""

                    width: list.width
                    height: 56
                    activeFocusOnTab: true
                    focus: entryRow.current

                    CortetsuSurface {
                        anchors.fill: parent
                        radiusValue: CortetsuDesign.radiusMedium
                        outlined: false
                        active: entryRow.current
                        hovered: rowMouse.containsMouse
                        focused: entryRow.activeFocus
                        baseColor: Qt.alpha(CortetsuDesign.colorSurfaceGlass, 0.72)
                        hoverColor: CortetsuDesign.colorSurfaceGlassStrong
                        activeColor: Qt.alpha(CortetsuDesign.colorPrimaryContainer, 0.76)
                        outlineColor: Qt.alpha(CortetsuDesign.colorWashi, 0.86)
                    }

                    MouseArea {
                        id: rowMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: { root.selected = entryRow.modelData; entryRow.forceActiveFocus(); }
                    }
                    Keys.onReturnPressed: root.selected = entryRow.modelData
                    Keys.onEnterPressed: root.selected = entryRow.modelData
                    Keys.onSpacePressed: root.selected = entryRow.modelData

                    Item {
                        id: glyph
                        anchors.left: parent.left
                        anchors.leftMargin: CortetsuDesign.spacingStandard
                        anchors.verticalCenter: parent.verticalCenter
                        width: 26
                        height: 26

                        IconImage {
                            anchors.fill: parent
                            visible: entryRow.iconSource.length > 0
                            source: entryRow.iconSource
                        }

                        // An entry without an icon of its own gets a glyph
                        // for its kind, never a broken image.
                        CortetsuIcon {
                            anchors.centerIn: parent
                            visible: entryRow.iconSource.length === 0
                            text: String(entryRow.modelData.sourceType ?? "").startsWith("systemd") ? "settings_applications" : "terminal"
                            color: CortetsuDesign.colorOnSurfaceMuted
                            iconSize: CortetsuTypography.iconMediumPx
                        }
                    }

                    Column {
                        anchors.left: glyph.right
                        anchors.leftMargin: CortetsuDesign.spacingStandard
                        anchors.right: toggle.left
                        anchors.rightMargin: CortetsuDesign.spacingStandard
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2

                        CortetsuText {
                            width: parent.width
                            text: entryRow.modelData.name
                            textSize: CortetsuTypography.bodyPx
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }

                        CortetsuText {
                            width: parent.width
                            text: Format.join([root.sourceLabel(entryRow.modelData), root.stateLabel(entryRow.modelData), root.notes(entryRow.modelData)])
                            textSize: CortetsuTypography.labelSmallPx
                            color: entryRow.modelData.duplicateCount > 1 ? CortetsuDesign.colorWarning : CortetsuDesign.colorOnSurfaceVariant
                            elide: Text.ElideRight
                        }
                    }

                    CortetsuToggle {
                        id: toggle
                        anchors.right: parent.right
                        anchors.rightMargin: CortetsuDesign.spacingStandard
                        anchors.verticalCenter: parent.verticalCenter
                        checked: entryRow.modelData.configured
                        disabled: root.busy || !entryRow.modelData.modifiable
                        Accessible.name: `${qsTr("Inicio automático para")} ${entryRow.modelData.name}`
                        Accessible.description: root.sourceLabel(entryRow.modelData)
                        onToggled: checked => root.setEnabled(entryRow.modelData, checked)
                    }
                }
            }

            Panel {
                visible: root.selected !== null
                width: parent.width - list.width - parent.spacing
                height: parent.height

                Flickable {
                    anchors.fill: parent
                    contentHeight: details.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    Column {
                        id: details
                        width: parent.width
                        spacing: CortetsuDesign.spacingStandard

                        CortetsuText {
                            width: parent.width
                            text: root.selected?.name ?? ""
                            textSize: CortetsuTypography.titleMediumPx
                            font.weight: Font.DemiBold
                            wrapMode: Text.WordWrap
                        }

                        Detail { label: qsTr("Por qué se inicia"); value: root.selected?.reason ?? "" }
                        Detail { label: qsTr("Tipo"); value: root.selected ? root.sourceLabel(root.selected) : "" }
                        Detail { label: qsTr("Cuándo"); value: root.selected ? root.phaseLabel(root.selected.startupPhase) : "" }
                        Detail {
                            label: qsTr("Inicio automático")
                            value: root.selected
                                ? Format.join([root.stateLabel(root.selected), root.selected.unitState ? qsTr("systemd: %1").arg(root.selected.unitState) : ""])
                                : ""
                        }
                        Detail {
                            label: qsTr("Ahora")
                            value: root.selected?.activeState
                                ?? (root.selected?.running === true ? qsTr("En ejecución") : root.selected?.running === false ? qsTr("Detenido") : qsTr("No se puede saber"))
                        }
                        Detail { label: qsTr("Origen"); value: root.selected?.origin ?? ""; anywhere: true }
                        Detail { label: qsTr("Comando"); value: root.selected?.command ?? ""; anywhere: true }
                        Detail {
                            caution: true
                            label: qsTr("Aviso")
                            value: Format.join([
                                root.selected?.eligible === false ? qsTr("La especificación XDG excluye esta entrada en esta sesión.") : "",
                                root.selected?.sourceType === "systemd-system" ? qsTr("Los servicios del sistema son de solo lectura.") : "",
                                root.selected?.duplicateCount > 1 ? qsTr("Se inicia desde varios orígenes: revisa cada uno antes de cambiarlo.") : ""
                            ], " ")
                        }

                        CortetsuButton {
                            visible: root.selected?.sourceType === "systemd-user" && root.selected?.modifiable && root.selected?.running === true
                            danger: root.stopConfirmationId === root.selected?.id
                            icon: "stop_circle"
                            label: root.stopConfirmationId === root.selected?.id ? qsTr("Confirmar detener") : qsTr("Detener ahora")
                            disabled: root.busy || !visible
                            onClicked: root.requestStop(root.selected)
                        }
                    }
                }
            }
        }
    }

    // One group of mutually exclusive filters.
    component FilterRow: Flow {
        id: filterRow

        property var options: []
        property string current: ""
        signal picked(string key)

        spacing: CortetsuDesign.spacingCompact

        Repeater {
            model: filterRow.options

            delegate: CortetsuButton {
                required property var modelData

                compact: true
                active: filterRow.current === modelData.key
                label: modelData.label
                onClicked: filterRow.picked(modelData.key)
            }
        }
    }

    // A labelled detail whose value may wrap. It disappears when empty.
    component Detail: Column {
        id: detail

        property string label: ""
        property string value: ""
        property bool anywhere: false
        property bool caution: false

        visible: detail.value.length > 0
        width: parent.width
        spacing: 2

        CortetsuText {
            width: parent.width
            text: detail.label
            color: detail.caution ? CortetsuDesign.colorWarning : CortetsuDesign.colorOnSurfaceVariant
            textSize: CortetsuTypography.labelSmallPx
            font.weight: Font.DemiBold
        }

        CortetsuText {
            width: parent.width
            text: detail.value
            textSize: CortetsuTypography.bodySmallPx
            wrapMode: detail.anywhere ? Text.WrapAnywhere : Text.WordWrap
        }
    }
}
