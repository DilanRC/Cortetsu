pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import "../../components"
import "../../theme"
import ".."
import "../CortetsuTypography.js" as CortetsuTypography
import "controls"

// Settings: the sidebar on the left lists the categories; the main panel
// holds the one page that is open, under a header that says where it is and
// leads back. A page exists only while it is shown, so nothing outside it
// runs or rebuilds.
FocusScope {
    id: root

    required property var screenState
    required property var screen
    required property var controller

    // Automatic density follows the window until the user chooses a mode.
    property int railMode: 0 // 0 automatic, 1 expanded, -1 compact
    readonly property bool collapsed: railMode === 0 ? width < 1000 : railMode < 0
    readonly property var category: controller.selectedCategory
    readonly property var subpage: controller.selectedPage
    readonly property string pageId: controller.pageId
    readonly property string alert: subpage ? settingsContext.pageAlert(pageId) : category ? settingsContext.categoryAlert(category.id) : ""
    readonly property string summary: subpage ? settingsContext.pageSummary(pageId) : pageId === "about" ? settingsContext.pageSummary("about") : ""
    readonly property Item focusItem: Window.activeFocusItem
    readonly property alias page: pageLoader.item
    // Where each page was scrolled to, so going back lands where you were.
    property var positions: ({})
    property bool returning: false
    // The page column, shared by the header so both line up.
    readonly property real columnWidth: Math.min(scroller.width - root.gutter * 2, page?.maxWidth ?? 780)
    readonly property real gutter: CortetsuDesign.spacingSpacious

    function close(): void {
        root.screenState.settings = false;
    }

    function open(): void {
        nexus.focusSelected();
    }

    function goBack(): void {
        if (!root.controller.canGoBack)
            return;
        root.returning = true;
        root.controller.back();
    }

    function within(item, ancestor): bool {
        for (let current = item; current; current = current.parent) {
            if (current === ancestor)
                return true;
        }
        return false;
    }

    function focusPage(): void {
        if (!pageLoader.item)
            return;
        const first = pageLoader.item.nextItemInFocusChain(true);
        if (first && root.within(first, pageLoader.item))
            first.forceActiveFocus(Qt.TabFocusReason);
    }

    function scrollTo(item, margin): void {
        const top = item.mapToItem(scroller.contentItem, 0, 0).y;
        const bottom = top + item.height;
        if (top - margin < scroller.contentY)
            scroller.contentY = Math.max(0, top - margin);
        else if (bottom + margin > scroller.contentY + scroller.height)
            scroller.contentY = Math.min(Math.max(0, scroller.contentHeight - scroller.height), bottom + margin - scroller.height);
    }

    // Keeps the control that has the focus inside the visible part.
    function revealFocus(): void {
        const item = root.focusItem;
        if (item && pageLoader.item && root.within(item, pageLoader.item))
            root.scrollTo(item, CortetsuDesign.spacingStandard);
    }

    // The item a search result named: the first visible one whose title is
    // the setting. Rows, groups and choices all expose `title`.
    function findTitled(item, title) {
        if (!item || item.visible === false)
            return null;
        if (item !== pageLoader.item && item.title === title)
            return item;
        const children = item.children ?? [];
        for (let i = 0; i < children.length; ++i) {
            const found = root.findTitled(children[i], title);
            if (found)
                return found;
        }
        return null;
    }

    function revealSetting(): void {
        const title = root.controller.reveal;
        if (!title || !pageLoader.item)
            return;
        root.controller.reveal = "";
        const target = root.findTitled(pageLoader.item, title);
        if (!target)
            return;
        if (target.collapsible === true)
            target.expanded = true;
        scroller.contentY = Math.max(0, Math.min(scroller.contentHeight - scroller.height,
            target.mapToItem(scroller.contentItem, 0, 0).y - scroller.height / 3));
        // A group or a grid is not a stop itself: its first control is.
        const stop = target.activeFocusOnTab ? target : target.nextItemInFocusChain(true);
        if (stop && root.within(stop, target))
            stop.forceActiveFocus(Qt.OtherFocusReason);
        highlight.show(target);
    }

    onFocusItemChanged: root.revealFocus()
    Connections {
        target: root.controller
        function onRevealChanged(): void { Qt.callLater(root.revealSetting); }
    }

    // A shortcut, not a key handler: it works wherever the focus is, even
    // when a control that held it has just been disabled. It steps aside
    // only while the search has text, which Escape clears first.
    Shortcut {
        sequence: "Escape"
        enabled: !nexus.searchHoldsEscape && root.focusItem?.objectName !== "entry"
        onActivated: root.close()
    }

    Shortcut {
        sequences: [StandardKey.Find]
        onActivated: nexus.focusSearch()
    }

    Shortcut {
        sequences: [StandardKey.Back, "Alt+Left"]
        onActivated: root.goBack()
    }

    Shortcut {
        sequences: ["Ctrl+PgDown", "Ctrl+Tab"]
        onActivated: {
            root.controller.selectNeighbour(1);
            nexus.focusSelected();
        }
    }

    Shortcut {
        sequences: ["Ctrl+PgUp", "Ctrl+Shift+Tab"]
        onActivated: {
            root.controller.selectNeighbour(-1);
            nexus.focusSelected();
        }
    }

    SettingsContext {
        id: settingsContext
        screen: root.screen
        screenState: root.screenState
    }

    PageRegistry {
        id: registry
        context: settingsContext
        controller: root.controller
    }

    RowLayout {
        anchors.fill: parent
        spacing: CortetsuDesign.spacingComfortable

        Nexus {
            id: nexus
            objectName: "nexus"
            Layout.fillHeight: true
            Layout.preferredWidth: root.collapsed ? 56 : 268
            Layout.maximumWidth: Layout.preferredWidth
            controller: root.controller
            context: settingsContext
            collapsed: root.collapsed
            onCollapseRequested: root.railMode = root.collapsed ? 1 : -1
            onContentRequested: root.focusPage()

            Behavior on Layout.preferredWidth {
                NumberAnimation { duration: CortetsuDesign.motionStandardMs; easing.type: Easing.BezierSpline; easing.bezierCurve: CortetsuDesign.easeOut }
            }
        }

        // The main panel: its own material, set apart from the sidebar.
        Item {
            id: main
            objectName: "mainPanel"
            Layout.fillWidth: true
            Layout.fillHeight: true

            CortetsuInkPanel {
                anchors.fill: parent
                radius: CortetsuDesign.radiusLarge
                ground: CortetsuDesign.colorTetsu
                groundAlpha: CortetsuDesign.materialStyle === 1 ? 0.92 : 0.6
                washAlpha: CortetsuDesign.materialWashAlpha * 0.5
                washX: 0.9
                grain: CortetsuDesign.materialGrain * 0.5
                marks: false
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.topMargin: CortetsuDesign.spacingSpacious
                spacing: CortetsuDesign.spacingStandard

                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: header.implicitHeight

                    SettingsHeader {
                        id: header
                        x: Math.round((parent.width - width) / 2)
                        width: root.columnWidth
                        category: root.category
                        subpage: root.subpage
                        summary: root.alert.length > 0 ? root.alert : root.summary
                        alerting: root.alert.length > 0
                        canGoBack: root.controller.canGoBack
                        onBackRequested: root.goBack()
                        onCategoryRequested: root.controller.select(root.category.id)
                    }

                    CortetsuButton {
                        objectName: "closeSettings"
                        anchors.right: parent.right
                        anchors.rightMargin: CortetsuDesign.spacingStandard
                        anchors.top: parent.top
                        compact: true
                        icon: "close"
                        label: ""
                        tooltipText: qsTr("Cerrar")
                        Accessible.name: qsTr("Cerrar Ajustes")
                        onClicked: root.close()
                    }
                }

                Flickable {
                    id: scroller
                    objectName: "pageScroller"
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    contentWidth: width
                    contentHeight: pageLoader.implicitHeight + CortetsuDesign.spacingSection
                    boundsBehavior: Flickable.StopAtBounds

                    ScrollBar.vertical: ScrollBar {
                        policy: scroller.contentHeight > scroller.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
                    }

                    Behavior on contentY {
                        enabled: !root.returning
                        NumberAnimation { duration: CortetsuDesign.motionFastMs; easing.type: Easing.BezierSpline; easing.bezierCurve: CortetsuDesign.easeOut }
                    }

                    Keys.onLeftPressed: nexus.focusSelected()

                    Loader {
                        id: pageLoader

                        readonly property string pageId: root.pageId
                        property string shownId: ""

                        // Equal gutters on both sides: one of them holds the
                        // scroll bar, so it never covers a control.
                        x: root.gutter
                        width: scroller.width - root.gutter * 2
                        sourceComponent: registry.component(pageId)

                        onPageIdChanged: {
                            if (shownId)
                                root.positions[shownId] = scroller.contentY;
                            shownId = pageId;
                        }
                        onLoaded: {
                            scroller.contentY = root.returning ? root.positions[pageId] ?? 0 : 0;
                            root.returning = false;
                            arrive.restart();
                            Qt.callLater(root.revealSetting);
                        }

                        ParallelAnimation {
                            id: arrive
                            NumberAnimation {
                                target: pageLoader
                                property: "opacity"
                                from: 0
                                to: 1
                                duration: CortetsuDesign.motionStandardMs
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: CortetsuDesign.easeOut
                            }
                            NumberAnimation {
                                target: pageLoader
                                property: "y"
                                from: CortetsuDesign.materialStyle === 2 ? 8 : 20
                                to: 0
                                duration: CortetsuDesign.motionStandardMs
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: CortetsuDesign.easeOut
                            }
                        }
                    }

                    // Marks the setting a search result opened, then fades.
                    Rectangle {
                        id: highlight
                        objectName: "revealHighlight"
                        property Item target: null
                        function show(item): void {
                            target = item;
                            const at = item.mapToItem(scroller.contentItem, 0, 0);
                            x = at.x - 4;
                            y = at.y - 4;
                            width = item.width + 8;
                            height = item.height + 8;
                            fadeOut.stop();
                            opacity = 1;
                            hold.restart();
                        }
                        visible: opacity > 0
                        opacity: 0
                        radius: CortetsuDesign.radiusMedium
                        color: Qt.alpha(CortetsuDesign.colorPrimary, 0.12)
                        border.width: 2
                        border.color: CortetsuDesign.colorIndicator

                        // How long the mark stays is reading time, not motion:
                        // it holds even with reduced motion.
                        Timer {
                            id: hold
                            interval: 1400
                            onTriggered: fadeOut.restart()
                        }

                        NumberAnimation {
                            id: fadeOut
                            target: highlight
                            property: "opacity"
                            to: 0
                            duration: CortetsuDesign.motionDeliberateMs
                        }
                    }
                }
            }
        }
    }
}
