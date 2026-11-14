pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../components"
import "../theme"
import "CortetsuTypography.js" as CortetsuTypography
import "HubAnchor.js" as HubAnchor

// The Hub's edit mode on one monitor (HubEditState). The eight places the
// Hub can take are drawn where it would really sit; the Hub itself is a
// shape that can be dragged, and while it moves the place it would snap to
// lights up. Dropped, it settles there. Clicking a place, or the arrows,
// choose too. Enter saves, Escape leaves everything as it was.
//
// Only loaded while editing. The real Hub does not move until the choice is
// saved, so windows are not pushed around while the pointer travels.
PanelWindow {
    id: root

    // What the real Hub measures, so the previews match it.
    required property real thickness
    required property real packedLength
    readonly property real endMargin: 8
    readonly property real edgeMargin: 2
    readonly property real edgeGap: 8

    function place(id: string): var {
        return HubAnchor.footprint(id, root.width, root.height, root.thickness, root.packedLength,
            root.endMargin, root.edgeGap, root.edgeMargin);
    }

    // The shape being dragged, in this window's coordinates (for the IPC).
    readonly property rect ghostRect: Qt.rect(ghost.x, ghost.y, ghost.width, ghost.height)

    color: "transparent"
    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "cortetsu-hub-edit"
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    Item {
        id: stage
        anchors.fill: parent
        focus: true

        Keys.onLeftPressed: HubEditState.target(HubAnchor.move(HubEditState.pending, -1, 0))
        Keys.onRightPressed: HubEditState.target(HubAnchor.move(HubEditState.pending, 1, 0))
        Keys.onUpPressed: HubEditState.target(HubAnchor.move(HubEditState.pending, 0, -1))
        Keys.onDownPressed: HubEditState.target(HubAnchor.move(HubEditState.pending, 0, 1))
        Keys.onReturnPressed: HubEditState.save()
        Keys.onEnterPressed: HubEditState.save()
        Keys.onEscapePressed: HubEditState.cancel()
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Home) {
                HubEditState.restoreDefault();
                event.accepted = true;
            }
        }

        Rectangle {
            anchors.fill: parent
            color: Qt.alpha(CortetsuDesign.colorSumi, 0.46)
        }

        // Each place is a short mark in the middle of where the Hub would
        // sit (the places overlap, so their outlines would tangle). Where the
        // Hub is now keeps a faint outline; while dragging, the place it
        // would snap to fills in.
        Repeater {
            model: HubAnchor.ids

            Item {
                id: slot

                required property string modelData
                readonly property var rect: root.place(modelData)
                readonly property bool chosen: HubEditState.pending === modelData
                readonly property bool current: HubEditState.original === modelData
                readonly property bool lateral: HubAnchor.describe(modelData).vertical

                objectName: `hubEditSlot-${modelData}`
                x: rect.x
                y: rect.y
                width: rect.width
                height: rect.height

                Rectangle {
                    anchors.fill: parent
                    visible: (slot.chosen && drag.active) || (slot.current && !slot.chosen)
                    radius: Math.min(width / 2, height / 2, CortetsuDesign.radiusSurface)
                    color: slot.chosen ? Qt.alpha(CortetsuDesign.colorIndigo, 0.26) : "transparent"
                    border.width: slot.chosen ? 2 : 1
                    border.color: slot.chosen ? Qt.alpha(CortetsuDesign.colorIndigo, 0.92) : Qt.alpha(CortetsuDesign.colorWashi, 0.42)

                    CortetsuText {
                        anchors.centerIn: parent
                        visible: slot.current && !slot.chosen
                        text: qsTr("Ahora")
                        textSize: CortetsuTypography.labelSmallPx
                        color: CortetsuDesign.colorWashi
                    }
                }

                Rectangle {
                    anchors.centerIn: parent
                    width: slot.lateral ? 6 : 72
                    height: slot.lateral ? 72 : 6
                    radius: Math.min(width, height) / 2
                    color: slot.chosen ? CortetsuDesign.colorIndigo
                        : markHover.hovered ? CortetsuDesign.colorWashi
                        : Qt.alpha(CortetsuDesign.colorWashi, 0.52)
                    Behavior on color { ColorAnimation { duration: CortetsuDesign.motionFastMs; easing.type: Easing.BezierSpline; easing.bezierCurve: CortetsuDesign.easeOut } }
                }

                // A target larger than the mark.
                Item {
                    anchors.centerIn: parent
                    width: slot.lateral ? Math.min(slot.width, 56) : 112
                    height: slot.lateral ? 112 : Math.min(slot.height, 56)
                    Accessible.role: Accessible.RadioButton
                    Accessible.name: HubAnchor.labels[slot.modelData]
                    Accessible.checked: slot.chosen

                    HoverHandler {
                        id: markHover
                        cursorShape: Qt.PointingHandCursor
                    }
                    TapHandler {
                        onTapped: HubEditState.target(slot.modelData)
                    }
                }
            }
        }

        // The Hub being moved. At rest it covers the place it will take;
        // dragged, it is a short bar in that place's orientation under the
        // pointer, and dropped it settles into the place that lit up.
        Rectangle {
            id: ghost

            readonly property var home: root.place(HubEditState.pending)
            readonly property bool lateral: HubAnchor.describe(HubEditState.pending).vertical
            readonly property point grab: drag.centroid.scenePosition
            readonly property real handle: Math.min(240, (lateral ? root.height : root.width) / 3)

            objectName: "hubEditGhost"
            x: drag.active ? grab.x - width / 2 : home.x
            y: drag.active ? grab.y - height / 2 : home.y
            width: drag.active ? (lateral ? root.thickness : handle) : home.width
            height: drag.active ? (lateral ? handle : root.thickness) : home.height
            radius: Math.min(width / 2, height / 2, CortetsuDesign.radiusSurface)
            color: Qt.alpha(CortetsuDesign.colorSumi, 0.9)
            border.width: 2
            border.color: Qt.alpha(CortetsuDesign.colorIndigo, drag.active ? 0.95 : 0.7)

            // design-lint: allow motion-layout-property: the dropped Hub settles into its place
            Behavior on x { enabled: !drag.active; NumberAnimation { duration: CortetsuDesign.motionStandardMs; easing.type: Easing.BezierSpline; easing.bezierCurve: CortetsuDesign.easeOut } }
            // design-lint: allow motion-layout-property: same settle on the other axis
            Behavior on y { enabled: !drag.active; NumberAnimation { duration: CortetsuDesign.motionStandardMs; easing.type: Easing.BezierSpline; easing.bezierCurve: CortetsuDesign.easeOut } }
            // design-lint: allow motion-layout-property: the bar takes the shape of the place it settles into
            Behavior on width { NumberAnimation { duration: CortetsuDesign.motionStandardMs; easing.type: Easing.BezierSpline; easing.bezierCurve: CortetsuDesign.easeOut } }
            // design-lint: allow motion-layout-property: same shape change on the other axis
            Behavior on height { NumberAnimation { duration: CortetsuDesign.motionStandardMs; easing.type: Easing.BezierSpline; easing.bezierCurve: CortetsuDesign.easeOut } }

            CortetsuEvolvingMark {
                anchors.left: ghost.lateral ? undefined : parent.left
                anchors.top: ghost.lateral ? parent.top : undefined
                anchors.horizontalCenter: ghost.lateral ? parent.horizontalCenter : undefined
                anchors.verticalCenter: ghost.lateral ? undefined : parent.verticalCenter
                anchors.margins: CortetsuDesign.spacingStandard
                width: Math.round(root.thickness * 0.5)
                height: width
                monochrome: true
                monochromeColor: CortetsuDesign.colorWashi
                animated: false
            }

            CortetsuIcon {
                anchors.centerIn: parent
                text: "open_with"
                color: CortetsuDesign.colorWashi
                iconSize: CortetsuTypography.iconMediumPx
            }

            HoverHandler {
                cursorShape: drag.active ? Qt.ClosedHandCursor : Qt.OpenHandCursor
            }

            DragHandler {
                id: drag
                target: null
                onCentroidChanged: if (active)
                    HubEditState.target(HubAnchor.nearest(centroid.scenePosition.x, centroid.scenePosition.y, root.width, root.height))
            }
        }

        // In the middle of the screen, the one place no Hub can take.
        CortetsuPopupSurface {
            id: card
            anchors.centerIn: parent
            implicitWidth: Math.min(420, root.width - 32)
            implicitHeight: cardBody.implicitHeight + CortetsuDesign.spacingComfortable * 2

            ColumnLayout {
                id: cardBody
                anchors.fill: parent
                anchors.margins: CortetsuDesign.spacingComfortable
                spacing: CortetsuDesign.spacingStandard

                CortetsuSectionHeader {
                    Layout.fillWidth: true
                    title: qsTr("Mover el Hub")
                    detail: qsTr("%1 · %2").arg(HubAnchor.labels[HubEditState.pending]).arg(HubEditState.monitor)
                }

                CortetsuText {
                    Layout.fillWidth: true
                    text: qsTr("Arrástralo o elige un lugar; las flechas también lo mueven. Intro guarda y Esc lo deja como estaba.")
                    textSize: CortetsuTypography.labelMediumPx
                    color: CortetsuDesign.colorOnSurfaceVariant
                    wrapMode: Text.WordWrap
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: CortetsuDesign.spacingCompact

                    CortetsuButton {
                        objectName: "hubEditDefault"
                        icon: "restart_alt"
                        label: qsTr("Predeterminada")
                        tooltipText: qsTr("Abajo, a lo ancho (Inicio)")
                        disabled: HubEditState.pending === HubAnchor.fallback
                        onClicked: HubEditState.restoreDefault()
                    }

                    Item { Layout.fillWidth: true }

                    CortetsuButton {
                        objectName: "hubEditCancel"
                        label: qsTr("Cancelar")
                        onClicked: HubEditState.cancel()
                    }

                    CortetsuButton {
                        objectName: "hubEditSave"
                        icon: "check"
                        label: qsTr("Guardar")
                        active: true
                        onClicked: HubEditState.save()
                    }
                }
            }
        }
    }
}
