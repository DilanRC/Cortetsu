pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import "CortetsuDesign.js" as CortetsuDesign
import "CortetsuTypography.js" as CortetsuTypography

Item {
    id: root

    required property var items
    required property real maxWidth

    signal activateRequested(string key)
    signal togglePinnedRequested(string key)
    signal closeRequested(string key)
    signal cycleRequested(string key, int direction)

    implicitWidth: Math.min(appRailContent.implicitWidth + 16, maxWidth)
    implicitHeight: 52
    width: implicitWidth
    height: implicitHeight
    clip: true

    CortetsuSurface {
        anchors.fill: parent
        radiusValue: CortetsuDesign.radiusLarge
        baseColor: Qt.alpha(CortetsuDesign.colorSurfaceHigh, 0.72)
        outlineColor: Qt.alpha(CortetsuDesign.colorMuted, 0.2)
        outlined: true
    }

    Flickable {
        id: appRail
        anchors.fill: parent
        anchors.leftMargin: CortetsuDesign.spacingCompact
        anchors.rightMargin: CortetsuDesign.spacingCompact
        contentWidth: appRailContent.implicitWidth
        contentHeight: height
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentWidth > width
        clip: true

        Row {
            id: appRailContent
            height: parent.height
            spacing: CortetsuDesign.spacingUnit

            Repeater {
                model: root.items

                Item {
                    id: appItem
                    required property var modelData

                    implicitWidth: 44
                    implicitHeight: 52
                    width: implicitWidth
                    height: implicitHeight
                    focus: true
                    activeFocusOnTab: true
                    scale: appMouse.pressed
                        ? 0.97
                        : appMouse.containsMouse
                            ? 1.018
                            : 1

                    Behavior on scale {
                        NumberAnimation {
                            duration: appMouse.pressed
                                ? CortetsuDesign.motionInstantMs
                                : CortetsuDesign.motionFastMs
                            easing.type: Easing.OutCubic
                        }
                    }

                    CortetsuSurface {
                        anchors.fill: parent
                        anchors.topMargin: 3
                        anchors.bottomMargin: 3
                        radiusValue: CortetsuDesign.radiusMedium
                        baseColor: "transparent"
                        hoverColor: Qt.alpha(CortetsuDesign.colorSurfaceHigh, 0.94)
                        activeColor: Qt.alpha(CortetsuDesign.colorIndigo, 0.52)
                        outlineColor: appItem.activeFocus
                            ? Qt.alpha(CortetsuDesign.colorWashi, 0.82)
                            : appItem.modelData.active
                                ? Qt.alpha(CortetsuDesign.colorWashi, 0.2)
                                : Qt.alpha(CortetsuDesign.colorMuted, 0.12)
                        hovered: appMouse.containsMouse
                        pressed: appMouse.pressed
                        active: appItem.modelData.active
                        focused: appItem.activeFocus
                        outlined: appItem.modelData.active
                    }

                    Image {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.top: parent.top
                        anchors.topMargin: appItem.modelData.active ? 7 : 8
                        width: 30
                        height: 30
                        source: appItem.modelData.iconSource
                        sourceSize.width: 64
                        sourceSize.height: 64
                        asynchronous: false
                        retainWhileLoading: true
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                        mipmap: true
                        opacity: appItem.modelData.running || appMouse.containsMouse || appItem.activeFocus
                            ? 1
                            : 0.68

                        Behavior on anchors.topMargin {
                            NumberAnimation {
                                duration: CortetsuDesign.motionFastMs
                                easing.type: Easing.OutCubic
                            }
                        }

                        Behavior on opacity {
                            NumberAnimation {
                                duration: CortetsuDesign.motionFastMs
                                easing.type: Easing.OutCubic
                            }
                        }
                    }

                    Rectangle {
                        visible: appItem.modelData.pinned && !appItem.modelData.running
                        anchors.top: parent.top
                        anchors.right: parent.right
                        anchors.topMargin: 7
                        anchors.rightMargin: 5
                        width: 6
                        height: 6
                        radius: 3
                        color: Qt.alpha(CortetsuDesign.colorMuted, 0.82)
                    }

                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 5
                        spacing: 3
                        visible: appItem.modelData.running

                        Repeater {
                            model: Math.min(appItem.modelData.windowCount, 4)

                            Rectangle {
                                required property int index
                                width: appItem.modelData.active ? 9 : 4
                                height: 3
                                radius: 2
                                color: appItem.modelData.active
                                    ? CortetsuDesign.colorWashi
                                    : CortetsuDesign.colorMuted
                                opacity: index < 3 ? 0.92 : 0.52

                                Behavior on width {
                                    NumberAnimation {
                                        duration: CortetsuDesign.motionFastMs
                                        easing.type: Easing.OutCubic
                                    }
                                }
                            }
                        }
                    }

                    MouseArea {
                        id: appMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                        cursorShape: Qt.PointingHandCursor

                        onPressed: appItem.forceActiveFocus()

                        onClicked: event => {
                            if (event.button === Qt.RightButton) {
                                root.togglePinnedRequested(appItem.modelData.key);
                                return;
                            }

                            if (event.button === Qt.MiddleButton) {
                                root.closeRequested(appItem.modelData.key);
                                return;
                            }

                            root.activateRequested(appItem.modelData.key);
                        }

                        onWheel: wheel => {
                            if (wheel.angleDelta.y > 0)
                                root.cycleRequested(appItem.modelData.key, -1);
                            else if (wheel.angleDelta.y < 0)
                                root.cycleRequested(appItem.modelData.key, 1);

                            wheel.accepted = true;
                        }
                    }

                    Keys.onEnterPressed: root.activateRequested(appItem.modelData.key)
                    Keys.onReturnPressed: root.activateRequested(appItem.modelData.key)
                    Keys.onSpacePressed: root.activateRequested(appItem.modelData.key)
                    Keys.onLeftPressed: root.cycleRequested(appItem.modelData.key, -1)
                    Keys.onRightPressed: root.cycleRequested(appItem.modelData.key, 1)

                    ToolTip {
                        id: appTooltip
                        parent: appItem
                        visible: appItem.modelData.title?.length > 0
                            && (appMouse.containsMouse || appItem.activeFocus)
                        delay: CortetsuDesign.motionDeliberateMs
                        text: appItem.modelData.title

                        background: CortetsuSurface {
                            radiusValue: CortetsuDesign.radiusSmall
                            baseColor: CortetsuDesign.colorTetsu
                            outlineColor: Qt.alpha(CortetsuDesign.colorMuted, 0.28)
                            outlined: true
                        }

                        contentItem: CortetsuText {
                            text: appTooltip.text
                            textSize: CortetsuTypography.labelSmallPx
                            color: CortetsuDesign.colorWashi
                        }
                    }
                }
            }
        }
    }
}
