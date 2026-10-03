import QtQuick
import Quickshell
import "../../../theme"
import "../../../services"

Item {
    id: root

    readonly property int spacing: CortetsuDesign.spacingCompact
    readonly property var visibleToasts: CortetsuToaster.toasts.slice(0, 5)
    readonly property alias repeater: toastRepeater
    implicitWidth: 368
    implicitHeight: column.childrenRect.height
    width: implicitWidth
    height: implicitHeight
    z: 100
    focus: false

    Column {
        id: column
        anchors.fill: parent
        spacing: root.spacing

        Repeater {
            id: toastRepeater
            model: ScriptModel {
                values: root.visibleToasts
                objectProp: "id"
            }

            delegate: ToastItem {
                id: toastItem
                required property var modelData
                width: root.width
                toast: modelData
                opacity: 1
                onDismissed: CortetsuToaster.dismiss(modelData.id)

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

    function focusToast(id: int): bool {
        for (let i = 0; i < toastRepeater.count; i++) {
            const item = toastRepeater.itemAt(i);
            if (item?.toast?.id === id) {
                item.forceActiveFocus(Qt.TabFocusReason);
                return true;
            }
        }
        return false;
    }
}
