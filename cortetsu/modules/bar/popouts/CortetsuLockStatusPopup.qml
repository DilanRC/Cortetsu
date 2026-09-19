import QtQuick.Layouts
import ".."
import "../.."
import "../../../components"
import "../../../services"
import "../../CortetsuDesign.js" as CortetsuDesign

ColumnLayout {
    spacing: CortetsuDesign.spacingCompact
    CortetsuSectionHeader { title: qsTr("Estado de bloqueo"); detail: qsTr("Indicadores del teclado") }
    CortetsuListRow { icon: "keyboard_capslock"; title: qsTr("Bloq Mayús"); subtitle: Hypr.capsLock ? qsTr("Activado") : qsTr("Desactivado") }
    CortetsuListRow { icon: "pin"; title: qsTr("Bloq Num"); subtitle: Hypr.numLock ? qsTr("Activado") : qsTr("Desactivado") }
}
