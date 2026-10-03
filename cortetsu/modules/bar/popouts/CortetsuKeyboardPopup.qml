pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "kblayout"
import "../../../components"
import "../../CortetsuDesign.js" as CortetsuDesign

ColumnLayout {
    id: root
    width: 240
    spacing: CortetsuDesign.spacingCompact

    KbLayoutModel { id: layouts }
    Component.onCompleted: layouts.start()

    CortetsuSectionHeader { title: qsTr("Distribución del teclado"); detail: layouts.activeLabel }

    ListView {
        Layout.fillWidth: true
        Layout.preferredHeight: Math.min(contentHeight, 320)
        clip: true
        spacing: CortetsuDesign.spacingCompact
        model: layouts.visibleModel
        delegate: CortetsuListRow {
            required property int layoutIndex
            required property string label
            width: ListView.view.width
            icon: layoutIndex === layouts.activeIndex ? "check" : "keyboard"
            title: label
            subtitle: layoutIndex > 3 ? qsTr("No disponible: XKB admite 4 distribuciones") : ""
            disabled: layoutIndex > 3
            onClicked: layouts.switchTo(layoutIndex)
        }
    }

    CortetsuStateMessage {
        visible: layouts.visibleModel.count === 0
        kind: "empty"
        title: qsTr("No hay más distribuciones")
    }
}
