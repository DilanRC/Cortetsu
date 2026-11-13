import QtQuick
import QtQuick.Effects
import "../theme"
import "CortetsuTypography.js" as CortetsuTypography

HubFlow {
    id: root

    required property int workspaceCount
    required property int workspaceOffset
    required property int activeWsId
    required property int displayType
    required property var occupiedWorkspaceIds
    property bool showAppIcons: false
    property bool monochromeAppIcons: false
    property var appIconSources: ({})
    readonly property color appIconTint: CortetsuDesign.colorWashi

    signal workspaceRequested(int workspaceId)

    function focusWorkspace(workspaceId): void {
        const target = root.children.find(child => child.wsId === workspaceId);
        if (target)
            target.forceActiveFocus();
    }

    spacing: 6

    Item {
        width: root.vertical ? 1 : 3
        height: root.vertical ? 3 : 1
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

            // The dot grows along the Hub: wider in a row, taller in a column.
            property real along: root.displayType === 1 ? 24 : showAppIcon ? 20 : active ? 20 : 6
            width: root.vertical ? 36 : along
            height: root.vertical ? along : 36
            activeFocusOnTab: true

            // design-lint: allow motion-layout-property: active and icon-bearing workspaces lengthen
            Behavior on along {
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
                width: root.vertical ? 6 : parent.width
                height: root.vertical ? parent.height : 6
                radius: Math.min(width, height) / 2
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
                layer.enabled: workspaceDot.showAppIcon && root.monochromeAppIcons
                layer.effect: MultiEffect {
                    colorization: 1
                    colorizationColor: root.appIconTint
                }
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
                anchors.leftMargin: root.vertical ? 0 : -root.spacing / 2
                anchors.rightMargin: root.vertical ? 0 : -root.spacing / 2
                anchors.topMargin: root.vertical ? -root.spacing / 2 : 0
                anchors.bottomMargin: root.vertical ? -root.spacing / 2 : 0
                cursorShape: Qt.PointingHandCursor
                onPressed: workspaceDot.forceActiveFocus()
                onClicked: workspaceDot.activateWorkspace(workspaceDot.wsId)
            }

            Keys.onEnterPressed: workspaceDot.activateWorkspace(workspaceDot.wsId)
            Keys.onReturnPressed: workspaceDot.activateWorkspace(workspaceDot.wsId)
            Keys.onSpacePressed: workspaceDot.activateWorkspace(workspaceDot.wsId)
            function step(delta: int): void {
                activateWorkspace(Math.max(root.workspaceOffset + 1,
                    Math.min(root.workspaceOffset + root.workspaceCount, wsId + delta)));
            }
            Keys.onLeftPressed: event => { if (root.vertical) event.accepted = false; else step(-1); }
            Keys.onRightPressed: event => { if (root.vertical) event.accepted = false; else step(1); }
            Keys.onUpPressed: event => { if (root.vertical) step(-1); else event.accepted = false; }
            Keys.onDownPressed: event => { if (root.vertical) step(1); else event.accepted = false; }
        }
    }

    Item {
        width: root.vertical ? 1 : 7
        height: root.vertical ? 7 : 1
    }
}
