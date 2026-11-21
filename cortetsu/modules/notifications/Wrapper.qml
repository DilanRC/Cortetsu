import QtQuick
import ".."
import "../../theme"
import "../../services"

Item {
    id: root

    required property var screenState
    required property Item sidebarPanel
    property Item osdPanel
    property Item sessionPanel
    property Item utilitiesPanel

    implicitWidth: 320
    implicitHeight: list.implicitHeight
    // With the sidebar open the same notification is listed there; a popup
    // on top of it would cover its header (clear all, DND).
    visible: Notifs.popups().length > 0 && !(screenState?.sidebar ?? false)

    Column {
        id: list
        anchors.fill: parent
        spacing: CortetsuDesign.spacingCompact

        move: Transition {
            NumberAnimation {
                properties: "y"
                duration: CortetsuDesign.motionStandardMs
                easing.type: Easing.BezierSpline
                easing.bezierCurve: CortetsuDesign.easeOut
            }
        }

        add: Transition {
            NumberAnimation {
                property: "opacity"
                from: 0
                to: 1
                duration: CortetsuDesign.motionStandardMs
                easing.type: Easing.BezierSpline
                easing.bezierCurve: CortetsuDesign.easeOut
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
                expanded: CortetsuConfig.notificationOpenExpanded
                screenState: root.screenState
            }
        }
    }
}
