pragma ComponentBehavior: Bound

import QtQuick
import "../theme"

// A row of CortetsuTab on one track: the views of the same subject (nearby
// and saved networks, output and input). The bar is a single Tab stop; Left
// and Right move the selection inside it, as a tab list does.
//
// model: [{ label, icon }]. The caller owns currentIndex.
Item {
    id: root

    property var model: []
    property int currentIndex: 0
    // Equal shares fill the bar; otherwise each tab is as wide as its label.
    property bool fill: true
    property string accessibleName: ""
    signal selected(int index)

    // With fill the tabs take their width from the bar, so the bar cannot
    // take its implicit width from them (the Row and the layout would resize
    // each other forever); a fixed share per tab stands in.
    implicitWidth: root.fill ? root.model.length * 112 + root.inset * (root.model.length + 1) : track.implicitWidth
    implicitHeight: 40 + inset * 2
    readonly property real inset: 3

    Accessible.role: Accessible.PageTabList
    Accessible.name: root.accessibleName

    function select(index: int): void {
        if (index < 0 || index >= root.model.length || index === root.currentIndex)
            return;
        // Focus moves first: Qt will not drop the Tab stop from the item
        // that still holds the focus.
        const tab = tabs.itemAt(index);
        if (tab)
            tab.forceActiveFocus(Qt.TabFocusReason);
        root.selected(index);
    }

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: Qt.alpha(CortetsuDesign.colorSurfaceGlassStrong, 0.6)
    }

    Row {
        id: track
        x: root.inset
        y: root.inset
        spacing: root.inset

        Repeater {
            id: tabs
            model: root.model

            delegate: CortetsuTab {
                required property var modelData
                width: root.fill
                    ? (root.width - root.inset * (root.model.length + 1)) / Math.max(1, root.model.length)
                    : implicitWidth
                count: root.model.length
                label: modelData.label
                icon: modelData.icon ?? ""
                selected: root.currentIndex === index
                // Only the selected tab is a Tab stop.
                // Qt will not drop the flag from the item that holds the focus.
                activeFocusOnTab: selected || activeFocus
                onActivated: root.select(index)
                onPreviousRequested: root.select(index - 1)
                onNextRequested: root.select(index + 1)
            }
        }
    }
}
