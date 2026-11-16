pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../../../components"
import "../../../services"
import "../../../theme"
import "../.."
import "../../CortetsuTypography.js" as CortetsuTypography
import ".."
import "../controls"

// The desktop behind the windows: the wallpaper as it is now, the way to
// change it, and a link to the widgets that sit on it.
ColumnLayout {
    id: root

    required property var context

    readonly property string status: CortetsuWallpapers.applyStatus

    spacing: CortetsuDesign.spacingSection

    SettingsGroup {
        title: qsTr("Fondo actual")
        icon: "wallpaper"

        // The picture itself, at the screen's proportions, beside what it is
        // and what can be done with it.
        GridLayout {
            Layout.fillWidth: true
            Layout.margins: CortetsuDesign.spacingStandard
            columns: width >= 560 ? 2 : 1
            columnSpacing: CortetsuDesign.spacingComfortable
            rowSpacing: CortetsuDesign.spacingStandard

            Item {
                Layout.preferredWidth: Math.min(320, parent.width)
                Layout.preferredHeight: Layout.preferredWidth * 9 / 16

                Rectangle {
                    anchors.fill: parent
                    radius: CortetsuDesign.radiusMedium
                    color: CortetsuDesign.colorSurfaceHigh
                }

                CortetsuRoundedImage {
                    id: preview
                    objectName: "wallpaperPreview"
                    anchors.fill: parent
                    radius: CortetsuDesign.radiusMedium
                    source: CortetsuWallpapers.actualCurrent ? `file://${CortetsuWallpapers.actualCurrent}` : ""
                }

                // Loading, missing or unreadable: say which instead of a bare icon.
                Column {
                    objectName: "wallpaperPreviewFallback"
                    anchors.centerIn: parent
                    width: parent.width - CortetsuDesign.spacingSection * 2
                    visible: preview.status !== Image.Ready
                    spacing: CortetsuDesign.spacingUnit

                    CortetsuIcon {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: !CortetsuWallpapers.actualCurrent ? "hide_image"
                            : preview.status === Image.Loading ? "wallpaper" : "broken_image"
                        iconSize: CortetsuTypography.iconLargePx
                        color: CortetsuDesign.colorOnSurfaceVariant
                    }
                    CortetsuText {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        text: !CortetsuWallpapers.actualCurrent ? qsTr("Sin fondo de Cortetsu")
                            : preview.status === Image.Loading ? qsTr("Cargando vista previa…")
                            : qsTr("No se puede abrir la imagen")
                        textSize: CortetsuTypography.labelSmallPx
                        color: CortetsuDesign.colorOnSurfaceVariant
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                spacing: CortetsuDesign.spacingCompact

                SettingValueRow {
                    objectName: "wallpaperFile"
                    Layout.leftMargin: -CortetsuDesign.spacingStandard
                    Layout.rightMargin: -CortetsuDesign.spacingStandard
                    title: root.status === "applying"
                        ? qsTr("Aplicando")
                        : root.status === "failed" ? qsTr("No se pudo aplicar") : qsTr("Imagen")
                    detail: root.status === "failed"
                        ? (CortetsuWallpapers.applyError || CortetsuWallpapers.applyStatusPath.split("/").pop())
                        : CortetsuWallpapers.actualCurrent
                    status: root.status === "failed" ? "error" : ""
                    statusText: CortetsuWallpapers.applyError || qsTr("El fondo anterior sigue puesto")
                    value: root.status === "applying"
                        ? CortetsuWallpapers.applyStatusPath.split("/").pop()
                        : root.context.wallpaperName.length > 0 ? root.context.wallpaperName : qsTr("Sin fondo")
                    attention: root.status === "failed"
                }

                Flow {
                    Layout.fillWidth: true
                    spacing: CortetsuDesign.spacingCompact

                    CortetsuButton {
                        objectName: "openWallpaperManager"
                        icon: "collections"
                        label: qsTr("Elegir otro fondo")
                        active: true
                        onClicked: root.context.openSurface("wallpaperManager")
                    }

                    CortetsuButton {
                        objectName: "randomWallpaper"
                        icon: "shuffle"
                        label: qsTr("Aleatorio")
                        disabled: root.status === "applying"
                        onClicked: CortetsuWallpapers.applyRandom()
                    }
                }
            }
        }

        SettingToggleRow {
            title: qsTr("Cortetsu pone el fondo")
            detail: qsTr("Si se apaga, el escritorio queda sin fondo de Cortetsu")
            checked: CortetsuConfig.wallpaperEnabled
            onToggled: value => { CortetsuConfig.wallpaperEnabled = value; CortetsuConfig.save(); }
        }
    }

    // The 2.x desktop clock is now a widget among others.
    SettingsGroup {
        title: qsTr("Sobre el fondo")
        icon: "widgets"

        SettingNavRow {
            objectName: "desktopWidgetsLink"
            title: qsTr("Widgets del escritorio")
            detail: qsTr("Reloj, calendario, clima, sistema, notas y más, por monitor")
            icon: "widgets"
            value: DesktopWidgets.items.length === 0 ? qsTr("Ninguno")
                : DesktopWidgets.items.length === 1 ? qsTr("1 widget") : qsTr("%1 widgets").arg(DesktopWidgets.items.length)
            onActivated: SettingsController.select("widgets")
        }
    }
}
