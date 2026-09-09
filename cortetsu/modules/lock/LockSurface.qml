pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.components
import qs.services
import qs.utils
import "../CortetsuDesign.js" as CortetsuDesign
import "../CortetsuTypography.js" as CortetsuTypography

WlSessionLockSurface {
    id: root
    required property WlSessionLock lock
    required property Pam pam

    property string keyboardLayout: qsTr("Unknown layout")
    property bool capsLock: false
    property bool numLock: false
    readonly property string userLabel: Quickshell.env("USER") || qsTr("User")
    readonly property int batteryPercent: Math.round(UPower.displayDevice.percentage * 100)
    readonly property bool batteryCharging: [
        UPowerDeviceState.Charging,
        UPowerDeviceState.FullyCharged,
        UPowerDeviceState.PendingCharge
    ].includes(UPower.displayDevice.state)
    readonly property string batteryLabel: UPower.displayDevice?.isLaptopBattery
        ? qsTr("Battery %1%").arg(batteryPercent)
        : qsTr("AC power")
    readonly property string networkLabel: CortetsuNetwork.activeEthernet
        ? qsTr("Ethernet")
        : CortetsuNetwork.active?.ssid ?? qsTr("Offline")

    color: CortetsuDesign.colorSumi

    function updateKeyboardState(raw: string): void {
        try {
            const devices = JSON.parse(raw);
            const keyboards = devices?.keyboards ?? [];
            const keyboard = keyboards.find(device => device.main) || keyboards[0];
            if (!keyboard)
                return;

            const active = String(keyboard.active_keymap ?? keyboard.activeKeymap ?? "").trim();
            keyboardLayout = active.length > 0 ? active : qsTr("Unknown layout");
            capsLock = Boolean(keyboard.capsLock ?? keyboard.caps_lock ?? false);
            numLock = Boolean(keyboard.numLock ?? keyboard.num_lock ?? false);
        } catch (_) {
            keyboardLayout = qsTr("Unknown layout");
            capsLock = false;
            numLock = false;
        }
    }

    Component.onCompleted: keyboardProbe.running = true

    ScreencopyView {
        anchors.fill: parent
        captureSource: root.screen
        opacity: 0.28
    }

    Rectangle {
        anchors.fill: parent
        color: Qt.alpha(CortetsuDesign.colorSumi, 0.76)
    }

    Item {
        id: keyboardFocus
        anchors.fill: parent
        focus: true
        Keys.onPressed: event => {
            pam.handleKey(event);
            event.accepted = true;
        }
    }

    Process {
        id: keyboardProbe
        command: ["hyprctl", "-j", "devices"]
        stdout: StdioCollector {
            onStreamFinished: root.updateKeyboardState(text)
        }
    }

    Timer {
        interval: 2000
        repeat: true
        running: true
        onTriggered: if (!keyboardProbe.running)
            keyboardProbe.running = true
    }

    ColumnLayout {
        anchors.centerIn: parent
        width: Math.min(parent.width - 64, 560)
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

        CortetsuText {
            Layout.alignment: Qt.AlignHCenter
            text: qsTr("Cortetsu")
            textSize: 28
            font.weight: Font.DemiBold
        }

        CortetsuText {
            Layout.alignment: Qt.AlignHCenter
            text: Qt.formatDateTime(Time.date, "dddd, d MMMM")
            textSize: CortetsuTypography.bodyPx
            color: CortetsuDesign.colorOnSurfaceVariant
        }

        CortetsuText {
            Layout.alignment: Qt.AlignHCenter
            text: `${Time.hourStr}:${Time.minuteStr}`
            textSize: 72
            font.weight: Font.DemiBold
        }

        CortetsuText {
            Layout.alignment: Qt.AlignHCenter
            text: root.userLabel
            textSize: CortetsuTypography.titleMediumPx
            font.weight: Font.DemiBold
        }

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

                CortetsuText {
                    text: qsTr("Password")
                    textSize: CortetsuTypography.labelSmallPx
                    color: CortetsuDesign.colorOnSurfaceVariant
                }

                CortetsuText {
                    text: pam.buffer.length ? "• ".repeat(pam.buffer.length) : qsTr("Type your password and press Enter")
                    textSize: CortetsuTypography.bodyPx
                    color: pam.buffer.length ? CortetsuDesign.colorOnSurface : CortetsuDesign.colorOnSurfaceVariant
                }
            }

            MouseArea {
                anchors.fill: parent
                onClicked: keyboardFocus.forceActiveFocus()
            }
        }

        CortetsuText {
            Layout.alignment: Qt.AlignHCenter
            visible: pam.state > 0
            text: pam.state === 3 ? qsTr("Authentication failed. Try again.") : qsTr("Authentication unavailable")
            textSize: CortetsuTypography.bodySmallPx
            color: CortetsuDesign.colorVermillion
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: CortetsuDesign.spacingCompact

            CortetsuSurface {
                Layout.fillWidth: true
                implicitHeight: 48
                radiusValue: CortetsuDesign.radiusMedium
                baseColor: Qt.alpha(CortetsuDesign.colorSurfaceGlass, 0.68)
                outlined: true

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: CortetsuDesign.spacingCompact
                    spacing: CortetsuDesign.spacingCompact
                    CortetsuIcon {
                        text: UPower.displayDevice?.isLaptopBattery
                            ? Icons.getBatteryIcon(UPower.displayDevice?.percentage ?? 0, root.batteryCharging)
                            : "power"
                        iconSize: CortetsuTypography.iconSmallPx
                        color: CortetsuDesign.colorOnSurfaceVariant
                    }
                    CortetsuText {
                        Layout.fillWidth: true
                        text: root.batteryLabel
                        textSize: CortetsuTypography.labelSmallPx
                        color: CortetsuDesign.colorOnSurfaceVariant
                        elide: Text.ElideRight
                    }
                }
            }

            CortetsuSurface {
                Layout.fillWidth: true
                implicitHeight: 48
                radiusValue: CortetsuDesign.radiusMedium
                baseColor: Qt.alpha(CortetsuDesign.colorSurfaceGlass, 0.68)
                outlined: true

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: CortetsuDesign.spacingCompact
                    spacing: CortetsuDesign.spacingCompact
                    CortetsuIcon {
                        text: CortetsuNetwork.activeEthernet ? "cable" : (CortetsuNetwork.active ? "wifi" : "wifi_off")
                        iconSize: CortetsuTypography.iconSmallPx
                        color: CortetsuDesign.colorOnSurfaceVariant
                    }
                    CortetsuText {
                        Layout.fillWidth: true
                        text: root.networkLabel
                        textSize: CortetsuTypography.labelSmallPx
                        color: CortetsuDesign.colorOnSurfaceVariant
                        elide: Text.ElideRight
                    }
                }
            }
        }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: CortetsuDesign.spacingCompact

            CortetsuIcon {
                text: "keyboard"
                iconSize: CortetsuTypography.iconSmallPx
                color: CortetsuDesign.colorOnSurfaceVariant
            }

            CortetsuText {
                text: root.keyboardLayout
                textSize: CortetsuTypography.labelSmallPx
                color: CortetsuDesign.colorOnSurfaceVariant
            }

            CortetsuText {
                visible: root.capsLock
                text: qsTr("CAPS")
                textSize: CortetsuTypography.labelSmallPx
                font.weight: Font.DemiBold
                color: CortetsuDesign.colorWarning
            }

            CortetsuText {
                visible: root.numLock
                text: qsTr("NUM")
                textSize: CortetsuTypography.labelSmallPx
                font.weight: Font.DemiBold
                color: CortetsuDesign.colorOnSurfaceVariant
            }
        }

        CortetsuText {
            Layout.alignment: Qt.AlignHCenter
            text: qsTr("Enter to authenticate")
            textSize: CortetsuTypography.labelSmallPx
            color: CortetsuDesign.colorOnSurfaceVariant
        }
    }
}
