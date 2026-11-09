pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../../../components"
import "../../../theme"
import "../../CortetsuTypography.js" as CortetsuTypography

// A way into a subpage, as on a Windows 11 category page: its icon, what it
// holds, how it stands now, and a chevron. A dot marks a page that needs a
// look.
SettingRow {
    id: root

    property string icon: ""
    property string value: ""
    property string alertText: ""
    signal activated()

    interactive: true
    activeFocusOnTab: true
    leadingIcon: root.icon
    Accessible.role: Accessible.Link
    Accessible.name: root.alertText.length > 0 ? qsTr("%1, requiere atención: %2").arg(root.title).arg(root.alertText) : root.title
    Accessible.description: root.detail
    Accessible.onPressAction: root.activated()
    onClicked: root.activated()
    Keys.onReturnPressed: root.activated()
    Keys.onEnterPressed: root.activated()
    Keys.onSpacePressed: root.activated()

    CortetsuText {
        objectName: "value"
        Layout.maximumWidth: Math.max(80, root.width * 0.32)
        visible: text.length > 0
        text: root.alertText || root.value
        textSize: CortetsuTypography.bodySmallPx
        color: root.alertText.length > 0 ? CortetsuDesign.colorVermillion : CortetsuDesign.colorOnSurfaceVariant
        elide: Text.ElideRight
        horizontalAlignment: Text.AlignRight
    }

    CortetsuIcon {
        text: "chevron_right"
        iconSize: CortetsuTypography.iconSmallPx
        color: CortetsuDesign.colorOnSurfaceVariant
    }
}
