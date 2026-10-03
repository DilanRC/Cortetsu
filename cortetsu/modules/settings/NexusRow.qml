pragma ComponentBehavior: Bound

import QtQuick
import "../../components"
import "../../theme"
import "../CortetsuTypography.js" as CortetsuTypography

// One destination of the Nexus: where it leads and, to its right, how that
// domain stands right now. A vermillion dot means the page needs a look.
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
    // Only the open page is a Tab stop; the arrows reach the rest. A row that
    // holds the focus stays one until it lets go: Qt refuses to drop the flag
    // from the focused item, and would leave it set for good.
    activeFocusOnTab: selected || activeFocus

    Accessible.role: Accessible.PageTab
    Accessible.name: root.alerting ? qsTr("%1, requiere atención: %2").arg(root.title).arg(root.alertText) : root.title
    Accessible.selected: root.selected

    CortetsuSurface {
        anchors.fill: parent
        radiusValue: CortetsuDesign.radiusSmall
        active: root.selected
        focused: root.activeFocus
        hovered: mouse.containsMouse
        pressed: mouse.pressed
        baseColor: "transparent"
        hoverColor: Qt.alpha(CortetsuDesign.colorSurfaceGlassStrong, 0.9)
        activeColor: Qt.alpha(CortetsuDesign.colorPrimaryContainer, 0.72)
        outlineColor: root.activeFocus
            ? Qt.alpha(CortetsuDesign.colorWashi, 0.82)
            : Qt.alpha(CortetsuDesign.colorPrimary, 0.32)
        outlined: root.selected
    }

    // The same washi tick marks the current item across Cortetsu lists.
    Rectangle {
        anchors.left: parent.left
        anchors.leftMargin: 3
        anchors.verticalCenter: parent.verticalCenter
        visible: root.selected
        width: 2
        height: 20
        radius: 1
        color: CortetsuDesign.colorWashi
    }

    CortetsuIcon {
        id: glyph
        anchors.verticalCenter: parent.verticalCenter
        x: root.collapsed ? (root.width - width) / 2 : CortetsuDesign.spacingStandard
        text: root.icon
        iconSize: CortetsuTypography.iconSmallPx
        color: root.selected ? CortetsuDesign.colorOnPrimaryContainer : CortetsuDesign.colorOnSurfaceVariant
    }

    CortetsuText {
        id: label
        visible: !root.collapsed
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: glyph.right
        anchors.leftMargin: CortetsuDesign.spacingStandard
        width: Math.min(implicitWidth, root.width - x - CortetsuDesign.spacingStandard)
        text: root.title
        textSize: CortetsuTypography.bodyPx
        font.weight: root.selected ? Font.DemiBold : Font.Normal
        color: root.selected ? CortetsuDesign.colorOnPrimaryContainer : CortetsuDesign.colorOnSurface
        elide: Text.ElideRight
    }

    CortetsuText {
        objectName: "value"
        visible: !root.collapsed && text.length > 0
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: label.right
        anchors.leftMargin: CortetsuDesign.spacingCompact
        anchors.right: alertDot.visible ? alertDot.left : parent.right
        anchors.rightMargin: alertDot.visible ? CortetsuDesign.spacingCompact : CortetsuDesign.spacingStandard
        horizontalAlignment: Text.AlignRight
        text: root.value
        textSize: CortetsuTypography.labelSmallPx
        color: root.alerting
            ? CortetsuDesign.colorVermillion
            : root.selected
                ? Qt.alpha(CortetsuDesign.colorOnPrimaryContainer, 0.76)
                : CortetsuDesign.colorOnSurfaceVariant
        elide: Text.ElideRight
    }

    Rectangle {
        id: alertDot
        objectName: "alertDot"
        visible: root.alerting
        width: 6
        height: 6
        radius: 3
        color: CortetsuDesign.colorVermillion
        anchors.verticalCenter: root.collapsed ? undefined : parent.verticalCenter
        anchors.right: parent.right
        anchors.rightMargin: root.collapsed ? 12 : CortetsuDesign.spacingStandard
        y: root.collapsed ? 8 : 0
    }

    CortetsuTooltip {
        target: root
        hovered: mouse.containsMouse
        focused: root.activeFocus
        text: root.collapsed
            ? (root.alerting ? `${root.title}: ${root.alertText}` : root.value.length > 0 ? `${root.title} · ${root.value}` : root.title)
            : root.alertText
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
