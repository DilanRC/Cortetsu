pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../../../components"
import "../../../services"
import "../../../theme"
import "../.."
import "../controls"

SettingsColumns {
    id: root

    required property var context

    SettingsGroup {
        title: qsTr("Segmentos")
        icon: "view_column"
        detail: qsTr("Qué grupos ocupan la barra")

        SettingToggleRow {
            objectName: "segmentMode"
            title: qsTr("Modo y espacios")
            detail: qsTr("Lanzador, fondo y espacios de trabajo")
            checked: CortetsuConfig.bottomHub.segments.mode
            onToggled: value => { CortetsuConfig.bottomHub.segments.mode = value; CortetsuConfig.save(); }
        }

        SettingToggleRow {
            objectName: "appsSegment"
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

        SettingToggleRow {
            objectName: "trayMonochromeIcons"
            title: qsTr("Iconos monocromos de la bandeja")
            detail: qsTr("Adaptar el color de los iconos al tema activo")
            checked: CortetsuConfig.bar.tray.recolour
            onToggled: value => { CortetsuConfig.bar.tray.recolour = value; }
        }
    }

    SettingsGroup {
        title: qsTr("Interacción")
        icon: "touch_app"

        SettingToggleRow {
            objectName: "barAutoHide"
            title: qsTr("Ocultar automáticamente")
            detail: qsTr("Ocultar Bottom Hub al alejar el puntero; se revela desde el borde inferior y también se abre con el atajo")
            checked: CortetsuConfig.bar.showOnHover
            onToggled: value => { CortetsuConfig.bar.showOnHover = value; }
        }

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

    aside: [
        SettingsGroup {
            title: qsTr("Indicadores de estado")
            icon: "toggle_on"
            detail: qsTr("Qué muestra el grupo de la derecha")

            SettingToggleRow {
                objectName: "notificationCount"
                title: qsTr("Mostrar cantidad de notificaciones")
                detail: qsTr("Mostrar el total conservado en el historial junto al botón")
                checked: CortetsuConfig.bottomHub.statusCluster.showNotificationCount
                onToggled: value => { CortetsuConfig.bottomHub.statusCluster.showNotificationCount = value; CortetsuConfig.save(); }
            }

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
        },

        SettingsGroup {
            title: qsTr("Espacios de trabajo")
            icon: "workspaces"
            detail: qsTr("Cuántos espacios muestra Bottom Hub alrededor del activo")

            SettingSliderRow {
                objectName: "workspacesShown"
                title: qsTr("Espacios visibles")
                valueText: qsTr("%1").arg(CortetsuConfig.workspacesShown)
                from: 1
                to: 20
                step: 1
                value: CortetsuConfig.workspacesShown
                onMoved: value => CortetsuConfig.setWorkspacesShown(Math.round(value))
            }

            SettingToggleRow {
                objectName: "workspaceNumbers"
                title: qsTr("Mostrar números")
                detail: qsTr("Usar cifras en lugar de indicadores gráficos")
                checked: CortetsuConfig.bar.workspaces.displayType === 1
                onToggled: value => {
                    CortetsuConfig.bar.workspaces.displayType = value ? 1 : 0;
                    CortetsuConfig.save();
                }
            }

            SettingToggleRow {
                objectName: "workspaceAppIcons"
                title: qsTr("Icono de la aplicación")
                detail: qsTr("Mostrar el icono de una ventana en los espacios ocupados")
                checked: CortetsuConfig.bar.workspaces.showAppIcons
                onToggled: value => { CortetsuConfig.bar.workspaces.showAppIcons = value; }
            }

            SettingToggleRow {
                objectName: "workspaceMonochromeIcons"
                title: qsTr("Iconos monocromos")
                detail: qsTr("Aplicar el color de texto del tema a los iconos de aplicación")
                checked: CortetsuConfig.bar.workspaces.monochromeIcons
                onToggled: value => { CortetsuConfig.bar.workspaces.monochromeIcons = value; }
            }

            SettingToggleRow {
                objectName: "perMonitorWorkspaces"
                title: qsTr("Espacios por monitor")
                detail: qsTr("Cada pantalla marca el espacio activo de su propio monitor")
                checked: CortetsuConfig.bar.workspaces.perMonitorWorkspaces
                onToggled: value => { CortetsuConfig.bar.workspaces.perMonitorWorkspaces = value; CortetsuConfig.save(); }
            }
        }
    ]
}
