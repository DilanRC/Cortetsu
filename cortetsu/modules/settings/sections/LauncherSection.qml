pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../../../components"
import "../.."
import "../../../theme"
import "../../CortetsuTypography.js" as CortetsuTypography

ColumnLayout {
    id: root

    required property var page

    spacing: CortetsuDesign.spacingStandard

    CortetsuSectionHeader {
        Layout.fillWidth: true
        title: qsTr("Búsqueda del lanzador")
        detail: qsTr("Ajustar cómo Cortetsu encuentra aplicaciones y acciones")
    }

    DomainHero {
        icon: "search"
        title: CortetsuConfig.launcher.enabled ? qsTr("Lanzador disponible") : qsTr("Lanzador desactivado")
        detail: qsTr("Aplicaciones, acciones, fondos y esquemas")
        value: qsTr("%1 modos").arg(root.page.enabledSearchModes)
        meta: qsTr("%1 resultados visibles").arg(CortetsuConfig.launcher.maxShown)
        warningState: !CortetsuConfig.launcher.enabled
    }

    PreferenceToggle {
        title: qsTr("Lanzador habilitado")
        detail: qsTr("Permitir que Cortetsu abra el buscador con SUPER")
        icon: "search"
        checked: CortetsuConfig.launcher.enabled
        onChanged: checked => { CortetsuConfig.launcher.enabled = checked; root.page.savePreference(); }
    }

    PreferenceToggle {
        title: qsTr("Búsqueda aproximada de aplicaciones")
        detail: qsTr("Encontrar nombres de aplicaciones parecidos")
        icon: "search"
        checked: CortetsuConfig.useFuzzyApps
        onChanged: checked => {
            CortetsuConfig.useFuzzyApps = checked;
            root.page.savePreference();
        }
    }

    PreferenceToggle {
        title: qsTr("Acciones aproximadas")
        detail: qsTr("Usar coincidencias aproximadas para las acciones")
        icon: "bolt"
        checked: CortetsuConfig.useFuzzyActions
        onChanged: checked => {
            CortetsuConfig.useFuzzyActions = checked;
            root.page.savePreference();
        }
    }

    PreferenceToggle {
        title: qsTr("Abrir el lanzador al pasar el puntero")
        detail: qsTr("Mostrar el lanzador al acercarte al borde inferior")
        icon: "search"
        checked: CortetsuConfig.launcher.showOnHover
        onChanged: checked => {
            CortetsuConfig.launcher.showOnHover = checked;
            root.page.savePreference();
        }
    }

    PreferenceToggle {
        title: qsTr("Búsqueda aproximada de fondos")
        detail: qsTr("Encontrar fondos aunque el nombre no coincida exactamente")
        icon: "wallpaper"
        checked: CortetsuConfig.useFuzzyWallpapers
        onChanged: checked => {
            CortetsuConfig.useFuzzyWallpapers = checked;
            root.page.savePreference();
        }
    }

    PreferenceToggle {
        title: qsTr("Búsqueda aproximada de esquemas")
        detail: qsTr("Encontrar esquemas por nombre y variante")
        icon: "palette"
        checked: CortetsuConfig.useFuzzySchemes
        onChanged: checked => {
            CortetsuConfig.useFuzzySchemes = checked;
            root.page.savePreference();
        }
    }

    CortetsuSectionHeader {
        Layout.fillWidth: true
        title: qsTr("Densidad de resultados")
        detail: qsTr("Controlar cuántas opciones muestra cada búsqueda")
    }

    CortetsuSurface {
        Layout.fillWidth: true
        implicitHeight: 94
        radiusValue: CortetsuDesign.radiusMedium
        baseColor: Qt.alpha(CortetsuDesign.colorSurfaceGlass, 0.72)
        outlined: true

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: CortetsuDesign.spacingStandard
            spacing: CortetsuDesign.spacingCompact

            RowLayout {
                Layout.fillWidth: true
                CortetsuText { Layout.fillWidth: true; text: qsTr("Aplicaciones y acciones"); textSize: CortetsuTypography.bodyPx; font.weight: Font.DemiBold }
                CortetsuText { text: qsTr("%1").arg(CortetsuConfig.launcher.maxShown); textSize: CortetsuTypography.labelSmallPx; color: CortetsuDesign.colorOnSurfaceVariant }
            }
            CortetsuSlider {
                Layout.fillWidth: true
                from: 4
                to: 16
                step: 1
                value: CortetsuConfig.launcher.maxShown
                disabled: !CortetsuConfig.launcher.enabled
                onMoved: nextValue => { CortetsuConfig.launcher.maxShown = Math.round(nextValue); root.page.savePreference(); }
            }
        }
    }

    CortetsuSurface {
        Layout.fillWidth: true
        implicitHeight: 94
        radiusValue: CortetsuDesign.radiusMedium
        baseColor: Qt.alpha(CortetsuDesign.colorSurfaceGlass, 0.72)
        outlined: true

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: CortetsuDesign.spacingStandard
            spacing: CortetsuDesign.spacingCompact

            RowLayout {
                Layout.fillWidth: true
                CortetsuText { Layout.fillWidth: true; text: qsTr("Fondos y esquemas"); textSize: CortetsuTypography.bodyPx; font.weight: Font.DemiBold }
                CortetsuText { text: qsTr("%1").arg(CortetsuConfig.launcher.maxWallpapers); textSize: CortetsuTypography.labelSmallPx; color: CortetsuDesign.colorOnSurfaceVariant }
            }
            CortetsuSlider {
                Layout.fillWidth: true
                from: 4
                to: 16
                step: 1
                value: CortetsuConfig.launcher.maxWallpapers
                disabled: !CortetsuConfig.launcher.enabled
                onMoved: nextValue => { CortetsuConfig.launcher.maxWallpapers = Math.round(nextValue); root.page.savePreference(); }
            }
        }
    }

    ActionCard {
        title: qsTr("Abrir lanzador")
        detail: qsTr("Probar la búsqueda con la configuración actual")
        icon: "search"
        onActivated: root.page.openRetained("launcher")
    }

}
