pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../../../components"
import "../../../theme"
import "../.."
import "../../CortetsuTypography.js" as CortetsuTypography
import "../controls"

// The Premium sobria library, live, in the theme that is active: every
// shared primitive in its states (rest, active, danger, disabled, busy),
// so a theme, a token change or a QA pass is judged on the real controls
// and not on a mockup. Interactive pieces change only local state here.
ColumnLayout {
    id: root

    property bool sampleToggle: true
    property real sampleLevel: 0.62
    property int sampleTab: 0

    spacing: CortetsuDesign.spacingSection

    SettingsGroup {
        title: qsTr("Protagonista y datos")
        detail: qsTr("Un CortetsuHero por vista; CortetsuFact para pares etiqueta y valor")
        icon: "star"
        panel: false

        CortetsuHero {
            Layout.fillWidth: true
            ColumnLayout {
                spacing: CortetsuDesign.spacingUnit
                CortetsuText {
                    text: qsTr("Todo en orden")
                    textSize: CortetsuTypography.titleLargePx
                    font.family: CortetsuDesign.fontHeading
                }
                CortetsuText {
                    text: qsTr("El bloque protagonista lleva el único lavado de acento de la vista")
                    color: CortetsuDesign.colorOnSurfaceVariant
                }
                RowLayout {
                    spacing: CortetsuDesign.spacingSection
                    CortetsuFact { icon: "thermostat"; label: qsTr("CPU"); value: "57 °C" }
                    CortetsuFact { icon: "memory"; label: qsTr("Memoria"); value: "9.0 GiB" }
                    CortetsuFact { icon: "warning"; label: qsTr("Disco"); value: "93 %"; valueColor: CortetsuDesign.colorVermillion }
                }
            }
        }
    }

    SettingsGroup {
        title: qsTr("Botones")
        detail: qsTr("Reposo, activo, peligro, deshabilitado y solo icono (con su texto emergente)")
        icon: "smart_button"
        panel: false

        Flow {
            Layout.fillWidth: true
            spacing: CortetsuDesign.spacingCompact
            CortetsuButton { label: qsTr("Reposo"); icon: "touch_app" }
            CortetsuButton { label: qsTr("Activo"); icon: "check"; active: true }
            CortetsuButton { label: qsTr("Peligro"); icon: "delete"; danger: true }
            CortetsuButton { label: qsTr("Deshabilitado"); icon: "block"; disabled: true }
            CortetsuButton { label: qsTr("Compacto"); icon: "tune"; compact: true }
            CortetsuButton { label: ""; icon: "settings"; compact: true; tooltipText: qsTr("Solo icono") }
        }
    }

    SettingsGroup {
        title: qsTr("Filas")
        detail: qsTr("Abiertas: sin marco en reposo, una línea entre ellas")
        icon: "view_list"

        SettingToggleRow {
            title: qsTr("Interruptor")
            detail: root.sampleToggle ? qsTr("Activado") : qsTr("Desactivado")
            checked: root.sampleToggle
            onToggled: value => root.sampleToggle = value
        }
        SettingSliderRow {
            title: qsTr("Deslizador")
            valueText: qsTr("%1 %").arg(Math.round(root.sampleLevel * 100))
            value: root.sampleLevel
            onMoved: next => root.sampleLevel = next
        }
        SettingValueRow {
            title: qsTr("Valor")
            detail: qsTr("Un dato sin acción no reacciona al puntero")
            value: qsTr("No disponible")
        }
        SettingValueRow {
            title: qsTr("Valor que pide atención")
            value: qsTr("Disco al 93 %")
            attention: true
        }
        SettingActionRow {
            title: qsTr("Acción destructiva")
            detail: qsTr("La primera pulsación arma; la segunda confirma")
            actionLabel: qsTr("Olvidar")
            actionIcon: "delete"
            danger: true
            confirm: true
        }
        SettingToggleRow {
            title: qsTr("Fila ocupada")
            status: "busy"
            statusText: qsTr("Aplicando…")
            checked: true
        }
        SettingToggleRow {
            title: qsTr("Fila con error")
            status: "error"
            statusText: qsTr("El servicio rechazó el cambio")
            checked: false
        }
    }

    SettingsGroup {
        title: qsTr("Pestañas, mosaicos y progreso")
        icon: "tab"
        panel: false

        CortetsuTabBar {
            Layout.fillWidth: true
            accessibleName: qsTr("Ejemplo de pestañas")
            model: [{ label: qsTr("Ahorro"), icon: "energy_savings_leaf" }, { label: qsTr("Equilibrado"), icon: "balance" }, { label: qsTr("Rendimiento"), icon: "rocket_launch" }]
            currentIndex: root.sampleTab
            onSelected: index => root.sampleTab = index
        }

        GridLayout {
            Layout.fillWidth: true
            columns: 3
            columnSpacing: CortetsuDesign.spacingCompact
            rowSpacing: CortetsuDesign.spacingCompact
            CortetsuActionTile { Layout.fillWidth: true; compact: true; label: qsTr("Encendido"); detail: qsTr("Resaltado"); icon: "bolt"; highlighted: true }
            CortetsuActionTile { Layout.fillWidth: true; compact: true; label: qsTr("Apagado"); detail: qsTr("En reposo"); icon: "power_settings_new" }
            CortetsuActionTile { Layout.fillWidth: true; compact: true; label: qsTr("Aviso"); detail: qsTr("Necesita atención"); icon: "warning"; warning: true }
            CortetsuActionTile { Layout.fillWidth: true; compact: true; label: qsTr("Lectura"); detail: qsTr("Sin acción"); icon: "info"; clickable: false }
            CortetsuActionTile { Layout.fillWidth: true; compact: true; label: qsTr("Deshabilitado"); detail: qsTr("No disponible"); icon: "block"; disabled: true }
        }

        CortetsuProgressBar { Layout.fillWidth: true; value: root.sampleLevel }
        CortetsuProgressBar { Layout.fillWidth: true; value: 0.94; fillColor: CortetsuDesign.colorVermillion }
        CortetsuDivider { Layout.fillWidth: true }
    }

    SettingsGroup {
        title: qsTr("Estados de datos")
        detail: qsTr("Primera lectura, vacío y error, con CortetsuStateMessage")
        icon: "inbox"
        panel: false

        RowLayout {
            Layout.fillWidth: true
            spacing: CortetsuDesign.spacingStandard
            CortetsuStateMessage { Layout.fillWidth: true; Layout.preferredWidth: 1; kind: "loading"; title: qsTr("Leyendo"); detail: qsTr("Estructura sin ceros") }
            CortetsuStateMessage { Layout.fillWidth: true; Layout.preferredWidth: 1; kind: "empty"; title: qsTr("Vacío"); detail: qsTr("Qué falta y cómo conseguirlo") }
            CortetsuStateMessage { Layout.fillWidth: true; Layout.preferredWidth: 1; kind: "error"; title: qsTr("Error"); detail: qsTr("Qué falló") }
        }
    }
}
