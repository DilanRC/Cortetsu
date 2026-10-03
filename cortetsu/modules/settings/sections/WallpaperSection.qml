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
        title: qsTr("Fondo de pantalla")
        detail: qsTr("Fuente actual del fondo de pantalla")
    }

    DomainHero {
        icon: CortetsuWallpapers.applyStatus === "failed" ? "error" : "wallpaper"
        title: CortetsuWallpapers.applyStatus === "applying"
            ? qsTr("Aplicando fondo")
            : CortetsuWallpapers.applyStatus === "failed"
                ? qsTr("No se pudo aplicar")
                : qsTr("Fondo activo")
        detail: CortetsuConfig.wallpaperEnabled
            ? qsTr("Cortetsu controla la superficie del escritorio")
            : qsTr("La integración automática está desactivada")
        value: CortetsuWallpapers.actualCurrent.split("/").pop() || qsTr("Sin fondo")
        meta: CortetsuWallpapers.actualCurrent.length > 0
            ? CortetsuWallpapers.actualCurrent
            : qsTr("Abre el gestor para elegir una imagen")
        warningState: CortetsuWallpapers.applyStatus === "failed"
    }

    StatusCard {
        title: qsTr("Fondo de pantalla")
        value: CortetsuWallpapers.applyStatus === "applying"
            ? qsTr("Aplicando…")
            : CortetsuWallpapers.applyStatus === "failed"
                ? qsTr("Error al aplicar")
                : CortetsuWallpapers.applyStatus === "applied"
                    ? qsTr("Aplicado")
                    : CortetsuWallpapers.actualCurrent.split("/").pop()
        detail: CortetsuWallpapers.applyStatus === "applying" || CortetsuWallpapers.applyStatus === "failed"
            ? CortetsuWallpapers.applyStatusPath.split("/").pop()
            : CortetsuWallpapers.actualCurrent
        icon: CortetsuWallpapers.applyStatus === "applying"
            ? "sync"
            : CortetsuWallpapers.applyStatus === "failed"
                ? "error"
                : "wallpaper"
        activeState: CortetsuConfig.wallpaperEnabled
            && (CortetsuWallpapers.applyStatus === "applying" || CortetsuWallpapers.applyStatus === "applied")
        warningState: CortetsuWallpapers.applyStatus === "failed"
    }

    PreferenceToggle {
        title: qsTr("Integración del fondo")
        detail: qsTr("Permitir que Cortetsu controle el fondo del escritorio")
        icon: "wallpaper"
        checked: CortetsuConfig.wallpaperEnabled
        onChanged: checked => {
            CortetsuConfig.wallpaperEnabled = checked;
            root.page.savePreference();
        }
    }

    ActionCard {
        title: qsTr("Abrir gestor de fondos")
        detail: qsTr("Explorar el selector orbital y previsualizar un fondo")
        icon: "collections"
        onActivated: root.page.openRetained("wallpaperManager")
    }
}
