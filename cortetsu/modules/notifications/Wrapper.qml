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

    readonly property var visibleNotifications: Notifs.popups.filter(item => !item.closed)
    implicitWidth: 352
    implicitHeight: list.implicitHeight
    visible: visibleNotifications.length > 0

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
            model: root.visibleNotifications
            delegate: Notification {
                required property int index
                modelData: root.visibleNotifications[index]
                width: list.width
                props: ({})
                expanded: false
                screenState: root.screenState
            }
        }
    }
}
