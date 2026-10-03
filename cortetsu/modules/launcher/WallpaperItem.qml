pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import ".."
import "../CortetsuDesign.js" as CortetsuDesign
import "../CortetsuTypography.js" as CortetsuTypography

Item {
    id: root

    required property var modelData
    required property var screenState
    required property var applyOwner

    scale: 0.5
    opacity: 0
    z: PathView.z ?? 0 // qmllint disable missing-property

    Component.onCompleted: {
        scale = Qt.binding(() => PathView.isCurrentItem ? 1 : PathView.onPath ? 0.8 : 0);
        opacity = Qt.binding(() => PathView.onPath ? 1 : 0);
    }

    implicitWidth: image.width + CortetsuDesign.spacingStandard * 2
    implicitHeight: image.height + label.height + CortetsuDesign.spacingCompact + CortetsuDesign.spacingComfortable + CortetsuDesign.spacingStandard

    CortetsuStateLayer {
        radius: CortetsuDesign.radiusLarge
        disabled: CortetsuWallpapers.applying
        onClicked: root.applyOwner.requestWallpaper(root.modelData.path)
    }

    CortetsuSurface {
        id: imageFrame

        anchors.fill: image
        radiusValue: image.radius
        baseColor: CortetsuDesign.colorSurfaceHigh
        outlined: false
        opacity: root.PathView.isCurrentItem ? 1 : 0.86
    }

    CortetsuSurface {
        id: image

        anchors.horizontalCenter: parent.horizontalCenter
        y: CortetsuDesign.spacingComfortable
        radiusValue: CortetsuDesign.radiusLarge
        baseColor: CortetsuDesign.colorSurfaceHigh
        outlined: false
        implicitWidth: 176
        implicitHeight: implicitWidth / 16 * 9

        CortetsuIcon {
            anchors.centerIn: parent
            text: "image"
            color: CortetsuDesign.colorOutline
            iconSize: CortetsuTypography.iconExtraLargePx
        }

        Image {
            anchors.fill: parent
            source: root.modelData.path
            fillMode: Image.PreserveAspectCrop
            smooth: !(PathView.view?.moving ?? false)
            sourceSize: {
                const dpr = (QsWindow.window as QsWindow)?.devicePixelRatio ?? 1;
                return Qt.size(image.implicitWidth * dpr, image.implicitHeight * dpr);
            }
        }
    }

    CortetsuText {
        id: label

        anchors.top: image.bottom
        anchors.topMargin: CortetsuDesign.spacingCompact
        anchors.horizontalCenter: parent.horizontalCenter
        width: image.width - CortetsuDesign.spacingStandard * 2
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        text: root.modelData.relativePath
        textSize: CortetsuTypography.labelSmallPx
    }

    Behavior on scale { CortetsuAnim {} }
    Behavior on opacity { CortetsuAnim { type: CortetsuAnim.DefaultEffects } }
}
