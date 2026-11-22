import QtQuick
import QtQuick.Effects

// An image cropped to fill a rounded rectangle. It decodes at the size it is
// shown, never at the file's full resolution.
Item {
    id: root
    property alias source: image.source
    property real radius: 0
    readonly property alias status: image.status

    Image {
        id: image
        anchors.fill: parent
        visible: false
        asynchronous: true
        cache: false
        // A new source keeps the old picture until it is ready: covers
        // changing with the track do not flash the empty state.
        retainWhileLoading: true
        fillMode: Image.PreserveAspectCrop
        sourceSize.width: Math.ceil(root.width * 2)
        sourceSize.height: Math.ceil(root.height * 2)
    }

    Rectangle {
        id: mask
        anchors.fill: parent
        radius: root.radius
        visible: false
        layer.enabled: true
    }

    MultiEffect {
        anchors.fill: parent
        source: image
        maskEnabled: true
        maskSource: mask
    }
}
