pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../../components"
import "../../theme"
import ".."
import "../CortetsuSearchBar.qml"
import "../CortetsuTypography.js" as CortetsuTypography

// The map of Settings, organised as in Windows 11: search on top, then every
// category with its full name. While a search has text the list becomes the
// results, each naming the setting and where it lives; opening one goes
// straight to it. Categories are filtered, not rebuilt, so rows keep their
// identity and their focus.
Item {
    id: root

    required property var controller
    required property var context
    property bool collapsed: false
    signal collapseRequested()
    signal contentRequested()

    readonly property bool searching: controller.search.trim().length > 0
    readonly property bool searchHoldsEscape: searchField.activeFocus && searchField.text.length > 0
    // Home stands alone and the maintenance pages close the list, as the
    // groups of the Windows 11 sidebar do.
    readonly property var groupStarts: ["system", "advanced"]

    function focusSearch(): void {
        if (root.collapsed)
            root.collapseRequested();
        searchField.forceActiveFocus();
        searchField.selectAll();
    }

    // True while move() changes the selection, so the follow-up below does
    // not focus the row before move() focuses it as a keyboard move.
    property bool moving: false

    // reason: Qt.TabFocusReason when the keyboard moved it, which shows the
    // row's tooltip; opening Settings or a deep link focuses it quietly.
    function focusSelected(reason): void {
        for (let i = 0; i < rows.count; ++i) {
            const entry = rows.itemAt(i);
            if (entry && entry.category.id === root.controller.selectedId) {
                entry.row.forceActiveFocus(reason ?? Qt.OtherFocusReason);
                root.reveal(entry);
                return;
            }
        }
    }

    // A selection made elsewhere (a deep link, a search result, a card on
    // Inicio) moves the focus with it when the focus was on a category row;
    // otherwise the old row would keep its focus ring and tooltip.
    Connections {
        target: root.controller
        function onSelectedIdChanged(): void {
            if (root.moving)
                return;
            for (let i = 0; i < rows.count; ++i) {
                if (rows.itemAt(i)?.row.activeFocus) {
                    root.focusSelected();
                    return;
                }
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
        root.moving = true;
        root.controller.selectNeighbour(delta);
        root.moving = false;
        root.focusSelected(Qt.TabFocusReason);
    }

    function focusResult(index: int): void {
        const entry = results.itemAt(Math.max(0, Math.min(results.count - 1, index)));
        if (entry) {
            entry.forceActiveFocus();
            root.reveal(entry);
        }
    }

    function openResult(result): void {
        root.controller.openResult(result.page, result.setting);
        searchField.clear();
        root.contentRequested();
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: CortetsuDesign.spacingStandard

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 44
            Layout.leftMargin: root.collapsed ? 0 : CortetsuDesign.spacingCompact
            spacing: CortetsuDesign.spacingStandard

            CortetsuEvolvingMark {
                Layout.preferredWidth: 28
                Layout.preferredHeight: 28
                Layout.alignment: root.collapsed ? Qt.AlignHCenter : Qt.AlignVCenter
                visible: !root.collapsed
                phase: "Ascended"
                animated: false
                monochrome: true
                monochromeColor: CortetsuDesign.colorOnSurface
            }

            CortetsuText {
                Layout.fillWidth: true
                visible: !root.collapsed
                text: qsTr("Ajustes")
                textSize: CortetsuTypography.titleMediumPx
                font.family: CortetsuDesign.fontHeading
                font.weight: CortetsuDesign.headingWeight
                elide: Text.ElideRight
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

        CortetsuSearchBar {
            id: searchField
            objectName: "nexusSearch"
            Layout.fillWidth: true
            visible: !root.collapsed
            compact: true
            placeholderText: qsTr("Buscar un ajuste")
            Accessible.name: qsTr("Buscar un ajuste")
            onTextChanged: root.controller.search = text
            Keys.onDownPressed: root.searching ? root.focusResult(0) : root.focusSelected(Qt.TabFocusReason)
            Keys.onReturnPressed: if (root.searching && root.controller.results.length) root.openResult(root.controller.results[0])
            Keys.onEnterPressed: if (root.searching && root.controller.results.length) root.openResult(root.controller.results[0])
            // Escape first empties the query. With nothing typed the
            // window's own shortcut takes it and closes.
            Keys.onEscapePressed: clear()
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
                spacing: 2

                Repeater {
                    id: rows
                    model: root.controller.categories

                    delegate: Column {
                        id: entry

                        required property var modelData
                        readonly property var category: modelData
                        readonly property alias row: row

                        width: column.width
                        visible: !root.searching
                        spacing: 2

                        Rectangle {
                            visible: root.groupStarts.includes(entry.category.id)
                            x: CortetsuDesign.spacingStandard
                            width: parent.width - CortetsuDesign.spacingStandard * 2
                            height: visible ? 1 : 0
                            color: Qt.alpha(CortetsuDesign.colorOutlineVariant, 0.5)
                        }

                        Item {
                            width: parent.width
                            height: root.groupStarts.includes(entry.category.id) ? CortetsuDesign.spacingCompact : 0
                        }

                        NexusRow {
                            id: row
                            objectName: `nexus-${entry.category.id}`
                            width: parent.width
                            icon: entry.category.icon
                            title: entry.category.title
                            value: root.context.categorySummary(entry.category.id)
                            alertText: root.context.categoryAlert(entry.category.id)
                            selected: root.controller.selectedId === entry.category.id
                            collapsed: root.collapsed
                            onActivated: root.controller.select(entry.category.id)
                            Keys.onUpPressed: root.move(-1)
                            Keys.onDownPressed: root.move(1)
                            Keys.onRightPressed: root.contentRequested()
                        }
                    }
                }

                Repeater {
                    id: results
                    model: root.searching ? root.controller.results : []

                    delegate: NexusResult {
                        required property var modelData
                        required property int index
                        objectName: `nexusResult-${index}`
                        width: column.width
                        icon: modelData.icon
                        title: modelData.title
                        path: modelData.path
                        onActivated: root.openResult(modelData)
                        Keys.onUpPressed: index === 0 ? searchField.forceActiveFocus() : root.focusResult(index - 1)
                        Keys.onDownPressed: root.focusResult(index + 1)
                    }
                }
            }

            CortetsuStateMessage {
                objectName: "nexusEmpty"
                anchors.top: parent.top
                anchors.topMargin: CortetsuDesign.spacingSection
                x: CortetsuDesign.spacingCompact
                width: list.width - CortetsuDesign.spacingCompact * 2
                visible: !root.collapsed && root.searching && root.controller.results.length === 0
                kind: "empty"
                icon: "search_off"
                title: qsTr("Sin resultados")
                detail: qsTr("Ningún ajuste coincide con «%1»").arg(root.controller.search.trim())
            }
        }
    }
}
