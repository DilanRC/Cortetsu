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
        title: qsTr("Dashboard")
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
        title: qsTr("Contenido del Dashboard")
        visible: CortetsuConfig.dashboard.enabled

        SettingToggleRow {
            title: qsTr("Multimedia")
            detail: qsTr("El reproductor en curso")
            checked: CortetsuConfig.dashboard.showMedia
            onToggled: value => { CortetsuConfig.dashboard.showMedia = value; CortetsuConfig.save(); }
        }

        SettingToggleRow {
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

    SettingsGroup {
        title: qsTr("Fondo del escritorio")

        SettingToggleRow {
            title: qsTr("Reloj del escritorio")
            detail: qsTr("Un reloj sobre el fondo, detrás de las ventanas")
            checked: CortetsuConfig.desktopClockEnabled
            onToggled: value => { CortetsuConfig.desktopClockEnabled = value; CortetsuConfig.save(); }
        }

        SettingToggleRow {
            title: qsTr("Espacios por monitor")
            detail: qsTr("BottomHub marca el espacio activo de su propia pantalla")
            checked: CortetsuConfig.bar.workspaces.perMonitorWorkspaces
            onToggled: value => { CortetsuConfig.bar.workspaces.perMonitorWorkspaces = value; CortetsuConfig.save(); }
        }
    }
}
