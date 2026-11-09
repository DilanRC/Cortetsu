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

    property string actionPrefixError: ""
    spacing: CortetsuDesign.spacingSection

    SettingsGroup {
        title: qsTr("Lanzador")
        icon: "apps"

        SettingToggleRow {
            objectName: "launcherEnabled"
            title: qsTr("Lanzador")
            detail: qsTr("Si se apaga, la tecla SUPER no lo abre")
            checked: CortetsuConfig.launcher.enabled
            onToggled: value => { CortetsuConfig.launcher.enabled = value; CortetsuConfig.save(); }
        }

        SettingToggleRow {
            objectName: "launcherShowOnHover"
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

        SettingTextRow {
            objectName: "actionPrefix"
            title: qsTr("Prefijo de acciones")
            detail: qsTr("Escribe este carácter antes de un comando, por ejemplo > calendario")
            value: CortetsuConfig.actionPrefix
            placeholderText: ">"
            status: root.actionPrefixError ? "error" : ""
            statusText: root.actionPrefixError
            onCommitted: value => {
                const prefix = value.trim();
                if (prefix.length !== 1 || prefix === CortetsuConfig.specialPrefix[0]) {
                    root.actionPrefixError = qsTr("Usa un carácter y evita el prefijo de selección %1").arg(CortetsuConfig.specialPrefix[0]);
                    return;
                }
                root.actionPrefixError = "";
                CortetsuConfig.actionPrefix = prefix;
                CortetsuConfig.save();
            }
        }
    }

    SettingsGroup {
        title: qsTr("Búsqueda aproximada")
        icon: "manage_search"
        detail: qsTr("Aceptar nombres parecidos a lo escrito")

        SettingToggleRow {
            objectName: "fuzzyApplications"
            title: qsTr("Aplicaciones")
            checked: CortetsuConfig.useFuzzyApps
            onToggled: value => { CortetsuConfig.useFuzzyApps = value; CortetsuConfig.save(); }
        }

        SettingToggleRow {
            objectName: "fuzzyActions"
            title: qsTr("Acciones")
            checked: CortetsuConfig.useFuzzyActions
            onToggled: value => { CortetsuConfig.useFuzzyActions = value; CortetsuConfig.save(); }
        }

        SettingToggleRow {
            objectName: "fuzzySchemes"
            title: qsTr("Esquemas de color")
            checked: CortetsuConfig.useFuzzySchemes
            onToggled: value => { CortetsuConfig.useFuzzySchemes = value; CortetsuConfig.save(); }
        }

        SettingToggleRow {
            objectName: "fuzzyVariants"
            title: qsTr("Variantes de color")
            checked: CortetsuConfig.useFuzzyVariants
            onToggled: value => { CortetsuConfig.useFuzzyVariants = value; CortetsuConfig.save(); }
        }

        SettingToggleRow {
            objectName: "fuzzyWallpapers"
            title: qsTr("Fondos")
            checked: CortetsuConfig.useFuzzyWallpapers
            onToggled: value => { CortetsuConfig.useFuzzyWallpapers = value; CortetsuConfig.save(); }
        }
    }
}
