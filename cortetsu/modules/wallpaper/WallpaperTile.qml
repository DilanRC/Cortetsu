import QtQuick
import ".."
import "../../components"
import "../../theme"
import "../CortetsuTypography.js" as CortetsuTypography

// A 16:9 thumbnail with the chamfered frame. Decoding stays bounded and
// shares the pixmap cache with the prefetch in Content.qml.
Item {
    id: root

    property string source: ""
    property bool selected: false
    property bool applied: false
    property bool hovered: false
    property real chamfer: 10
    readonly property alias status: image.status

    OctagonFrame {
        id: mask
        anchors.fill: parent
        chamfer: root.chamfer
        fillColor: CortetsuDesign.colorSurfaceHigh
        visible: false
        layer.enabled: true
    }

    Image {
        id: image
        anchors.fill: parent
        source: root.source
        asynchronous: true
        sourceSize.width: 256
        sourceSize.height: 256
        fillMode: Image.PreserveAspectCrop
        cache: true
        mipmap: true
        retainWhileLoading: true
        layer.enabled: true
        layer.effect: CortetsuMask { maskSource: mask }
    }

    CortetsuIcon {
        anchors.centerIn: parent
        visible: image.status === Image.Error
        text: "broken_image"
        color: CortetsuDesign.colorOnSurfaceVariant
        iconSize: CortetsuTypography.iconMediumPx
    }

    OctagonFrame {
        anchors.fill: parent
        chamfer: root.chamfer
        strokeColor: root.selected
            ? CortetsuDesign.colorPrimary
            : root.hovered
                ? CortetsuDesign.colorOnSurface
                : Qt.alpha(CortetsuDesign.colorOutlineVariant, 0.72)
        strokeWidth: root.selected ? 2 : 1
    }

    Rectangle {
        visible: root.applied
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 6
        width: 18
        height: 18
        radius: 9
        color: CortetsuDesign.colorSecondaryContainer
        border.width: 1
        border.color: CortetsuDesign.colorSecondary
        CortetsuIcon {
            anchors.centerIn: parent
            text: "check"
            iconSize: 12
            color: CortetsuDesign.colorOnSecondaryContainer
        }
    }
}
