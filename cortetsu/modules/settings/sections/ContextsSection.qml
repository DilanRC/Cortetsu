pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../../services"
import "../../../theme"
import "../controls"

// Ajustes → Contextos. Pick a context to see what it changes; activate,
// deactivate, copy, edit, export and import. Built-in contexts are read
// only: copying one gives an editable version.
ColumnLayout {
    id: root

    required property var context

    readonly property string home: Quickshell.env("HOME") || ""
    property string selectedId: CortetsuContexts.activeId || "university"
    readonly property var selected: CortetsuContexts.contexts.find(c => c.id === root.selectedId) ?? CortetsuContexts.contexts[0]
    readonly property bool editable: root.selected && !root.selected.builtin
    readonly property bool selectedActive: root.selected && CortetsuContexts.activeId === root.selected.id
    property string transferPath: root.home + "/cortetsu-context.json"

    // Choices per setting. "keep" means the context leaves it alone.
    function options(key: string): var {
        const spec = CortetsuContexts.keys[key];
        const keep = [{ value: "keep", label: qsTr("Sin cambio") }];
        if (spec.kind === "bool")
            return keep.concat([{ value: true, label: qsTr("Activar") }, { value: false, label: qsTr("Desactivar") }]);
        if (key === "themeId")
            return keep.concat([{ value: "ink", label: "Ink" }, { value: "washi", label: "Washi" }, { value: "kurogane", label: "Kurogane" }]);
        if (key === "bottomHub.spacing")
            return keep.concat([{ value: "compact", label: qsTr("Compacta") }, { value: "standard", label: qsTr("Normal") }, { value: "airy", label: qsTr("Amplia") }]);
        if (key === "powerProfile")
            return keep.concat([{ value: "power-saver", label: qsTr("Ahorro") }, { value: "balanced", label: qsTr("Equilibrado") }, { value: "performance", label: qsTr("Rendimiento") }]);
        return keep.concat([1000, 1500, 3000, 5000, 10000].map(ms => ({ value: ms, label: qsTr("%1 s").arg(ms / 1000) })));
    }

    // How a setting's value reads in a built-in context.
    function valueLabel(key: string, value): string {
        if (value === undefined)
            return "";
        const option = root.options(key).find(item => item.value === value);
        if (typeof value === "boolean")
            return value ? qsTr("Activado") : qsTr("Desactivado");
        return option ? option.label : String(value);
    }

    spacing: CortetsuDesign.spacingSection

    SettingsGroup {
        title: qsTr("Contexto activo")
        icon: "tune"
        detail: qsTr("Un contexto cambia varios ajustes a la vez. Al desactivarlo vuelven los valores anteriores, salvo los que cambiaste mientras estaba activo.")

        SettingValueRow {
            objectName: "activeContext"
            title: CortetsuContexts.active ? CortetsuContexts.active.name : qsTr("Ninguno")
            detail: CortetsuContexts.error || CortetsuContexts.notice
                || (CortetsuContexts.active ? "" : qsTr("Elige uno abajo para ver qué cambia y actívalo"))
            attention: CortetsuContexts.error.length > 0
            value: CortetsuContexts.active ? qsTr("Activo") : ""
        }

        SettingActionRow {
            objectName: "deactivateContext"
            visible: CortetsuContexts.activeId.length > 0
            title: qsTr("Desactivar el contexto")
            detail: qsTr("Restaura los ajustes que el contexto cambió")
            actionLabel: qsTr("Desactivar")
            onActivated: CortetsuContexts.deactivate()
        }

        SettingChoiceChips {
            objectName: "contextChoice"
            Layout.fillWidth: true
            title: qsTr("Contextos")
            options: CortetsuContexts.contexts.map(c => ({ value: c.id, label: c.name, icon: c.icon }))
            current: root.selected?.id
            onChosen: value => root.selectedId = value
        }
    }

    SettingsGroup {
        visible: !!root.selected
        title: root.selected?.name ?? ""
        icon: root.selected?.icon ?? "tune"
        detail: root.selected?.summary ?? ""

        SettingActionRow {
            objectName: "toggleContext"
            title: root.selectedActive ? qsTr("Desactivar «%1»").arg(root.selected.name) : qsTr("Activar «%1»").arg(root.selected?.name ?? "")
            detail: root.selectedActive ? qsTr("Vuelven los valores anteriores")
                : CortetsuContexts.activeId.length > 0 ? qsTr("Primero se desactiva el contexto activo")
                : qsTr("Los ajustes de abajo se aplican al momento")
            actionLabel: root.selectedActive ? qsTr("Desactivar") : qsTr("Activar")
            actionDisabled: !CortetsuContexts.loaded
            onActivated: CortetsuContexts.toggle(root.selected.id)
        }

        SettingTextRow {
            objectName: "contextName"
            visible: root.editable
            title: qsTr("Nombre")
            value: root.selected?.name ?? ""
            onCommitted: value => CortetsuContexts.update(root.selected.id, { name: value })
        }

        // A built-in context is read only: what it changes reads as plain
        // values. A context of one's own offers every setting to edit.
        Repeater {
            model: Object.keys(CortetsuContexts.keys)
            delegate: ColumnLayout {
                id: settingRow
                required property string modelData
                readonly property var setting: root.selected?.settings[modelData]
                // Said before activating too, with the rule the service applies.
                readonly property string skippedNote: root.selectedActive
                    ? (CortetsuContexts.skipped.includes(modelData) ? qsTr("Lo gestiona la automatización; el contexto no lo tocó") : "")
                    : (setting !== undefined && CortetsuContexts.ownedByAutomation(modelData) ? qsTr("Lo gestiona la automatización; el contexto no lo tocará") : "")
                Layout.fillWidth: true
                spacing: 0
                visible: root.editable || setting !== undefined

                SettingChoiceChips {
                    Layout.fillWidth: true
                    visible: root.editable
                    title: CortetsuContexts.describe(settingRow.modelData)
                    detail: settingRow.skippedNote
                    options: root.options(settingRow.modelData)
                    current: settingRow.setting === undefined ? "keep" : settingRow.setting
                    onChosen: value => CortetsuContexts.setSetting(root.selected.id, settingRow.modelData, value === "keep" ? undefined : value)
                }

                SettingValueRow {
                    Layout.fillWidth: true
                    visible: !root.editable
                    title: CortetsuContexts.describe(settingRow.modelData)
                    detail: settingRow.skippedNote
                    value: root.valueLabel(settingRow.modelData, settingRow.setting)
                }
            }
        }

        SettingActionRow {
            objectName: "duplicateContext"
            title: qsTr("Duplicar")
            detail: qsTr("Crea un contexto propio con estos ajustes para editarlo")
            actionLabel: qsTr("Duplicar")
            actionDisabled: CortetsuContexts.custom.length >= 32
            onActivated: {
                const id = CortetsuContexts.duplicate(root.selected.id);
                if (id.length > 0)
                    root.selectedId = id;
            }
        }

        SettingActionRow {
            objectName: "removeContext"
            visible: root.editable
            title: qsTr("Eliminar")
            detail: root.selectedActive ? qsTr("Se desactiva antes y vuelven los valores anteriores") : ""
            actionLabel: qsTr("Eliminar")
            danger: true
            confirm: true
            onActivated: {
                CortetsuContexts.remove(root.selected.id);
                root.selectedId = "university";
            }
        }
    }

    SettingsGroup {
        title: qsTr("Exportar e importar")
        icon: "save"
        detail: qsTr("Un contexto exportado solo contiene los ajustes de esta lista; al importar se descarta cualquier otro campo.")

        SettingTextRow {
            objectName: "contextPath"
            title: qsTr("Archivo")
            value: root.transferPath
            displayValue: root.home.length > 0 && root.transferPath.startsWith(root.home + "/")
                ? "~" + root.transferPath.slice(root.home.length) : root.transferPath
            placeholderText: qsTr("Ruta absoluta a un archivo JSON")
            fieldWidth: Math.max(260, width * 0.66)
            onCommitted: value => root.transferPath = value.trim()
        }

        SettingActionRow {
            objectName: "exportContext"
            title: qsTr("Exportar «%1»").arg(root.selected?.name ?? "")
            detail: qsTr("Si el archivo existe, se reemplaza")
            actionLabel: qsTr("Exportar")
            confirm: true
            onActivated: CortetsuContexts.exportTo(root.selected.id, root.transferPath)
        }

        SettingActionRow {
            objectName: "importContext"
            title: qsTr("Importar un contexto")
            detail: qsTr("Se añade como contexto propio; no se activa")
            actionLabel: qsTr("Importar")
            actionDisabled: CortetsuContexts.custom.length >= 32
            onActivated: CortetsuContexts.importFrom(root.transferPath)
        }
    }
}
