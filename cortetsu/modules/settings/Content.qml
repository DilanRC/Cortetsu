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
import "sections"

// Settings: the Nexus on the left says where you are and how each domain
// stands; the right side holds the one page that is open. A page exists only
// while it is selected, so nothing outside it runs or rebuilds.
FocusScope {
    id: root

    required property var screenState
    required property var screen
    required property var controller

    property bool userCollapsed: false
    // Below this width the names give way to icons so the page keeps room.
    readonly property bool collapsed: userCollapsed || width < 940
    readonly property var category: controller.selectedCategory
    readonly property string alert: category ? settingsContext.alert[category.id] : ""
    readonly property string summary: category ? settingsContext.summary[category.id] : ""
    readonly property Item focusItem: Window.activeFocusItem
    readonly property alias page: pageLoader.item
    readonly property alias pageId: pageLoader.pageId

    function close(): void {
        root.screenState.settings = false;
    }

    function open(): void {
        nexus.focusSelected();
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

    // Keeps the control that has the focus inside the visible part.
    function revealFocus(): void {
        const item = root.focusItem;
        if (!item || !pageLoader.item || !root.within(item, pageLoader.item))
            return;
        const margin = CortetsuDesign.spacingStandard;
        const top = item.mapToItem(scroller.contentItem, 0, 0).y;
        const bottom = top + item.height;
        if (top - margin < scroller.contentY)
            scroller.contentY = Math.max(0, top - margin);
        else if (bottom + margin > scroller.contentY + scroller.height)
            scroller.contentY = Math.min(Math.max(0, scroller.contentHeight - scroller.height), bottom + margin - scroller.height);
    }

    onFocusItemChanged: root.revealFocus()

    // A shortcut, not a key handler: it works wherever the focus is, even
    // when a control that held it has just been disabled. It steps aside
    // only while the search has text, which Escape clears first.
    Shortcut {
        sequence: "Escape"
        enabled: !nexus.searchHoldsEscape
        onActivated: root.close()
    }

    Shortcut {
        sequences: [StandardKey.Find]
        onActivated: nexus.focusSearch()
    }

    SettingsContext {
        id: settingsContext
        screen: root.screen
        screenState: root.screenState
    }

    RowLayout {
        anchors.fill: parent
        spacing: CortetsuDesign.spacingSection

        ColumnLayout {
            Layout.fillHeight: true
            Layout.preferredWidth: root.collapsed ? 64 : 264
            Layout.maximumWidth: Layout.preferredWidth
            spacing: CortetsuDesign.spacingStandard

            Behavior on Layout.preferredWidth {
                NumberAnimation { duration: CortetsuDesign.motionStandardMs; easing.type: Easing.OutCubic }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 44
                Layout.leftMargin: root.collapsed ? 0 : CortetsuDesign.spacingCompact
                spacing: CortetsuDesign.spacingStandard

                CortetsuEvolvingMark {
                    Layout.preferredWidth: 28
                    Layout.preferredHeight: 28
                    Layout.alignment: root.collapsed ? Qt.AlignHCenter : Qt.AlignVCenter
                    phase: "Ascended"
                    animated: false
                    monochrome: true
                    monochromeColor: CortetsuDesign.colorWashi
                }

                CortetsuText {
                    Layout.fillWidth: true
                    visible: !root.collapsed
                    text: qsTr("Ajustes")
                    textSize: CortetsuTypography.titleMediumPx
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }
            }

            Nexus {
                id: nexus
                objectName: "nexus"
                Layout.fillWidth: true
                Layout.fillHeight: true
                controller: root.controller
                context: settingsContext
                collapsed: root.collapsed
                onCollapseRequested: root.userCollapsed = !root.userCollapsed
                onContentRequested: root.focusPage()
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: CortetsuDesign.spacingStandard

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 44
                spacing: CortetsuDesign.spacingStandard

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    CortetsuText {
                        objectName: "pageTitle"
                        Layout.fillWidth: true
                        text: root.category?.title ?? qsTr("Ajustes")
                        textSize: CortetsuTypography.titleLargePx
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }

                    // The current state of the page's domain, or what is
                    // wrong with it.
                    CortetsuText {
                        objectName: "pageSummary"
                        Layout.fillWidth: true
                        visible: text.length > 0
                        text: root.alert.length > 0 ? root.alert : root.summary
                        textSize: CortetsuTypography.bodySmallPx
                        color: root.alert.length > 0 ? CortetsuDesign.colorVermillion : CortetsuDesign.colorOnSurfaceVariant
                        elide: Text.ElideRight
                    }
                }

                SaveIndicator {
                    objectName: "saveIndicator"
                    Layout.alignment: Qt.AlignVCenter
                }

                CortetsuButton {
                    objectName: "closeSettings"
                    Layout.alignment: Qt.AlignVCenter
                    compact: true
                    icon: "close"
                    label: qsTr("Cerrar")
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
                contentHeight: pageLoader.implicitHeight + CortetsuDesign.spacingSpacious
                boundsBehavior: Flickable.StopAtBounds

                ScrollBar.vertical: ScrollBar {
                    policy: scroller.contentHeight > scroller.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
                }

                Behavior on contentY {
                    NumberAnimation { duration: CortetsuDesign.motionFastMs; easing.type: Easing.OutCubic }
                }

                Keys.onLeftPressed: nexus.focusSelected()

                Loader {
                    id: pageLoader

                    readonly property string pageId: root.controller.selectedId
                    readonly property var pages: ({
                        network: networkPage, bluetooth: bluetoothPage, audio: audioPage, display: displayPage,
                        power: powerPage, notifications: notificationsPage, input: inputPage,
                        appearance: appearancePage, wallpaper: wallpaperPage, desktop: desktopPage,
                        bottomhub: bottomHubPage, launcher: launcherPage, shortcuts: shortcutsPage, automation: automationPage, about: aboutPage
                    })

                    // Leaves room for the scroll bar so it never covers a
                    // control. Rows of label and switch stop growing before
                    // the two drift apart; a page that is a grid asks for all.
                    width: Math.min(scroller.width - CortetsuDesign.spacingStandard,
                        item?.wide === true ? Infinity : 820)
                    sourceComponent: pages[pageId] ?? null

                    onPageIdChanged: scroller.contentY = 0
                    onLoaded: arrive.restart()

                    NumberAnimation {
                        id: arrive
                        target: pageLoader
                        property: "opacity"
                        from: 0
                        to: 1
                        duration: CortetsuDesign.motionFastMs
                        easing.type: Easing.OutCubic
                    }
                }
            }
        }
    }

    Component { id: networkPage; NetworkPage { context: settingsContext } }
    Component { id: bluetoothPage; BluetoothSection { context: settingsContext } }
    Component { id: audioPage; AudioSection { context: settingsContext } }
    Component { id: displayPage; DisplaySection { context: settingsContext } }
    Component { id: powerPage; PowerSection { context: settingsContext } }
    Component { id: notificationsPage; NotificationsSection { context: settingsContext } }
    Component { id: inputPage; InputSection { context: settingsContext } }
    Component { id: appearancePage; AppearanceSection { context: settingsContext } }
    Component { id: wallpaperPage; WallpaperSection { context: settingsContext } }
    Component { id: desktopPage; DesktopSection { context: settingsContext } }
    Component { id: bottomHubPage; BottomHubSection { context: settingsContext } }
    Component { id: launcherPage; LauncherSection { context: settingsContext } }
    Component { id: shortcutsPage; ShortcutsSection { context: settingsContext } }
    Component { id: automationPage; AutomationSection { context: settingsContext } }
    Component { id: aboutPage; AboutSection { context: settingsContext } }
}
