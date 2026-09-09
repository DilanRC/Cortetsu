import QtQuick
import "../../CortetsuDesign.js" as CortetsuDesign
import "../../../services"

Item {
    id: root

    readonly property int spacing: CortetsuDesign.spacingCompact
    readonly property var visibleToasts: CortetsuToaster.toasts.slice(0, 5)
    implicitWidth: 368
    implicitHeight: column.childrenRect.height
    width: implicitWidth
    height: implicitHeight
    z: 100
    focus: visibleToasts.length > 0

    onVisibleToastsChanged: {
        if (visibleToasts.length > 0)
            forceActiveFocus();
    }

    Column {
        id: column
        anchors.fill: parent
        spacing: root.spacing

        Repeater {
            model: root.visibleToasts

            delegate: ToastItem {
                id: toastItem
                required property int index
                focus: index === 0
                width: root.width
                toast: root.visibleToasts[index]
                opacity: 1
                onDismissed: CortetsuToaster.dismiss(root.visibleToasts[index].id)

                Behavior on y {
                    NumberAnimation {
                        duration: CortetsuDesign.motionStandardMs
                        easing.type: Easing.OutCubic
                    }
                }

                Behavior on opacity {
                    NumberAnimation {
                        duration: CortetsuDesign.motionFastMs
                        easing.type: Easing.OutCubic
                    }
                }
            }
        }
    }

    Keys.onEscapePressed: {
        if (root.visibleToasts.length > 0)
            CortetsuToaster.dismiss(root.visibleToasts[0].id);
    }
}
