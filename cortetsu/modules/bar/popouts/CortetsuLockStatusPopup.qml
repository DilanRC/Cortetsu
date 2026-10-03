import QtQuick.Layouts
import ".."
import "../.."
import "../../../components"
import "../../../services"
import "../../CortetsuDesign.js" as CortetsuDesign

ColumnLayout {
    id: root
    spacing: CortetsuDesign.spacingCompact

    function label(active: bool): string {
        if (!Hypr.keyboardKnown)
            return qsTr("No disponible");
        return active ? qsTr("Activado") : qsTr("Desactivado");
    }

    // Lock keys have no compositor event; poll only while this popup exists.
    Component.onCompleted: CortetsuHypr.watchKeyboard()
    Component.onDestruction: CortetsuHypr.unwatchKeyboard()

    CortetsuSectionHeader { title: qsTr("Estado de bloqueo"); detail: qsTr("Indicadores del teclado") }
    CortetsuListRow { icon: "keyboard_capslock"; title: qsTr("Bloq Mayús"); subtitle: root.label(Hypr.capsLock); selected: Hypr.keyboardKnown && Hypr.capsLock }
    CortetsuListRow { icon: "pin"; title: qsTr("Bloq Num"); subtitle: root.label(Hypr.numLock); selected: Hypr.keyboardKnown && Hypr.numLock }
}
