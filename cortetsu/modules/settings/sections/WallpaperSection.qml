pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../../../components"
import "../../../services"
import "../../../theme"
import "../.."
import "../../CortetsuTypography.js" as CortetsuTypography
import "../controls"

// The desktop behind the windows: the wallpaper as it is now, the way to
// change it, and the clock that sits on it.
ColumnLayout {
    id: root

    required property var context

    readonly property string status: CortetsuWallpapers.applyStatus
    readonly property var positions: [
        {id: "top-left", name: qsTr("Arriba izquierda")},
        {id: "top-center", name: qsTr("Arriba centro")},
        {id: "top-right", name: qsTr("Arriba derecha")},
        {id: "middle-left", name: qsTr("Centro izquierda")},
        {id: "middle-center", name: qsTr("Centro")},
        {id: "middle-right", name: qsTr("Centro derecha")},
        {id: "bottom-left", name: qsTr("Abajo izquierda")},
        {id: "bottom-center", name: qsTr("Abajo centro")},
        {id: "bottom-right", name: qsTr("Abajo derecha")}
    ]

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

                CortetsuIcon {
                    anchors.centerIn: parent
                    visible: preview.status !== Image.Ready
                    text: CortetsuWallpapers.actualCurrent ? "wallpaper" : "hide_image"
                    iconSize: CortetsuTypography.iconLargePx
                    color: CortetsuDesign.colorOnSurfaceVariant
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

    SettingsGroup {
        title: qsTr("Reloj del escritorio")
        icon: "schedule"

        SettingToggleRow {
            objectName: "desktopClockEnabled"
            title: qsTr("Reloj del escritorio")
            detail: qsTr("Un reloj sobre el fondo, detrás de las ventanas")
            checked: CortetsuConfig.desktopClockEnabled
            onToggled: value => { CortetsuConfig.desktopClockEnabled = value; CortetsuConfig.save(); }
        }

        SettingToggleRow {
            objectName: "clockShowDate"
            title: qsTr("Mostrar fecha")
            detail: qsTr("Muestra el mes, día y nombre del día junto a la hora")
            checked: CortetsuConfig.desktopClockShowDate
            onToggled: value => { CortetsuConfig.desktopClockShowDate = value; CortetsuConfig.save(); }
        }

        // A small screen: each cell is a place the clock can sit.
        RowLayout {
            readonly property string title: qsTr("Posición del reloj")
            Layout.fillWidth: true
            Layout.margins: CortetsuDesign.spacingStandard
            spacing: CortetsuDesign.spacingComfortable

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                CortetsuText {
                    text: qsTr("Posición del reloj")
                    textSize: CortetsuTypography.bodyLargePx
                }

                CortetsuText {
                    Layout.fillWidth: true
                    text: root.positions.find(item => item.id === CortetsuConfig.desktopClockPosition)?.name ?? ""
                    textSize: CortetsuTypography.bodySmallPx
                    color: CortetsuDesign.colorOnSurfaceVariant
                }
            }

            Rectangle {
                implicitWidth: 192
                implicitHeight: 112
                radius: CortetsuDesign.radiusMedium
                color: Qt.alpha(CortetsuDesign.colorSurfaceHigh, 0.9)
                border.width: 1
                border.color: Qt.alpha(CortetsuDesign.colorOutlineVariant, 0.7)

                Grid {
                    anchors.fill: parent
                    anchors.margins: 6
                    columns: 3
                    spacing: 4

                    Repeater {
                        id: cells
                        model: root.positions

                        Item {
                            id: cell
                            required property var modelData
                            required property int index
                            readonly property bool selected: CortetsuConfig.desktopClockPosition === modelData.id

                            function request(): void {
                                CortetsuConfig.desktopClockPosition = modelData.id;
                                CortetsuConfig.save();
                            }

                            objectName: "clock-" + modelData.id
                            width: (parent.width - 8) / 3
                            height: (parent.height - 8) / 3
                            activeFocusOnTab: selected || activeFocus
                            Accessible.role: Accessible.RadioButton
                            Accessible.name: modelData.name
                            Accessible.checked: selected
                            Accessible.onPressAction: request()
                            Keys.onSpacePressed: request()
                            Keys.onReturnPressed: request()
                            Keys.onLeftPressed: cells.itemAt(Math.max(0, index - 1)).forceActiveFocus()
                            Keys.onRightPressed: cells.itemAt(Math.min(8, index + 1)).forceActiveFocus()
                            Keys.onUpPressed: cells.itemAt(Math.max(0, index - 3)).forceActiveFocus()
                            Keys.onDownPressed: cells.itemAt(Math.min(8, index + 3)).forceActiveFocus()

                            CortetsuSurface {
                                anchors.fill: parent
                                radiusValue: CortetsuDesign.radiusSmall
                                active: cell.selected
                                focused: cell.activeFocus
                                hovered: cellMouse.containsMouse
                                baseColor: "transparent"
                                hoverColor: Qt.alpha(CortetsuDesign.colorOnSurface, 0.08)
                                activeColor: CortetsuDesign.colorPrimaryContainer
                                outlined: cell.selected || cell.activeFocus
                            }

                            CortetsuText {
                                anchors.centerIn: parent
                                visible: cell.selected
                                text: "12:30"
                                textSize: CortetsuTypography.labelSmallPx
                                font.weight: Font.DemiBold
                                color: CortetsuDesign.colorOnPrimaryContainer
                            }

                            MouseArea {
                                id: cellMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: { cell.forceActiveFocus(); cell.request(); }
                            }

                            CortetsuTooltip {
                                target: cell
                                hovered: cellMouse.containsMouse
                                text: cell.modelData.name
                            }
                        }
                    }
                }
            }
        }
    }
}
