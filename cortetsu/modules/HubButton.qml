import QtQuick
import QtQuick.Controls
import "CortetsuDesign.js" as CortetsuDesign
import "CortetsuTypography.js" as CortetsuTypography

Item {
    id: root

    focus: !disabled
    activeFocusOnTab: !disabled

    property string icon: "circle"
    property string imageSource: ""
    property bool cropImage: false
    property bool active: false
    property bool disabled: false
    property string tooltip: ""
    property bool tooltipOnHover: true
    property int buttonSize: 48
    property int iconSize: CortetsuTypography.iconMediumPx
    property color activeColor: Qt.alpha(CortetsuDesign.colorIndigo, 0.62)
    property color hoverColor: Qt.alpha(CortetsuDesign.colorSurfaceHigh, 0.92)
    property color iconColor: active || hovered || activeFocus
        ? CortetsuDesign.colorWashi
        : CortetsuDesign.colorMuted
    readonly property bool hovered: mouse.containsMouse
    readonly property bool pressed: mouse.pressed

    signal clicked()
    signal wheel(real delta)

    implicitWidth: buttonSize
    implicitHeight: buttonSize
    width: implicitWidth
    height: implicitHeight
    scale: root.pressed
        ? 0.965
        : root.hovered
            ? CortetsuDesign.hoverScale
            : 1

    Behavior on scale {
        NumberAnimation {
            duration: root.pressed
                ? CortetsuDesign.motionInstantMs
                : CortetsuDesign.motionFastMs
            easing.type: Easing.OutCubic
        }
    }

    CortetsuSurface {
        anchors.fill: parent
        anchors.margins: 3
        radiusValue: CortetsuDesign.radiusMedium
        baseColor: "transparent"
        hoverColor: root.hoverColor
        activeColor: root.activeColor
        outlineColor: root.activeFocus
            ? Qt.alpha(CortetsuDesign.colorWashi, 0.82)
            : root.active
                ? Qt.alpha(CortetsuDesign.colorWashi, 0.22)
                : Qt.alpha(CortetsuDesign.colorMuted, 0.14)
        hovered: root.hovered
        pressed: root.pressed
        active: root.active
        focused: root.activeFocus
        disabled: root.disabled
        outlined: root.active
    }

    CortetsuIcon {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: root.active ? -1 : 0
        visible: root.imageSource.length === 0
        text: root.icon
        color: root.iconColor
        iconSize: root.iconSize

        Behavior on color {
            ColorAnimation {
                duration: CortetsuDesign.motionFastMs
                easing.type: Easing.OutCubic
            }
        }

        Behavior on anchors.verticalCenterOffset {
            NumberAnimation {
                duration: CortetsuDesign.motionFastMs
                easing.type: Easing.OutCubic
            }
        }
    }

    Image {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: root.active ? -1 : 0
        visible: root.imageSource.length > 0
        width: Math.round(root.buttonSize * 0.56)
        height: width
        source: root.imageSource
        sourceSize.width: 64
        sourceSize.height: 64
        asynchronous: false
        retainWhileLoading: true
        fillMode: root.cropImage ? Image.PreserveAspectCrop : Image.PreserveAspectFit
        smooth: true
        mipmap: true
        opacity: root.hovered || root.active || root.activeFocus ? 1 : 0.86

        Behavior on opacity {
            NumberAnimation {
                duration: CortetsuDesign.motionFastMs
                easing.type: Easing.OutCubic
            }
        }

        Behavior on anchors.verticalCenterOffset {
            NumberAnimation {
                duration: CortetsuDesign.motionFastMs
                easing.type: Easing.OutCubic
            }
        }
    }

    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 4
        visible: root.active
        width: root.activeFocus ? 20 : 16
        height: 2
        radius: 1
        color: root.activeColor === CortetsuDesign.colorVermillion
            ? CortetsuDesign.colorVermillion
            : CortetsuDesign.colorWashi
        opacity: root.disabled ? 0 : 0.9

        Behavior on width {
            NumberAnimation {
                duration: CortetsuDesign.motionFastMs
                easing.type: Easing.OutCubic
            }
        }
    }

    ToolTip {
        id: tooltipPopup

        parent: root
        visible: root.tooltip.length > 0
            && ((root.tooltipOnHover && root.hovered) || root.activeFocus)
        delay: CortetsuDesign.motionDeliberateMs
        text: root.tooltip

        background: CortetsuSurface {
            radiusValue: CortetsuDesign.radiusSmall
            baseColor: CortetsuDesign.colorTetsu
            outlineColor: Qt.alpha(CortetsuDesign.colorMuted, 0.28)
            outlined: true
        }

        contentItem: CortetsuText {
            text: tooltipPopup.text
            textSize: CortetsuTypography.labelSmallPx
            color: CortetsuDesign.colorWashi
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        enabled: !root.disabled
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onPressed: root.forceActiveFocus()
        onClicked: root.clicked()
        onWheel: event => {
            root.wheel(event.angleDelta.y);
            event.accepted = true;
        }
    }

    Keys.onEnterPressed: root.clicked()
    Keys.onReturnPressed: root.clicked()
    Keys.onSpacePressed: root.clicked()
}
