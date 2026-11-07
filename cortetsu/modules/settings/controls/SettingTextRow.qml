pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import "../../../theme"

SettingRow {
    id: root
    property string value: ""
    property string placeholderText: ""
    signal committed(string value)

    TextField {
        id: field
        objectName: "entry"
        property string draft: root.value
        onActiveFocusChanged: if (activeFocus) draft = text
        onTextEdited: draft = text
        implicitWidth: Math.min(260, root.width * 0.45)
        implicitHeight: CortetsuDesign.controlHeight
        enabled: !root.disabled
        placeholderText: root.placeholderText
        color: CortetsuDesign.colorOnSurface
        placeholderTextColor: CortetsuDesign.colorOnSurfaceVariant
        selectionColor: CortetsuDesign.colorPrimaryContainer
        selectedTextColor: CortetsuDesign.colorOnPrimaryContainer
        font.family: CortetsuDesign.fontUi
        Accessible.name: root.title
        background: Rectangle {
            color: CortetsuDesign.colorSurfaceHigh
            radius: CortetsuDesign.radiusSmall
            border.width: field.activeFocus ? 2 : 1
            border.color: field.activeFocus ? CortetsuDesign.colorIndicator : CortetsuDesign.colorOutlineVariant
        }
        Binding { target: field; property: "text"; value: root.value; when: !field.activeFocus }
        onEditingFinished: {
            if (draft !== root.value)
                root.committed(draft);
        }
        Keys.onEscapePressed: {
            draft = root.value;
            text = root.value;
            focus = false;
        }
    }
}
