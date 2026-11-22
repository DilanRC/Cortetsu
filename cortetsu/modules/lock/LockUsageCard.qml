import QtQuick
import "../../components"
import "../../theme"
import "../CortetsuTypography.js" as CortetsuTypography

// One reading of the machine under the password (Nebula's UsageCard): the
// card fills from the bottom to the value, with a slow wave on its surface,
// and says its name, value and a detail. `fraction` < 0 means no reading:
// the card stays empty. `fill` may be any colour of the scheme.
Item {
    id: root

    property string label: ""
    property string icon: ""
    property string text: "—"
    property string subText: ""
    property real fraction: -1
    property color fill: CortetsuDesign.colorPrimary
    default property alias extra: custom.data

    readonly property real level: Math.max(0, Math.min(1, fraction))
    property real wave: 0
    NumberAnimation on wave {
        from: 0
        to: Math.PI * 2
        duration: 4000
        loops: Animation.Infinite
        running: root.visible && root.fraction > 0.01 && root.fraction < 0.99 && !CortetsuDesign.reducedMotion
    }

    implicitWidth: 176
    implicitHeight: 118

    Rectangle {
        id: card
        anchors.fill: parent
        radius: 24
        color: Qt.alpha(CortetsuDesign.colorSurfaceHigh, 0.9)
        border.width: 1
        border.color: Qt.alpha(CortetsuDesign.colorWashi, 0.08)
        clip: true

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: root.fraction < 0 ? 0 : Math.max(0, parent.height * root.level + 4 * Math.sin(root.wave))
            // The card clips square; the fill keeps its rounded bottom.
            radius: card.radius
            gradient: Gradient {
                GradientStop { position: 0; color: Qt.lighter(root.fill, 1.12) }
                GradientStop { position: 1; color: root.fill }
            }
        }
    }

    readonly property color ink: root.level > 0.55 ? CortetsuDesign.colorOnPrimary : CortetsuDesign.colorOnSurface

    Row {
        x: 14
        y: 12
        spacing: 6
        Rectangle {
            width: 24
            height: 24
            radius: 12
            color: Qt.alpha(root.fill, 0.28)
            CortetsuIcon {
                anchors.centerIn: parent
                text: root.icon
                iconSize: 15
                color: CortetsuDesign.colorOnSurface
            }
        }
        CortetsuText {
            anchors.verticalCenter: parent.verticalCenter
            text: root.label
            textSize: CortetsuTypography.labelSmallPx
            color: root.level > 0.78 ? Qt.alpha(root.ink, 0.85) : CortetsuDesign.colorOnSurfaceVariant
            width: Math.min(implicitWidth, root.width - 58)
            elide: Text.ElideRight
        }
    }
    Column {
        x: 14
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 12
        CortetsuText {
            text: root.text
            textSize: CortetsuTypography.titleMediumPx
            font.weight: Font.DemiBold
            font.features: ({ "tnum": 1 })
            color: root.ink
        }
        CortetsuText {
            visible: text.length > 0
            text: root.subText
            textSize: CortetsuTypography.labelSmallPx
            color: Qt.alpha(root.ink, 0.75)
        }
    }
    Item {
        id: custom
        anchors.fill: parent
    }
}
