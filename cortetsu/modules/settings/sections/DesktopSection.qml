pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../../../components"
import "../.."
import "../../CortetsuDesign.js" as CortetsuDesign

ColumnLayout {
    id: root

    required property var page

    spacing: CortetsuDesign.spacingStandard

    CortetsuSectionHeader {
        Layout.fillWidth: true
        title: qsTr("Comportamiento del escritorio")
        detail: qsTr("Espacios y presentación del escritorio")
    }

    DomainHero {
        icon: "desktop_windows"
        title: qsTr("Escritorio preparado")
        detail: qsTr("Estado de los monitores, espacios y Dashboard")
        value: qsTr("%1 monitores").arg(root.page.monitorCount)
        meta: qsTr("%1 espacios · Dashboard %2")
            .arg(root.page.workspaceCount)
            .arg(CortetsuConfig.dashboard.showDashboard ? qsTr("visible") : qsTr("oculto"))
    }

    PreferenceToggle {
        title: qsTr("Dashboard disponible")
        detail: qsTr("Permitir que Cortetsu presente el panel superior y sus controles")
        icon: "dashboard"
        checked: CortetsuConfig.dashboard.enabled
        onChanged: checked => {
            CortetsuConfig.dashboard.enabled = checked;
            root.page.savePreference();
        }
    }

    PreferenceToggle {
        title: qsTr("Dashboard al abrirlo")
        detail: qsTr("Mantener el panel visible cuando se solicita desde el atajo")
        icon: "visibility"
        checked: CortetsuConfig.dashboard.showDashboard
        controlDisabled: !CortetsuConfig.dashboard.enabled
        onChanged: checked => {
            CortetsuConfig.dashboard.showDashboard = checked;
            root.page.savePreference();
        }
    }

    PreferenceToggle {
        title: qsTr("Reloj del escritorio")
        detail: qsTr("Mostrar el reloj de Cortetsu en el escritorio")
        icon: "schedule"
        checked: CortetsuConfig.desktopClockEnabled
        onChanged: checked => {
            CortetsuConfig.desktopClockEnabled = checked;
            root.page.savePreference();
        }
    }

    PreferenceToggle {
        title: qsTr("Espacios por monitor")
        detail: qsTr("Mantener el estado de espacios separado por pantalla")
        icon: "view_carousel"
        checked: CortetsuConfig.bar.workspaces.perMonitorWorkspaces
        onChanged: checked => {
            CortetsuConfig.bar.workspaces.perMonitorWorkspaces = checked;
            root.page.savePreference();
        }
    }

    PreferenceToggle {
        title: qsTr("Panel superior al pasar el puntero")
        detail: qsTr("Mostrar el Dashboard al acercarte al borde superior")
        icon: "dashboard"
        checked: CortetsuConfig.dashboard.showOnHover
        onChanged: checked => {
            CortetsuConfig.dashboard.showOnHover = checked;
            root.page.savePreference();
        }
    }

    PreferenceToggle {
        title: qsTr("Contenido multimedia del Dashboard")
        detail: qsTr("Mostrar el reproductor en el panel superior")
        icon: "music_note"
        checked: CortetsuConfig.dashboard.showMedia
        onChanged: checked => {
            CortetsuConfig.dashboard.showMedia = checked;
            root.page.savePreference();
        }
    }

    PreferenceToggle {
        title: qsTr("Métricas del Dashboard")
        detail: qsTr("Mostrar CPU, GPU, memoria y red en el panel superior")
        icon: "monitoring"
        checked: CortetsuConfig.dashboard.showPerformance
        onChanged: checked => {
            CortetsuConfig.dashboard.showPerformance = checked;
            root.page.savePreference();
        }
    }

    PreferenceToggle {
        title: qsTr("Clima del Dashboard")
        detail: qsTr("Mostrar el estado del tiempo en el panel superior")
        icon: "cloud"
        checked: CortetsuConfig.dashboard.showWeather
        onChanged: checked => {
            CortetsuConfig.dashboard.showWeather = checked;
            root.page.savePreference();
        }
    }

    CortetsuSectionHeader {
        Layout.fillWidth: true
        title: qsTr("Métricas visibles")
        detail: qsTr("Elegir qué lecturas ocupan espacio en el Dashboard")
    }

    PreferenceToggle {
        title: qsTr("CPU")
        detail: qsTr("Uso del procesador")
        icon: "memory"
        checked: CortetsuConfig.dashboard.performance.showCpu
        controlDisabled: !CortetsuConfig.dashboard.showPerformance
        onChanged: checked => { CortetsuConfig.dashboard.performance.showCpu = checked; root.page.savePreference(); }
    }

    PreferenceToggle {
        title: qsTr("GPU")
        detail: qsTr("Uso de la tarjeta gráfica cuando está disponible")
        icon: "developer_board"
        checked: CortetsuConfig.dashboard.performance.showGpu
        controlDisabled: !CortetsuConfig.dashboard.showPerformance
        onChanged: checked => { CortetsuConfig.dashboard.performance.showGpu = checked; root.page.savePreference(); }
    }

    PreferenceToggle {
        title: qsTr("Memoria y almacenamiento")
        detail: qsTr("Consumo de RAM y espacio usado")
        icon: "storage"
        checked: CortetsuConfig.dashboard.performance.showMemory && CortetsuConfig.dashboard.performance.showStorage
        controlDisabled: !CortetsuConfig.dashboard.showPerformance
        onChanged: checked => {
            CortetsuConfig.dashboard.performance.showMemory = checked;
            CortetsuConfig.dashboard.performance.showStorage = checked;
            root.page.savePreference();
        }
    }

    PreferenceToggle {
        title: qsTr("Red y batería")
        detail: qsTr("Tráfico de red y estado de la batería")
        icon: "monitoring"
        checked: CortetsuConfig.dashboard.performance.showNetwork && CortetsuConfig.dashboard.performance.showBattery
        controlDisabled: !CortetsuConfig.dashboard.showPerformance
        onChanged: checked => {
            CortetsuConfig.dashboard.performance.showNetwork = checked;
            CortetsuConfig.dashboard.performance.showBattery = checked;
            root.page.savePreference();
        }
    }
}
