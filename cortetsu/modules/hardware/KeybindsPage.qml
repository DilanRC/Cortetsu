pragma ComponentBehavior: Bound

import QtQuick
import ".."
import "../CortetsuDesign.js" as CortetsuDesign
import "../CortetsuTypography.js" as CortetsuTypography
import QtQuick.Layouts
import QtCore
import Quickshell
import Quickshell.Io
import Quickshell.Widgets

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
            statusText = qsTr("Press delete again to confirm");
            deleteReset.restart();
            return;
        }
        deleteReset.stop();
        pendingDeleteId = "";
        busy = true;
        deleteProcess.command = [helperPath, "delete", identifier];
        deleteProcess.running = true;
    }

    function beginCapture(identifier, isNewApp): void {
        captureId = identifier;
        captureNewApp = isNewApp;
        statusText = qsTr("Press the new key combination · Esc cancels");
        forceActiveFocus();
    }

    function keyName(event): string {
        if (event.key >= Qt.Key_A && event.key <= Qt.Key_Z)
            return String.fromCharCode(event.key);
        if (event.key >= Qt.Key_0 && event.key <= Qt.Key_9)
            return String.fromCharCode(event.key);

        const names = {};
        names[Qt.Key_Space] = "Space";
        names[Qt.Key_Return] = "Return";
        names[Qt.Key_Enter] = "Return";
        names[Qt.Key_Tab] = "Tab";
        names[Qt.Key_Backspace] = "Backspace";
        names[Qt.Key_Delete] = "Delete";
        names[Qt.Key_Left] = "Left";
        names[Qt.Key_Right] = "Right";
        names[Qt.Key_Up] = "Up";
        names[Qt.Key_Down] = "Down";
        names[Qt.Key_PageUp] = "Page_Up";
        names[Qt.Key_PageDown] = "Page_Down";
        names[Qt.Key_Home] = "Home";
        names[Qt.Key_End] = "End";
        names[Qt.Key_Comma] = "Comma";
        names[Qt.Key_Period] = "Period";
        names[Qt.Key_Slash] = "Slash";
        names[Qt.Key_Backslash] = "Backslash";
        names[Qt.Key_Minus] = "Minus";
        names[Qt.Key_Equal] = "Equal";
        return names[event.key] ?? "";
    }

    function chordFor(event): string {
        const parts = [];
        if (event.modifiers & Qt.ControlModifier)
            parts.push("CTRL");
        if (event.modifiers & Qt.AltModifier)
            parts.push("ALT");
        if (event.modifiers & Qt.ShiftModifier)
            parts.push("SHIFT");
        if (event.modifiers & Qt.MetaModifier)
            parts.push("SUPER");
        const key = keyName(event);
        if (!key)
            return "";
        parts.push(key);
        return parts.join(" + ");
    }

    function saveChord(chord): void {
        busy = true;
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
        captureId = "";
        captureNewApp = false;
        saveProcess.running = true;
    }

    Keys.onPressed: event => {
        if (!captureId && !captureNewApp)
            return;
        if (event.key === Qt.Key_Escape) {
            captureId = "";
            captureNewApp = false;
            statusText = qsTr("Cambio de atajo cancelado");
            event.accepted = true;
            return;
        }
        const chord = chordFor(event);
        if (!chord)
            return;
        saveChord(chord);
        event.accepted = true;
    }

    Component.onCompleted: refresh()

    Process {
        id: listProcess
        command: [root.helperPath, "list"]

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const result = JSON.parse(text.trim());
                    root.bindings = result.bindings ?? [];
                    root.statusText = qsTr("%1 shortcuts loaded").arg(root.bindings.length);
                } catch (error) {
                    root.statusText = qsTr("Could not read shortcuts");
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
                    root.statusText = result.ok
                        ? qsTr("Guardado · %1").arg(result.chord)
                        : result.error;
                    if (result.ok)
                        root.refresh();
                } catch (error) {
                    root.statusText = qsTr("The shortcut could not be saved");
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
                    root.statusText = result.ok
                        ? qsTr("Eliminado · %1").arg(result.deleted)
                        : result.error;
                    if (result.ok)
                        root.refresh();
                } catch (error) {
                    root.statusText = qsTr("The shortcut could not be deleted");
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
                    text: qsTr("Create app shortcut")
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
                        text: qsTr("Search installed applications")
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
                                    onClicked: root.beginCapture("", true)
                                }

                                CortetsuText {
                                    id: shortcutText
                                    anchors.centerIn: parent
                                    text: root.captureNewApp ? qsTr("Press keys…") : qsTr("Set shortcut")
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
                        color: root.statusText.includes("already") || root.statusText.includes("could not")
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
                                    onClicked: root.beginCapture(parent.parent.parent.modelData.id, false)
                                }

                                CortetsuText {
                                    id: chordLabel
                                    anchors.centerIn: parent
                                    text: root.captureId === modelData.id ? qsTr("Press keys…") : modelData.chord
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
}
