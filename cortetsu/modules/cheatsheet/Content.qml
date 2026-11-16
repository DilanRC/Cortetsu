pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import ".."
import "../../components"
import "../../theme"
import "../CortetsuTypography.js" as CortetsuTypography
import "../CortetsuOverlayPolicy.js" as OverlayPolicy
import "../keyboards" as Keyboards
import "../keyboards/Model.js" as KeyModel
import "../settings/Navigation.js" as Navigation
import "Columns.js" as Columns

// The shortcut sheet: every active Hyprland binding, grouped as Ajustes →
// Atajos groups them, read from the same helper (cortetsu-keybinds list).
// It answers one question, "what is the key for X?", so it opens on the
// search field and filters as you type. Editing stays in Atajos y teclados.
FocusScope {
    id: root

    required property var screenState

    // loading | ready | error
    property string state: "loading"
    property string error: ""
    property var groups: []
    property string query: ""

    readonly property var groupTitles: ({
        "Cortetsu": qsTr("Cortetsu"),
        "Application": qsTr("Aplicaciones"),
        "Custom": qsTr("Propios"),
        "Hardware": qsTr("Teclas del equipo")
    })
    readonly property var visibleGroups: groups
        .map(group => ({ name: group.name, bindings: group.bindings.filter(binding => root.matches(binding)) }))
        .filter(group => group.bindings.length > 0)
    readonly property int total: groups.reduce((sum, group) => sum + group.bindings.length, 0)
    readonly property int shown: visibleGroups.reduce((sum, group) => sum + group.bindings.length, 0)
    readonly property int columnCount: width >= 980 ? 3 : width >= 640 ? 2 : 1
    readonly property var columns: Columns.balance(visibleGroups, columnCount)

    function matches(binding): bool {
        const needle = Navigation.normalise(root.query);
        return !needle || Navigation.normalise(`${binding.label} ${binding.chord} ${binding.description ?? ""}`).includes(needle);
    }

    function openSurface(): void {
        search.text = "";
        search.forceActiveFocus();
        flick.contentY = 0;
        root.load();
    }

    function close(): void {
        root.screenState?.cortetsuState?.setRetained("cheatsheet", false);
    }

    function openEditor(): void {
        OverlayPolicy.open(CortetsuShellState.allStates(), root.screenState, "keyboards");
    }

    function load(): void {
        if (listProcess.running)
            return;
        if (root.groups.length === 0)
            root.state = "loading";
        root.error = "";
        listProcess.running = true;
    }

    function receive(text: string): void {
        try {
            const data = JSON.parse(text);
            if (!data.ok || !Array.isArray(data.bindings))
                throw new Error(data.error || "invalid");
            const byGroup = new Map();
            for (const binding of data.bindings) {
                if (binding.active === false || !binding.chord)
                    continue;
                if (!byGroup.has(binding.group))
                    byGroup.set(binding.group, []);
                byGroup.get(binding.group).push(binding);
            }
            root.groups = Array.from(byGroup, ([name, bindings]) => ({ name, bindings }));
            root.state = "ready";
        } catch (failure) {
            root.error = qsTr("La lista de atajos no se pudo leer");
            root.state = "error";
        }
    }

    // PageUp/PageDown scroll the sheet from the search field.
    Keys.onPressed: event => {
        if (event.key === Qt.Key_PageDown || event.key === Qt.Key_PageUp) {
            const step = flick.height * 0.85 * (event.key === Qt.Key_PageDown ? 1 : -1);
            flick.contentY = Math.max(0, Math.min(flick.contentHeight - flick.height, flick.contentY + step));
            event.accepted = true;
        }
    }

    // startup inventory: cortetsu:cheatsheet-keybind-list (on open only)
    Process {
        id: listProcess
        command: ["cortetsu-keybinds", "list"]
        stdout: StdioCollector { id: listOutput }
        onExited: code => {
            if (code === 0) {
                root.receive(listOutput.text);
            } else if (root.groups.length === 0) {
                root.error = qsTr("El ayudante de atajos terminó con el código %1").arg(code);
                root.state = "error";
            }
        }
    }

    CortetsuInkPanel {
        anchors.fill: parent
        radius: CortetsuDesign.radiusSurface
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: CortetsuDesign.spacingSection
        spacing: CortetsuDesign.spacingStandard

        RowLayout {
            Layout.fillWidth: true
            spacing: CortetsuDesign.spacingStandard

            CortetsuIcon {
                text: "keyboard_command_key"
                iconSize: CortetsuTypography.iconMediumPx
                color: CortetsuDesign.colorPrimary
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                CortetsuText {
                    text: qsTr("Atajos de teclado")
                    textSize: CortetsuTypography.titleLargePx
                    font.family: CortetsuDesign.fontHeading
                    font.weight: CortetsuDesign.headingWeight
                }
                CortetsuText {
                    text: root.state !== "ready" ? ""
                        : root.query.length > 0 ? qsTr("%1 de %2").arg(root.shown).arg(root.total)
                        : root.total === 1 ? qsTr("1 atajo") : qsTr("%1 atajos").arg(root.total)
                    textSize: CortetsuTypography.bodySmallPx
                    color: CortetsuDesign.colorOnSurfaceVariant
                }
            }

            CortetsuSearchBar {
                id: search
                objectName: "cheatsheetSearch"
                Layout.preferredWidth: Math.min(360, root.width * 0.4)
                compact: true
                focus: true
                placeholderText: qsTr("Buscar acción o tecla")
                Accessible.name: placeholderText
                onTextChanged: root.query = text
                // Escape clears a search before it closes the sheet.
                Keys.onShortcutOverride: event => event.accepted = event.key === Qt.Key_Escape && text.length > 0
                Keys.onEscapePressed: event => {
                    if (text.length > 0) {
                        text = "";
                        event.accepted = true;
                    }
                }
            }

            CortetsuButton {
                objectName: "cheatsheetEdit"
                compact: true
                icon: "edit"
                label: qsTr("Editar")
                tooltipText: qsTr("Abrir Atajos y teclados")
                onClicked: root.openEditor()
            }

            CortetsuButton {
                compact: true
                icon: "close"
                label: ""
                tooltipText: qsTr("Cerrar")
                onClicked: root.close()
            }
        }

        CortetsuDivider { Layout.fillWidth: true }

        CortetsuStateMessage {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.state !== "ready" || root.shown === 0
            kind: root.state === "ready" ? "empty" : root.state
            title: root.state === "loading" ? qsTr("Leyendo los atajos")
                : root.state === "error" ? root.error
                : root.total === 0 ? qsTr("No hay atajos definidos")
                : qsTr("Ningún atajo coincide con «%1»").arg(root.query)
            detail: root.state === "error" ? qsTr("Comprueba que cortetsu-keybinds está instalado") : ""
        }

        Flickable {
            id: flick
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.state === "ready" && root.shown > 0
            clip: true
            contentWidth: width
            contentHeight: columnsRow.implicitHeight
            boundsBehavior: Flickable.StopAtBounds

            RowLayout {
                id: columnsRow
                width: flick.width
                spacing: CortetsuDesign.spacingSection

                Repeater {
                    model: root.columns

                    delegate: ColumnLayout {
                        id: column
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        Layout.alignment: Qt.AlignTop
                        spacing: CortetsuDesign.spacingSection

                        Repeater {
                            model: column.modelData

                            delegate: ColumnLayout {
                                id: group
                                required property var modelData
                                Layout.fillWidth: true
                                spacing: CortetsuDesign.spacingUnit

                                CortetsuText {
                                    Layout.fillWidth: true
                                    text: CortetsuDesign.labelCaps
                                        ? (root.groupTitles[group.modelData.name] ?? group.modelData.name).toUpperCase()
                                        : root.groupTitles[group.modelData.name] ?? group.modelData.name
                                    textSize: CortetsuDesign.labelCaps ? CortetsuTypography.labelLargePx : CortetsuTypography.titleSmallPx
                                    font.family: CortetsuDesign.fontHeading
                                    font.weight: CortetsuDesign.headingWeight
                                    font.letterSpacing: CortetsuDesign.labelTracking
                                    color: CortetsuDesign.colorPrimary
                                    Accessible.role: Accessible.Heading
                                }

                                Repeater {
                                    model: group.modelData.bindings

                                    delegate: Item {
                                        id: row
                                        required property var modelData
                                        required property int index
                                        readonly property bool conflicted: (modelData.conflicts ?? []).length > 0
                                        Layout.fillWidth: true
                                        implicitHeight: Math.max(36, label.implicitHeight + 8)
                                        Accessible.role: Accessible.StaticText
                                        Accessible.name: `${modelData.label}: ${modelData.chord}`

                                        CortetsuDivider {
                                            visible: row.index > 0
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.top: parent.top
                                        }

                                        CortetsuIcon {
                                            id: conflictIcon
                                            visible: row.conflicted
                                            anchors.left: parent.left
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: "warning"
                                            iconSize: CortetsuTypography.iconSmallPx
                                            color: CortetsuDesign.colorVermillion
                                        }

                                        CortetsuText {
                                            id: label
                                            anchors.left: row.conflicted ? conflictIcon.right : parent.left
                                            anchors.leftMargin: row.conflicted ? CortetsuDesign.spacingUnit : 0
                                            anchors.right: caps.left
                                            anchors.rightMargin: CortetsuDesign.spacingStandard
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: row.conflicted
                                                ? qsTr("%1 · también %2").arg(row.modelData.label).arg(row.modelData.conflicts.join(", "))
                                                : row.modelData.label
                                            textSize: CortetsuTypography.bodyPx
                                            elide: Text.ElideRight
                                        }

                                        Row {
                                            id: caps
                                            anchors.right: parent.right
                                            anchors.verticalCenter: parent.verticalCenter
                                            spacing: CortetsuDesign.spacingUnit

                                            Repeater {
                                                model: KeyModel.parts(row.modelData.chord)
                                                delegate: Keyboards.KeyCap {
                                                    required property string modelData
                                                    text: modelData
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        CortetsuText {
            Layout.fillWidth: true
            text: qsTr("SUPER+F1 abre y cierra esta hoja · RePág y AvPág desplazan · Escape vacía la búsqueda y después cierra")
            textSize: CortetsuTypography.labelSmallPx
            color: CortetsuDesign.colorOnSurfaceVariant
            elide: Text.ElideRight
        }
    }
}
