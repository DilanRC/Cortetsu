pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../../../components"
import "../../../theme"
import "../../CortetsuTypography.js" as CortetsuTypography

// One option of a segmented choice: a pill with an optional icon. The
// selected one is filled; the rest wait on the page's surface.
Item {
    id: root

    property string label: ""
    property string icon: ""
    property bool selected: false
    property bool disabled: false
    property bool busy: false
    signal clicked()

    function request(): void {
        if (!root.disabled && !root.busy)
            root.clicked();
    }

    implicitWidth: row.implicitWidth + CortetsuDesign.spacingComfortable * 2
    implicitHeight: Math.max(34, CortetsuDesign.controlHeight)
    opacity: root.disabled && !root.selected ? 0.5 : 1
    activeFocusOnTab: !root.disabled || activeFocus

    Accessible.role: Accessible.RadioButton
    Accessible.name: root.label
    Accessible.checkable: true
    Accessible.checked: root.selected
    Accessible.onPressAction: root.request()

    Keys.onSpacePressed: root.request()
    Keys.onReturnPressed: root.request()
    Keys.onEnterPressed: root.request()

    CortetsuSurface {
        anchors.fill: parent
        radiusValue: CortetsuDesign.materialStyle === 2 ? CortetsuDesign.radiusSmall : height / 2
        active: root.selected
        focused: root.activeFocus
        hovered: mouse.containsMouse && !root.disabled
        pressed: mouse.pressed
        baseColor: Qt.alpha(CortetsuDesign.colorSurfaceGlassStrong, 0.8)
        activeColor: CortetsuDesign.colorPrimaryContainer
        outlined: !root.selected || CortetsuDesign.materialStyle === 2
    }

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 6

        CortetsuIcon {
            visible: root.icon.length > 0 || root.busy
            text: root.busy ? "progress_activity" : root.icon
            iconSize: CortetsuTypography.iconSmallPx
            color: root.selected ? CortetsuDesign.colorOnPrimaryContainer : CortetsuDesign.colorOnSurfaceVariant
        }

        CortetsuText {
            text: root.label
            textSize: CortetsuTypography.bodyPx
            font.weight: root.selected ? Font.DemiBold : Font.Normal
            color: root.selected ? CortetsuDesign.colorOnPrimaryContainer : CortetsuDesign.colorOnSurface
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: root.disabled ? Qt.ArrowCursor : Qt.PointingHandCursor
        onClicked: {
            root.forceActiveFocus();
            root.request();
        }
    }
}
