import QtQuick
import "../CortetsuDesign.js" as CortetsuDesign
import "../../services"

Item {
    id: root

    required property var screenState
    required property Item sidebarPanel
    property Item osdPanel
    property Item sessionPanel
    property Item utilitiesPanel

    implicitWidth: 352
    implicitHeight: list.implicitHeight
    visible: Notifs.popups().length > 0

    Column {
        id: list
        anchors.fill: parent
        spacing: CortetsuDesign.spacingCompact

        move: Transition {
            NumberAnimation {
                properties: "y"
                duration: CortetsuDesign.motionStandardMs
                easing.type: Easing.OutCubic
            }
        }

        add: Transition {
            NumberAnimation {
                property: "opacity"
                from: 0
                to: 1
                duration: CortetsuDesign.motionStandardMs
                easing.type: Easing.OutCubic
            }
        }

        Repeater {
            model: Notifs.popups()
            delegate: Notification {
                required property int index
                focus: index === 0
                width: list.width
                modelData: Notifs.popups()[index]
                props: ({})
                expanded: false
                screenState: root.screenState
            }
        }
    }
}
