import QtQuick
import "../theme"
import "../modules/CortetsuTypography.js" as CortetsuTypography

// The width comes from the caller (a Layout, an anchor or an explicit value)
// and only the height follows the content. Deriving the width from the
// content as well made a Layout and this item resize each other forever.
Item {
    id: root

    property string kind: "empty"
    property string icon: kind === "loading" ? "sync" : kind === "error" ? "error_outline" : "inbox"
    property string title
    property string detail

    implicitWidth: 280
    implicitHeight: column.implicitHeight

    Column {
        id: column
        width: root.width
        spacing: CortetsuDesign.spacingCompact

        CortetsuIcon {
            id: stateIcon
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.icon
            iconSize: CortetsuTypography.iconLargePx
            color: root.kind === "error" ? CortetsuDesign.colorVermillion : CortetsuDesign.colorOnSurfaceVariant

            RotationAnimation on rotation {
                running: root.kind === "loading" && root.visible
                loops: Animation.Infinite
                from: 0
                to: 360
                duration: CortetsuDesign.motionPanelMs * 2
            }
        }

        CortetsuText {
            width: column.width
            text: root.title
            textSize: CortetsuTypography.bodyPx
            color: CortetsuDesign.colorOnSurface
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
        }

        CortetsuText {
            width: column.width
            visible: text.length > 0
            text: root.detail
            textSize: CortetsuTypography.bodySmallPx
            color: CortetsuDesign.colorOnSurfaceVariant
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
        }
    }
}
