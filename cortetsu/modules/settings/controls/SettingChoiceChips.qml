pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../../components"
import "../../../theme"
import "../../CortetsuTypography.js" as CortetsuTypography

// A choice among a few named options, laid out as pills that wrap to the
// width they have. Arrows move between options; the caller binds `current`
// to the real value, so a refused choice leaves the selection where it was.
ColumnLayout {
    id: root

    property string title: ""
    property string detail: ""
    // [{ value, label, icon?, name? }]: `name` becomes the chip's objectName.
    property var options: []
    property var current
    property var pending
    property bool disabled: false
    property string status: ""
    property string statusText: ""
    signal chosen(var value)

    Layout.fillWidth: true
    Layout.margins: CortetsuDesign.spacingStandard
    spacing: CortetsuDesign.spacingCompact

    function move(from: int, delta: int): void {
        const next = chips.itemAt(Math.max(0, Math.min(chips.count - 1, from + delta)));
        if (next)
            next.forceActiveFocus(Qt.TabFocusReason);
    }

    CortetsuText {
        Layout.fillWidth: true
        visible: root.title.length > 0
        text: root.title
        textSize: CortetsuTypography.bodyLargePx
        elide: Text.ElideRight
    }

    Flow {
        Layout.fillWidth: true
        spacing: 6

        Repeater {
            id: chips
            // Matched by value: a new options array with the same choices
            // keeps every chip instead of rebuilding them.
            model: ScriptModel { values: root.options; objectProp: "value" }

            ChoiceChip {
                required property var modelData
                required property int index
                objectName: modelData.name ?? `choice-${modelData.value}`
                label: modelData.label
                icon: modelData.icon ?? ""
                selected: root.current === modelData.value
                busy: root.pending === modelData.value && root.status === "busy"
                disabled: root.disabled
                Keys.onLeftPressed: root.move(index, -1)
                Keys.onRightPressed: root.move(index, 1)
                onClicked: root.chosen(modelData.value)
            }
        }
    }

    CortetsuText {
        objectName: "rowDetail"
        Layout.fillWidth: true
        visible: text.length > 0
        text: root.status === "error" || root.status === "busy" ? root.statusText || root.detail : root.detail
        textSize: CortetsuTypography.bodySmallPx
        color: root.status === "error" ? CortetsuDesign.colorVermillion : CortetsuDesign.colorOnSurfaceVariant
        wrapMode: Text.WordWrap
    }
}
