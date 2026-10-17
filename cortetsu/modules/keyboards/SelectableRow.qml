import QtQuick
import ".."
import "../../components"
import "../../theme"
import "../CortetsuTypography.js" as CortetsuTypography

// A list row with a title, a detail line and trailing content (keycaps,
// state chips). Same surface, focus ring and activation keys as
// CortetsuListRow, which has no trailing slot.
Item {
    id: root

    property string icon: ""
    // An application icon path; replaces the glyph when it loads.
    property string image: ""
    property string title: ""
    property string detail: ""
    property bool warning: false
    property bool selected: false
    property bool muted: false
    default property alias trailing: trailingBox.data

    signal clicked()

    implicitHeight: 52
    activeFocusOnTab: true
    Accessible.role: Accessible.Button
    Accessible.name: title
    Accessible.description: detail

    Keys.onReturnPressed: root.clicked()
    Keys.onEnterPressed: root.clicked()
    Keys.onSpacePressed: root.clicked()

    CortetsuSurface {
        anchors.fill: parent
        radiusValue: CortetsuDesign.radiusMedium
        active: root.selected
        focused: root.activeFocus
        hovered: mouse.containsMouse
        pressed: mouse.pressed
        outlined: root.selected || root.activeFocus
        baseColor: root.selected ? Qt.alpha(CortetsuDesign.colorPrimaryContainer, 0.55)
                                 : Qt.alpha(CortetsuDesign.colorSurfaceGlassStrong, 0.42)
        hoverColor: Qt.alpha(CortetsuDesign.colorSurfaceGlassStrong, 0.9)
        activeColor: Qt.alpha(CortetsuDesign.colorPrimaryContainer, 0.7)
        outlineColor: root.activeFocus ? Qt.alpha(CortetsuDesign.colorWashi, 0.82) : Qt.alpha(CortetsuDesign.colorPrimary, 0.32)
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }

    CortetsuIcon {
        id: glyph
        anchors.left: parent.left
        anchors.leftMargin: CortetsuDesign.spacingStandard
        anchors.verticalCenter: parent.verticalCenter
        visible: root.icon.length > 0 && appImage.status !== Image.Ready
        width: root.icon.length > 0 || root.image.length > 0 ? 22 : 0
        text: root.icon
        iconSize: CortetsuTypography.iconMediumPx
        color: root.selected ? CortetsuDesign.colorWashi : CortetsuDesign.colorPrimary
    }

    Image {
        id: appImage
        anchors.centerIn: glyph
        width: 22
        height: 22
        sourceSize: Qt.size(44, 44)
        source: root.image
        asynchronous: true
        visible: status === Image.Ready
    }

    Column {
        anchors.left: glyph.right
        anchors.leftMargin: glyph.width > 0 ? CortetsuDesign.spacingStandard : 0
        anchors.right: trailingBox.left
        anchors.rightMargin: CortetsuDesign.spacingStandard
        anchors.verticalCenter: parent.verticalCenter
        spacing: 1

        CortetsuText {
            width: parent.width
            text: root.title
            textSize: CortetsuTypography.bodyPx
            font.weight: root.selected ? Font.DemiBold : Font.Normal
            color: root.muted ? CortetsuDesign.colorOnSurfaceVariant : CortetsuDesign.colorOnSurface
            elide: Text.ElideRight
        }

        CortetsuText {
            width: parent.width
            visible: text.length > 0
            text: root.detail
            textSize: CortetsuTypography.labelSmallPx
            color: root.warning ? CortetsuDesign.colorVermillion : CortetsuDesign.colorOnSurfaceVariant
            elide: Text.ElideMiddle
        }
    }

    Item {
        id: trailingBox
        anchors.right: parent.right
        anchors.rightMargin: CortetsuDesign.spacingStandard
        anchors.verticalCenter: parent.verticalCenter
        width: childrenRect.width
        height: childrenRect.height
    }
}
