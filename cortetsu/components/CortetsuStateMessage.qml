import QtQuick
import "../theme"
import "../modules/CortetsuTypography.js" as CortetsuTypography

Column {
    id: root

    property string kind: "empty"
    property string icon: kind === "loading" ? "sync" : kind === "error" ? "error_outline" : "inbox"
    property string title
    property string detail

    width: Math.max(implicitWidth, 160)
    spacing: CortetsuDesign.spacingCompact

    CortetsuIcon {
        id: stateIcon
        anchors.horizontalCenter: parent.horizontalCenter
        text: root.icon
        iconSize: CortetsuTypography.iconLargePx
        color: root.kind === "error" ? CortetsuDesign.colorVermillion : CortetsuDesign.colorOnSurfaceVariant

        RotationAnimation on rotation {
            running: root.kind === "loading"
            loops: Animation.Infinite
            from: 0
            to: 360
            duration: CortetsuDesign.motionPanelMs * 2
        }
    }

    CortetsuText {
        width: parent.width
        text: root.title
        textSize: CortetsuTypography.bodyPx
        color: CortetsuDesign.colorOnSurface
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
    }

    CortetsuText {
        width: parent.width
        visible: text.length > 0
        text: root.detail
        textSize: CortetsuTypography.bodySmallPx
        color: CortetsuDesign.colorOnSurfaceVariant
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
    }
}
