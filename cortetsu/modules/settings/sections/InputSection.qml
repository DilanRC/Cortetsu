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
        title: qsTr("Teclado")

        SettingValueRow {
            objectName: "layout"
            title: qsTr("Distribución activa")
            detail: qsTr("Se cambia con el atajo de Hyprland")
            value: root.context.keyboardLayout.length > 0 ? root.context.keyboardLayout : qsTr("No disponible")
        }

        SettingToggleRow {
            title: qsTr("Navegación estilo Vim")
            detail: qsTr("Ctrl con h, j, k y l mueve la selección del lanzador")
            checked: CortetsuConfig.vimKeybinds
            onToggled: value => { CortetsuConfig.vimKeybinds = value; CortetsuConfig.save(); }
        }
    }
}
