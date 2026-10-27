pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../../components"
import "../../theme"
import ".."
import "../CortetsuSearchBar.qml"
import "../CortetsuTypography.js" as CortetsuTypography
import "Navigation.js" as Navigation

// The map of Settings. Every destination is always there and says how its
// domain stands; a search hides what does not match instead of rebuilding
// the list, so the rows keep their identity and their focus.
CortetsuSurface {
    id: root

    required property var controller
    required property var context
    property bool collapsed: false
    signal collapseRequested()
    signal contentRequested()

    readonly property bool searching: controller.search.trim().length > 0
    readonly property bool searchHoldsEscape: searchField.activeFocus && searchField.text.length > 0
    // The first visible category of each group carries the group label.
    readonly property var groupHeads: {
        const heads = ({});
        const seen = ({});
        for (const category of controller.categories) {
            if (!controller.matchingIds.includes(category.id) || seen[category.group])
                continue;
            seen[category.group] = true;
            heads[category.id] = true;
        }
        return heads;
    }

    function focusSearch(): void {
        if (root.collapsed)
            root.collapseRequested();
        searchField.forceActiveFocus();
        searchField.selectAll();
    }

    function focusSelected(): void {
        for (let i = 0; i < rows.count; ++i) {
            const entry = rows.itemAt(i);
            if (entry && entry.category.id === root.controller.selectedId) {
                entry.row.forceActiveFocus();
                root.reveal(entry);
                return;
            }
        }
    }

    function reveal(entry): void {
        if (!entry)
            return;
        const top = entry.y;
        const bottom = entry.y + entry.height;
        if (top < list.contentY)
            list.contentY = top;
        else if (bottom > list.contentY + list.height)
            list.contentY = bottom - list.height;
    }

    function move(delta: int): void {
        root.controller.selectNeighbour(delta);
        root.focusSelected();
    }

    radiusValue: CortetsuDesign.radiusLarge
    baseColor: Qt.alpha(CortetsuDesign.colorSurfaceGlass, 0.72)
    outlined: true
    outlineColor: Qt.alpha(CortetsuDesign.colorOutlineVariant, 0.48)

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: CortetsuDesign.spacingCompact
        spacing: CortetsuDesign.spacingCompact

        RowLayout {
            Layout.fillWidth: true
            spacing: CortetsuDesign.spacingCompact

            CortetsuSearchBar {
                id: searchField
                objectName: "nexusSearch"
                Layout.fillWidth: true
                visible: !root.collapsed
                compact: true
                placeholderText: qsTr("Buscar un ajuste")
                Accessible.name: qsTr("Buscar un ajuste")
                onTextChanged: root.controller.search = text
                Keys.onDownPressed: root.move(root.controller.matchingIds.includes(root.controller.selectedId) ? 0 : 1)
                Keys.onReturnPressed: root.move(root.controller.matchingIds.includes(root.controller.selectedId) ? 0 : 1)
                Keys.onEnterPressed: root.move(root.controller.matchingIds.includes(root.controller.selectedId) ? 0 : 1)
                // Escape first empties the query. With nothing typed the
                // window's own shortcut takes it and closes.
                Keys.onEscapePressed: clear()
            }

            CortetsuButton {
                objectName: "nexusCollapse"
                Layout.alignment: Qt.AlignHCenter
                Layout.fillWidth: root.collapsed
                compact: true
                icon: root.collapsed ? "left_panel_open" : "left_panel_close"
                label: ""
                tooltipText: root.collapsed ? qsTr("Mostrar nombres") : qsTr("Solo iconos")
                Accessible.name: tooltipText
                onClicked: root.collapseRequested()
            }
        }

        Flickable {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentWidth: width
            contentHeight: column.implicitHeight
            boundsBehavior: Flickable.StopAtBounds

            Behavior on contentY {
                NumberAnimation { duration: CortetsuDesign.motionFastMs; easing.type: Easing.BezierSpline; easing.bezierCurve: CortetsuDesign.easeOut }
            }

            Column {
                id: column
                width: list.width

                Repeater {
                    id: rows
                    model: root.controller.categories

                    delegate: Column {
                        id: entry

                        required property var modelData
                        readonly property var category: modelData
                        readonly property alias row: row
                        readonly property var found: Navigation.match(category, root.controller.search)

                        width: column.width
                        visible: found.matches

                        Item {
                            width: parent.width
                            visible: root.groupHeads[entry.category.id] === true
                            height: root.collapsed ? CortetsuDesign.spacingStandard : groupLabel.implicitHeight + CortetsuDesign.spacingStandard

                            Rectangle {
                                visible: root.collapsed && entry.y > 0
                                anchors.centerIn: parent
                                width: 20
                                height: 1
                                color: Qt.alpha(CortetsuDesign.colorOutlineVariant, 0.6)
                            }

                            CortetsuText {
                                id: groupLabel
                                visible: !root.collapsed
                                anchors.bottom: parent.bottom
                                anchors.bottomMargin: CortetsuDesign.spacingUnit
                                x: CortetsuDesign.spacingStandard
                                text: entry.category.group
                                textSize: CortetsuTypography.labelSmallPx
                                color: CortetsuDesign.colorOnSurfaceVariant
                            }
                        }

                        NexusRow {
                            id: row
                            objectName: `nexus-${entry.category.id}`
                            width: parent.width
                            icon: entry.category.icon
                            title: entry.category.title
                            // While searching, the row names the setting that matched.
                            value: root.searching && entry.found.setting.length > 0
                                ? entry.found.setting
                                : root.context.summary[entry.category.id]
                            alertText: root.context.alert[entry.category.id]
                            selected: root.controller.selectedId === entry.category.id
                            collapsed: root.collapsed
                            onActivated: root.controller.select(entry.category.id)
                            Keys.onUpPressed: root.move(-1)
                            Keys.onDownPressed: root.move(1)
                            Keys.onRightPressed: root.contentRequested()
                        }
                    }
                }
            }

            CortetsuStateMessage {
                objectName: "nexusEmpty"
                anchors.top: parent.top
                anchors.topMargin: CortetsuDesign.spacingSection
                x: CortetsuDesign.spacingCompact
                width: list.width - CortetsuDesign.spacingCompact * 2
                visible: !root.collapsed && root.controller.matchingIds.length === 0
                kind: "empty"
                icon: "search_off"
                title: qsTr("Sin resultados")
                detail: qsTr("Ningún ajuste coincide con «%1»").arg(root.controller.search.trim())
            }
        }
    }
}
