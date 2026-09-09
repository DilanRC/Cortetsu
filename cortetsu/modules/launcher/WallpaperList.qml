pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import Quickshell
import ".."
import "../CortetsuDesign.js" as CortetsuDesign
import ".."

PathView {
    id: root

    required property TextField search
    required property var screenState
    required property var panels
    required property var content

    readonly property int itemWidth: 176 * 0.8 + CortetsuDesign.spacingStandard * 2
    readonly property int numItems: {
        const screen = (QsWindow.window as QsWindow)?.screen;
        if (!screen)
            return 0;

        const barMargins = Math.max(CortetsuOverlayConfig.border.thickness, panels.bar.implicitWidth);
        let outerMargins = 0;
        if (panels.popouts.hasCurrent && panels.popouts.currentCenter + panels.popouts.nonAnimHeight / 2 > screen.height - content.implicitHeight - CortetsuOverlayConfig.border.thickness * 2)
            outerMargins = panels.popouts.nonAnimWidth;
        if ((screenState.utilities || screenState.sidebar) && panels.utilities.implicitWidth > outerMargins)
            outerMargins = panels.utilities.implicitWidth;
        const maxWidth = screen.width - CortetsuOverlayConfig.border.rounding * 4 - (barMargins + outerMargins) * 2;
        if (maxWidth <= 0)
            return 0;

        const maxItemsOnScreen = Math.floor(maxWidth / itemWidth);
        const visible = Math.min(maxItemsOnScreen, 12, scriptModel.values.length);
        if (visible === 2)
            return 1;
        if (visible > 1 && visible % 2 === 0)
            return visible - 1;
        return visible;
    }

    model: ScriptModel {
        id: scriptModel
        readonly property string query: root.search.text.split(" ").slice(1).join(" ")
        values: CortetsuWallpapers.query(query)
        onValuesChanged: root.currentIndex = query ? 0 : values.findIndex(w => w.path === CortetsuWallpapers.actualCurrent)
    }

    Component.onCompleted: currentIndex = CortetsuWallpapers.list.findIndex(w => w.path === CortetsuWallpapers.actualCurrent)
    Component.onDestruction: CortetsuWallpapers.stopPreview()

    onCurrentItemChanged: {
        if (currentItem)
            CortetsuWallpapers.preview(currentItem.modelData.path);
    }

    implicitWidth: Math.min(numItems, count) * itemWidth
    pathItemCount: numItems
    cacheItemCount: 4
    snapMode: PathView.SnapToItem
    preferredHighlightBegin: 0.5
    preferredHighlightEnd: 0.5
    highlightRangeMode: PathView.StrictlyEnforceRange

    delegate: WallpaperItem {
        screenState: root.screenState
        applyOwner: root.content
    }

    path: Path {
        startY: root.height / 2
        PathAttribute { name: "z"; value: 0 }
        PathLine { x: root.width / 2; relativeY: 0 }
        PathAttribute { name: "z"; value: 1 }
        PathLine { x: root.width; relativeY: 0 }
    }
}
