pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Mpris
import "../../components"
import "../../services"
import "../../utils"
import ".."
import "../../theme"
import "../CortetsuTypography.js" as CortetsuTypography

// Cover art as a print on a mount of wallpaper ink, with paper grain.
Item {
    id: cover
    property string art
    property real size: 300
    implicitWidth: size
    implicitHeight: size
    // An ink block offset behind the print, like a mount.
    Rectangle {
        x: cover.size * 0.04; y: cover.size * 0.04
        width: cover.size; height: cover.size
        radius: CortetsuDesign.radiusSmall
        color: Qt.alpha(CortetsuDesign.colorPrimary, 0.28)
    }
    Rectangle {
        anchors.fill: parent
        radius: CortetsuDesign.radiusSmall
        color: CortetsuDesign.colorSurfaceHigh
        clip: true
        CortetsuIcon { anchors.centerIn: parent; text: "music_note"; iconSize: cover.size * 0.3; color: CortetsuDesign.colorOnSurfaceVariant; visible: image.status !== Image.Ready }
        Image {
            id: image
            anchors.fill: parent
            source: cover.art
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            sourceSize.width: 600
            sourceSize.height: 600
        }
        CortetsuGrain { anchors.fill: parent; radius: CortetsuDesign.radiusSmall; strength: CortetsuDesign.materialGrain }
    }
}
