pragma ComponentBehavior: Bound

import QtQuick
import "../../components"
import "../../theme"
import "../CortetsuTypography.js" as CortetsuTypography

// One category of the sidebar: its icon and its full name. How the domain
// stands is not printed beside the name, where it would squeeze it; it is
// the row's tooltip and accessible description, and a vermillion dot marks
// a category that needs a look.
Item {
    id: root

    required property string icon
    required property string title
    property string value: ""
    property string alertText: ""
    property bool selected: false
    property bool collapsed: false
    readonly property bool alerting: alertText.length > 0
    signal activated()

    implicitHeight: 40
    // Only the open category is a Tab stop; the arrows reach the rest. A row
    // that holds the focus stays one until it lets go: Qt refuses to drop the
    // flag from the focused item, and would leave it set for good.
    activeFocusOnTab: selected || activeFocus

    Accessible.role: Accessible.PageTab
    Accessible.name: root.alerting ? qsTr("%1, requiere atención: %2").arg(root.title).arg(root.alertText) : root.title
    Accessible.description: root.value
    Accessible.selected: root.selected

    CortetsuSurface {
        anchors.fill: parent
        radiusValue: CortetsuDesign.materialStyle === 2 ? CortetsuDesign.radiusSmall : CortetsuDesign.radiusMedium
        active: root.selected
        focused: root.activeFocus
        hovered: mouse.containsMouse
        pressed: mouse.pressed
        baseColor: "transparent"
        hoverColor: Qt.alpha(CortetsuDesign.colorOnSurface, 0.07)
        activeColor: Qt.alpha(CortetsuDesign.colorPrimaryContainer, CortetsuDesign.materialStyle === 1 ? 0.9 : 0.72)
        outlineColor: root.activeFocus
            ? Qt.alpha(CortetsuDesign.colorWashi, 0.82)
            : Qt.alpha(CortetsuDesign.colorPrimary, 0.4)
        outlined: root.selected && CortetsuDesign.materialStyle === 2
    }

    // The current category is marked by an accent bar on its left edge.
    Rectangle {
        anchors.left: parent.left
        anchors.leftMargin: 2
        anchors.verticalCenter: parent.verticalCenter
        visible: root.selected
        width: 3
        height: 18
        radius: CortetsuDesign.materialStyle === 2 ? 0 : 1.5
        color: CortetsuDesign.colorIndicator
    }

    CortetsuIcon {
        id: glyph
        anchors.verticalCenter: parent.verticalCenter
        x: root.collapsed ? (root.width - width) / 2 : CortetsuDesign.spacingStandard + 2
        text: root.icon
        iconSize: CortetsuTypography.iconSmallPx
        color: root.selected ? CortetsuDesign.colorOnPrimaryContainer : CortetsuDesign.colorOnSurfaceVariant
    }

    CortetsuText {
        id: label
        objectName: "label"
        visible: !root.collapsed
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: glyph.right
        anchors.leftMargin: CortetsuDesign.spacingStandard
        anchors.right: alertDot.visible ? alertDot.left : parent.right
        anchors.rightMargin: CortetsuDesign.spacingCompact
        text: root.title
        textSize: CortetsuTypography.bodyLargePx
        font.weight: root.selected ? Font.DemiBold : Font.Normal
        color: root.selected ? CortetsuDesign.colorOnPrimaryContainer : CortetsuDesign.colorOnSurface
        elide: Text.ElideRight
    }

    Rectangle {
        id: alertDot
        objectName: "alertDot"
        visible: root.alerting
        width: 7
        height: 7
        radius: width / 2
        color: CortetsuDesign.colorVermillion
        anchors.verticalCenter: root.collapsed ? undefined : parent.verticalCenter
        anchors.right: parent.right
        anchors.rightMargin: root.collapsed ? 12 : CortetsuDesign.spacingStandard
        y: root.collapsed ? 8 : 0
    }

    CortetsuTooltip {
        target: root
        placement: "right"
        hovered: mouse.containsMouse
        // Keyboard focus only: a row focused on opening shows no tooltip.
        focused: root.activeFocus && [Qt.TabFocusReason, Qt.BacktabFocusReason].includes(root.focusReason)
        text: root.alerting ? `${root.title}: ${root.alertText}`
            : root.value.length > 0 ? `${root.title} · ${root.value}`
            : root.collapsed ? root.title : ""
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            root.forceActiveFocus();
            root.activated();
        }
    }

    Keys.onEnterPressed: root.activated()
    Keys.onReturnPressed: root.activated()
    Keys.onSpacePressed: root.activated()
}
