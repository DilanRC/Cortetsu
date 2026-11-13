pragma ComponentBehavior: Bound

import QtQuick
import "../components"
import "../theme"
import "CortetsuTypography.js" as CortetsuTypography

Item {
    id: root

    required property var items
    // The most the rail may take along the Hub before it scrolls.
    required property real maxWidth
    property var delegateModel: items
    property bool vertical: false
    property string tooltipPlacement: "above"
    readonly property real thickness: Math.max(46, CortetsuDesign.rowHeight - 2)

    signal activateRequested(string key)
    signal togglePinnedRequested(string key)
    signal closeRequested(string key)
    signal cycleRequested(string key, int direction)

    implicitWidth: vertical ? thickness : Math.min(appRailContent.implicitWidth + 24, maxWidth)
    implicitHeight: vertical ? Math.min(appRailContent.implicitHeight + 24, maxWidth) : thickness
    width: implicitWidth
    height: implicitHeight
    clip: true

    CortetsuIsland {}

    Flickable {
        id: appRail
        anchors.fill: parent
        anchors.leftMargin: root.vertical ? 0 : 12
        anchors.rightMargin: root.vertical ? 0 : 12
        anchors.topMargin: root.vertical ? 12 : 0
        anchors.bottomMargin: root.vertical ? 12 : 0
        contentWidth: root.vertical ? width : appRailContent.implicitWidth
        contentHeight: root.vertical ? appRailContent.implicitHeight : height
        boundsBehavior: Flickable.StopAtBounds
        interactive: root.vertical ? contentHeight > height : contentWidth > width
        clip: true

        HubFlow {
            id: appRailContent
            vertical: root.vertical
            x: root.vertical ? Math.round((appRail.width - width) / 2) : 0
            y: root.vertical ? 0 : Math.round((appRail.height - height) / 2)
            spacing: 2

            Repeater {
                model: root.delegateModel

                Item {
                    id: appItem
                    required property var modelData
                    objectName: `dock-${modelData.key}`
                    enabled: modelData.enabled ?? true

                    implicitWidth: 46
                    implicitHeight: 50
                    width: implicitWidth
                    height: implicitHeight
                    activeFocusOnTab: enabled

                    CortetsuSurface {
                        anchors.fill: parent
                        anchors.margins: 3
                        radiusValue: height / 2
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
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: CortetsuDesign.easeOut
                            }
                        }
                        Behavior on opacity {
                            NumberAnimation {
                                duration: CortetsuDesign.motionFastMs
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: CortetsuDesign.easeOut
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
                        radius: height / 2
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
                                radius: height / 2
                                color: appItem.modelData.active
                                    ? CortetsuDesign.colorWashi
                                    : CortetsuDesign.colorMuted
                                opacity: index < 3 ? 0.88 : 0.48

                                // design-lint: allow motion-layout-property: the active window bar widens inside a row of at most four
                                Behavior on width {
                                    NumberAnimation {
                                        duration: CortetsuDesign.motionFastMs
                                        easing.type: Easing.BezierSpline
                                        easing.bezierCurve: CortetsuDesign.easeOut
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
                    // Tab into an item that scrolled out of the rail.
                    onActiveFocusChanged: if (activeFocus) {
                        if (root.vertical)
                            appRail.contentY = Math.max(0, Math.min(y, Math.max(0, appRail.contentHeight - appRail.height)));
                        else
                            appRail.contentX = Math.max(0, Math.min(x, Math.max(0, appRail.contentWidth - appRail.width)));
                    }

                    CortetsuTooltip {
                        target: appItem
                        hovered: appMouse.containsMouse
                        focused: appItem.activeFocus
                        text: appItem.modelData.title
                        placement: root.tooltipPlacement
                    }
                }
            }
        }
    }
}
