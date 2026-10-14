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

    spacing: CortetsuDesign.spacingSection

    SettingsGroup {
        title: qsTr("Lanzador")

        SettingToggleRow {
            objectName: "launcherEnabled"
            title: qsTr("Lanzador")
            detail: qsTr("Si se apaga, la tecla SUPER no lo abre")
            checked: CortetsuConfig.launcher.enabled
            onToggled: value => { CortetsuConfig.launcher.enabled = value; CortetsuConfig.save(); }
        }

        SettingToggleRow {
            title: qsTr("Abrir al acercar el puntero")
            detail: qsTr("Llevar el puntero al borde inferior muestra el lanzador")
            checked: CortetsuConfig.launcher.showOnHover
            disabled: !CortetsuConfig.launcher.enabled
            onToggled: value => { CortetsuConfig.launcher.showOnHover = value; CortetsuConfig.save(); }
        }

        SettingActionRow {
            title: qsTr("Probar el lanzador")
            detail: qsTr("Cierra Ajustes y abre el buscador en esta pantalla")
            actionLabel: qsTr("Abrir lanzador")
            actionIcon: "search"
            disabled: !CortetsuConfig.launcher.enabled
            onActivated: root.context.openSurface("launcher")
        }
    }

    SettingsGroup {
        title: qsTr("Búsqueda aproximada")
        detail: qsTr("Aceptar nombres parecidos a lo escrito")

        SettingToggleRow {
            title: qsTr("Aplicaciones, acciones y esquemas")
            checked: CortetsuConfig.useFuzzyApps
            onToggled: value => { CortetsuConfig.useFuzzyApps = value; CortetsuConfig.save(); }
        }

        SettingToggleRow {
            title: qsTr("Fondos")
            checked: CortetsuConfig.useFuzzyWallpapers
            onToggled: value => { CortetsuConfig.useFuzzyWallpapers = value; CortetsuConfig.save(); }
        }
    }
}
