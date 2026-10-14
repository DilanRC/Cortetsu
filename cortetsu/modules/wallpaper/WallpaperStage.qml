import QtQuick
import ".."
import "../../components"
import "../../theme"
import "../CortetsuTypography.js" as CortetsuTypography

// The candidate at the proportion it will have on the desktop, with the
// applied wallpaper beside it for comparison and the state of the candidate.
Item {
    id: root

    property string source: ""
    property string outgoingSource: ""
    property real sourceOpacity: 1
    property real outgoingOpacity: 0
    // Empty when the candidate is the applied wallpaper: nothing to compare.
    property string appliedSource: ""
    property bool applied: false
    property bool failed: false
    property string title: ""
    property string stateLabel: ""
    property string detail: ""
    property string errorText: ""
    readonly property alias status: heroImage.status


    OctagonFrame {
        id: heroMask
        anchors.fill: parent
        chamfer: 22
        fillColor: CortetsuDesign.colorSurfaceHigh
        visible: false
        layer.enabled: true
    }
    Image {
        anchors.fill: parent
        source: root.outgoingSource
        opacity: root.outgoingOpacity
        asynchronous: true
        sourceSize.width: 1280
        sourceSize.height: 1280
        fillMode: Image.PreserveAspectCrop
        cache: true
        mipmap: true
        retainWhileLoading: true
        layer.enabled: true
        layer.effect: CortetsuMask { maskSource: heroMask }
    }
    Image {
        id: heroImage
        anchors.fill: parent
        source: root.source
        opacity: root.sourceOpacity
        asynchronous: true
        sourceSize.width: 1280
        sourceSize.height: 1280
        fillMode: Image.PreserveAspectCrop
        cache: true
        mipmap: true
        retainWhileLoading: true
        layer.enabled: true
        layer.effect: CortetsuMask { maskSource: heroMask }
    }
    CortetsuIcon {
        anchors.centerIn: parent
        visible: heroImage.status === Image.Error
        text: "broken_image"
        color: CortetsuDesign.colorOnSurfaceVariant
        iconSize: CortetsuTypography.iconExtraLargePx
    }
    OctagonFrame {
        anchors.fill: parent
        chamfer: 22
        strokeColor: root.failed
            ? CortetsuDesign.colorVermillion
            : root.applied ? CortetsuDesign.colorSecondary : CortetsuDesign.colorPrimary
        strokeWidth: 2
    }

    // The applied wallpaper, for comparison with the candidate.
    Column {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: CortetsuDesign.spacingComfortable
        spacing: CortetsuDesign.spacingCompact
        visible: !!root.appliedSource

        WallpaperTile {
            width: Math.min(176, root.width * 0.24)
            height: width * 9 / 16
            source: root.appliedSource
            applied: true
        }
        Rectangle {
            anchors.right: parent.right
            width: appliedLabel.implicitWidth + 16
            height: 22
            radius: CortetsuDesign.radiusSmall
            color: Qt.alpha(CortetsuDesign.colorSurface, 0.88)
            CortetsuText {
                id: appliedLabel
                anchors.centerIn: parent
                text: qsTr("Fondo actual")
                textSize: CortetsuTypography.labelSmallPx
                color: CortetsuDesign.colorOnSurfaceVariant
            }
        }
    }

    // Name, place in the collection and state of the candidate.
    Rectangle {
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.margins: CortetsuDesign.spacingComfortable
        width: Math.min(heroInfo.implicitWidth + 28, root.width - 2 * CortetsuDesign.spacingComfortable)
        height: heroInfo.implicitHeight + 20
        radius: CortetsuDesign.radiusMedium
        color: Qt.alpha(CortetsuDesign.colorSurface, 0.88)
        border.width: 1
        border.color: Qt.alpha(CortetsuDesign.colorOutlineVariant, 0.55)

        Column {
            id: heroInfo
            anchors.left: parent.left
            anchors.leftMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, root.width - 2 * CortetsuDesign.spacingComfortable - 28)
            spacing: 4

            CortetsuText {
                width: Math.min(implicitWidth, root.width - 2 * CortetsuDesign.spacingComfortable - 28)
                text: root.title
                elide: Text.ElideMiddle
                textSize: CortetsuTypography.titleSmallPx
                font.weight: Font.DemiBold
            }
            Row {
                spacing: CortetsuDesign.spacingCompact
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: heroStateText.implicitWidth + 14
                    height: 20
                    radius: CortetsuDesign.radiusSmall
                    color: root.failed
                        ? Qt.alpha(CortetsuDesign.colorVermillion, 0.24)
                        : root.applied ? CortetsuDesign.colorSecondaryContainer : CortetsuDesign.colorPrimaryContainer
                    CortetsuText {
                        id: heroStateText
                        anchors.centerIn: parent
                        text: root.stateLabel
                        textSize: CortetsuTypography.labelSmallPx
                        color: root.failed
                            ? CortetsuDesign.colorOnSurface
                            : root.applied ? CortetsuDesign.colorOnSecondaryContainer : CortetsuDesign.colorOnPrimaryContainer
                    }
                }
                CortetsuText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.detail
                    textSize: CortetsuTypography.labelMediumPx
                    color: CortetsuDesign.colorOnSurfaceVariant
                }
            }
            CortetsuText {
                visible: !!root.errorText
                width: Math.min(implicitWidth, root.width - 2 * CortetsuDesign.spacingComfortable - 28)
                text: root.errorText
                elide: Text.ElideRight
                textSize: CortetsuTypography.labelSmallPx
                color: CortetsuDesign.colorVermillion
            }
        }
    }
}
