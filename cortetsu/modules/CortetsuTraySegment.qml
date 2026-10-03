pragma ComponentBehavior: Bound

import QtQuick
import "../components"
import "../theme"
import "CortetsuTypography.js" as CortetsuTypography
import "BottomHubTray.js" as BottomHubTray

Item {
    id: root

    required property var items
    property var delegateModel: items

    signal hoverRequested(string itemKey, real centerX)
    signal activateRequested(string itemKey)
    signal secondaryRequested(string itemKey, real centerX)
    signal secondaryActivateRequested(string itemKey)
    signal scrollRequested(string itemKey, int delta, bool horizontal)

    implicitWidth: trayRow.implicitWidth + CortetsuDesign.spacingStandard
    implicitHeight: 52
    width: visible ? implicitWidth : 0
    height: implicitHeight
    visible: items.length > 0

    CortetsuSurface {
        anchors.fill: parent
        radiusValue: CortetsuDesign.radiusLarge
        baseColor: CortetsuDesign.colorTetsu
        outlined: true
    }

    Row {
        id: trayRow
        anchors.centerIn: parent
        spacing: 2

        Repeater {
            model: root.delegateModel

            Item {
                id: trayItem
                required property var modelData
                objectName: `tray-${modelData.key}`
                enabled: modelData.enabled ?? true

                implicitWidth: 34
                implicitHeight: 40
                width: implicitWidth
                height: implicitHeight
                activeFocusOnTab: enabled

                function activatePrimary(): void {
                    const action = BottomHubTray.primaryAction(modelData);
                    if (action === "activate")
                        root.activateRequested(modelData.key);
                    else if (action === "menu")
                        root.secondaryRequested(modelData.key, x + width / 2);
                }

                CortetsuSurface {
                    anchors.fill: parent
                    anchors.margins: 2
                    radiusValue: CortetsuDesign.radiusSmall
                    baseColor: "transparent"
                    hoverColor: Qt.lighter(CortetsuDesign.colorTetsu, 1.18)
                    hovered: trayMouse.containsMouse
                    pressed: trayMouse.pressed
                    focused: trayItem.activeFocus
                    outlined: false
                }

                Image {
                    anchors.centerIn: parent
                    width: 22
                    height: 22
                    source: trayItem.modelData.iconSource
                    sourceSize.width: 48
                    sourceSize.height: 48
                    asynchronous: false
                    retainWhileLoading: true
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    mipmap: true
                }

                Rectangle {
                    objectName: `tray-${trayItem.modelData.key}-attention-indicator`
                    visible: trayItem.modelData.needsAttention ?? false
                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.topMargin: 3
                    anchors.rightMargin: 3
                    width: 6
                    height: 6
                    radius: width / 2
                    color: CortetsuDesign.colorVermillion
                }

                MouseArea {
                    id: trayMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                    cursorShape: Qt.PointingHandCursor
                    onPressed: trayItem.forceActiveFocus()
                    onWheel: wheel => {
                        const delta = wheel.angleDelta.y !== 0
                            ? wheel.angleDelta.y
                            : wheel.angleDelta.x;
                        if (delta !== 0)
                            root.scrollRequested(
                                trayItem.modelData.key,
                                delta,
                                wheel.angleDelta.y === 0
                            );
                        wheel.accepted = true;
                    }
                    onEntered: root.hoverRequested(
                        trayItem.modelData.key,
                        trayItem.x + trayItem.width / 2
                    )
                    onClicked: event => {
                        if (event.button === Qt.LeftButton)
                            trayItem.activatePrimary();
                        else if (event.button === Qt.RightButton) {
                            if (BottomHubTray.contextAction(trayItem.modelData) === "menu")
                                root.secondaryRequested(trayItem.modelData.key, trayItem.x + trayItem.width / 2);
                        } else
                            root.secondaryActivateRequested(trayItem.modelData.key);
                    }
                }

                Keys.onEnterPressed: trayItem.activatePrimary()
                Keys.onReturnPressed: trayItem.activatePrimary()
                Keys.onSpacePressed: trayItem.activatePrimary()
                Keys.onMenuPressed: root.secondaryRequested(
                    trayItem.modelData.key,
                    trayItem.x + trayItem.width / 2
                )

                CortetsuTooltip {
                    target: trayItem
                    hovered: trayMouse.containsMouse
                    focused: trayItem.activeFocus
                    text: trayItem.modelData.title
                }
            }
        }
    }
}
