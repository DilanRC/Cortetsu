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
        title: qsTr("Posición del reloj")
        detail: qsTr("El reloj se activa desde Interface")
        SettingToggleRow {
            objectName: "clockShowDate"
            title: qsTr("Mostrar fecha")
            detail: qsTr("Muestra el mes, día y nombre del día junto a la hora")
            checked: CortetsuConfig.desktopClockShowDate
            onToggled: value => { CortetsuConfig.desktopClockShowDate = value; CortetsuConfig.save(); }
        }
        Repeater {
            model: [
                {id: "top-left", name: qsTr("Arriba izquierda")},
                {id: "top-center", name: qsTr("Arriba centro")},
                {id: "top-right", name: qsTr("Arriba derecha")},
                {id: "middle-left", name: qsTr("Centro izquierda")},
                {id: "middle-center", name: qsTr("Centro")},
                {id: "middle-right", name: qsTr("Centro derecha")},
                {id: "bottom-left", name: qsTr("Abajo izquierda")},
                {id: "bottom-center", name: qsTr("Abajo centro")},
                {id: "bottom-right", name: qsTr("Abajo derecha")}
            ]
            SettingActionRow {
                required property var modelData
                objectName: "clock-" + modelData.id
                title: modelData.name
                actionLabel: CortetsuConfig.desktopClockPosition === modelData.id ? qsTr("Activa") : qsTr("Elegir")
                actionDisabled: CortetsuConfig.desktopClockPosition === modelData.id
                onActivated: { CortetsuConfig.desktopClockPosition = modelData.id; CortetsuConfig.save(); }
            }
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
