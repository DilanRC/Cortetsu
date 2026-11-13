import QtQuick
import "../theme"

// The protagonist of a view: the active connection, the track that is
// playing, the battery. One per view. It is the only block that carries the
// accent wash, so the eye lands on it first and the rows around it can stay
// on the plain ground without a frame each.
//
// The width comes from the caller; the height follows the content.
Item {
    id: root

    property real padding: CortetsuDesign.spacingComfortable
    // Where the wash bleeds from, in fractions of the block.
    property real washX: 0.0
    property real washY: 1.0
    default property alias content: body.data

    implicitWidth: 320
    implicitHeight: body.implicitHeight + padding * 2

    // Washi lifts a sheet with a shadow that falls straight down, kept
    // inside the block's width so it never leaves its column.
    Rectangle {
        visible: CortetsuDesign.materialStyle === 1
        anchors.fill: parent
        anchors.topMargin: 3
        anchors.bottomMargin: -3
        radius: CortetsuDesign.radiusLarge
        color: Qt.alpha(CortetsuDesign.colorOnSurface, CortetsuDesign.materialShadowAlpha * 0.4)
    }

    CortetsuInkPanel {
        anchors.fill: parent
        shadowAlpha: 0
        radius: CortetsuDesign.radiusLarge
        ground: CortetsuDesign.colorSurfaceGlass
        washAlpha: CortetsuDesign.materialHeroWashAlpha
        washX: root.washX
        washY: root.washY
        grain: CortetsuDesign.materialPopupGrain
        marks: false
    }

    Column {
        id: body
        x: root.padding
        y: root.padding
        width: root.width - root.padding * 2
        spacing: CortetsuDesign.spacingStandard
    }
}
