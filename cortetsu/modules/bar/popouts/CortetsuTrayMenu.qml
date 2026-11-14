pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Widgets
import "../../../components"
import "../../../theme"
import "../../BottomHubTray.js" as BottomHubTray

CortetsuPopupSurface {
    id: root

    required property PopoutState popouts
    required property QsMenuHandle trayItem
    readonly property real menuMinWidth: 152
    readonly property Item currentPage: stack.currentItem
    readonly property real menuContentWidth: currentPage?.fittedWidth ?? menuMinWidth
    readonly property real menuContentHeight: currentPage?.naturalHeight ?? 48
    readonly property int menuDepth: stack.depth
    // Read-only evidence for tests (BottomHub inspect): the row the keys act
    // on, and the row that draws the keyboard mark.
    readonly property int focusedRow: currentPage?.focusedIndex ?? -1
    function markedRow(): int {
        return currentPage?.markedIndex() ?? -1;
    }
    // Per row: "" or the toggle drawn, "check-on", "radio-off"...
    function rowToggles(): var {
        return currentPage?.toggleMarks() ?? [];
    }
    // Keep long DBus labels readable without letting one Steam title stretch
    // the popup. The width cap leaves the useful name prefix visible and
    // lets Text.ElideRight handle the rest.
    readonly property real menuMaxWidth: 220
    // Bind directly to the current page so StackView pushes and DBus row
    // updates resize the attached popup before ClipWrapper positions it.
    implicitWidth: menuContentWidth + CortetsuDesign.spacingStandard * 2
    implicitHeight: menuContentHeight + CortetsuDesign.spacingStandard * 2

    // Keys typed on the Hub's tray icon after a right click land here: the
    // keyboard stays on the Hub (OnDemand), the popout window never takes it.
    function handleKey(key: int, modifiers: int): bool {
        return currentPage?.handleKey(currentPage.focusedIndex, key, modifiers) ?? false;
    }

    // Back to the first level with focus on its first row, for a menu
    // opened again before it finished closing (Content.qml).
    function reset(): void {
        stack.pop(null, StackView.Immediate);
        const page = stack.currentItem;
        if (!page)
            return;
        page.focusedEntry = null;
        page.focusedIndex = -1;
        page.restoreFocus();
    }

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
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: CortetsuDesign.easeOut
                }
                NumberAnimation {
                    property: "opacity"
                    from: 0
                    to: 1
                    duration: CortetsuDesign.motionFastMs
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: CortetsuDesign.easeOut
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
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: CortetsuDesign.easeOut
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
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: CortetsuDesign.easeOut
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
                    // design-lint: allow motion-ease-in: popExit is the leaving submenu
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
            readonly property real naturalHeight: {
                return Math.max(48, childrenRect.height + padding * 2);
            }
            width: fittedWidth
            height: naturalHeight

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

            function toggleMarks(): var {
                const marks = [];
                for (let index = 0; index < entries.count; index++)
                    marks.push(entries.itemAt(index)?.toggleMark ?? "");
                return marks;
            }

            function markedIndex(): int {
                for (let index = 0; index < entries.count; index++)
                    if (entries.itemAt(index)?.outlined)
                        return index;
                return -1;
            }

            function focusEdge(direction): void {
                const start = direction > 0 ? -1 : entries.count;
                const index = nextSelectable(start, direction);
                if (index >= 0)
                    focusEntry(index);
            }

            // One key on the row at `index` (-1: none focused yet); true when used.
            function handleKey(index: int, key: int, modifiers: int): bool {
                const tab = key === Qt.Key_Tab || key === Qt.Key_Backtab;
                const entry = index >= 0 ? entries.itemAt(index)?.modelData ?? null : null;
                if (key === Qt.Key_Down || key === Qt.Key_Up || tab) {
                    const back = key === Qt.Key_Up || key === Qt.Key_Backtab
                        || (key === Qt.Key_Tab && (modifiers & Qt.ShiftModifier));
                    const target = nextSelectable(index >= 0 ? index : back ? entries.count : -1, back ? -1 : 1);
                    if (target >= 0)
                        focusEntry(target);
                    // Tab past the last row leaves the menu; arrows stop there.
                    return !tab || target >= 0;
                }
                if (key === Qt.Key_Home || key === Qt.Key_End) {
                    focusEdge(key === Qt.Key_Home ? 1 : -1);
                    return true;
                }
                if (key === Qt.Key_Return || key === Qt.Key_Enter || key === Qt.Key_Space) {
                    root.activateEntry(entry);
                    return true;
                }
                if (key === Qt.Key_Right && (entry?.hasChildren ?? false)) {
                    root.activateEntry(entry);
                    return true;
                }
                if (key === Qt.Key_Left && subMenu) {
                    stack.pop();
                    return true;
                }
                if (key === Qt.Key_Left || key === Qt.Key_Escape) {
                    root.popouts.hasCurrent = false;
                    return true;
                }
                return false;
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

            // A child Timer, not a queued call: a tray app that quits with its
            // menu open destroys this Column, and a queued call would then
            // run restoreFocus on the dead object.
            Timer {
                id: focusRestore
                interval: 0
                onTriggered: menu.restoreFocus()
            }

            Component.onCompleted: focusRestore.restart()

            QsMenuOpener {
                id: opener
                menu: menu.handle
            }

            Repeater {
                id: entries
                // QsMenuOpener.children is a live ObjectModel. Keeping it as
                // the Repeater model preserves asynchronous DBus menu updates.
                model: opener.children

                onItemAdded: focusRestore.restart()
                onItemRemoved: focusRestore.restart()

                CortetsuSurface {
                    id: entryItem
                    required property int index
                    required property QsMenuEntry modelData
                    readonly property bool separator: modelData?.isSeparator ?? false
                    onEnabledChanged: focusRestore.restart()
                    onSeparatorChanged: focusRestore.restart()
                    // A check box or radio row (nm-applet's "Enable Networking",
                    // a radio group of modes) shows its state.
                    readonly property int toggleType: modelData?.buttonType ?? QsMenuButtonType.None
                    readonly property bool toggleOn: (modelData?.checkState ?? Qt.Unchecked) === Qt.Checked
                    Accessible.role: toggleType === QsMenuButtonType.RadioButton ? Accessible.RadioButton
                        : toggleType === QsMenuButtonType.CheckBox ? Accessible.CheckBox : Accessible.MenuItem
                    Accessible.name: modelData?.text ?? ""
                    Accessible.checkable: toggleType !== QsMenuButtonType.None
                    Accessible.checked: toggleOn
                    readonly property string toggleMark: !toggleIcon.visible ? ""
                        : `${toggleType === QsMenuButtonType.RadioButton ? "radio" : "check"}-${toggleOn ? "on" : "off"}`
                    readonly property real naturalWidth: (modelData?.isSeparator ?? false)
                        ? 0
                        : labelMetrics.width
                            + (toggleIcon.visible ? toggleIcon.width + row.spacing : 0)
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
                    // The keys live on the Hub's tray icon and this window
                    // never takes the keyboard, so activeFocus never shows
                    // here: the row the keys act on is marked by its index.
                    readonly property bool keyboardRow: index === menu.focusedIndex
                        && (root.popouts?.keyboardHeld ?? false)
                    focused: keyboardRow
                    hovered: stateLayer.containsMouse
                    pressed: stateLayer.pressed
                    radiusValue: 0
                    hoverColor: Qt.alpha(CortetsuDesign.colorSurfaceGlassStrong, 0.9)
                    outlined: keyboardRow
                    outlineColor: keyboardRow ? CortetsuDesign.colorWashi : "transparent"

                    Row {
                        id: row
                        anchors.fill: parent
                        anchors.margins: CortetsuDesign.spacingCompact
                        spacing: CortetsuDesign.spacingStandard

                        CortetsuIcon {
                            id: toggleIcon
                            visible: entryItem.toggleType !== QsMenuButtonType.None
                            text: entryItem.toggleType === QsMenuButtonType.RadioButton
                                ? (entryItem.toggleOn ? "radio_button_checked" : "radio_button_unchecked")
                                : (entryItem.toggleOn ? "check_box" : "check_box_outline_blank")
                            color: entryItem.toggleOn ? CortetsuDesign.colorWashi : CortetsuDesign.colorOnSurfaceVariant
                            anchors.verticalCenter: parent.verticalCenter
                        }

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
                                - (toggleIcon.visible ? toggleIcon.width + row.spacing : 0)
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
                            color: entryItem.keyboardRow
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
                        event.accepted = menu.handleKey(index, event.key, event.modifiers);
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
