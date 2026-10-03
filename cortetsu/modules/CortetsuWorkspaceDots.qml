import QtQuick
import "../theme"

Row {
    id: root

    required property int workspaceCount
    required property int workspaceOffset
    required property int activeWsId
    required property var occupiedWorkspaceIds

    signal workspaceRequested(int workspaceId)

    function focusWorkspace(workspaceId): void {
        const target = root.children.find(child => child.wsId === workspaceId);
        if (target)
            target.forceActiveFocus();
    }

    spacing: 5

    Item {
        width: 3
        height: 1
    }

    Repeater {
        model: root.workspaceCount

        Item {
            id: workspaceDot
            objectName: `workspace-${wsId}`

            required property int index

            readonly property int wsId: root.workspaceOffset + index + 1
            readonly property bool active: wsId === root.activeWsId
            readonly property bool occupied: root.occupiedWorkspaceIds.includes(wsId)

            function activateWorkspace(workspaceId): void {
                root.workspaceRequested(workspaceId);
                restoreFocus.workspaceId = workspaceId;
                restoreFocus.restart();
            }

            width: active ? 18 : 8
            height: 28
            activeFocusOnTab: true

            Behavior on width {
                NumberAnimation {
                    duration: CortetsuDesign.motionStandardMs
                    easing.type: Easing.OutCubic
                }
            }

            Timer {
                id: restoreFocus
                interval: 60
                repeat: false
                property int workspaceId: workspaceDot.wsId
                onTriggered: root.focusWorkspace(workspaceId)
            }

            Rectangle {
                anchors.centerIn: parent
                width: workspaceDot.active ? 18 : 8
                height: 8
                radius: height / 2
                color: workspaceDot.active
                    ? CortetsuDesign.colorIndigo
                    : workspaceDot.occupied
                        ? CortetsuDesign.colorMuted
                        : Qt.darker(CortetsuDesign.colorMuted, 1.35)
                border.width: workspaceDot.activeFocus ? 1 : 0
                border.color: CortetsuDesign.colorWashi

                Behavior on width {
                    NumberAnimation {
                        duration: CortetsuDesign.motionStandardMs
                        easing.type: Easing.OutCubic
                    }
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onPressed: workspaceDot.forceActiveFocus()
                onClicked: workspaceDot.activateWorkspace(workspaceDot.wsId)
            }

            Keys.onEnterPressed: workspaceDot.activateWorkspace(workspaceDot.wsId)
            Keys.onReturnPressed: workspaceDot.activateWorkspace(workspaceDot.wsId)
            Keys.onSpacePressed: workspaceDot.activateWorkspace(workspaceDot.wsId)
            Keys.onLeftPressed: workspaceDot.activateWorkspace(
                Math.max(root.workspaceOffset + 1, workspaceDot.wsId - 1)
            )
            Keys.onRightPressed: workspaceDot.activateWorkspace(
                Math.min(root.workspaceOffset + root.workspaceCount, workspaceDot.wsId + 1)
            )
        }
    }

    Item {
        width: 7
        height: 1
    }
}
