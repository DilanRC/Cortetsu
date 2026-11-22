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

    // Text takes the colour of what is under it: white keeps 4.5:1 only on
    // a fill darker than luminance 0.18 (WCAG); above that, dark ink. The
    // light fill, light on a dark one) once the fill reaches it.
    readonly property color fillInk: CortetsuDesign.luminance(root.fill) > 0.18 ? "#14121c" : "#f4f1fb"
    readonly property color ink: root.fraction >= 0 && root.level > 0.1 ? root.fillInk : CortetsuDesign.colorOnSurface
    readonly property color headInk: root.fraction >= 0 && root.level > 0.72 ? root.fillInk : CortetsuDesign.colorOnSurfaceVariant

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
                // Fill the disc and centre the glyph in it: the icon font's
                // own box is not square, so centring the item was off.
                anchors.fill: parent
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                text: root.icon
                iconSize: 15
                color: root.headInk
            }
        }
        CortetsuText {
            anchors.verticalCenter: parent.verticalCenter
            text: root.label
            textSize: CortetsuTypography.labelSmallPx
            color: root.headInk
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
