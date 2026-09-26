import QtQuick
import "../../CortetsuDesign.js" as CortetsuDesign
import "../../CortetsuTypography.js" as CortetsuTypography
import "../../CortetsuText.qml"
import "../../../services"

Item {
    implicitWidth: 92
    implicitHeight: 180

    Column {
        anchors.centerIn: parent
        spacing: 0

        CortetsuText {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Time.hourStr
            color: CortetsuDesign.colorSecondary
            textSize: CortetsuTypography.displayMediumPx
            font.weight: Font.Bold
        }
        CortetsuText {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "•••"
            color: CortetsuDesign.colorPrimary
            textSize: CortetsuTypography.displaySmallPx
        }
        CortetsuText {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Time.minuteStr
            color: CortetsuDesign.colorSecondary
            textSize: CortetsuTypography.displayMediumPx
            font.weight: Font.Bold
        }
        CortetsuText {
            visible: CortetsuConfig.useTwelveHourClock
            anchors.horizontalCenter: parent.horizontalCenter
            text: Time.amPmStr
            color: CortetsuDesign.colorPrimary
            textSize: CortetsuTypography.titleSmallPx
        }
    }
}
