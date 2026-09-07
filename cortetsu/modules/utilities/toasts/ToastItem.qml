import QtQuick
import "../.."
import "../../CortetsuDesign.js" as CortetsuDesign

CortetsuSurface {
    id: root

    required property var toast
    signal dismissed()
    property bool hovered: false
    readonly property bool urgent: toast.type === 2

    implicitHeight: body.implicitHeight + CortetsuDesign.spacingStandard * 2
    width: parent ? parent.width : implicitWidth
    height: implicitHeight
    radiusValue: CortetsuDesign.radiusMedium
    baseColor: root.urgent
        ? Qt.alpha(CortetsuDesign.colorVermillion, 0.10)
        : Qt.alpha(CortetsuDesign.colorSurfaceHigh, 0.94)
    outlined: true
    focus: true
    activeFocusOnTab: true
    focused: root.activeFocus
    outlineColor: root.activeFocus
        ? Qt.alpha(CortetsuDesign.colorWashi, 0.82)
        : root.urgent
            ? Qt.alpha(CortetsuDesign.colorVermillion, 0.48)
            : Qt.alpha(CortetsuDesign.colorOutlineVariant, root.hovered ? 0.40 : 0.24)
    scale: toastMouse.pressed ? 0.992 : root.hovered ? 1.006 : 1

    Behavior on scale {
        NumberAnimation {
            duration: CortetsuDesign.motionFastMs
            easing.type: Easing.OutCubic
        }
    }

    Rectangle {
        anchors.left: parent.left
        anchors.leftMargin: 3
        anchors.verticalCenter: parent.verticalCenter
        width: 2
        height: Math.max(24, parent.height - CortetsuDesign.spacingStandard * 2)
        radius: 1
        color: root.urgent ? CortetsuDesign.colorVermillion : CortetsuDesign.colorPrimary
        opacity: 0.82
    }

    Row {
        id: body
        anchors.fill: parent
        anchors.margins: CortetsuDesign.spacingStandard
        spacing: CortetsuDesign.spacingStandard

        Item {
            width: 36
            height: 36
            anchors.verticalCenter: parent.verticalCenter

            CortetsuSurface {
                anchors.fill: parent
                radiusValue: CortetsuDesign.radiusSmall
                baseColor: root.urgent
                    ? Qt.alpha(CortetsuDesign.colorVermillion, 0.14)
                    : Qt.alpha(CortetsuDesign.colorPrimary, 0.14)
            }

            CortetsuIcon {
                anchors.centerIn: parent
                text: root.toast.icon || "info"
                color: root.urgent
                    ? CortetsuDesign.colorVermillion
                    : CortetsuDesign.colorPrimary
                iconSize: CortetsuDesign.iconMediumPx
            }
        }

        Column {
            width: Math.max(0, parent.width - 36 - parent.spacing)
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2

            CortetsuText {
                width: parent.width
                text: root.toast.title
                textSize: CortetsuDesign.bodyPx
                font.weight: Font.DemiBold
                color: CortetsuDesign.colorOnSurface
                elide: Text.ElideRight
            }

            CortetsuText {
                width: parent.width
                text: root.toast.message
                textSize: CortetsuDesign.bodySmallPx
                color: CortetsuDesign.colorOnSurfaceVariant
                maximumLineCount: 3
                elide: Text.ElideRight
                wrapMode: Text.Wrap
            }
        }
    }

    MouseArea {
        id: toastMouse
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onEntered: root.hovered = true
        onExited: root.hovered = false
        onPressed: root.forceActiveFocus()
        onClicked: root.dismissed()
    }

    Keys.onEnterPressed: root.dismissed()
    Keys.onReturnPressed: root.dismissed()
    Keys.onSpacePressed: root.dismissed()
    Keys.onEscapePressed: root.dismissed()

    Timer {
        interval: 5000
        running: !root.hovered
        onTriggered: root.dismissed()
    }
}
