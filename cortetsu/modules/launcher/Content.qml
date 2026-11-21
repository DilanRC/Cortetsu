pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import Quickshell
import ".."
import "../../components"
import "../../theme"
import "../CortetsuOverlayPolicy.js" as SurfacePolicy
import "../CortetsuSearchBar.qml"
import "services"

Item {
    id: root

    required property var screenState
    required property var panels
    required property real maxHeight
    property string pendingWallpaperPath: ""
    // Browse mode: the empty search shows a category of apps.
    property string category: "home"
    readonly property bool browsing: search.text.length === 0
    readonly property bool showCategories: browsing && Apps.categories.length > 2
    // The side column (commands, recent apps) while browsing, and only where
    // the grid and the column fit side by side. Its rows are shortcuts with
    // keyboard equivalents: the prefix for commands, and the recent apps
    // lead the browse grid, so Tab keeps moving through the results.
    readonly property bool showSide: browsing && !list.showWallpapers && (QsWindow.window?.width ?? 0) >= 1360
    readonly property int sideWidth: 280

    function cycleCategory(step: int): void {
        const ids = Apps.categories.map(item => item.id);
        const at = Math.max(0, ids.indexOf(root.category));
        root.category = ids[(at + step + ids.length) % ids.length];
    }

    readonly property int padding: CortetsuDesign.spacingStandard
    readonly property int rounding: CortetsuDesign.radiusLarge
    function focusSearch(): void {
        if (SurfacePolicy.isPreview(root.screenState, "launcher"))
            return;
        if (root.screenState?.launcher && CortetsuShellState.launcherQuery) {
            search.text = CortetsuShellState.launcherQuery;
            CortetsuShellState.launcherQuery = "";
        }
        search.forceActiveFocus();
        search.cursorPosition = search.text.length;
    }

    function requestWallpaper(path: string): void {
        const target = String(path ?? "").trim();
        if (!target || CortetsuWallpapers.applying)
            return;
        if (target === CortetsuWallpapers.actualCurrent) {
            pendingWallpaperPath = "";
            SurfacePolicy.closeOn(root.screenState, "launcher");
            return;
        }
        if (CortetsuWallpapers.apply(target))
            pendingWallpaperPath = target;
    }

    implicitWidth: listWrapper.width + padding * 2 + (showSide ? sideWidth + CortetsuDesign.spacingStandard : 0)
    implicitHeight: Math.max(showSide ? side.implicitHeight + padding * 2 : 0,
        padding +
        search.implicitHeight +
        CortetsuDesign.spacingStandard +
        (root.showCategories ? categoryRow.implicitHeight + CortetsuDesign.spacingCompact : 0) +
        listWrapper.implicitHeight +
        padding)

    CortetsuPopupSurface {
        anchors.fill: parent
        baseColor: Qt.alpha(CortetsuDesign.colorTetsu, 0.94)
        outlineColor: Qt.alpha(CortetsuDesign.colorOutlineVariant, 0.16)
    }

    CortetsuSearchBar {
        id: search
        objectName: "launcherSearch"
        onActiveFocusChanged: {
            if (activeFocus && SurfacePolicy.isPreview(root.screenState, "launcher"))
                SurfacePolicy.promotePreview(CortetsuShellState.allStates(), root.screenState, "launcher");
        }
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: root.padding
        anchors.leftMargin: root.padding
        anchors.rightMargin: root.padding + (root.showSide ? root.sideWidth + CortetsuDesign.spacingStandard : 0)
        placeholderText: qsTr("Buscar aplicaciones o comandos…")

        onAccepted: {
            const currentItem = list.currentList?.currentItem;
            if (currentItem) {
                if (list.showWallpapers) {
                    root.requestWallpaper(currentItem.modelData.path);
                } else if (text.startsWith(CortetsuConfig.actionPrefix)) {
                    if (text.startsWith(`${CortetsuConfig.actionPrefix}calc `))
                        currentItem.onClicked();
                    else
                        currentItem.modelData.onClicked(list.currentList);
                } else {
                    Apps.launch(currentItem.modelData);
                    SurfacePolicy.closeOn(root.screenState, "launcher");
                }
            }
        }

        Keys.onUpPressed: {
            if (list.showWallpapers)
                list.currentList?.decrementCurrentIndex();
            else
                list.currentList?.moveGridUp();
        }

        Keys.onDownPressed: {
            if (list.showWallpapers)
                list.currentList?.incrementCurrentIndex();
            else
                list.currentList?.moveGridDown();
        }

        Keys.onLeftPressed: event => {
            if (root.showCategories && (event.modifiers & Qt.ControlModifier)) {
                root.cycleCategory(-1);
                event.accepted = true;
                return;
            }
            if (list.showWallpapers)
                list.currentList?.decrementCurrentIndex();
            else
                list.currentList?.moveGridLeft();
            event.accepted = true;
        }

        Keys.onRightPressed: event => {
            if (root.showCategories && (event.modifiers & Qt.ControlModifier)) {
                root.cycleCategory(1);
                event.accepted = true;
                return;
            }
            if (list.showWallpapers)
                list.currentList?.incrementCurrentIndex();
            else
                list.currentList?.moveGridRight();
            event.accepted = true;
        }

        Keys.onEscapePressed: root.screenState.launcher = false

        Keys.onPressed: event => {
            if (CortetsuConfig.vimKeybinds && (event.modifiers & Qt.ControlModifier)) {
                if (event.key === Qt.Key_J || event.key === Qt.Key_N) {
                    list.currentList?.incrementCurrentIndex();
                    event.accepted = true;
                    return;
                } else if (event.key === Qt.Key_K || event.key === Qt.Key_P) {
                    list.currentList?.decrementCurrentIndex();
                    event.accepted = true;
                    return;
                }
            }

            if (event.key === Qt.Key_Tab && !(event.modifiers & Qt.ShiftModifier)) {
                list.currentList?.incrementCurrentIndex();
                event.accepted = true;
            } else if (event.key === Qt.Key_Backtab ||
                    (event.key === Qt.Key_Tab && (event.modifiers & Qt.ShiftModifier))) {
                list.currentList?.decrementCurrentIndex();
                event.accepted = true;
            }
        }

        Component.onCompleted: root.focusSearch()

        Connections {
            function onLauncherChanged(): void {
                if (root.screenState.launcher)
                    Qt.callLater(root.focusSearch);
                else {
                    search.text = "";
                    root.category = "home";
                }
            }

            function onSessionChanged(): void {
                if (!root.screenState.session)
                    root.focusSearch();
            }

            target: root.screenState
        }
    }

    Connections {
        target: CortetsuWallpapers
        function onWallpaperApplySucceeded(path: string, generation: int): void {
            if (path === root.pendingWallpaperPath) {
                root.pendingWallpaperPath = "";
                root.screenState.launcher = false;
            }
        }
        function onWallpaperApplyFailed(path: string, generation: int): void {
            if (path === root.pendingWallpaperPath)
                root.pendingWallpaperPath = path;
        }
    }

    // Categories, only while browsing and only those with an installed
    // app. Not Tab stops: Tab moves through the results, Ctrl+Left and
    // Ctrl+Right move through these.
    Flow {
        id: categoryRow
        objectName: "launcherCategories"
        visible: root.showCategories
        anchors.top: search.bottom
        anchors.topMargin: CortetsuDesign.spacingStandard
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: root.padding
        anchors.rightMargin: root.padding + (root.showSide ? root.sideWidth + CortetsuDesign.spacingStandard : 0)
        spacing: CortetsuDesign.spacingUnit

        Repeater {
            model: root.showCategories ? Apps.categories : []
            delegate: CortetsuButton {
                required property var modelData
                compact: true
                activeFocusOnTab: false
                active: root.category === modelData.id
                label: modelData.label
                onClicked: {
                    root.category = modelData.id;
                    search.forceActiveFocus();
                }
            }
        }
    }

    Item {
        id: listWrapper
        implicitWidth: list.width
        implicitHeight: list.height
        anchors.top: root.showCategories ? categoryRow.bottom : search.bottom
        anchors.topMargin: root.showCategories ? CortetsuDesign.spacingCompact : CortetsuDesign.spacingStandard
        anchors.left: parent.left
        anchors.leftMargin: root.padding

        ContentList {
            id: list
            content: root
            screenState: root.screenState
            panels: root.panels
            maxHeight:
                root.maxHeight -
                search.implicitHeight -
                root.padding * 3 -
                (root.showCategories ? categoryRow.implicitHeight + CortetsuDesign.spacingCompact : 0)
            search: search
            category: root.category
            padding: root.padding
            rounding: root.rounding
        }
    }

    LauncherSide {
        id: side
        objectName: "launcherSide"
        visible: root.showSide
        width: root.sideWidth
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        anchors.margins: root.padding
        screenState: root.screenState
        onQuery: text => {
            search.text = text;
            root.focusSearch();
        }
        onOpenSurface: name => {
            SurfacePolicy.closeOn(root.screenState, "launcher");
            SurfacePolicy.open(CortetsuShellState.allStates(), root.screenState, name);
        }
    }
}
