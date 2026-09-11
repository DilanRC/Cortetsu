pragma ComponentBehavior: Bound

import ".."
import QtQuick
import Quickshell
import "../OverlayPolicy.js" as OverlayPolicy
import "../CortetsuDesign.js" as CortetsuDesign

Item {
    id: root
    required property var screen
    required property var screenState
    readonly property bool shouldBeActive: screenState?.cortetsuState?.wallpaperManager ?? false
    readonly property bool presentationReady: contentLoader.item?.presentationReady ?? false
    readonly property bool globalOtherOverlayOpen: {
        for (const candidate of CortetsuScreens.screens) {
            if (OverlayPolicy.hasCompetingPanel(CortetsuShellState.forScreen(candidate)))
                return true;
        }
        return false;
    }

    function closeCompetingPanels(): void {
        for (const candidate of CortetsuScreens.screens)
            OverlayPolicy.closeForWallpaper(CortetsuShellState.forScreen(candidate));
    }

    // The manager must remain discoverable even when the catalog is empty or
    // an image is still loading. Content.qml owns the honest empty state.
    visible: opacity > 0.001
    opacity: shouldBeActive ? 1 : 0
    scale: shouldBeActive ? 1 : 0.96
    transformOrigin: Item.Center

    Behavior on opacity { NumberAnimation { duration: CortetsuDesign.wallUtilityPanelMotionMs; easing.type: Easing.OutCubic } }
    Behavior on scale { NumberAnimation { duration: CortetsuDesign.wallUtilityPanelMotionMs; easing.type: Easing.OutCubic } }

    Rectangle {
        anchors.fill: parent
        color: Qt.alpha(CortetsuDesign.colorScrim, 0.18)
    }

    Loader {
        id: contentLoader
        anchors.fill: parent
        active: root.shouldBeActive || root.opacity > 0.001
        sourceComponent: Content {
            screen: root.screen
            screenState: root.screenState
        }
    }

    onShouldBeActiveChanged: {
        if (shouldBeActive) {
            closeCompetingPanels();
            Qt.callLater(() => contentLoader.item?.openManager());
        } else {
            contentLoader.item?.closeManager();
            CortetsuWallpapers.stopPreview();
        }
    }

    onGlobalOtherOverlayOpenChanged: {
        if (shouldBeActive && globalOtherOverlayOpen) {
            if (screenState?.cortetsuState)
                screenState.cortetsuState.setRetained("wallpaperManager", false);
            CortetsuWallpapers.stopPreview();
        }
    }
}
