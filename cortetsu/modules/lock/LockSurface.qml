pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.components
import qs.services
import "../CortetsuDesign.js" as CortetsuDesign
import "../CortetsuTypography.js" as CortetsuTypography

WlSessionLockSurface {
    id: root
    required property WlSessionLock lock
    required property Pam pam
    color: CortetsuDesign.colorSumi

    ScreencopyView {
        anchors.fill: parent
        captureSource: root.screen
        opacity: 0.28
    }
    Rectangle { anchors.fill: parent; color: Qt.alpha(CortetsuDesign.colorSumi, 0.76) }

    Item {
        id: keyboardFocus
        anchors.fill: parent
        focus: true
        Keys.onPressed: event => { pam.handleKey(event); event.accepted = true }
    }

    ColumnLayout {
        anchors.centerIn: parent
        width: Math.min(parent.width - 64, 520)
        spacing: CortetsuDesign.spacingStandard

        Image {
            source: Quickshell.shellPath("assets/branding/cortetsu-mark.svg")
            sourceSize.width: 64
            sourceSize.height: 64
            Layout.preferredWidth: 64
            Layout.preferredHeight: 64
            Layout.alignment: Qt.AlignHCenter
            fillMode: Image.PreserveAspectFit
        }
        CortetsuText { Layout.alignment: Qt.AlignHCenter; text: qsTr("Cortetsu"); textSize: 28; font.weight: Font.DemiBold }
        CortetsuText { Layout.alignment: Qt.AlignHCenter; text: Qt.formatDateTime(Time.date, "dddd, d MMMM"); textSize: CortetsuTypography.bodyPx; color: CortetsuDesign.colorOnSurfaceVariant }
        CortetsuText { Layout.alignment: Qt.AlignHCenter; text: `${Time.hourStr}:${Time.minuteStr}`; textSize: 72; font.weight: Font.DemiBold }

        CortetsuSurface {
            Layout.fillWidth: true
            implicitHeight: 72
            radiusValue: CortetsuDesign.radiusLarge
            baseColor: Qt.alpha(CortetsuDesign.colorSurfaceGlassStrong, 0.92)
            focused: true
            outlined: true
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: CortetsuDesign.spacingStandard
                spacing: 2
                CortetsuText { text: qsTr("Password"); textSize: CortetsuTypography.labelSmallPx; color: CortetsuDesign.colorOnSurfaceVariant }
                CortetsuText { text: pam.buffer.length ? "• ".repeat(pam.buffer.length) : qsTr("Type your password and press Enter"); textSize: CortetsuTypography.bodyPx; color: pam.buffer.length ? CortetsuDesign.colorOnSurface : CortetsuDesign.colorOnSurfaceVariant }
            }
            MouseArea { anchors.fill: parent; onClicked: keyboardFocus.forceActiveFocus() }
        }

        CortetsuText {
            Layout.alignment: Qt.AlignHCenter
            visible: pam.state > 0
            text: pam.state === 3 ? qsTr("Authentication failed. Try again.") : qsTr("Authentication unavailable")
            textSize: CortetsuTypography.bodySmallPx
            color: CortetsuDesign.colorVermillion
        }
        CortetsuText { Layout.alignment: Qt.AlignHCenter; text: qsTr("%1 · %2").arg(UPower.displayDevice?.isLaptopBattery ? qsTr("Battery %1%").arg(Math.round(UPower.displayDevice.percentage * 100)) : qsTr("AC power")).arg(CortetsuNetwork.active?.ssid ?? qsTr("Network unavailable")); textSize: CortetsuTypography.labelSmallPx; color: CortetsuDesign.colorOnSurfaceVariant }
        CortetsuText { Layout.alignment: Qt.AlignHCenter; text: qsTr("Keyboard layout · Enter to authenticate"); textSize: CortetsuTypography.labelSmallPx; color: CortetsuDesign.colorOnSurfaceVariant }
    }
}
