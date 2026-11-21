pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../components"
import "../../theme"
import "../CortetsuTypography.js" as CortetsuTypography
import "services"

// The favourites row of the expanded launcher's home (03-launcher): a tile
// per pinned app, icon over name. Pinning stays where it was (right click
// on an app); "Gestionar" shows the whole favourites view.
ColumnLayout {
    id: root

    required property var apps
    property int maxTiles: 7
    signal launched(var entry)
    signal manageRequested()

    spacing: CortetsuDesign.spacingCompact

    RowLayout {
        Layout.fillWidth: true
        CortetsuIcon {
            text: "star"
            iconSize: CortetsuTypography.iconSmallPx
            color: CortetsuDesign.colorPrimary
        }
        CortetsuText {
            Layout.fillWidth: true
            text: qsTr("Favoritos")
            textSize: CortetsuTypography.bodyPx
            font.weight: Font.DemiBold
        }
        CortetsuButton {
            compact: true
            pill: true
            activeFocusOnTab: false
            visible: root.apps.length > root.maxTiles
            label: qsTr("Ver todos · %1").arg(root.apps.length)
            onClicked: root.manageRequested()
        }
    }

    Row {
        Layout.fillWidth: true
        spacing: CortetsuDesign.spacingCompact

        Repeater {
            model: root.apps.slice(0, root.maxTiles)
            delegate: Item {
                id: tile
                required property var modelData
                width: 92
                height: 88
                Accessible.role: Accessible.Button
                Accessible.name: qsTr("Abrir %1").arg(tile.modelData?.name ?? "")
                Accessible.onPressAction: root.launched(tile.modelData)

                CortetsuSurface {
                    anchors.fill: parent
                    radiusValue: CortetsuDesign.radiusLarge
                    baseColor: Qt.alpha(CortetsuDesign.colorSurfaceGlass, 0.55)
                    outlineColor: Qt.alpha(CortetsuDesign.colorOutlineVariant, 0.22)
                    hovered: mouse.containsMouse
                    pressed: mouse.pressed
                }
                Image {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 12
                    width: 38
                    height: 38
                    sourceSize.width: 76
                    sourceSize.height: 76
                    asynchronous: true
                    source: Quickshell.iconPath(tile.modelData?.icon, "application-x-executable")
                }
                CortetsuText {
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 10
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: parent.width - 10
                    horizontalAlignment: Text.AlignHCenter
                    text: tile.modelData?.name ?? ""
                    textSize: CortetsuTypography.labelSmallPx
                    elide: Text.ElideRight
                }
                MouseArea {
                    id: mouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.launched(tile.modelData)
                }
            }
        }
    }
}
