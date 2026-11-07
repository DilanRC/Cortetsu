import QtQuick
import "../theme"
import "CortetsuTypography.js" as CortetsuTypography

Row {
    id: root

    required property int workspaceCount
    required property int workspaceOffset
    required property int activeWsId
    required property int displayType
    required property var occupiedWorkspaceIds
    property bool showAppIcons: false
    property var appIconSources: ({})

    signal workspaceRequested(int workspaceId)

    function focusWorkspace(workspaceId): void {
        const target = root.children.find(child => child.wsId === workspaceId);
        if (target)
            target.forceActiveFocus();
    }

    spacing: 6

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
            readonly property string appIconSource: root.appIconSources[String(wsId)] ?? ""
            readonly property bool showAppIcon: root.showAppIcons
                && root.displayType === 0 && occupied && appIconSource.length > 0

            function activateWorkspace(workspaceId): void {
                root.workspaceRequested(workspaceId);
                restoreFocus.workspaceId = workspaceId;
                restoreFocus.restart();
            }

            width: root.displayType === 1 ? 24 : showAppIcon ? 20 : active ? 20 : 6
            height: 36
            activeFocusOnTab: true

            // design-lint: allow motion-layout-property: active and icon-bearing workspaces widen
            Behavior on width {
                NumberAnimation {
                    duration: CortetsuDesign.motionStandardMs
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: CortetsuDesign.easeOut
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
                objectName: `workspace-shape-${workspaceDot.wsId}`
                anchors.centerIn: parent
                visible: root.displayType === 0
                width: parent.width
                height: 6
                radius: height / 2
                // Active: scheme accent. Occupied and empty: the scheme's text
                // colour at two strengths, so the row follows the wallpaper.
                color: workspaceDot.active
                    ? CortetsuDesign.colorPrimary
                    : Qt.alpha(CortetsuDesign.colorOnSurface, workspaceDot.occupied ? 0.6 : 0.25)
                Behavior on color { ColorAnimation { duration: CortetsuDesign.motionStandardMs } }
                border.width: workspaceDot.activeFocus ? 1 : 0
                border.color: CortetsuDesign.colorWashi
            }

            Image {
                objectName: `workspace-app-icon-${workspaceDot.wsId}`
                anchors.centerIn: parent
                width: 14
                height: 14
                source: workspaceDot.appIconSource
                visible: workspaceDot.showAppIcon
                asynchronous: true
                cache: true
                fillMode: Image.PreserveAspectFit
            }

            Text {
                objectName: `workspace-number-${workspaceDot.wsId}`
                anchors.centerIn: parent
                visible: root.displayType === 1
                text: workspaceDot.wsId
                color: workspaceDot.active
                    ? CortetsuDesign.colorPrimary
                    : Qt.alpha(CortetsuDesign.colorOnSurface, workspaceDot.occupied ? 0.72 : 0.38)
                font.family: CortetsuDesign.fontUi
                font.pixelSize: CortetsuTypography.labelMediumPx
                font.weight: workspaceDot.active ? Font.Bold : Font.Medium
            }

            // The hit area covers half the gap on each side, so the row has
            // no dead pixels between workspaces in either display mode.
            MouseArea {
                anchors.fill: parent
                anchors.leftMargin: -root.spacing / 2
                anchors.rightMargin: -root.spacing / 2
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
