import QtQuick
import QtQuick.Controls
import "../../theme"

TextField {
    id: root
    color: CortetsuDesign.colorOnSurface
    font.family: CortetsuDesign.fontUi
    placeholderTextColor: CortetsuDesign.colorOnSurfaceVariant
    selectionColor: CortetsuDesign.colorPrimary
    selectedTextColor: CortetsuDesign.colorOnPrimary
    selectByMouse: true
    Accessible.name: placeholderText
    implicitHeight: 36
    background: Rectangle {
        color: CortetsuDesign.colorSurface
        radius: CortetsuDesign.radiusSmall
        border.width: root.activeFocus ? 2 : 1
        border.color: root.activeFocus ? CortetsuDesign.colorPrimary : CortetsuDesign.colorOutline
    }
}
