pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../../../components"
import "../../../services"
import "../../../theme"
import "../.."
import "../controls"

// The panels that open from the screen's edges: the Dashboard at the top,
// the notification panel and the utilities. Each reads these preferences
// directly; nothing here keeps a copy.
SettingsColumns {
    id: root

    required property var context

    SettingsGroup {
        title: qsTr("Dashboard")
        icon: "space_dashboard"
        detail: qsTr("El panel que baja desde el borde superior")

        SettingToggleRow {
            objectName: "dashboardEnabled"
            title: qsTr("Dashboard")
            detail: qsTr("Si se apaga, ni el atajo ni el borde superior lo abren")
            // Two stored flags gate the panel and nothing tells them apart;
            // the switch reads and writes both so neither is left stranded.
            checked: CortetsuConfig.dashboard.enabled && CortetsuConfig.dashboard.showDashboard
            onToggled: value => {
                CortetsuConfig.dashboard.enabled = value;
                CortetsuConfig.dashboard.showDashboard = value;
                CortetsuConfig.save();
            }
        }

        SettingToggleRow {
            title: qsTr("Abrir al acercar el puntero")
            detail: qsTr("Llevar el puntero al borde superior muestra el panel")
            checked: CortetsuConfig.dashboard.showOnHover
            disabled: !CortetsuConfig.dashboard.enabled
            onToggled: value => { CortetsuConfig.dashboard.showOnHover = value; CortetsuConfig.save(); }
        }
    }

    SettingsGroup {
        title: qsTr("Paneles laterales")
        icon: "side_navigation"
        detail: qsTr("Los paneles que se abren desde los bordes de la pantalla")

        SettingToggleRow {
            objectName: "sidebarEnabled"
            title: qsTr("Panel de avisos")
            detail: qsTr("El panel lateral con las notificaciones y su historial")
            checked: CortetsuConfig.sidebar.enabled
            onToggled: value => { CortetsuConfig.sidebar.enabled = value; CortetsuConfig.save(); }
        }

        SettingToggleRow {
            objectName: "sidebarShowOnHover"
            title: qsTr("Abrir avisos al acercar el puntero")
            detail: qsTr("Llevar el puntero al borde muestra el panel de avisos")
            checked: CortetsuConfig.sidebar.showOnHover
            disabled: !CortetsuConfig.sidebar.enabled
            onToggled: value => { CortetsuConfig.sidebar.showOnHover = value; CortetsuConfig.save(); }
        }

        SettingToggleRow {
            objectName: "utilitiesEnabled"
            title: qsTr("Panel de utilidades")
            detail: qsTr("Mantener despierto, grabador y conmutadores rápidos")
            checked: CortetsuConfig.utilities.enabled
            onToggled: value => { CortetsuConfig.utilities.enabled = value; CortetsuConfig.save(); }
        }
    }

    aside: [
        SettingsGroup {
            title: qsTr("Contenido del Dashboard")
            icon: "widgets"
            visible: CortetsuConfig.dashboard.enabled

            SettingToggleRow {
                title: qsTr("Multimedia")
                detail: qsTr("El reproductor en curso")
                checked: CortetsuConfig.dashboard.showMedia
                onToggled: value => { CortetsuConfig.dashboard.showMedia = value; CortetsuConfig.save(); }
            }

            SettingToggleRow {
                objectName: "dashboardWeather"
                title: qsTr("Clima")
                checked: CortetsuConfig.dashboard.showWeather
                onToggled: value => { CortetsuConfig.dashboard.showWeather = value; CortetsuConfig.save(); }
            }

            SettingToggleRow {
                objectName: "dashboardMetrics"
                title: qsTr("Métricas")
                detail: qsTr("Uso del equipo; cada lectura se elige abajo")
                checked: CortetsuConfig.dashboard.showPerformance
                onToggled: value => { CortetsuConfig.dashboard.showPerformance = value; CortetsuConfig.save(); }
            }

            SettingToggleRow {
                title: qsTr("CPU")
                checked: CortetsuConfig.dashboard.performance.showCpu
                disabled: !CortetsuConfig.dashboard.showPerformance
                onToggled: value => { CortetsuConfig.dashboard.performance.showCpu = value; CortetsuConfig.save(); }
            }

            SettingToggleRow {
                title: qsTr("GPU")
                checked: CortetsuConfig.dashboard.performance.showGpu
                disabled: !CortetsuConfig.dashboard.showPerformance
                onToggled: value => { CortetsuConfig.dashboard.performance.showGpu = value; CortetsuConfig.save(); }
            }

            SettingToggleRow {
                title: qsTr("Memoria")
                checked: CortetsuConfig.dashboard.performance.showMemory
                disabled: !CortetsuConfig.dashboard.showPerformance
                onToggled: value => { CortetsuConfig.dashboard.performance.showMemory = value; CortetsuConfig.save(); }
            }

            SettingToggleRow {
                title: qsTr("Almacenamiento")
                checked: CortetsuConfig.dashboard.performance.showStorage
                disabled: !CortetsuConfig.dashboard.showPerformance
                onToggled: value => { CortetsuConfig.dashboard.performance.showStorage = value; CortetsuConfig.save(); }
            }

            SettingToggleRow {
                title: qsTr("Red")
                checked: CortetsuConfig.dashboard.performance.showNetwork
                disabled: !CortetsuConfig.dashboard.showPerformance
                onToggled: value => { CortetsuConfig.dashboard.performance.showNetwork = value; CortetsuConfig.save(); }
            }

            SettingToggleRow {
                title: qsTr("Batería")
                checked: CortetsuConfig.dashboard.performance.showBattery
                disabled: !CortetsuConfig.dashboard.showPerformance
                onToggled: value => { CortetsuConfig.dashboard.performance.showBattery = value; CortetsuConfig.save(); }
            }
        }
    ]
}
