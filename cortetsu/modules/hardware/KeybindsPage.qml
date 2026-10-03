pragma ComponentBehavior: Bound

import QtQuick
import ".."
import "../../theme"
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

    RowLayout {
        anchors.fill: parent
        spacing: 14

        Rectangle {
            Layout.preferredWidth: Math.min(390, root.width * 0.34)
            Layout.fillHeight: true
            radius: CortetsuDesign.radiusLarge
            color: CortetsuDesign.colorSurface
            border.width: 1
            border.color: CortetsuDesign.colorOutlineVariant

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 10

                CortetsuText {
                    Layout.fillWidth: true
                    text: qsTr("Crear atajo de aplicación")
                    color: CortetsuDesign.colorOnSurface
                    textSize: CortetsuTypography.titleMediumPx
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 44
                    radius: CortetsuDesign.radiusMedium
                    color: CortetsuDesign.colorSurfaceHigh
                    border.width: appSearch.activeFocus ? 1 : 0
                    border.color: CortetsuDesign.colorPrimary

                    CortetsuIcon {
                        anchors.left: parent.left
                        anchors.leftMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        text: "search"
                        color: CortetsuDesign.colorOnSurfaceVariant
                        iconSize: CortetsuTypography.iconMediumPx
                    }

                    TextInput {
                        id: appSearch
                        anchors.fill: parent
                        anchors.leftMargin: 42
                        anchors.rightMargin: 10
                        verticalAlignment: TextInput.AlignVCenter
                        color: CortetsuDesign.colorOnSurface
                        selectionColor: CortetsuDesign.colorPrimary
                        font.pixelSize: 15
                        text: root.appFilter
                        onTextChanged: root.appFilter = text
                    }

                    CortetsuText {
                        anchors.left: parent.left
                        anchors.leftMargin: 42
                        anchors.verticalCenter: parent.verticalCenter
                        visible: appSearch.text.length === 0
                        text: qsTr("Buscar aplicaciones instaladas")
                        color: CortetsuDesign.colorOutline
                        textSize: CortetsuTypography.bodyPx
                    }
                }

                ListView {
                    id: appResults
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(contentHeight, 296)
                    visible: root.filteredApps.length > 0
                    model: root.filteredApps
                    spacing: 4
                    clip: true

                    delegate: Rectangle {
                        required property DesktopEntry modelData
                        width: appResults.width
                        height: 48
                        radius: CortetsuDesign.radiusSmall
                        color: root.selectedApp?.id === modelData.id
                            ? CortetsuDesign.colorSecondaryContainer
                            : "transparent"

                        CortetsuStateLayer {
                            radius: parent.radius
                            onClicked: {
                                root.selectedApp = parent.modelData;
                                root.appFilter = parent.modelData.name;
                            }
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            spacing: 10

                            IconImage {
                                implicitSize: 30
                                source: Quickshell.iconPath(parent.parent.modelData.icon, "image-missing")
                            }

                            CortetsuText {
                                Layout.fillWidth: true
                                text: parent.parent.modelData.name
                                color: CortetsuDesign.colorOnSurface
                                textSize: CortetsuTypography.bodyPx
                                elide: Text.ElideRight
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: root.selectedApp ? 106 : 0
                    visible: root.selectedApp
                    radius: CortetsuDesign.radiusMedium
                    color: CortetsuDesign.colorSurfaceHigh

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 12

                        IconImage {
                            implicitSize: 52
                            source: Quickshell.iconPath(root.selectedApp?.icon, "image-missing")
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            CortetsuText {
                                Layout.fillWidth: true
                                text: root.selectedApp?.name ?? ""
                                color: CortetsuDesign.colorOnSurface
                                textSize: CortetsuTypography.titleSmallPx
                                elide: Text.ElideRight
                            }

                            CortetsuText {
                                Layout.fillWidth: true
                                text: root.selectedApp?.execString ?? ""
                                color: CortetsuDesign.colorOutline
                                textSize: CortetsuTypography.labelSmallPx
                                elide: Text.ElideMiddle
                            }

                            Rectangle {
                                Layout.preferredWidth: shortcutText.implicitWidth + 24
                                Layout.preferredHeight: 34
                                radius: CortetsuDesign.radiusSmall
                                color: root.captureNewApp
                                    ? CortetsuDesign.colorPrimaryContainer
                                    : CortetsuDesign.colorSecondaryContainer

                                CortetsuStateLayer {
                                    radius: parent.radius
                                    enabled: !root.busy
                                    onClicked: root.beginCapture("", true, root.selectedApp?.name ?? "", "")
                                }

                                CortetsuText {
                                    id: shortcutText
                                    anchors.centerIn: parent
                                    text: root.captureNewApp ? qsTr("Escuchando…") : qsTr("Asignar atajo")
                                    color: CortetsuDesign.colorOnSecondaryContainer
                                    textSize: CortetsuTypography.labelMediumPx
                                }
                            }
                        }
                    }
                }

                Item { Layout.fillHeight: true }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: CortetsuDesign.radiusLarge
            color: CortetsuDesign.colorSurface
            border.width: 1
            border.color: CortetsuDesign.colorOutlineVariant

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true

                    CortetsuText {
                        Layout.fillWidth: true
                        text: qsTr("Todos los atajos")
                        color: CortetsuDesign.colorOnSurface
                        textSize: CortetsuTypography.titleMediumPx
                    }

                    CortetsuText {
                        text: root.statusText
                        color: root.statusFailed
                            ? CortetsuDesign.colorVermillion
                            : CortetsuDesign.colorOutline
                        textSize: CortetsuTypography.labelSmallPx
                        elide: Text.ElideRight
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 42
                    radius: CortetsuDesign.radiusMedium
                    color: CortetsuDesign.colorSurfaceHigh

                    CortetsuIcon {
                        anchors.left: parent.left
                        anchors.leftMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        text: "filter_list"
                        color: CortetsuDesign.colorOnSurfaceVariant
                        iconSize: CortetsuTypography.iconMediumPx
                    }

                    TextInput {
                        anchors.fill: parent
                        anchors.leftMargin: 42
                        anchors.rightMargin: 10
                        verticalAlignment: TextInput.AlignVCenter
                        color: CortetsuDesign.colorOnSurface
                        selectionColor: CortetsuDesign.colorPrimary
                        font.pixelSize: 15
                        onTextChanged: root.bindingFilter = text
                    }
                }

                ListView {
                    id: bindingList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    model: root.filteredBindings
                    spacing: 5
                    clip: true

                    delegate: Rectangle {
                        id: bindingRow
                        required property var modelData
                        readonly property var appEntry: root.appForBinding(modelData)
                        width: bindingList.width
                        height: 48
                        radius: CortetsuDesign.radiusSmall
                        color: CortetsuDesign.colorSurfaceHigh

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 8
                            spacing: 10

                            IconImage {
                                visible: bindingRow.appEntry !== null
                                implicitSize: 26
                                source: visible
                                    ? Quickshell.iconPath(bindingRow.appEntry.icon, "image-missing")
                                    : ""
                            }

                            CortetsuIcon {
                                visible: bindingRow.appEntry === null
                                text: modelData.command ? "terminal" : "keyboard"
                                color: CortetsuDesign.colorSecondary
                                iconSize: CortetsuTypography.iconMediumPx
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0

                                CortetsuText {
                                    Layout.fillWidth: true
                                    text: bindingRow.appEntry?.name ?? modelData.appName ?? modelData.label
                                    color: CortetsuDesign.colorOnSurface
                                    textSize: CortetsuTypography.bodyPx
                                    elide: Text.ElideRight
                                }

                                CortetsuText {
                                    text: modelData.description
                                    color: CortetsuDesign.colorOutline
                                    textSize: CortetsuTypography.labelSmallPx
                                    elide: Text.ElideMiddle
                                }
                            }

                            Rectangle {
                                Layout.preferredWidth: Math.max(118, chordLabel.implicitWidth + 24)
                                Layout.preferredHeight: 34
                                radius: CortetsuDesign.radiusSmall
                                color: root.captureId === modelData.id
                                    ? CortetsuDesign.colorPrimaryContainer
                                    : CortetsuDesign.colorSecondaryContainer

                                CortetsuStateLayer {
                                    radius: parent.radius
                                    enabled: !root.busy
                                    onClicked: root.beginCapture(bindingRow.modelData.id, false, bindingRow.appEntry?.name ?? bindingRow.modelData.appName ?? bindingRow.modelData.label, bindingRow.modelData.chord)
                                }

                                CortetsuText {
                                    id: chordLabel
                                    anchors.centerIn: parent
                                    text: root.captureId === modelData.id ? qsTr("Escuchando…") : modelData.chord
                                    color: CortetsuDesign.colorOnSecondaryContainer
                                    textSize: CortetsuTypography.labelMediumPx
                                }
                            }

                            Rectangle {
                                Layout.preferredWidth: 34
                                Layout.preferredHeight: 34
                                radius: CortetsuDesign.radiusSmall
                                color: root.pendingDeleteId === modelData.id
                                    ? Qt.darker(CortetsuDesign.colorVermillion, 1.5)
                                    : "transparent"

                                CortetsuStateLayer {
                                    radius: parent.radius
                                    enabled: !root.busy
                                    onClicked: root.requestDelete(bindingRow.modelData.id)
                                }

                                CortetsuIcon {
                                    anchors.centerIn: parent
                                    text: "delete"
                                    color: root.pendingDeleteId === bindingRow.modelData.id
                                        ? CortetsuDesign.colorOnSurface
                                        : CortetsuDesign.colorOnSurfaceVariant
                                    iconSize: CortetsuTypography.iconMediumPx
                                }
                            }
                        }
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
