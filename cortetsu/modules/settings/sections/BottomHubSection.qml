pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../../components"
import "../.."
import ".."
import "../../CortetsuDesign.js" as CortetsuDesign

ColumnLayout {
    id: root

    required property var page

    spacing: CortetsuDesign.spacingStandard

    CortetsuSectionHeader {
        Layout.fillWidth: true
        title: qsTr("Comportamiento de BottomHub")
        detail: qsTr("Estado e interacción con el puntero")
    }

    DomainHero {
        icon: "dock_to_bottom"
        title: qsTr("BottomHub activo")
        detail: qsTr("La barra se actualiza con esta configuración en todos los monitores")
        value: qsTr("%1 grupos").arg(root.page.enabledBottomSegments)
        meta: qsTr("%1 estados visibles · %2")
            .arg(root.page.enabledStatusSegments)
            .arg(CortetsuConfig.bar.persistent ? qsTr("persistente") : qsTr("al pasar el puntero"))
    }

    PreferenceToggle {
        title: qsTr("Barra persistente")
        detail: qsTr("Mantener BottomHub visible sin depender del borde inferior")
        icon: "push_pin"
        checked: CortetsuConfig.bar.persistent
        onChanged: checked => { CortetsuConfig.bar.persistent = checked; root.page.savePreference(); }
    }

    PreferenceToggle {
        title: qsTr("Ventanas emergentes del estado")
        detail: qsTr("Abrir el detalle de audio, red, Bluetooth y batería desde la barra")
        icon: "open_in_new"
        checked: CortetsuConfig.bar.popouts.statusIcons
        onChanged: checked => { CortetsuConfig.bar.popouts.statusIcons = checked; root.page.savePreference(); }
    }

    PreferenceToggle {
        title: qsTr("Desplazamiento del volumen")
        detail: qsTr("Ajustar el volumen con la rueda sobre BottomHub")
        icon: "volume_up"
        checked: CortetsuConfig.bar.scrollActions.volume
        onChanged: checked => {
            CortetsuConfig.bar.scrollActions.volume = checked;
            root.page.savePreference();
        }
    }

    PreferenceToggle {
        title: qsTr("Desplazamiento de espacios")
        detail: qsTr("Cambiar de espacio con la rueda sobre el grupo de espacios")
        icon: "view_carousel"
        checked: CortetsuConfig.bar.scrollActions.workspaces
        onChanged: checked => { CortetsuConfig.bar.scrollActions.workspaces = checked; root.page.savePreference(); }
    }

    PreferenceToggle {
        title: qsTr("Desplazamiento del brillo")
        detail: qsTr("Ajustar el brillo con la rueda sobre la barra")
        icon: "brightness_6"
        checked: CortetsuConfig.bar.scrollActions.brightness
        onChanged: checked => { CortetsuConfig.bar.scrollActions.brightness = checked; root.page.savePreference(); }
    }

    CortetsuSectionHeader {
        Layout.fillWidth: true
        title: qsTr("Segmentos visibles")
        detail: qsTr("Elegir qué grupos de BottomHub permanecen en la barra")
    }

    PreferenceToggle {
        title: qsTr("Modo y espacios")
        detail: qsTr("Mostrar controles del lanzador, fondo y espacios")
        icon: "apps"
        checked: CortetsuConfig.bottomHub.segments.mode
        onChanged: checked => {
            CortetsuConfig.bottomHub.segments.mode = checked;
            root.page.savePreference();
        }
    }

    PreferenceToggle {
        title: qsTr("Barra de aplicaciones")
        detail: qsTr("Mostrar aplicaciones abiertas y fijadas")
        icon: "apps"
        checked: CortetsuConfig.bottomHub.segments.apps
        onChanged: checked => {
            CortetsuConfig.bottomHub.segments.apps = checked;
            root.page.savePreference();
        }
    }

    PreferenceToggle {
        title: qsTr("Bandeja")
        detail: qsTr("Mostrar aplicaciones y menús de StatusNotifier")
        icon: "notifications"
        checked: CortetsuConfig.bottomHub.segments.tray
        onChanged: checked => {
            CortetsuConfig.bottomHub.segments.tray = checked;
            root.page.savePreference();
        }
    }

    PreferenceToggle {
        title: qsTr("Estado de audio")
        detail: qsTr("Mostrar volumen y salida en el grupo de estado")
        icon: "volume_up"
        checked: CortetsuConfig.bottomHub.statusCluster.audio
        onChanged: checked => {
            CortetsuConfig.bottomHub.statusCluster.audio = checked;
            root.page.savePreference();
        }
    }

    PreferenceToggle {
        title: qsTr("Estado de red")
        detail: qsTr("Mostrar Wi-Fi o Ethernet en el grupo de estado")
        icon: "wifi"
        checked: CortetsuConfig.bottomHub.statusCluster.network
        onChanged: checked => {
            CortetsuConfig.bottomHub.statusCluster.network = checked;
            root.page.savePreference();
        }
    }

    PreferenceToggle {
        title: qsTr("Estado de Bluetooth")
        detail: qsTr("Mostrar el adaptador Bluetooth en el grupo de estado")
        icon: "bluetooth"
        checked: CortetsuConfig.bottomHub.statusCluster.bluetooth
        onChanged: checked => {
            CortetsuConfig.bottomHub.statusCluster.bluetooth = checked;
            root.page.savePreference();
        }
    }

    PreferenceToggle {
        title: qsTr("Estado de batería")
        detail: qsTr("Mostrar carga y alimentación en el grupo de estado")
        icon: "battery_full"
        checked: CortetsuConfig.bottomHub.statusCluster.battery
        onChanged: checked => {
            CortetsuConfig.bottomHub.statusCluster.battery = checked;
            root.page.savePreference();
        }
    }

    CortetsuSectionHeader {
        Layout.fillWidth: true
        title: qsTr("Presentación de la barra")
        detail: qsTr("Densidad, reloj y ventanas activas")
    }

    PreferenceToggle {
        title: qsTr("Bandeja compacta")
        detail: qsTr("Agrupar los iconos de StatusNotifier en menos espacio")
        icon: "apps"
        checked: CortetsuConfig.bar.tray.compact
        onChanged: checked => { CortetsuConfig.bar.tray.compact = checked; root.page.savePreference(); }
    }

    PreferenceToggle {
        title: qsTr("Fecha en el reloj")
        detail: qsTr("Mostrar la fecha junto a la hora")
        icon: "calendar_today"
        checked: CortetsuConfig.bar.clock.showDate
        onChanged: checked => { CortetsuConfig.bar.clock.showDate = checked; root.page.savePreference(); }
    }

    PreferenceToggle {
        title: qsTr("Ventana activa compacta")
        detail: qsTr("Reducir el ancho del título de la ventana enfocada")
        icon: "web_asset"
        checked: CortetsuConfig.bar.activeWindow.compact
        onChanged: checked => { CortetsuConfig.bar.activeWindow.compact = checked; root.page.savePreference(); }
    }

}
