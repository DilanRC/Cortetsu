pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import "../../../components"
import "../../../theme"
import "../.."
import "../../CortetsuSearchBar.qml"
import "../../CortetsuTypography.js" as CortetsuTypography
import "../controls"
import "../Navigation.js" as Navigation

// The bindings Hyprland really has, read from the same helper the editor
// uses. This page lists them; they are changed in Hardware.
ColumnLayout {
    id: root

    required property var context

    // loading | ready | error
    property string state: "loading"
    property string error: ""
    property var groups: []
    property string query: ""
    readonly property int total: groups.reduce((sum, group) => sum + group.bindings.length, 0)

    readonly property var groupTitles: ({
        "Cortetsu": qsTr("Cortetsu"),
        "Application": qsTr("Aplicaciones"),
        "Custom": qsTr("Propios")
    })

    function matches(binding): bool {
        const needle = Navigation.normalise(root.query);
        return !needle || Navigation.normalise(`${binding.label} ${binding.chord} ${binding.description ?? ""}`).includes(needle);
    }

    function load(): void {
        if (listProcess.running)
            return;
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

    spacing: CortetsuDesign.spacingSection

    Component.onCompleted: root.load()

    // startup inventory: cortetsu:settings-keybind-list
    Process {
        id: listProcess
        command: ["cortetsu-keybinds", "list"]
        stdout: StdioCollector { id: listOutput }
        onExited: code => {
            if (code === 0) {
                root.receive(listOutput.text);
            } else {
                root.error = qsTr("El ayudante de atajos terminó con el código %1").arg(code);
                root.state = "error";
            }
        }
    }

    SettingsGroup {
        title: qsTr("Edición")

        SettingActionRow {
            title: qsTr("Cambiar o añadir atajos")
            detail: qsTr("El editor está en Hardware, página Teclas")
            actionLabel: qsTr("Abrir Hardware")
            actionIcon: "keyboard_command_key"
            onActivated: root.context.openSurface("hardware")
        }
    }

    CortetsuStateMessage {
        objectName: "shortcutsState"
        Layout.fillWidth: true
        Layout.topMargin: CortetsuDesign.spacingSection
        visible: root.state !== "ready" || root.total === 0
        kind: root.state === "ready" ? "empty" : root.state
        title: root.state === "loading"
            ? qsTr("Leyendo los atajos")
            : root.state === "error" ? root.error : qsTr("No hay atajos definidos")
        detail: root.state === "error" ? qsTr("Comprueba que cortetsu-keybinds está instalado") : ""
    }

    CortetsuButton {
        Layout.alignment: Qt.AlignHCenter
        visible: root.state === "error"
        compact: true
        icon: "refresh"
        label: qsTr("Reintentar")
        onClicked: root.load()
    }

    CortetsuSearchBar {
        objectName: "shortcutFilter"
        Layout.fillWidth: true
        visible: root.state === "ready" && root.total > 0
        compact: true
        placeholderText: qsTr("Filtrar por acción o tecla")
        Accessible.name: placeholderText
        onTextChanged: root.query = text
    }

    Repeater {
        model: root.groups

        delegate: SettingsGroup {
            id: group

            required property var modelData
            readonly property int shown: modelData.bindings.filter(binding => root.matches(binding)).length

            visible: shown > 0
            title: root.groupTitles[modelData.name] ?? modelData.name
            detail: shown === modelData.bindings.length ? String(shown) : qsTr("%1 de %2").arg(shown).arg(modelData.bindings.length)

            Repeater {
                model: group.modelData.bindings

                delegate: SettingValueRow {
                    required property var modelData
                    visible: root.matches(modelData)
                    title: modelData.label
                    detail: modelData.description !== modelData.label ? (modelData.description ?? "") : ""
                    value: modelData.chord
                }
            }
        }
    }
}
