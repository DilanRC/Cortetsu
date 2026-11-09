pragma ComponentBehavior: Bound

import QtQuick
import "../../../services"
import "../.."
import "../controls"

// Where the palette goes outside the shell, and how each target took it.
SettingsGroup {
    title: qsTr("Aplicaciones sincronizadas")
    icon: "sync"
    detail: qsTr("La paleta se comparte con los destinos compatibles. Algunas aplicaciones deben abrirse de nuevo.")

    Repeater {
        model: [{id: "hyprland", title: qsTr("Compositor")}, {id: "kitty", title: qsTr("Terminal Kitty")},
            {id: "gtk", title: qsTr("GTK")}, {id: "qt", title: qsTr("Qt / KDE")}]
        SettingToggleRow {
            required property var modelData
            readonly property var result: CortetsuThemes.integrations[modelData.id] || ({status: "pending"})
            objectName: "themeIntegration-" + modelData.id
            title: modelData.title
            checked: CortetsuConfig.themeIntegrations[modelData.id] !== false
            disabled: CortetsuThemes.busy || CortetsuThemes.syncAfterSave
            status: result.status === "error" ? "error" : CortetsuThemes.busy ? "busy" : ""
            statusText: result.status === "error" ? result.detail || "" : ""
            detail: result.status === "applied" ? qsTr("Aplicado")
                : result.status === "reopen" ? qsTr("Requiere reabrir la aplicación")
                : result.status === "disabled" ? qsTr("Desactivado")
                : result.status === "unavailable" ? qsTr("No disponible: %1").arg(result.detail || "")
                : result.status === "error" ? qsTr("Error de sincronización") : qsTr("Pendiente de sincronización")
            onToggled: enabled => CortetsuThemes.setIntegration(modelData.id, enabled)
        }
    }
    SettingActionRow {
        objectName: "themeSync"
        title: qsTr("Volver a sincronizar")
        actionLabel: qsTr("Sincronizar")
        actionIcon: "sync"
        actionDisabled: CortetsuThemes.busy
        status: CortetsuThemes.error ? "error" : ""
        statusText: CortetsuThemes.error
        onActivated: CortetsuThemes.sync()
    }
}
