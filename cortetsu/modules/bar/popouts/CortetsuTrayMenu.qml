pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Widgets
import "../../../components"
import "../../CortetsuDesign.js" as CortetsuDesign
import "../../BottomHubTray.js" as BottomHubTray

CortetsuPopupSurface {
    id: root

    required property PopoutState popouts
    required property QsMenuHandle trayItem
    property real menuContentHeight: 72
    property real menuContentWidth: 184
    readonly property real menuMinWidth: 152
    // Keep long DBus labels readable without letting one Steam title stretch
    // the popup. The width cap leaves the useful name prefix visible and
    // lets Text.ElideRight handle the rest.
    readonly property real menuMaxWidth: 220
    // StackView does not propagate the implicit size of a dynamically-created
    // Column. Keep the popup measurable so the menu is not rendered as an
    // empty square while its DBus entries are loading.
    implicitWidth: menuContentWidth + CortetsuDesign.spacingStandard * 2
    implicitHeight: menuContentHeight + CortetsuDesign.spacingStandard * 2

    StackView {
        id: stack
        anchors.fill: parent
        anchors.margins: CortetsuDesign.spacingStandard
        initialItem: menuComponent

        pushEnter: Transition {
            ParallelAnimation {
                NumberAnimation {
                    property: "x"
                    from: CortetsuDesign.spacingComfortable
                    to: 0
                    duration: CortetsuDesign.motionStandardMs
                    easing.type: Easing.OutCubic
                }
                NumberAnimation {
                    property: "opacity"
                    from: 0
                    to: 1
                    duration: CortetsuDesign.motionFastMs
                    easing.type: Easing.OutCubic
                }
            }
        }

        pushExit: Transition {
            ParallelAnimation {
                NumberAnimation {
                    property: "x"
                    from: 0
                    to: -CortetsuDesign.spacingCompact
                    duration: CortetsuDesign.motionStandardMs
                    easing.type: Easing.OutCubic
                }
                NumberAnimation {
                    property: "opacity"
                    from: 1
                    to: 0.72
                    duration: CortetsuDesign.motionFastMs
                }
            }
        }

        popEnter: Transition {
            ParallelAnimation {
                NumberAnimation {
                    property: "x"
                    from: -CortetsuDesign.spacingCompact
                    to: 0
                    duration: CortetsuDesign.motionStandardMs
                    easing.type: Easing.OutCubic
                }
                NumberAnimation {
                    property: "opacity"
                    from: 0.72
                    to: 1
                    duration: CortetsuDesign.motionFastMs
                }
            }
        }

        popExit: Transition {
            ParallelAnimation {
                NumberAnimation {
                    property: "x"
                    from: 0
                    to: CortetsuDesign.spacingComfortable
                    duration: CortetsuDesign.motionFastMs
                    easing.type: Easing.InCubic
                }
                NumberAnimation {
                    property: "opacity"
                    from: 1
                    to: 0
                    duration: CortetsuDesign.motionFastMs
                }
            }
        }
    }

    function activateEntry(entry): void {
        if (!entry || !entry.enabled || entry.isSeparator)
            return;
        if (entry.hasChildren)
            stack.push(menuComponent, { handle: entry, subMenu: true });
        else {
            entry.triggered();
            root.popouts.hasCurrent = false;
        }
    }

    Component {
        id: menuComponent

        Column {
            id: menu
            property QsMenuHandle handle: root.trayItem
            property bool subMenu: false
            property int focusedIndex: -1
            property QsMenuEntry focusedEntry: null
            padding: CortetsuDesign.spacingCompact
            spacing: CortetsuDesign.spacingUnit
            readonly property real fittedWidth: {
                let widest = 0;
                for (let i = 0; i < entries.count; i++) {
                    const item = entries.itemAt(i);
                    if (item)
                        widest = Math.max(widest, item.naturalWidth);
                }
                return Math.max(root.menuMinWidth, Math.min(root.menuMaxWidth, widest + padding * 2));
            }
            width: fittedWidth
            height: Math.max(
                48,
                childrenRect.height + padding * 2
                    + (subMenu ? CortetsuDesign.spacingStandard + 48 : 0)
            )

            onHeightChanged: root.menuContentHeight = height
            onWidthChanged: root.menuContentWidth = width

            function selectable(index): bool {
                const item = entries.itemAt(index);
                return item !== null && item.enabled && !item.separator;
            }

            function nextSelectable(fromIndex, direction): int {
                return BottomHubTray.nextSelectable(entries.count, fromIndex, direction, index => selectable(index));
            }

            function focusEntry(index): void {
                if (!selectable(index))
                    return;
                focusedIndex = index;
                focusedEntry = entries.itemAt(index).modelData;
                entries.itemAt(index).forceActiveFocus();
            }

            function focusEdge(direction): void {
                const start = direction > 0 ? -1 : entries.count;
                const index = nextSelectable(start, direction);
                if (index >= 0)
                    focusEntry(index);
            }

            function restoreFocus(): void {
                const currentIndex = focusedEntry
                    ? BottomHubTray.indexOfEntry(entries.count, index => entries.itemAt(index)?.modelData, focusedEntry)
                    : -1;
                if (currentIndex >= 0 && selectable(currentIndex)) {
                    focusEntry(currentIndex);
                    return;
                }
                if (focusedIndex >= 0 && selectable(focusedIndex)) {
                    focusEntry(focusedIndex);
                    return;
                }
                focusedEntry = null;
                focusedIndex = -1;
                focusEdge(1);
            }

            Component.onCompleted: Qt.callLater(restoreFocus)

            QsMenuOpener {
                id: opener
                menu: menu.handle
            }

            Repeater {
                id: entries
                // QsMenuOpener.children is a live ObjectModel. Keeping it as
                // the Repeater model preserves asynchronous DBus menu updates.
                model: opener.children

                onItemAdded: Qt.callLater(menu.restoreFocus)
                onItemRemoved: Qt.callLater(menu.restoreFocus)

                CortetsuSurface {
                    required property QsMenuEntry modelData
                    readonly property bool separator: modelData?.isSeparator ?? false
                    onEnabledChanged: Qt.callLater(menu.restoreFocus)
                    onSeparatorChanged: Qt.callLater(menu.restoreFocus)
                    readonly property real naturalWidth: (modelData?.isSeparator ?? false)
                        ? 0
                        : labelMetrics.width
                            + (menuIcon.visible ? menuIcon.width + row.spacing : 0)
                            + (submenuIcon.visible ? submenuIcon.width + row.spacing : 0)
                            + CortetsuDesign.spacingCompact * 2
                    enabled: (modelData?.enabled ?? false) && !separator
                    activeFocusOnTab: enabled
                    width: Math.max(0, menu.width - menu.padding * 2)
                    implicitHeight: (modelData?.isSeparator ?? false)
                        ? 1
                        : row.implicitHeight + CortetsuDesign.spacingStandard
                    baseColor: (modelData?.isSeparator ?? false) ? CortetsuDesign.colorOutlineVariant : "transparent"
                    disabled: !enabled
                    focused: activeFocus
                    hovered: stateLayer.containsMouse
                    pressed: stateLayer.pressed
                    radiusValue: 0
                    hoverColor: Qt.alpha(CortetsuDesign.colorSurfaceGlassStrong, 0.9)
                    outlined: activeFocus
                    outlineColor: activeFocus ? CortetsuDesign.colorWashi : "transparent"

                    Row {
                        id: row
                        anchors.fill: parent
                        anchors.margins: CortetsuDesign.spacingCompact
                        spacing: CortetsuDesign.spacingStandard

                        IconImage {
                            id: menuIcon
                            visible: (modelData?.icon ?? "") !== ""
                            implicitSize: 16
                            source: modelData?.icon ?? ""
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        CortetsuText {
                            id: label
                            width: Math.max(0, row.width
                                - (menuIcon.visible ? menuIcon.width + row.spacing : 0)
                                - (submenuIcon.visible ? submenuIcon.width + row.spacing : 0))
                            text: modelData?.text ?? ""
                            color: (modelData?.enabled ?? false)
                                ? CortetsuDesign.colorOnSurface
                                : CortetsuDesign.colorOutline
                            elide: Text.ElideRight
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        CortetsuIcon {
                            id: submenuIcon
                            visible: modelData?.hasChildren ?? false
                            text: "chevron_right"
                            color: activeFocus
                                ? CortetsuDesign.colorWashi
                                : CortetsuDesign.colorOnSurfaceVariant
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    TextMetrics {
                        id: labelMetrics
                        text: modelData?.text ?? ""
                        font: label.font
                    }

                    CortetsuStateLayer {
                        id: stateLayer
                        anchors.fill: parent
                        radius: parent.radiusValue
                        disabled: !parent.enabled
                        onPressed: parent.forceActiveFocus()
                        onContainsMouseChanged: {
                            if (containsMouse)
                                menu.focusEntry(index);
                        }
                        onClicked: root.activateEntry(modelData)
                    }

                    Keys.onPressed: event => {
                        const tabForward = event.key === Qt.Key_Tab && !(event.modifiers & Qt.ShiftModifier);
                        const tabBackward = event.key === Qt.Key_Tab && (event.modifiers & Qt.ShiftModifier);
                        if (event.key === Qt.Key_Down || tabForward) {
                            const next = menu.nextSelectable(index, 1);
                            if (next >= 0)
                                menu.focusEntry(next);
                            event.accepted = !tabForward || next >= 0;
                        } else if (event.key === Qt.Key_Up || tabBackward) {
                            const previous = menu.nextSelectable(index, -1);
                            if (previous >= 0)
                                menu.focusEntry(previous);
                            event.accepted = !tabBackward || previous >= 0;
                        } else if (event.key === Qt.Key_Home) {
                            menu.focusEdge(1);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_End) {
                            menu.focusEdge(-1);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                            root.activateEntry(modelData);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Right && (modelData?.hasChildren ?? false)) {
                            root.activateEntry(modelData);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Left && menu.subMenu) {
                            stack.pop();
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Left && !menu.subMenu) {
                            root.popouts.hasCurrent = false;
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Escape) {
                            root.popouts.hasCurrent = false;
                            event.accepted = true;
                        }
                    }
                }
            }

            CortetsuButton {
                visible: menu.subMenu
                compact: true
                icon: "chevron_left"
                label: qsTr("Atrás")
                onClicked: stack.pop()
                Keys.onEscapePressed: root.popouts.hasCurrent = false
            }
        }
    }
}
