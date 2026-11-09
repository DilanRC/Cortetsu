pragma ComponentBehavior: Bound

import QtQuick
import "../../../components"
import "../.."
import "../../../theme"
import "../../CortetsuTypography.js" as CortetsuTypography
import "../../../services/DisplayLayout.js" as Arrange

// The outputs drawn to scale. Click selects; dragging moves an output and it
// snaps to the others' edges. Left and Right change the selection.
Item {
    id: root

    required property var model

    readonly property var outputs: model.candidateOutputs
    readonly property var area: Arrange.bounds(outputs)
    readonly property real padding: CortetsuDesign.spacingSection * 2
    readonly property real factor: Math.min((width - padding * 2) / area.width, (height - padding * 2) / area.height)
    // Centre the drawing: the arrangement rarely has the canvas's shape.
    readonly property real originX: (width - area.width * factor) / 2
    readonly property real originY: (height - area.height * factor) / 2

    implicitHeight: 240
    activeFocusOnTab: outputs.length > 0
    Accessible.role: Accessible.List
    Accessible.name: qsTr("Disposición de pantallas")

    Keys.onLeftPressed: model.selectedIndex = Math.max(0, model.selectedIndex - 1)
    Keys.onRightPressed: model.selectedIndex = Math.min(outputs.length - 1, model.selectedIndex + 1)

    CortetsuSurface {
        anchors.fill: parent
        // A plain well inside the group; the outline only marks keyboard focus.
        baseColor: Qt.alpha(CortetsuDesign.colorSurfaceGlass, 0.46)
        outlineColor: Qt.alpha(CortetsuDesign.colorWashi, 0.82)
        outlined: root.activeFocus
        radiusValue: CortetsuDesign.radiusMedium
    }

    Repeater {
        model: root.outputs

        delegate: Item {
            id: screen
            required property var modelData
            required property int index
            readonly property var size: Arrange.logicalSize(modelData)
            readonly property bool selected: root.model.selectedIndex === index
            readonly property real homeX: root.originX + (Number(modelData.x ?? 0) - root.area.minX) * root.factor
            readonly property real homeY: root.originY + (Number(modelData.y ?? 0) - root.area.minY) * root.factor

            objectName: "displayCanvas-" + modelData.name
            visible: modelData.enabled ?? true
            // Dragging writes x and y; releasing hands them back to the model.
            x: homeX
            y: homeY
            width: Math.max(56, size.width * root.factor - 3)
            height: Math.max(36, size.height * root.factor - 3)
            z: selected ? 2 : 1
            Accessible.role: Accessible.ListItem
            Accessible.name: `${modelData.name}, ${size.width} × ${size.height}`
            Accessible.selected: selected

            CortetsuSurface {
                anchors.fill: parent
                baseColor: screen.selected ? Qt.alpha(CortetsuDesign.colorPrimaryContainer, 0.92)
                    : Qt.alpha(CortetsuDesign.colorSurfaceGlassStrong, 0.96)
                outlineColor: screen.selected ? CortetsuDesign.colorPrimary : Qt.alpha(CortetsuDesign.colorOutline, 0.6)
                outlined: true
                radiusValue: CortetsuDesign.radiusSmall
                hovered: mouse.containsMouse
            }

            Column {
                anchors.centerIn: parent
                width: parent.width - CortetsuDesign.spacingCompact * 2
                spacing: 2

                CortetsuText {
                    width: parent.width
                    text: String(screen.index + 1)
                    textSize: CortetsuTypography.titleLargePx
                    font.weight: Font.DemiBold
                    horizontalAlignment: Text.AlignHCenter
                    color: screen.selected ? CortetsuDesign.colorOnPrimaryContainer : CortetsuDesign.colorOnSurface
                }
                CortetsuText {
                    width: parent.width
                    visible: screen.height > 70
                    text: screen.modelData.name
                    textSize: CortetsuTypography.labelSmallPx
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    color: screen.selected ? CortetsuDesign.colorOnPrimaryContainer : CortetsuDesign.colorOnSurfaceVariant
                }
            }

            MouseArea {
                id: mouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: drag.active ? Qt.ClosedHandCursor : root.outputs.length > 1 ? Qt.OpenHandCursor : Qt.PointingHandCursor
                drag.target: root.outputs.length > 1 ? screen : null
                drag.threshold: 6
                onPressed: {
                    root.forceActiveFocus();
                    root.model.selectedIndex = screen.index;
                }
                onReleased: {
                    if (!drag.active)
                        return;
                    const x = (screen.x - root.originX) / root.factor + root.area.minX;
                    const y = (screen.y - root.originY) / root.factor + root.area.minY;
                    screen.x = Qt.binding(() => screen.homeX);
                    screen.y = Qt.binding(() => screen.homeY);
                    root.model.move(screen.index, x, y);
                }
            }
        }
    }

    CortetsuStateMessage {
        anchors.centerIn: parent
        width: Math.min(parent.width - CortetsuDesign.spacingSection * 2, 360)
        visible: root.outputs.length === 0
        kind: root.model.probeState === "running" ? "loading" : root.model.probeState === "error" ? "error" : "empty"
        icon: kind === "loading" ? "sync" : "monitor"
        title: kind === "loading" ? qsTr("Leyendo pantallas") : qsTr("No hay pantallas que mostrar")
        detail: root.model.message
    }
}
