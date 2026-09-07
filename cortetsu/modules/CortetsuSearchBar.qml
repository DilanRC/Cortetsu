import QtQuick
import QtQuick.Controls
import "CortetsuDesign.js" as CortetsuDesign
import "CortetsuTypography.js" as CortetsuTypography

TextField {
    id: root

    property alias searchIcon: root
    property alias clearIcon: root
    property alias bg: root

    implicitHeight: 52
    leftPadding: 48
    rightPadding: text.length > 0 ? 46 : CortetsuDesign.spacingComfortable
    topPadding: CortetsuDesign.spacingStandard
    bottomPadding: CortetsuDesign.spacingStandard
    color: CortetsuDesign.colorOnSurface
    placeholderTextColor: Qt.alpha(CortetsuDesign.colorOnSurfaceVariant, 0.82)
    selectionColor: Qt.alpha(CortetsuDesign.colorPrimary, 0.56)
    selectedTextColor: CortetsuDesign.colorWashi
    font.pixelSize: CortetsuTypography.bodyLargePx
    selectByMouse: true

    CortetsuIcon {
        anchors.left: parent.left
        anchors.leftMargin: CortetsuDesign.spacingStandard
        anchors.verticalCenter: parent.verticalCenter
        text: "search"
        iconSize: CortetsuTypography.iconMediumPx
        color: root.activeFocus
            ? CortetsuDesign.colorOnSurface
            : CortetsuDesign.colorOnSurfaceVariant
    }

    Item {
        anchors.right: parent.right
        anchors.rightMargin: CortetsuDesign.spacingCompact
        anchors.verticalCenter: parent.verticalCenter
        width: 34
        height: 34
        visible: root.text.length > 0

        CortetsuSurface {
            anchors.fill: parent
            radiusValue: CortetsuDesign.radiusPill
            baseColor: clearMouse.containsMouse
                ? CortetsuDesign.colorSurfaceGlassStrong
                : "transparent"
            outlined: false
        }

        CortetsuIcon {
            anchors.centerIn: parent
            text: "close"
            iconSize: CortetsuTypography.iconSmallPx
            color: CortetsuDesign.colorOnSurfaceVariant
        }

        MouseArea {
            id: clearMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                root.clear();
                root.forceActiveFocus();
            }
        }
    }

    background: CortetsuSurface {
        radiusValue: CortetsuDesign.radiusLarge
        baseColor: root.activeFocus
            ? Qt.alpha(CortetsuDesign.colorSurfaceGlassStrong, 0.96)
            : Qt.alpha(CortetsuDesign.colorSurfaceGlass, 0.78)
        outlineColor: root.activeFocus
            ? Qt.alpha(CortetsuDesign.colorPrimary, 0.72)
            : root.hovered
                ? Qt.alpha(CortetsuDesign.colorOutlineVariant, 0.34)
                : Qt.alpha(CortetsuDesign.colorOutlineVariant, 0.16)
        outlined: true
        focused: false

        Behavior on baseColor {
            ColorAnimation {
                duration: CortetsuDesign.motionFastMs
                easing.type: Easing.OutCubic
            }
        }
    }
}
