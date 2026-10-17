pragma ComponentBehavior: Bound

import QtQuick
import ".."
import "../../components"
import "../../theme"
import "../CortetsuTypography.js" as CortetsuTypography
import "Model.js" as Model

// Connected keyboards, from the hotplug inventory. «Todos» is the default
// selection; system buttons (power, video bus) sit apart at the end.
Item {
    id: root

    property var keyboards: []
    property string selectedId: ""
    property string error: ""
    property bool loaded: false

    signal selected(string id)

    readonly property var keyboardRows: keyboards.filter(k => k.kind !== "system-buttons")
    readonly property var systemRows: keyboards.filter(k => k.kind === "system-buttons")

    function subtitle(keyboard): string {
        const parts = [keyboard.detail];
        if (keyboard.interfaces.length > 1)
            parts.push(qsTr("%1 interfaces").arg(keyboard.interfaces.length));
        if (keyboard.ambiguous)
            parts.push(qsTr("identidad compartida"));
        else if (!keyboard.hyprlandLinked)
            parts.push(qsTr("sin nombre seguro en Hyprland"));
        return parts.filter(Boolean).join(" · ");
    }

    Column {
        anchors.fill: parent
        spacing: CortetsuDesign.spacingUnit

        CortetsuText {
            width: parent.width
            text: qsTr("Teclados")
            textSize: CortetsuTypography.labelMediumPx
            font.weight: Font.DemiBold
            color: CortetsuDesign.colorOnSurfaceVariant
            bottomPadding: CortetsuDesign.spacingUnit
        }

        CortetsuListRow {
            objectName: "deviceAll"
            width: parent.width
            icon: "select_all"
            title: qsTr("Todos los teclados")
            subtitle: root.loaded ? qsTr("%1 conectados").arg(root.keyboardRows.length) : qsTr("Buscando teclados…")
            selected: root.selectedId === ""
            Accessible.role: Accessible.Button
            Accessible.name: title
            onClicked: root.selected("")
        }

        Repeater {
            model: root.keyboardRows

            delegate: CortetsuListRow {
                id: row
                required property var modelData
                width: parent.width
                icon: Model.kindIcon(row.modelData.kind)
                title: row.modelData.label
                subtitle: root.subtitle(row.modelData)
                tooltipText: row.modelData.interfaces.map(i => i.hyprlandName ?? i.name).join("\n")
                selected: root.selectedId === row.modelData.id
                Accessible.role: Accessible.Button
                Accessible.name: title
                onClicked: root.selected(row.modelData.id)
            }
        }

        CortetsuText {
            visible: root.error.length > 0
            width: parent.width
            text: root.error
            wrapMode: Text.WordWrap
            textSize: CortetsuTypography.labelSmallPx
            color: CortetsuDesign.colorWarning
        }

        CortetsuText {
            visible: root.systemRows.length > 0
            width: parent.width
            topPadding: CortetsuDesign.spacingStandard
            text: qsTr("Botones del sistema")
            textSize: CortetsuTypography.labelSmallPx
            color: CortetsuDesign.colorOnSurfaceVariant
        }

        Repeater {
            model: root.systemRows

            delegate: CortetsuListRow {
                id: systemRow
                required property var modelData
                width: parent.width
                compact: false
                icon: Model.kindIcon(systemRow.modelData.kind)
                title: systemRow.modelData.label
                subtitle: root.subtitle(systemRow.modelData)
                selected: root.selectedId === systemRow.modelData.id
                Accessible.role: Accessible.Button
                Accessible.name: title
                onClicked: root.selected(systemRow.modelData.id)
            }
        }
    }
}
