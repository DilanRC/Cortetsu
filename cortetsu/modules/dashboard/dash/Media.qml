import QtQuick
import "../../CortetsuDesign.js" as CortetsuDesign
import "../../CortetsuTypography.js" as CortetsuTypography
import "../../CortetsuIcon.qml"
import "../../CortetsuText.qml"
import "../../../services"

Item {
    id: root

    implicitWidth: 260
    implicitHeight: 360

    Column {
        anchors.fill: parent
        anchors.margins: CortetsuDesign.spacingStandard
        spacing: CortetsuDesign.spacingStandard

        Rectangle {
            width: parent.width
            height: width
            radius: CortetsuDesign.radiusMedium
            color: CortetsuDesign.colorSurfaceHigh

            CortetsuIcon {
                anchors.centerIn: parent
                text: "music_note"
                color: CortetsuDesign.colorSecondary
                iconSize: CortetsuTypography.iconHeroPx
            }
        }

        CortetsuText {
            width: parent.width
            text: Players.active?.trackTitle || qsTr("No media")
            color: CortetsuDesign.colorWashi
            textSize: CortetsuTypography.titleSmallPx
            font.weight: Font.Bold
            elide: Text.ElideRight
        }

        CortetsuText {
            width: parent.width
            text: Players.active?.trackArtist || qsTr("No active player")
            color: CortetsuDesign.colorMuted
            textSize: CortetsuTypography.bodyPx
            elide: Text.ElideRight
        }

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: CortetsuDesign.spacingComfortable

            CortetsuIcon {
                text: "skip_previous"
                color: CortetsuDesign.colorWashi
                iconSize: CortetsuTypography.iconMediumPx
                MouseArea { anchors.fill: parent; onClicked: Players.active?.previous() }
            }
            CortetsuIcon {
                text: Players.active?.isPlaying ? "pause" : "play_arrow"
                color: CortetsuDesign.colorPrimary
                iconSize: CortetsuTypography.iconMediumPx
                MouseArea { anchors.fill: parent; onClicked: Players.active?.togglePlaying() }
            }
            CortetsuIcon {
                text: "skip_next"
                color: CortetsuDesign.colorWashi
                iconSize: CortetsuTypography.iconMediumPx
                MouseArea { anchors.fill: parent; onClicked: Players.active?.next() }
            }
        }
    }
}
