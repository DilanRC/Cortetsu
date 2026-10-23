import QtQuick
import ".."
import "../../theme"

Item {
    id: root

    readonly property string sourcePath: CortetsuWallpapers.current

    Rectangle {
        anchors.fill: parent
        color: CortetsuDesign.colorSurface
    }

    Image {
        id: image

        anchors.fill: parent
        asynchronous: true
        cache: true
        fillMode: Image.PreserveAspectCrop
        // Decode at screen resolution: with PreserveAspectCrop Qt scales to
        // cover this size, so a 4625x2600 wallpaper costs ~8 MiB, not ~48 MiB.
        sourceSize: Qt.size(Math.ceil(width * Screen.devicePixelRatio), Math.ceil(height * Screen.devicePixelRatio))
        source: width > 0 && height > 0 ? root.sourcePath : ""

        onStatusChanged: {
            if (status === Image.Error && source !== CortetsuWallpapers.fallback)
                source = CortetsuWallpapers.fallback;
        }
    }
}
