pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../../../components"
import "../../../services"
import "../../../theme"
import "../.."
import "../controls"

ColumnLayout {
    id: root

    required property var context

    readonly property string status: CortetsuWallpapers.applyStatus

    spacing: CortetsuDesign.spacingSection

    SettingsGroup {
        title: qsTr("Fondo actual")

        SettingValueRow {
            objectName: "wallpaperFile"
            title: root.status === "applying"
                ? qsTr("Aplicando")
                : root.status === "failed" ? qsTr("No se pudo aplicar") : qsTr("Imagen")
            detail: root.status === "failed"
                ? (CortetsuWallpapers.applyError || CortetsuWallpapers.applyStatusPath.split("/").pop())
                : CortetsuWallpapers.actualCurrent
            status: root.status === "failed" ? "error" : ""
            statusText: CortetsuWallpapers.applyError || qsTr("El fondo anterior sigue puesto")
            value: root.status === "applying"
                ? CortetsuWallpapers.applyStatusPath.split("/").pop()
                : root.context.wallpaperName.length > 0 ? root.context.wallpaperName : qsTr("Sin fondo")
            attention: root.status === "failed"
        }

        SettingActionRow {
            title: qsTr("Elegir otro fondo")
            detail: qsTr("El gestor muestra la carpeta de fondos y una vista previa")
            actionLabel: qsTr("Abrir gestor")
            actionIcon: "collections"
            onActivated: root.context.openSurface("wallpaperManager")
        }
    }

    SettingsGroup {
        title: qsTr("Integración")

        SettingToggleRow {
            title: qsTr("Cortetsu pone el fondo")
            detail: qsTr("Si se apaga, el escritorio queda sin fondo de Cortetsu")
            checked: CortetsuConfig.wallpaperEnabled
            onToggled: value => { CortetsuConfig.wallpaperEnabled = value; CortetsuConfig.save(); }
        }
    }
}
