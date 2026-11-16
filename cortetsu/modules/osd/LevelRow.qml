import QtQuick
import QtQuick.Layouts
import "../../components"
import "../../theme"
import "../CortetsuTypography.js" as CortetsuTypography

// A level's heading in the control center: what it is, whose device, the
// read-back amount, and its mute and device-list buttons. The slider sits
// under it, owned by the caller.
RowLayout {
    id: level

    property string icon: ""
    property string title: ""
    property string detail: ""
    property string amount: ""
    property bool muted: false
    property bool available: true
    property bool attention: false
    property bool showMute: true
    property string muteText: ""
    property bool expandable: false
    property bool expanded: false
    signal muteRequested()
    signal expandRequested()

    spacing: CortetsuDesign.spacingCompact

    CortetsuButton {
        visible: level.showMute
        compact: true
        disabled: !level.available
        active: level.muted
        icon: level.icon
        label: ""
        tooltipText: level.muteText
        onClicked: level.muteRequested()
    }
    CortetsuIcon {
        visible: !level.showMute
        Layout.leftMargin: CortetsuDesign.spacingCompact
        Layout.rightMargin: CortetsuDesign.spacingCompact
        text: level.icon
        iconSize: CortetsuTypography.iconSmallPx
        color: level.available ? CortetsuDesign.colorOnSurface : CortetsuDesign.colorOnSurfaceVariant
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 0
        CortetsuText {
            Layout.fillWidth: true
            text: level.title
            textSize: CortetsuTypography.bodyPx
            font.weight: Font.DemiBold
            elide: Text.ElideRight
        }
        CortetsuText {
            Layout.fillWidth: true
            visible: level.detail.length > 0
            text: level.detail
            textSize: CortetsuTypography.labelSmallPx
            color: CortetsuDesign.colorOnSurfaceVariant
            elide: Text.ElideRight
        }
    }

    CortetsuText {
        text: level.amount
        textSize: CortetsuTypography.labelMediumPx
        font.weight: level.attention ? Font.DemiBold : Font.Normal
        color: level.attention ? CortetsuDesign.colorVermillion
            : level.muted || !level.available ? CortetsuDesign.colorOnSurfaceVariant
            : CortetsuDesign.colorOnSurface
    }

    CortetsuButton {
        visible: level.expandable
        compact: true
        active: level.expanded
        icon: level.expanded ? "expand_less" : "expand_more"
        label: ""
        tooltipText: level.expanded ? qsTr("Ocultar dispositivos") : qsTr("Elegir dispositivo")
        onClicked: level.expandRequested()
    }
}
