import QtQuick
import "../../components"
import "../../theme"

// The block every Hardware page is built from: the same quiet surface as the
// summary, with no outline of its own.
Item {
    id: root

    default property alias content: body.data
    property real padding: CortetsuDesign.spacingComfortable
    property real radiusValue: CortetsuDesign.radiusLarge

    CortetsuSurface {
        anchors.fill: parent
        radiusValue: root.radiusValue
        outlined: false
        baseColor: Qt.alpha(CortetsuDesign.colorSurfaceGlass, 0.72)
    }

    Item {
        id: body
        anchors.fill: parent
        anchors.margins: root.padding
    }
}
