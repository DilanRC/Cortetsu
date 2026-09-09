pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import "../../utils"
import ".."
import "../CortetsuDesign.js" as CortetsuDesign
import "../CortetsuTypography.js" as CortetsuTypography

Item {
    id: root

    required property var client
    required property ShellScreen screen
    required property bool selected
    required property bool overviewVisible

    signal activate(var client)
    signal closeRequested(var client)
    signal toggleFloatingRequested(var client)
    signal selectRequested(var client)

    readonly property string address:
        client?.lastIpcObject?.address ?? ""

    readonly property string className:
        client?.lastIpcObject?.class ?? ""

    readonly property string title:
        client?.title ??
        client?.lastIpcObject?.title ??
        className

    readonly property int workspaceId:
        client?.workspace?.id ?? 0

    readonly property string workspaceName:
        client?.workspace?.name ?? ""

    readonly property string monitorName:
        client?.monitor?.name ?? ""

    readonly property var nativeSize:
        client?.lastIpcObject?.size ?? [16, 9]

    readonly property real windowAspect: {
        const w = Number(nativeSize?.[0] ?? 16);
        const h = Number(nativeSize?.[1] ?? 9);

        if (!Number.isFinite(w) ||
            !Number.isFinite(h) ||
            w <= 0 ||
            h <= 0)
            return 16 / 9;

        return Math.max(0.65, Math.min(2.4, w / h));
    }

    readonly property url iconSource:
        Icons.getAppIcon(className, "image-missing")

    /*
     * The preview follows the actual window aspect ratio instead of forcing
     * every application into the same 16:9 box.
     */
    readonly property real previewHeight:
        Math.max(
            185,
            Math.min(
                365,
                width / windowAspect
            )
        )

    implicitHeight: previewHeight + 60

    opacity: pointer.drag.active ? 0.55 : 1
    scale: selected ? 1.018 : pointer.containsMouse ? 1.008 : 1

    Behavior on scale {
        NumberAnimation {
            duration: 115
            easing.type: Easing.OutCubic
        }
    }

    Rectangle {
        id: cardBg

        anchors.fill: parent

        radius: CortetsuDesign.radiusLarge

        color:
            root.selected
                ? Qt.alpha(
                    CortetsuDesign.colorSecondaryContainer,
                    0.96
                )
                : pointer.containsMouse
                    ? Qt.alpha(
                        CortetsuDesign.colorSurfaceHigh,
                        0.96
                    )
                    : Qt.alpha(
                        CortetsuDesign.colorSurfaceHigh,
                        0.93
                    )

        border.width: root.selected ? 2 : 1

        border.color:
            root.selected
                ? CortetsuDesign.colorPrimary
                : Qt.alpha(
                    CortetsuDesign.colorOutlineVariant,
                    0.82
                )

        Behavior on color {
            ColorAnimation {
                duration: 110
            }
        }
    }

    Rectangle {
        id: preview
        clip: true

        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right

        anchors.topMargin: 8
        anchors.leftMargin: 8
        anchors.rightMargin: 8

        implicitHeight: root.previewHeight

        radius: CortetsuDesign.radiusMedium

        color:
            CortetsuDesign.colorSurface

        Image {
            anchors.centerIn: parent

            width: Math.min(72, parent.width * 0.18)
            height: width

            source: root.iconSource

            fillMode: Image.PreserveAspectFit
            smooth: true
            mipmap: true

            opacity: 0.22
        }

        Rectangle {
            z: 10

            anchors.top: parent.top
            anchors.left: parent.left

            anchors.topMargin: 9
            anchors.leftMargin: 9

            implicitWidth: selectedLabel.implicitWidth + 18
            implicitHeight: 28

            radius: 999
            color: CortetsuDesign.colorSecondaryContainer
            border.width: 1
            border.color: CortetsuDesign.colorPrimary
            visible: root.selected

            Row {
                anchors.centerIn: parent
                spacing: 5

                CortetsuIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "check_circle"
                    color: CortetsuDesign.colorOnSecondaryContainer
                    iconSize: CortetsuTypography.iconSmallPx
                }

                CortetsuText {
                    id: selectedLabel
                    text: qsTr("Selected")
                    color: CortetsuDesign.colorOnSecondaryContainer
                    textSize: CortetsuTypography.labelSmallPx
                }
            }
        }

        // Constrain the ScreencopyView using the client's real size.
        ScreencopyView {
            anchors.centerIn: parent

            captureSource:
                root.client?.wayland ?? null // qmllint disable unresolved-type

            live: root.overviewVisible

            constraintSize.width:
                Math.min(
                    preview.width,
                    preview.height * root.windowAspect
                )

            constraintSize.height:
                Math.min(
                    preview.height,
                    preview.width / root.windowAspect
                )
        }

        /*
         * Workspace/monitor badge. One compact badge is enough; the overview
         * no longer repeats workspace headings around every row of cards.
         */
        Rectangle {
            anchors.left: parent.left
            anchors.bottom: parent.bottom

            anchors.leftMargin: 9
            anchors.bottomMargin: 9

            implicitWidth:
                workspaceLabel.implicitWidth + 16

            implicitHeight:
                workspaceLabel.implicitHeight + 8

            radius: 999

            color:
                Qt.alpha(
                    CortetsuDesign.colorSurface,
                    0.92
                )

            border.width: 1
            border.color:
                Qt.alpha(
                    CortetsuDesign.colorOutlineVariant,
                    0.75
                )

            CortetsuText {
                id: workspaceLabel

                anchors.centerIn: parent

                text:
                    root.workspaceName.startsWith("special:")
                        ? root.workspaceName
                        : `WS ${root.workspaceId} · ${root.monitorName}`

                textSize: CortetsuTypography.labelSmallPx

                color:
                    CortetsuDesign.colorOnSurface
            }
        }

        /*
         * Direct window actions appear only when useful.
         * z > pointer ensures these controls receive clicks first.
         */
        Row {
            z: 20

            anchors.top: parent.top
            anchors.right: parent.right

            anchors.topMargin: 9
            anchors.rightMargin: 9

            spacing: 6

            opacity:
                pointer.containsMouse || root.selected
                    ? 1
                    : 0

            Behavior on opacity {
                NumberAnimation {
                    duration: 100
                }
            }

            Rectangle {
                implicitWidth: 36
                implicitHeight: 36
                activeFocusOnTab: true

                radius: 999

                color:
                    floatMouse.containsMouse
                        ? CortetsuDesign.colorSecondaryContainer
                        : Qt.alpha(
                            CortetsuDesign.colorSurface,
                            0.94
                        )

                border.width: 1
                border.color:
                    activeFocus
                        ? CortetsuDesign.colorPrimary
                        : CortetsuDesign.colorOutlineVariant

                CortetsuIcon {
                    anchors.centerIn: parent

                    text:
                        root.client?.lastIpcObject?.floating
                            ? "select_window"
                            : "open_in_full"

                    iconSize: CortetsuTypography.iconMediumPx
                }

                MouseArea {
                    id: floatMouse

                    anchors.fill: parent
                    hoverEnabled: true

                    cursorShape:
                        Qt.PointingHandCursor

                    onPressed: parent.forceActiveFocus()

                    onClicked:
                        root.toggleFloatingRequested(
                            root.client
                        )
                }

                ToolTip.visible: floatMouse.containsMouse || parent.activeFocus
                ToolTip.text: root.client?.lastIpcObject?.floating
                    ? qsTr("Tile window")
                    : qsTr("Float window")
                ToolTip.delay: CortetsuDesign.motionDeliberateMs

                Keys.onEnterPressed:
                    root.toggleFloatingRequested(root.client)
                Keys.onReturnPressed:
                    root.toggleFloatingRequested(root.client)
                Keys.onSpacePressed:
                    root.toggleFloatingRequested(root.client)
            }

            Rectangle {
                implicitWidth: 36
                implicitHeight: 36
                activeFocusOnTab: true

                radius: 999

                color:
                    closeMouse.containsMouse
                        ? Qt.darker(CortetsuDesign.colorVermillion, 1.5)
                        : Qt.alpha(
                            CortetsuDesign.colorSurface,
                            0.94
                        )

                border.width: 1
                border.color:
                    closeMouse.containsMouse
                        ? CortetsuDesign.colorVermillion
                        : activeFocus
                            ? CortetsuDesign.colorPrimary
                            : CortetsuDesign.colorOutlineVariant

                CortetsuIcon {
                    anchors.centerIn: parent

                    text: "close"

                    color:
                        closeMouse.containsMouse
                            ? CortetsuDesign.colorOnSurface
                            : CortetsuDesign.colorOnSurface

                    iconSize: CortetsuTypography.iconMediumPx
                }

                MouseArea {
                    id: closeMouse

                    anchors.fill: parent
                    hoverEnabled: true

                    cursorShape:
                        Qt.PointingHandCursor

                    onPressed: parent.forceActiveFocus()

                    onClicked:
                        root.closeRequested(
                            root.client
                        )
                }

                ToolTip.visible: closeMouse.containsMouse || parent.activeFocus
                ToolTip.text: qsTr("Close window")
                ToolTip.delay: CortetsuDesign.motionDeliberateMs

                Keys.onEnterPressed:
                    root.closeRequested(root.client)
                Keys.onReturnPressed:
                    root.closeRequested(root.client)
                Keys.onSpacePressed:
                    root.closeRequested(root.client)
            }
        }
    }

    Row {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom

        anchors.leftMargin: 13
        anchors.rightMargin: 13
        anchors.bottomMargin: 9

        spacing: 10

        Image {
            width: 30
            height: 30

            anchors.verticalCenter:
                parent.verticalCenter

            source: root.iconSource

            fillMode:
                Image.PreserveAspectFit

            smooth: true
            mipmap: true
        }

        Column {
            width: parent.width - 40

            anchors.verticalCenter:
                parent.verticalCenter

            spacing: 0

            CortetsuText {
                width: parent.width

                text: root.title

                textSize: CortetsuTypography.bodyPx

                elide: Text.ElideRight
            }

            CortetsuText {
                width: parent.width

                text:
                    root.className

                textSize: CortetsuTypography.labelSmallPx

                color:
                    CortetsuDesign.colorOutline

                elide: Text.ElideRight
            }
        }
    }

    /*
     * Tiny drag source so the card remains laid out by Grid while being
     * dragged. Drop targets receive WindowCard as drag.source.
     */
    Item {
        id: dragPoint

        x: root.width / 2
        y: root.previewHeight / 2

        width: 1
        height: 1

        Drag.active: pointer.drag.active || dragHandler.active
        Drag.source: root
        Drag.keys: ["overview-window"]
        Drag.supportedActions: Qt.MoveAction
        Drag.proposedAction: Qt.MoveAction
        Drag.hotSpot.x: 0
        Drag.hotSpot.y: 0
    }

    DragHandler {
        id: dragHandler
        target: dragPoint
        acceptedButtons: Qt.LeftButton
        grabPermissions: PointerHandler.CanTakeOverFromAnything
        onActiveChanged: {
            if (!active && dragPoint.Drag.active)
                dragPoint.Drag.drop();
        }
    }

    MouseArea {
        id: pointer

        z: 2

        anchors.fill: parent

        hoverEnabled: true

        acceptedButtons:
            Qt.LeftButton |
            Qt.MiddleButton |
            Qt.RightButton

        cursorShape:
            drag.active
                ? Qt.ClosedHandCursor
                : Qt.PointingHandCursor

        onEntered:
            root.selectRequested(root.client)

        onPressed:
            root.selectRequested(root.client)

        onClicked: event => {
            if (event.button === Qt.LeftButton)
                root.activate(root.client);
            else if (event.button === Qt.MiddleButton)
                root.closeRequested(root.client);
            else if (event.button === Qt.RightButton)
                root.toggleFloatingRequested(root.client);
        }

        onReleased: {
            if (dragPoint.Drag.active)
                dragPoint.Drag.drop();

            Qt.callLater(() => {
                dragPoint.x = root.width / 2;
                dragPoint.y = root.previewHeight / 2;
            });
        }
    }
}
