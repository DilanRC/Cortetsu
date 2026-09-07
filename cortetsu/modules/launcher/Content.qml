pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import ".."
import "../CortetsuDesign.js" as CortetsuDesign
import "../CortetsuSearchBar.qml"
import qs.modules.launcher.services

Item {
    id: root

    required property var screenState
    required property var panels
    required property real maxHeight

    readonly property int padding: CortetsuDesign.spacingStandard
    readonly property int rounding: CortetsuDesign.radiusLarge

    implicitWidth: listWrapper.width + padding * 2
    implicitHeight:
        padding +
        search.implicitHeight +
        CortetsuDesign.spacingStandard +
        listWrapper.implicitHeight +
        padding

    CortetsuPopupSurface {
        anchors.fill: parent
        baseColor: Qt.alpha(CortetsuDesign.colorTetsu, 0.94)
        outlineColor: Qt.alpha(CortetsuDesign.colorOutlineVariant, 0.16)
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
                    if (false && currentItem.modelData.path !== CortetsuWallpapers.actualCurrent)
                        CortetsuWallpapers.previewColourLock = true;

                    CortetsuWallpapers.setWallpaper(currentItem.modelData.path);
                    root.screenState.launcher = false;
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

        Component.onCompleted: forceActiveFocus()

        Connections {
            function onLauncherChanged(): void {
                if (!root.screenState.launcher)
                    search.text = "";
            }

            function onSessionChanged(): void {
                if (!root.screenState.session)
                    search.forceActiveFocus();
            }

            target: root.screenState
        }
    }

    Item {
        id: listWrapper
        implicitWidth: list.width
        implicitHeight: list.height
        anchors.top: search.bottom
        anchors.topMargin: CortetsuDesign.spacingStandard
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
