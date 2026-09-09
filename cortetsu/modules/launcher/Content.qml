pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import ".."
import "../../components"
import "../CortetsuDesign.js" as CortetsuDesign
import "../CortetsuTypography.js" as CortetsuTypography
import "../CortetsuSearchBar.qml"
import "services"

Item {
    id: root

    required property var screenState
    required property var panels
    required property real maxHeight
    property string pendingWallpaperPath: ""

    readonly property int padding: CortetsuDesign.spacingStandard
    readonly property int rounding: CortetsuDesign.radiusLarge
    readonly property string markPhase: CortetsuWallpapers.applying || pendingWallpaperPath.length > 0
        ? "Monster"
        : search.activeFocus || search.text.length > 0
            ? "Awakening"
            : "Human"

    function focusSearch(): void {
        search.forceActiveFocus();
        search.cursorPosition = search.text.length;
    }

    function modeLabel(): string {
        if (search.text.startsWith(`${CortetsuConfig.actionPrefix}scheme `)) return qsTr("Theme");
        if (search.text.startsWith(`${CortetsuConfig.actionPrefix}wallpaper `)) return qsTr("Wallpaper");
        if (search.text.startsWith(CortetsuConfig.actionPrefix)) return qsTr("Command");
        return qsTr("Apps");
    }

    function modeIcon(): string {
        if (modeLabel() === qsTr("Theme")) return "palette";
        if (modeLabel() === qsTr("Wallpaper")) return "wallpaper";
        if (modeLabel() === qsTr("Command")) return "terminal";
        return "apps";
    }

    function requestWallpaper(path: string): void {
        const target = String(path ?? "").trim();
        if (!target || CortetsuWallpapers.applying)
            return;
        if (target === CortetsuWallpapers.actualCurrent) {
            pendingWallpaperPath = "";
            root.screenState.launcher = false;
            return;
        }
        if (CortetsuWallpapers.apply(target))
            pendingWallpaperPath = target;
    }

    implicitWidth: listWrapper.width + padding * 2
    implicitHeight:
        padding +
        search.implicitHeight +
        CortetsuDesign.spacingStandard +
        mode.implicitHeight +
        CortetsuDesign.spacingCompact +
        listWrapper.implicitHeight +
        padding

    CortetsuPopupSurface {
        anchors.fill: parent
        baseColor: Qt.alpha(CortetsuDesign.colorTetsu, 0.94)
        outlineColor: Qt.alpha(CortetsuDesign.colorOutlineVariant, 0.16)
    }

    CortetsuSurface {
        id: mode
        anchors.top: search.bottom
        anchors.left: search.left
        anchors.right: search.right
        anchors.topMargin: CortetsuDesign.spacingCompact
        implicitHeight: 32
        radiusValue: CortetsuDesign.radiusSmall
        baseColor: Qt.alpha(CortetsuDesign.colorPrimaryContainer, 0.42)
        outlined: true
        Row {
            anchors.fill: parent
            anchors.leftMargin: CortetsuDesign.spacingCompact
            anchors.rightMargin: CortetsuDesign.spacingCompact
            spacing: CortetsuDesign.spacingCompact
            CortetsuEvolvingMark {
                width: 20
                height: 20
                anchors.verticalCenter: parent.verticalCenter
                phase: root.markPhase
                monochrome: true
                monochromeColor: CortetsuDesign.colorWashi
            }
            CortetsuIcon { anchors.verticalCenter: parent.verticalCenter; text: root.modeIcon(); iconSize: CortetsuTypography.iconSmallPx; color: CortetsuDesign.colorPrimary }
            CortetsuText { anchors.verticalCenter: parent.verticalCenter; text: root.modeLabel(); textSize: CortetsuTypography.labelSmallPx; font.weight: Font.DemiBold; color: CortetsuDesign.colorOnPrimaryContainer }
            CortetsuText { anchors.verticalCenter: parent.verticalCenter; text: CortetsuWallpapers.applyFailed && root.pendingWallpaperPath ? qsTr("Apply failed") : root.modeLabel() === qsTr("Apps") ? qsTr("Search-first") : qsTr("Prefix mode"); textSize: CortetsuTypography.labelSmallPx; color: CortetsuDesign.colorOnSurfaceVariant }
        }
    }

    CortetsuSearchBar {
        id: search
        objectName: "launcherSearch"
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: root.padding
        anchors.leftMargin: root.padding
        anchors.rightMargin: root.padding
        placeholderText: qsTr("Search apps or commands…")

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
                    root.screenState.launcher = false;
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
            if (list.showWallpapers)
                list.currentList?.decrementCurrentIndex();
            else
                list.currentList?.moveGridLeft();
            event.accepted = true;
        }

        Keys.onRightPressed: event => {
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
                else
                    search.text = "";
            }

            function onSessionChanged(): void {
                if (!root.screenState.session)
                    search.forceActiveFocus();
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

    Item {
        id: listWrapper
        implicitWidth: list.width
        implicitHeight: list.height
        anchors.top: mode.bottom
        anchors.topMargin: CortetsuDesign.spacingCompact
        anchors.horizontalCenter: parent.horizontalCenter

        ContentList {
            id: list
            content: root
            screenState: root.screenState
            panels: root.panels
            maxHeight:
                root.maxHeight -
                search.implicitHeight -
                root.padding * 3
            search: search
            padding: root.padding
            rounding: root.rounding
        }
    }
}
