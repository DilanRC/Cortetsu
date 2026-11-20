pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import "../components"
import "../theme"
import "CortetsuTypography.js" as CortetsuTypography
import "BottomHubTray.js" as BottomHubTray

Item {
    id: root

    // A popout or panel opened from this island is showing (CortetsuIsland).
    property bool engaged: false

    required property var items
    property var delegateModel: items
    property bool monochromeIcons: false
    property bool vertical: false
    property string tooltipPlacement: "above"
    // (key, modifiers) => bool: an open tray menu takes the keys typed here.
    property var menuKeyHandler: null
    // The popout open on this screen, so an icon's tooltip steps aside for
    // its own menu instead of covering a row of it.
    property string openPopoutName: ""
    readonly property real thickness: Math.max(48, CortetsuDesign.rowHeight)

    signal hoverRequested(string itemKey, real centerX)
    signal hoverEnded()
    signal activateRequested(string itemKey)
    signal secondaryRequested(string itemKey, real centerX)
    signal secondaryActivateRequested(string itemKey)
    signal scrollRequested(string itemKey, int delta, bool horizontal)

    implicitWidth: vertical ? thickness : trayRow.implicitWidth + 20
    implicitHeight: vertical ? trayRow.implicitHeight + 20 : thickness
    width: visible || vertical ? implicitWidth : 0
    height: visible || !vertical ? implicitHeight : 0
    visible: items.length > 0

    CortetsuIsland {}

    HubFlow {
        id: trayRow
        anchors.centerIn: parent
        vertical: root.vertical
        spacing: 2

        Repeater {
            model: root.delegateModel

            // design-lint: allow layout-small-target: trayMouse reaches 36 px into the 2 px gaps
            Item {
                id: trayItem
                required property var modelData
                objectName: `tray-${modelData.key}`
                enabled: modelData.enabled ?? true
                readonly property bool menuOpen: root.openPopoutName === BottomHubTray.menuName(modelData.key)
                // Focus from a click is not a reason to show the tooltip;
                // focus from Tab is.
                property bool pointerFocus: false
                onActiveFocusChanged: if (!activeFocus) pointerFocus = false

                implicitWidth: 34
                implicitHeight: 40
                width: implicitWidth
                height: implicitHeight
                activeFocusOnTab: enabled

                // Along the Hub, in segment coordinates: the icons are
                // centred inside the pill.
                function centerX(): real {
                    return root.vertical ? trayRow.y + y + height / 2 : trayRow.x + x + width / 2;
                }

                function activatePrimary(): void {
                    const action = BottomHubTray.primaryAction(modelData);
                    if (action === "activate")
                        root.activateRequested(modelData.key);
                    else if (action === "menu")
                        root.secondaryRequested(modelData.key, centerX());
                }

                CortetsuSurface {
                    anchors.fill: parent
                    anchors.margins: 2
                    radiusValue: height / 2
                    baseColor: "transparent"
                    hoverColor: Qt.lighter(CortetsuDesign.colorTetsu, 1.18)
                    hovered: trayMouse.containsMouse
                    pressed: trayMouse.pressed
                    focused: trayItem.activeFocus
                    outlined: false
                }

                Image {
                    objectName: `tray-${trayItem.modelData.key}-icon`
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
                    layer.enabled: root.monochromeIcons
                    layer.effect: MultiEffect {
                        colorization: 1
                        colorizationColor: CortetsuDesign.colorOnSurface
                    }
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

                // One pixel into the 2 px gap on each side: a 36 px target
                // with no overlap between neighbours.
                MouseArea {
                    id: trayMouse
                    anchors.fill: parent
                    anchors.leftMargin: -1
                    anchors.rightMargin: -1
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                    cursorShape: Qt.PointingHandCursor
                    onPressed: {
                        trayItem.pointerFocus = true;
                        trayItem.forceActiveFocus();
                    }
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
                        trayItem.centerX()
                    )
                    onExited: root.hoverEnded()
                    onClicked: event => {
                        if (event.button === Qt.LeftButton)
                            trayItem.activatePrimary();
                        else if (event.button === Qt.RightButton) {
                            if (BottomHubTray.contextAction(trayItem.modelData) === "menu")
                                root.secondaryRequested(trayItem.modelData.key, trayItem.centerX());
                        } else
                            root.secondaryActivateRequested(trayItem.modelData.key);
                    }
                }

                // An open tray menu takes the keys first. Keys emits the
                // specific signals (Return, Space) before onPressed and stops
                // there, so they ask too.
                function menuTakes(event): bool {
                    return !!root.menuKeyHandler?.(event.key, event.modifiers);
                }
                Keys.onPressed: event => event.accepted = trayItem.menuTakes(event)
                Keys.onEnterPressed: event => { if (!trayItem.menuTakes(event)) trayItem.activatePrimary(); }
                Keys.onReturnPressed: event => { if (!trayItem.menuTakes(event)) trayItem.activatePrimary(); }
                Keys.onSpacePressed: event => { if (!trayItem.menuTakes(event)) trayItem.activatePrimary(); }
                Keys.onMenuPressed: root.secondaryRequested(
                    trayItem.modelData.key,
                    trayItem.centerX()
                )

                CortetsuTooltip {
                    target: trayItem
                    hovered: trayMouse.containsMouse && !trayItem.menuOpen
                    focused: trayItem.activeFocus && !trayItem.pointerFocus && !trayItem.menuOpen
                    text: trayItem.modelData.title
                    placement: root.tooltipPlacement
                }
            }
        }
    }
}
