pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../../../components"
import "../../../theme"
import "../../CortetsuTypography.js" as CortetsuTypography

// A fact to read, not a control: it takes no focus and does not react.
SettingRow {
    id: root

    property string value: ""
    property bool attention: false

    CortetsuText {
        objectName: "value"
        Layout.maximumWidth: Math.max(120, root.width * 0.55)
        text: root.value
        textSize: CortetsuTypography.bodyPx
        font.weight: Font.DemiBold
        color: root.attention ? CortetsuDesign.colorVermillion : CortetsuDesign.colorOnSurface
        elide: Text.ElideMiddle
        horizontalAlignment: Text.AlignRight
    }
}
