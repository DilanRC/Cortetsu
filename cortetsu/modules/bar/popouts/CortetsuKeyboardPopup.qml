pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "kblayout"
import "../../../components"
import "../../../theme"

// The keyboard layouts the compositor has, the active one checked. Same
// header as the other service popouts, leading to Ajustes → Teclado.
ColumnLayout {
    id: root
    property var popouts: null
    width: 260
    spacing: CortetsuDesign.spacingCompact

    KbLayoutModel { id: layouts }
    Component.onCompleted: layouts.start()

    CortetsuPopoutHeader {
        Layout.fillWidth: true
        icon: "keyboard"
        title: qsTr("Teclado")
        detail: layouts.activeLabel
        settingsPage: "input"
        popouts: root.popouts
    }

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
        Layout.fillWidth: true
        visible: layouts.visibleModel.count === 0
        kind: "empty"
        title: qsTr("No hay más distribuciones")
    }
}
