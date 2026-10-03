pragma ComponentBehavior: Bound

import QtQuick
import ".."
import "../../components"
import "../../theme"
import "summary"
import "../CortetsuTypography.js" as CortetsuTypography
import QtQuick.Layouts
import QtCore
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import "KeyCapture.js" as KeyCapture

FocusScope {
    id: root

    property var bindings: []
    property string bindingFilter: ""
    property string appFilter: ""
    property var selectedApp: null
    property string captureId: ""
    property bool captureNewApp: false
    property string pendingDeleteId: ""
    property string statusText: qsTr("Cargando atajos…")
    property bool busy: false
    property bool statusFailed: false

    // Capture state. `capturing` is the only source of truth for "the editor
    // is recording the keyboard"; the overlay just presents it.
    readonly property bool capturing: captureId.length > 0 || captureNewApp
    property string captureLabel: ""
    property string captureCurrentChord: ""
    property var heldModifiers: []
    property string captureMessage: ""
    property bool captureFailed: false
    property real captureRemaining: 1
    readonly property int captureTimeoutMs: 10000

    readonly property string helperPath:
        StandardPaths.writableLocation(StandardPaths.HomeLocation) +
        "/.local/bin/cortetsu-keybinds"
    readonly property var filteredBindings: bindings.filter(item => {
        const query = bindingFilter.trim().toLowerCase();
        return !query
            || item.label.toLowerCase().includes(query)
            || item.chord.toLowerCase().includes(query)
            || (item.description ?? "").toLowerCase().includes(query);
    })
    readonly property var filteredApps: {
        const query = appFilter.trim().toLowerCase();
        if (!query)
            return [];
        return [...DesktopEntries.applications.values]
            .filter(app => app.name.toLowerCase().includes(query) || app.id.toLowerCase().includes(query))
            .sort((a, b) => a.name.localeCompare(b.name))
            .slice(0, 8);
    }

    function refresh(): void {
        if (!listProcess.running)
            listProcess.running = true;
    }

    function appForBinding(binding): var {
        const apps = [...DesktopEntries.applications.values];
        const wantedId = (binding.appId ?? "").replace(/\.desktop$/, "").toLowerCase();
        if (wantedId) {
            const exact = apps.find(app => app.id.replace(/\.desktop$/, "").toLowerCase() === wantedId);
            if (exact)
                return exact;
        }
        const command = binding.command ?? "";
        if (!command)
            return null;
        const executable = binding.appQuery ?? command.trim().split(/\s+/)[0].split("/").pop();
        const query = executable.toLowerCase();
        const byId = apps.find(app => {
            const id = app.id.replace(/\.desktop$/, "").toLowerCase();
            return id === query || id.endsWith(`.${query}`);
        });
        return byId ?? DesktopEntries.heuristicLookup(executable) ?? DesktopEntries.heuristicLookup(command);
    }

    function requestDelete(identifier): void {
        if (pendingDeleteId !== identifier) {
            pendingDeleteId = identifier;
            statusText = qsTr("Pulsa eliminar otra vez para confirmar");
            deleteReset.restart();
            return;
        }
        deleteReset.stop();
        pendingDeleteId = "";
        busy = true;
        deleteProcess.command = [helperPath, "delete", identifier];
        deleteProcess.running = true;
    }

    function beginCapture(identifier, isNewApp, label, currentChord): void {
        captureId = identifier;
        captureNewApp = isNewApp;
        captureLabel = label ?? "";
        captureCurrentChord = currentChord ?? "";
        heldModifiers = [];
        captureMessage = "";
        captureFailed = false;
        statusFailed = false;
        statusText = qsTr("Escuchando. Pulsa la combinación · Esc cancela");
        captureCountdown.restart();
        forceActiveFocus();
    }

    function endCapture(status: string): void {
        captureCountdown.stop();
        captureId = "";
        captureNewApp = false;
        heldModifiers = [];
        captureMessage = "";
        captureFailed = false;
        captureRemaining = 1;
        if (status.length > 0)
            statusText = status;
    }

    function saveChord(chord): void {
        busy = true;
        captureCountdown.stop();
        captureMessage = chord;
        captureFailed = false;
        if (captureNewApp) {
            saveProcess.command = [
                helperPath,
                "add-app",
                selectedApp.id,
                selectedApp.name,
                selectedApp.execString,
                chord
            ];
        } else {
            saveProcess.command = [helperPath, "set", captureId, chord];
        }
        saveProcess.running = true;
    }

    function captureProblem(message: string): void {
        captureMessage = message;
        captureFailed = true;
        captureCountdown.restart();
    }

    // While listening every key belongs to the editor: Escape must not close
    // the surface and digits must not switch tabs.
    Keys.onShortcutOverride: event => event.accepted = root.capturing

    Keys.onPressed: event => {
        if (!root.capturing)
            return;
        event.accepted = true;
        root.captureKey(event.key, event.modifiers);
    }

    function captureKey(key: int, modifiers: int): void {
        if (!root.capturing || root.busy)
            return;
        if (key === Qt.Key_Escape) {
            root.endCapture(qsTr("Cambio de atajo cancelado"));
            return;
        }
        const result = KeyCapture.resolve(key, modifiers);
        root.heldModifiers = result.held;
        if (result.kind === "modifier") {
            root.captureFailed = false;
            root.captureMessage = "";
        } else if (result.kind === "unsupported") {
            root.captureProblem(qsTr("Esa tecla no se puede asignar desde aquí. Prueba con otra."));
        } else if (result.kind === "bare") {
            root.captureProblem(qsTr("Añade un modificador: Ctrl, Alt, Shift o Super."));
        } else {
            root.saveChord(result.chord);
        }
    }

    Keys.onReleased: event => {
        if (!root.capturing)
            return;
        event.accepted = true;
        if (KeyCapture.isModifierKey(event.key)) {
            const released = KeyCapture.modifiers(event.modifiers);
            root.heldModifiers = root.heldModifiers.filter(name => released.indexOf(name) >= 0);
        }
    }

    NumberAnimation {
        id: captureCountdown
        target: root
        property: "captureRemaining"
        from: 1
        to: 0
        duration: root.captureTimeoutMs
        onFinished: root.endCapture(qsTr("Tiempo agotado: no se cambió el atajo"))
    }

    Component.onCompleted: refresh()

    // startup inventory: cortetsu:hardware-keybind-list
    Process {
        id: listProcess
        command: [root.helperPath, "list"]

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const result = JSON.parse(text.trim());
                    root.bindings = result.bindings ?? [];
                    root.statusFailed = false;
                    root.statusText = qsTr("%1 atajos cargados").arg(root.bindings.length);
                } catch (error) {
                    root.statusFailed = true;
                    root.statusText = qsTr("No se pudieron leer los atajos");
                }
            }
        }
    }

    Process {
        id: saveProcess

        stdout: StdioCollector {
            onStreamFinished: {
                root.busy = false;
                try {
                    const result = JSON.parse(text.trim());
                    root.statusFailed = !result.ok;
                    if (result.ok) {
                        root.endCapture(qsTr("Guardado · %1").arg(result.chord));
                        root.refresh();
                    } else {
                        // Stay in the listening state so another combination
                        // can be tried without reopening the editor.
                        root.statusText = result.error;
                        root.captureProblem(result.error);
                    }
                } catch (error) {
                    root.statusFailed = true;
                    root.endCapture(qsTr("No se pudo guardar el atajo"));
                }
            }
        }
    }

    Process {
        id: deleteProcess

        stdout: StdioCollector {
            onStreamFinished: {
                root.busy = false;
                try {
                    const result = JSON.parse(text.trim());
                    root.statusFailed = !result.ok;
                    root.statusText = result.ok
                        ? qsTr("Eliminado · %1").arg(result.deleted)
                        : result.error;
                    if (result.ok)
                        root.refresh();
                } catch (error) {
                    root.statusFailed = true;
                    root.statusText = qsTr("No se pudo eliminar el atajo");
                }
            }
        }
    }

    Timer {
        id: deleteReset
        interval: 4000
        onTriggered: root.pendingDeleteId = ""
    }

    Row {
        anchors.fill: parent
        spacing: CortetsuDesign.spacingStandard

        Panel {
            id: creator
            width: Math.min(390, Math.round(root.width * 0.34))
            height: parent.height

            Column {
                anchors.fill: parent
                spacing: CortetsuDesign.spacingStandard

                SummaryLabel {
                    icon: "add_circle"
                    text: qsTr("Atajo para una aplicación")
                    anchors.rightMargin: 0
                }

                CortetsuSearchBar {
                    id: appSearch
                    width: parent.width
                    compact: true
                    placeholderText: qsTr("Buscar aplicaciones instaladas")
                    text: root.appFilter
                    onTextChanged: root.appFilter = text
                }

                CortetsuText {
                    visible: root.filteredApps.length === 0 && !root.selectedApp
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: root.appFilter.length > 0
                        ? qsTr("Ninguna aplicación instalada coincide.")
                        : qsTr("Escribe el nombre de una aplicación para asignarle una combinación de teclas.")
                    color: CortetsuDesign.colorOnSurfaceVariant
                    textSize: CortetsuTypography.bodySmallPx
                }

                ListView {
                    id: appResults
                    width: parent.width
                    height: Math.min(contentHeight, 296)
                    visible: root.filteredApps.length > 0
                    model: root.filteredApps
                    spacing: CortetsuDesign.spacingUnit
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    delegate: CortetsuListRow {
                        id: appRow
                        required property DesktopEntry modelData

                        width: appResults.width
                        compact: true
                        title: appRow.modelData.name
                        selected: root.selectedApp?.id === appRow.modelData.id
                        onClicked: {
                            root.selectedApp = appRow.modelData;
                            root.appFilter = appRow.modelData.name;
                        }
                    }
                }

                Item {
                    visible: !!root.selectedApp
                    width: parent.width
                    height: 64

                    IconImage {
                        id: chosenIcon
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        implicitSize: 44
                        source: Quickshell.iconPath(root.selectedApp?.icon ?? "", true)
                    }

                    Column {
                        anchors.left: chosenIcon.right
                        anchors.leftMargin: CortetsuDesign.spacingStandard
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2

                        CortetsuText {
                            width: parent.width
                            text: root.selectedApp?.name ?? ""
                            textSize: CortetsuTypography.bodyLargePx
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }

                        CortetsuText {
                            width: parent.width
                            text: root.selectedApp ? root.selectedApp.execString : ""
                            color: CortetsuDesign.colorOnSurfaceVariant
                            textSize: CortetsuTypography.labelSmallPx
                            elide: Text.ElideMiddle
                        }
                    }
                }

                CortetsuButton {
                    visible: !!root.selectedApp
                    disabled: root.busy || !root.selectedApp
                    active: root.captureNewApp
                    icon: "keyboard"
                    label: root.captureNewApp ? qsTr("Escuchando…") : qsTr("Grabar combinación")
                    onClicked: root.beginCapture("", true, root.selectedApp?.name ?? "", "")
                }
            }
        }

        Panel {
            width: parent.width - creator.width - parent.spacing
            height: parent.height

            SummaryLabel {
                id: listLabel
                icon: "keyboard"
                text: qsTr("Atajos")
                detail: root.statusText
                anchors.rightMargin: 0
            }

            CortetsuSearchBar {
                id: bindingSearch
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: listLabel.bottom
                anchors.topMargin: CortetsuDesign.spacingStandard
                compact: true
                placeholderText: qsTr("Filtrar por acción, aplicación o combinación")
                onTextChanged: root.bindingFilter = text
            }

            ListView {
                id: bindingList
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: bindingSearch.bottom
                anchors.topMargin: CortetsuDesign.spacingStandard
                anchors.bottom: parent.bottom
                model: root.filteredBindings
                spacing: CortetsuDesign.spacingUnit
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                CortetsuStateMessage {
                    anchors.centerIn: parent
                    visible: root.filteredBindings.length === 0
                    width: 320
                    kind: root.statusFailed ? "error" : root.busy ? "loading" : "empty"
                    icon: root.statusFailed ? "error_outline" : "search_off"
                    title: root.statusFailed ? qsTr("No se pudieron leer los atajos") : qsTr("Ningún atajo coincide")
                    detail: root.statusFailed ? root.statusText : ""
                }

                delegate: Item {
                    id: bindingRow
                    required property var modelData
                    readonly property var appEntry: root.appForBinding(modelData)
                    readonly property string appIcon: bindingRow.appEntry !== null ? Quickshell.iconPath(bindingRow.appEntry.icon, true) : ""
                    readonly property string title: bindingRow.appEntry?.name ?? bindingRow.modelData.appName ?? bindingRow.modelData.label
                    readonly property bool deleting: root.pendingDeleteId === bindingRow.modelData.id

                    width: bindingList.width
                    height: 48

                    CortetsuSurface {
                        anchors.fill: parent
                        radiusValue: CortetsuDesign.radiusMedium
                        outlined: false
                        baseColor: Qt.alpha(CortetsuDesign.colorSurfaceGlassStrong, 0.6)
                    }

                    IconImage {
                        id: bindingIcon
                        anchors.left: parent.left
                        anchors.leftMargin: CortetsuDesign.spacingStandard
                        anchors.verticalCenter: parent.verticalCenter
                        visible: bindingRow.appIcon.length > 0
                        implicitSize: 26
                        source: bindingRow.appIcon
                    }

                    CortetsuIcon {
                        anchors.centerIn: bindingIcon
                        visible: bindingRow.appIcon.length === 0
                        text: bindingRow.modelData.command ? "terminal" : "keyboard"
                        color: CortetsuDesign.colorOnSurfaceMuted
                        iconSize: CortetsuTypography.iconMediumPx
                    }

                    Column {
                        anchors.left: parent.left
                        anchors.leftMargin: 26 + CortetsuDesign.spacingStandard * 2
                        anchors.right: chord.left
                        anchors.rightMargin: CortetsuDesign.spacingStandard
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 1

                        CortetsuText {
                            width: parent.width
                            text: bindingRow.title
                            textSize: CortetsuTypography.bodyPx
                            elide: Text.ElideRight
                        }

                        CortetsuText {
                            width: parent.width
                            // A description that only repeats the title adds nothing.
                            visible: text.length > 0 && text !== bindingRow.title
                            text: bindingRow.modelData.description ?? ""
                            color: CortetsuDesign.colorOnSurfaceVariant
                            textSize: CortetsuTypography.labelSmallPx
                            elide: Text.ElideMiddle
                        }
                    }

                    CortetsuButton {
                        id: chord
                        anchors.right: remove.left
                        anchors.rightMargin: CortetsuDesign.spacingCompact
                        anchors.verticalCenter: parent.verticalCenter
                        compact: true
                        disabled: root.busy
                        active: root.captureId === bindingRow.modelData.id
                        label: root.captureId === bindingRow.modelData.id ? qsTr("Escuchando…") : bindingRow.modelData.chord
                        tooltipText: qsTr("Cambiar la combinación")
                        onClicked: root.beginCapture(bindingRow.modelData.id, false, bindingRow.title, bindingRow.modelData.chord)
                    }

                    CortetsuButton {
                        id: remove
                        anchors.right: parent.right
                        anchors.rightMargin: CortetsuDesign.spacingCompact
                        anchors.verticalCenter: parent.verticalCenter
                        compact: true
                        disabled: root.busy
                        danger: bindingRow.deleting
                        icon: "delete"
                        label: bindingRow.deleting ? qsTr("Confirmar") : ""
                        tooltipText: qsTr("Eliminar el atajo")
                        Accessible.name: qsTr("Eliminar el atajo de %1").arg(bindingRow.title)
                        onClicked: root.requestDelete(bindingRow.modelData.id)
                    }
                }
            }
        }
    }

    KeyCaptureOverlay {
        anchors.fill: parent
        z: 10
        active: root.capturing
        actionLabel: root.captureLabel
        currentChord: root.captureCurrentChord
        heldModifiers: root.heldModifiers
        message: root.captureMessage
        failed: root.captureFailed
        saving: root.busy && root.capturing
        remaining: root.captureRemaining
        onCancelRequested: root.endCapture(qsTr("Cambio de atajo cancelado"))
    }
}
