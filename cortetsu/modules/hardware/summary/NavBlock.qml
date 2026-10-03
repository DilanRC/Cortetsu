pragma ComponentBehavior: Bound

import QtQuick
import "../../../components"
import "../../../theme"
import "../../CortetsuTypography.js" as CortetsuTypography

// A region of the summary that opens the page explaining it. The chevron marks
// it as a way in; the destination is named on hover and on keyboard focus.
Item {
    id: root

    default property alias content: body.data
    property string destination: ""
    property string accessibleName: ""
    property bool framed: true
    // A single-line row centres the chevron; a taller block keeps it in the corner.
    property bool compact: false
    property real padding: CortetsuDesign.spacingComfortable
    property real radiusValue: CortetsuDesign.radiusLarge
    readonly property bool hovered: mouse.containsMouse
    readonly property bool pressed: mouse.pressed
    readonly property bool engaged: root.hovered || root.activeFocus

    signal activated()

    activeFocusOnTab: true
    Accessible.role: Accessible.Button
    Accessible.name: root.accessibleName
    Accessible.description: root.destination
    Accessible.onPressAction: root.activated()

    CortetsuSurface {
        anchors.fill: parent
        radiusValue: root.radiusValue
        hovered: root.hovered
        pressed: root.pressed
        focused: root.activeFocus
        outlined: false
        baseColor: root.framed
            ? Qt.alpha(CortetsuDesign.colorSurfaceGlass, 0.72)
            : Qt.alpha(CortetsuDesign.colorSurfaceGlass, 0)
        hoverColor: CortetsuDesign.colorSurfaceGlassStrong
        outlineColor: Qt.alpha(CortetsuDesign.colorWashi, 0.86)
    }

    Item {
        id: body
        anchors.fill: parent
        anchors.margins: root.padding
    }

    Row {
        anchors.right: parent.right
        anchors.top: root.compact ? undefined : parent.top
        anchors.verticalCenter: root.compact ? parent.verticalCenter : undefined
        anchors.rightMargin: root.padding - 4
        anchors.topMargin: root.padding - 2
        spacing: 2

        CortetsuText {
            anchors.verticalCenter: parent.verticalCenter
            text: root.destination
            color: CortetsuDesign.colorOnSurfaceVariant
            textSize: CortetsuTypography.labelSmallPx
            opacity: root.engaged ? 1 : 0

            Behavior on opacity {
                NumberAnimation { duration: CortetsuDesign.motionFastMs; easing.type: Easing.OutCubic }
            }
        }

        CortetsuIcon {
            anchors.verticalCenter: parent.verticalCenter
            text: "chevron_right"
            color: root.engaged ? CortetsuDesign.colorOnSurface : CortetsuDesign.colorOutline
            iconSize: CortetsuTypography.iconSmallPx
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onPressed: root.forceActiveFocus()
        onClicked: root.activated()
    }

    Keys.onEnterPressed: root.activated()
    Keys.onReturnPressed: root.activated()
    Keys.onSpacePressed: root.activated()
}
