pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../../../components"
import "../.."
import "../../CortetsuDesign.js" as CortetsuDesign

ColumnLayout {
    id: root

    required property var page

    spacing: CortetsuDesign.spacingCompact

    CortetsuSectionHeader {
        Layout.fillWidth: true
        title: qsTr("Atajos configurados de Cortetsu")
        detail: qsTr("Asignaciones activas de la capa global de Hyprland")
    }

    DomainHero {
        icon: "keyboard_command_key"
        title: qsTr("Atajos del shell")
        detail: qsTr("Los atajos se resuelven en la configuración canónica de Cortetsu")
        value: qsTr("%1 accesos").arg(6)
        meta: qsTr("SUPER + I abre este centro")
    }

    ShortcutRow { keys: qsTr("SUPER + SHIFT + D"); action: qsTr("Panel principal"); detail: qsTr("Abrir o cerrar el Dashboard") }
    ShortcutRow { keys: qsTr("SUPER + I"); action: qsTr("Ajustes"); detail: qsTr("Abrir o cerrar este centro") }
    ShortcutRow { keys: qsTr("SUPER + / · SUPER + SHIFT + 7"); action: qsTr("OSD completo"); detail: qsTr("Controles rápidos de audio, brillo, red y sesión") }
    ShortcutRow { keys: qsTr("SUPER + V"); action: qsTr("Portapapeles"); detail: qsTr("Abrir el historial de Clipse") }
    ShortcutRow { keys: qsTr("SUPER + SHIFT + W"); action: qsTr("Gestor de fondos"); detail: qsTr("Abrir el selector orbital de fondos") }
    ShortcutRow { keys: qsTr("Print"); action: qsTr("Captura de área"); detail: qsTr("Seleccionar una región sin cerrar superficies QML") }
}
