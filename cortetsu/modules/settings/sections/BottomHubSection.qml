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
        title: qsTr("Segmentos")
        detail: qsTr("Qué grupos ocupan la barra")

        SettingToggleRow {
            objectName: "segmentMode"
            title: qsTr("Modo y espacios")
            detail: qsTr("Lanzador, fondo y espacios de trabajo")
            checked: CortetsuConfig.bottomHub.segments.mode
            onToggled: value => { CortetsuConfig.bottomHub.segments.mode = value; CortetsuConfig.save(); }
        }

        SettingToggleRow {
            title: qsTr("Aplicaciones")
            detail: qsTr("Abiertas y fijadas")
            checked: CortetsuConfig.bottomHub.segments.apps
            onToggled: value => { CortetsuConfig.bottomHub.segments.apps = value; CortetsuConfig.save(); }
        }

        SettingToggleRow {
            title: qsTr("Bandeja")
            detail: qsTr("Iconos de las aplicaciones en segundo plano")
            checked: CortetsuConfig.bottomHub.segments.tray
            onToggled: value => { CortetsuConfig.bottomHub.segments.tray = value; CortetsuConfig.save(); }
        }
    }

    SettingsGroup {
        title: qsTr("Indicadores de estado")
        detail: qsTr("Qué muestra el grupo de la derecha")

        SettingToggleRow {
            title: qsTr("Audio")
            checked: CortetsuConfig.bottomHub.statusCluster.audio
            onToggled: value => { CortetsuConfig.bottomHub.statusCluster.audio = value; CortetsuConfig.save(); }
        }

        SettingToggleRow {
            title: qsTr("Red")
            checked: CortetsuConfig.bottomHub.statusCluster.network
            onToggled: value => { CortetsuConfig.bottomHub.statusCluster.network = value; CortetsuConfig.save(); }
        }

        SettingToggleRow {
            title: qsTr("Bluetooth")
            checked: CortetsuConfig.bottomHub.statusCluster.bluetooth
            onToggled: value => { CortetsuConfig.bottomHub.statusCluster.bluetooth = value; CortetsuConfig.save(); }
        }

        SettingToggleRow {
            title: qsTr("Batería")
            checked: CortetsuConfig.bottomHub.statusCluster.battery
            onToggled: value => { CortetsuConfig.bottomHub.statusCluster.battery = value; CortetsuConfig.save(); }
        }
    }

    SettingsGroup {
        title: qsTr("Interacción")

        SettingToggleRow {
            title: qsTr("Detalle al pulsar un estado")
            detail: qsTr("Audio, red, Bluetooth y batería abren su panel desde la barra")
            checked: CortetsuConfig.bar.popouts.statusIcons
            onToggled: value => { CortetsuConfig.bar.popouts.statusIcons = value; CortetsuConfig.save(); }
        }

        SettingToggleRow {
            title: qsTr("Volumen con la rueda")
            detail: qsTr("Girar la rueda sobre la barra sube o baja el volumen")
            checked: CortetsuConfig.bar.scrollActions.volume
            onToggled: value => { CortetsuConfig.bar.scrollActions.volume = value; CortetsuConfig.save(); }
        }
    }
}
