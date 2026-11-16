import QtQuick
import QtQuick.Layouts
import ".."
import "../.."
import "../../../components"
import "../../../services"
import "../../../theme"

// Caps Lock and Num Lock as they are now. A reading, not a control: the
// keys change them, so the rows take no hover or focus (H-22).
ColumnLayout {
    id: root
    property var popouts: null
    width: 240
    spacing: CortetsuDesign.spacingStandard

    function label(active: bool): string {
        if (!Hypr.keyboardKnown)
            return qsTr("No disponible");
        return active ? qsTr("Activado") : qsTr("Desactivado");
    }

    // Lock keys have no compositor event; poll only while this popup exists.
    Component.onCompleted: CortetsuHypr.watchKeyboard()
    Component.onDestruction: CortetsuHypr.unwatchKeyboard()

    CortetsuPopoutHeader {
        Layout.fillWidth: true
        title: qsTr("Bloqueo de teclas")
        detail: Hypr.keyboardKnown ? qsTr("Teclado principal") : qsTr("Teclado no disponible")
        settingsPage: "input"
        popouts: root.popouts
    }
    CortetsuFact {
        Layout.fillWidth: true
        icon: "keyboard_capslock"
        label: qsTr("Bloq Mayús")
        value: root.label(Hypr.capsLock)
        valueColor: Hypr.keyboardKnown && Hypr.capsLock ? CortetsuDesign.colorPrimary : CortetsuDesign.colorOnSurface
    }
    CortetsuFact {
        Layout.fillWidth: true
        icon: "pin"
        label: qsTr("Bloq Num")
        value: root.label(Hypr.numLock)
        valueColor: Hypr.keyboardKnown && Hypr.numLock ? CortetsuDesign.colorPrimary : CortetsuDesign.colorOnSurface
    }
}
