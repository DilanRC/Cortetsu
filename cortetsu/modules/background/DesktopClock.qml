import QtQuick
import QtQuick.Layouts
import "../../theme"
import "../CortetsuTypography.js" as CortetsuTypography

Item {
    id: root

    required property Item wallpaper
    required property real absX
    required property real absY

    property real clockScale: 1
    property bool bgEnabled: true
    property bool blurEnabled: false
    property bool invertColors: false

    readonly property color primary: invertColors ? CortetsuDesign.colorOnPrimary : CortetsuDesign.colorPrimary
    readonly property color secondary: invertColors ? CortetsuDesign.colorWashi : CortetsuDesign.colorSecondary
    readonly property color tertiary: CortetsuDesign.colorTertiary

    implicitWidth: clockLayout.implicitWidth + 56 * clockScale
    implicitHeight: clockLayout.implicitHeight + 40 * clockScale

    Rectangle {
        anchors.fill: parent
        radius: CortetsuDesign.radiusLarge * root.clockScale
        color: CortetsuDesign.colorSurface
        opacity: root.bgEnabled ? 0.88 : 0
        border.color: CortetsuDesign.colorOutlineVariant
        border.width: 1
    }

    RowLayout {
        id: clockLayout
        anchors.centerIn: parent
        spacing: 18 * root.clockScale

        RowLayout {
            spacing: 2

            Text {
                text: Time.hourStr
                color: root.primary
                font.family: CortetsuTypography.uiFamily
                font.pixelSize: CortetsuTypography.titleLargePx * 3 * root.clockScale
                font.weight: Font.Bold
            }
            Text {
                text: ":"
                color: root.tertiary
                opacity: 0.8
                font.family: CortetsuTypography.uiFamily
                font.pixelSize: CortetsuTypography.titleLargePx * 3 * root.clockScale
            }
            Text {
                text: Time.minuteStr
                color: root.secondary
                font.family: CortetsuTypography.uiFamily
                font.pixelSize: CortetsuTypography.titleLargePx * 3 * root.clockScale
                font.weight: Font.Bold
            }
            Text {
                visible: CortetsuRegional.useTwelveHourClock
                text: Time.amPmStr
                color: root.secondary
                font.family: CortetsuTypography.uiFamily
                font.pixelSize: CortetsuTypography.titleMediumPx * root.clockScale
                Layout.alignment: Qt.AlignTop
            }
        }

        Rectangle {
            Layout.fillHeight: true
            Layout.preferredWidth: Math.max(2, 4 * root.clockScale)
            color: root.primary
            opacity: 0.8
        }

        ColumnLayout {
            spacing: 0
            Text {
                text: Time.format("MMMM").toUpperCase()
                color: root.secondary
                font.family: CortetsuTypography.uiFamily
                font.pixelSize: CortetsuTypography.titleMediumPx * root.clockScale
                font.weight: Font.Bold
            }
            Text {
                text: Time.format("dd")
                color: root.primary
                font.family: CortetsuTypography.uiFamily
                font.pixelSize: CortetsuTypography.titleLargePx * root.clockScale
                font.weight: Font.Medium
            }
            Text {
                text: Time.format("dddd")
                color: root.secondary
                font.family: CortetsuTypography.uiFamily
                font.pixelSize: CortetsuTypography.bodyLargePx * root.clockScale
            }
        }
    }

    states: [
        State { name: "top-left"; AnchorChanges { target: root; anchors.top: parent.top; anchors.left: parent.left } },
        State { name: "top-center"; AnchorChanges { target: root; anchors.top: parent.top; anchors.horizontalCenter: parent.horizontalCenter } },
        State { name: "top-right"; AnchorChanges { target: root; anchors.top: parent.top; anchors.right: parent.right } },
        State { name: "middle-left"; AnchorChanges { target: root; anchors.verticalCenter: parent.verticalCenter; anchors.left: parent.left } },
        State { name: "middle-center"; AnchorChanges { target: root; anchors.verticalCenter: parent.verticalCenter; anchors.horizontalCenter: parent.horizontalCenter } },
        State { name: "middle-right"; AnchorChanges { target: root; anchors.verticalCenter: parent.verticalCenter; anchors.right: parent.right } },
        State { name: "bottom-left"; AnchorChanges { target: root; anchors.bottom: parent.bottom; anchors.left: parent.left } },
        State { name: "bottom-center"; AnchorChanges { target: root; anchors.bottom: parent.bottom; anchors.horizontalCenter: parent.horizontalCenter } },
        State { name: "bottom-right"; AnchorChanges { target: root; anchors.bottom: parent.bottom; anchors.right: parent.right } }
    ]
}
