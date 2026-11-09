pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../../../components"
import "../../../services"
import "../../../theme"
import "../.."
import ".."
import "../../CortetsuTypography.js" as CortetsuTypography
import "../controls"

// Where Settings opens: the desktop as it looks now, how the main domains
// stand, the switches people reach for most, and the pages they visit most.
// Everything here is a shortcut; each setting still lives on its own page.
SettingsPage {
    id: root

    required property var context
    required property var controller

    readonly property var tiles: [
        { page: "wifi", icon: "wifi", title: qsTr("Red"), value: context.summary.network, alert: context.alert.network },
        { page: "bluetooth", icon: "bluetooth", title: qsTr("Bluetooth"), value: context.summary.bluetooth, alert: context.alert.bluetooth },
        { page: "sound", icon: "volume_up", title: qsTr("Sonido"), value: context.summary.audio, alert: context.alert.audio },
        { page: "power", icon: "battery_horiz_075", title: qsTr("Energía"), value: context.summary.power, alert: context.alert.power }
    ]

    kind: "wide"

    // The desktop as it is: wallpaper, theme and palette, with the way to
    // change each one.
    CortetsuSurface {
        objectName: "homeHero"
        Layout.fillWidth: true
        implicitHeight: heroRow.implicitHeight + CortetsuDesign.spacingSpacious * 2
        radiusValue: CortetsuDesign.radiusLarge
        baseColor: Qt.alpha(CortetsuDesign.colorSurfaceGlass, 0.75)

        GridLayout {
            id: heroRow
            anchors.fill: parent
            anchors.margins: CortetsuDesign.spacingSpacious
            columns: width >= 620 ? 2 : 1
            columnSpacing: CortetsuDesign.spacingSpacious
            rowSpacing: CortetsuDesign.spacingStandard

            Item {
                Layout.preferredWidth: 280
                Layout.preferredHeight: 158

                // Shown until the picture decodes, or when there is none.
                Rectangle {
                    anchors.fill: parent
                    radius: CortetsuDesign.radiusMedium
                    visible: wallpaper.status !== Image.Ready
                    gradient: Gradient {
                        GradientStop { position: 0; color: CortetsuDesign.colorPrimaryContainer }
                        GradientStop { position: 1; color: CortetsuDesign.colorSurfaceHigh }
                    }

                    CortetsuIcon {
                        anchors.centerIn: parent
                        text: "wallpaper"
                        iconSize: CortetsuTypography.iconLargePx
                        color: CortetsuDesign.colorOnPrimaryContainer
                    }
                }

                CortetsuRoundedImage {
                    id: wallpaper
                    objectName: "homeWallpaper"
                    anchors.fill: parent
                    radius: CortetsuDesign.radiusMedium
                    source: CortetsuWallpapers.actualCurrent ? `file://${CortetsuWallpapers.actualCurrent}` : ""
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: CortetsuDesign.spacingCompact

                CortetsuText {
                    text: root.context.hostName || qsTr("Este equipo")
                    textSize: CortetsuTypography.displaySmallPx
                    font.family: CortetsuDesign.fontHeading
                    font.weight: CortetsuDesign.headingWeight
                }

                CortetsuText {
                    Layout.fillWidth: true
                    text: qsTr("Tema %1 · esquema %2").arg(root.context.summary.theme).arg(root.context.summary.appearance || qsTr("del tema"))
                    textSize: CortetsuTypography.bodyLargePx
                    color: CortetsuDesign.colorOnSurfaceVariant
                    elide: Text.ElideRight
                }

                CortetsuText {
                    Layout.fillWidth: true
                    text: root.context.wallpaperName || qsTr("Sin fondo")
                    textSize: CortetsuTypography.bodySmallPx
                    color: CortetsuDesign.colorOnSurfaceVariant
                    elide: Text.ElideMiddle
                }

                Flow {
                    Layout.fillWidth: true
                    Layout.topMargin: CortetsuDesign.spacingCompact
                    spacing: CortetsuDesign.spacingCompact

                    CortetsuButton {
                        objectName: "homeThemes"
                        icon: "style"
                        label: qsTr("Temas")
                        active: true
                        onClicked: root.controller.select("themes")
                    }
                    CortetsuButton {
                        objectName: "homeBackground"
                        icon: "wallpaper"
                        label: qsTr("Fondo")
                        onClicked: root.controller.select("background")
                    }
                    CortetsuButton {
                        objectName: "homeColors"
                        icon: "format_paint"
                        label: qsTr("Colores")
                        onClicked: root.controller.select("colors")
                    }
                }
            }
        }
    }

    // The main domains at a glance; each tile opens its page.
    GridLayout {
        Layout.fillWidth: true
        columns: width >= 880 ? 4 : 2
        columnSpacing: CortetsuDesign.spacingStandard
        rowSpacing: CortetsuDesign.spacingStandard

        Repeater {
            model: root.tiles

            Item {
                id: tile
                required property var modelData
                objectName: `homeTile-${modelData.page}`
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                implicitHeight: 96
                activeFocusOnTab: true
                Accessible.role: Accessible.Link
                Accessible.name: `${modelData.title}: ${modelData.alert || modelData.value}`
                Accessible.onPressAction: root.controller.select(modelData.page)
                Keys.onReturnPressed: root.controller.select(modelData.page)
                Keys.onEnterPressed: root.controller.select(modelData.page)
                Keys.onSpacePressed: root.controller.select(modelData.page)

                CortetsuSurface {
                    anchors.fill: parent
                    radiusValue: CortetsuDesign.radiusLarge
                    focused: tile.activeFocus
                    hovered: tileMouse.containsMouse
                    pressed: tileMouse.pressed
                    baseColor: Qt.alpha(CortetsuDesign.colorSurfaceGlass, 0.72)
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: CortetsuDesign.spacingComfortable
                    spacing: 2

                    RowLayout {
                        Layout.fillWidth: true

                        CortetsuIcon {
                            text: tile.modelData.icon
                            iconSize: CortetsuTypography.iconMediumPx
                            color: tile.modelData.alert ? CortetsuDesign.colorVermillion : CortetsuDesign.colorPrimary
                        }
                        Item { Layout.fillWidth: true }
                        CortetsuIcon {
                            text: "chevron_right"
                            iconSize: CortetsuTypography.iconSmallPx
                            color: CortetsuDesign.colorOnSurfaceVariant
                        }
                    }

                    Item { Layout.fillHeight: true }

                    CortetsuText {
                        Layout.fillWidth: true
                        text: tile.modelData.title
                        textSize: CortetsuTypography.bodyLargePx
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }

                    CortetsuText {
                        Layout.fillWidth: true
                        text: tile.modelData.alert || tile.modelData.value
                        textSize: CortetsuTypography.bodySmallPx
                        color: tile.modelData.alert ? CortetsuDesign.colorVermillion : CortetsuDesign.colorOnSurfaceVariant
                        elide: Text.ElideRight
                    }
                }

                MouseArea {
                    id: tileMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.controller.select(tile.modelData.page)
                }
            }
        }
    }

    SettingsColumns {
        SettingsGroup {
            title: qsTr("Ajustes frecuentes")
            icon: "bolt"

            SettingToggleRow {
                objectName: "homeDnd"
                title: qsTr("No molestar")
                detail: qsTr("Los avisos esperan en el panel sin aparecer")
                checked: CortetsuNotifications.dnd
                onToggled: value => CortetsuNotifications.setDnd(value)
            }

            SettingToggleRow {
                objectName: "homeTransparency"
                title: qsTr("Superficies transparentes")
                checked: CortetsuConfig.transparencyEnabled
                onToggled: value => { CortetsuConfig.transparencyEnabled = value; CortetsuConfig.save(); }
            }

            SettingToggleRow {
                objectName: "homeReducedMotion"
                title: qsTr("Reducir movimiento")
                checked: CortetsuConfig.reducedMotion
                onToggled: value => { CortetsuConfig.reducedMotion = value; CortetsuConfig.save(); }
            }
        }

        aside: SettingsGroup {
            title: qsTr("Páginas habituales")
            icon: "star"

            Repeater {
                model: ["themes", "bottomhub", "display", "shortcuts"]

                SettingNavRow {
                    required property string modelData
                    readonly property var target: root.controller.pages[modelData]
                    objectName: `homeLink-${modelData}`
                    title: target.title
                    detail: target.detail
                    icon: target.icon
                    onActivated: root.controller.select(modelData)
                }
            }
        }
    }
}
