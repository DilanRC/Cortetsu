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

    implicitWidth: Math.min(appRailContent.implicitWidth + CortetsuDesign.spacingCompact, maxWidth)
    implicitHeight: 50
    width: implicitWidth
    height: implicitHeight
    clip: true

    Flickable {
        id: appRail
        anchors.fill: parent
        anchors.leftMargin: CortetsuDesign.spacingUnit
        anchors.rightMargin: CortetsuDesign.spacingUnit
        contentWidth: appRailContent.implicitWidth
        contentHeight: height
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentWidth > width
        clip: true

        Row {
            id: appRailContent
            height: parent.height
            spacing: 2

            Repeater {
                model: root.items

                Item {
                    id: appItem
                    required property var modelData

                    implicitWidth: 46
                    implicitHeight: 50
                    width: implicitWidth
                    height: implicitHeight
                    focus: true
                    activeFocusOnTab: true
                    scale: appMouse.pressed ? 0.97 : appMouse.containsMouse ? CortetsuDesign.hoverScale : 1

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
                        anchors.margins: 3
                        radiusValue: CortetsuDesign.radiusMedium
                        baseColor: appItem.modelData.active
                            ? Qt.alpha(CortetsuDesign.colorPrimaryContainer, 0.62)
                            : "transparent"
                        hoverColor: Qt.alpha(CortetsuDesign.colorSurfaceGlassStrong, 0.84)
                        outlineColor: appItem.activeFocus
                            ? Qt.alpha(CortetsuDesign.colorWashi, 0.72)
                            : "transparent"
                        hovered: appMouse.containsMouse
                        pressed: appMouse.pressed
                        focused: appItem.activeFocus
                        outlined: appItem.activeFocus
                    }

                    Image {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.top: parent.top
                        anchors.topMargin: appItem.modelData.running ? 6 : 8
                        width: 31
                        height: 31
                        source: appItem.modelData.iconSource
                        sourceSize.width: 64
                        sourceSize.height: 64
                        asynchronous: false
                        retainWhileLoading: true
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                        mipmap: true
                        opacity: appItem.modelData.running || appMouse.containsMouse || appItem.activeFocus ? 1 : 0.72

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
                        width: 5
                        height: 5
                        radius: 3
                        color: Qt.alpha(CortetsuDesign.colorMuted, 0.66)
                    }

                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 4
                        spacing: 3
                        visible: appItem.modelData.running

                        Repeater {
                            model: Math.min(appItem.modelData.windowCount, 4)

                            Rectangle {
                                required property int index
                                width: appItem.modelData.active ? 10 : 4
                                height: 3
                                radius: 2
                                color: appItem.modelData.active
                                    ? CortetsuDesign.colorWashi
                                    : CortetsuDesign.colorMuted
                                opacity: index < 3 ? 0.88 : 0.48

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
                            outlineColor: Qt.alpha(CortetsuDesign.colorMuted, 0.24)
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
