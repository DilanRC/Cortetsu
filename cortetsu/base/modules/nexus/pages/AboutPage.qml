import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import qs.components
import qs.services
import qs.utils
import qs.modules.nexus.common

PageBase {
    id: root

    // Plugin support is not wired up yet; always 0 for now
    readonly property int pluginCount: 0

    property string quickshellVersion
    property string cliVersion

    title: qsTr("About")

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: CortetsuTokens.spacing.extraSmall / 2

        // e.g. "Quickshell 0.3.0 (revision ...)"
        // startup inventory: cortetsu:about-quickshell-version
        Process {
            running: true
            command: ["quickshell", "--version"]
            stdout: StdioCollector {
                onStreamFinished: root.quickshellVersion = text.trim().split(" ")[1] ?? ""
            }
        }

        // Read the optional first-party CLI without making the shell depend on it.
        // startup inventory: cortetsu:about-cortetsu-version
        Process {
            running: true
            command: ["sh", "-c", "command -v cortetsu >/dev/null 2>&1 && cortetsu --version"]
            stdout: StdioCollector {
                onStreamFinished: {
                    const m = text.match(/Cortetsu\s+(\S+)/);
                    root.cliVersion = m ? m[1] : "";
                }
            }
        }

        // Hero
        ConnectedRect {
            Layout.fillWidth: true
            first: true
            last: true
            implicitHeight: hero.implicitHeight + CortetsuTokens.padding.extraLarge * 2

            ColumnLayout {
                id: hero

                anchors.centerIn: parent
                width: parent.width - CortetsuTokens.padding.largeIncreased * 2
                spacing: CortetsuTokens.spacing.small

                AnimatedLogo {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredWidth: implicitWidth
                    Layout.preferredHeight: implicitHeight
                }

                CortetsuText {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: CortetsuTokens.spacing.small
                    text: "Cortetsu"
                    font: CortetsuTokens.font.headline.builders.large.width(110).build()
                }

                CortetsuText {
                    Layout.alignment: Qt.AlignHCenter
                    text: CortetsuUtils.version ? `v${CortetsuUtils.version}` : "…"
                    color: CortetsuColours.palette.m3onSurfaceVariant
                    font: CortetsuTokens.font.body.medium
                }
            }
        }

        // System
        SectionHeader {
            text: qsTr("System")
        }

        InfoRow {
            first: true
            label: qsTr("Hostname")
            value: SysInfo.hostname
        }

        InfoRow {
            label: qsTr("Device")
            value: SysInfo.device
        }

        InfoRow {
            label: qsTr("Distro")
            value: SysInfo.osPrettyName || SysInfo.osName
        }

        InfoRow {
            label: qsTr("Kernel")
            value: SysInfo.kernel
        }

        InfoRow {
            last: true
            label: qsTr("Firmware")
            value: SysInfo.firmware
        }

        // Software
        SectionHeader {
            text: qsTr("Software")
        }

        InfoRow {
            first: true
            label: qsTr("Shell")
            value: CortetsuUtils.version || "…"
        }

        InfoRow {
            label: qsTr("CLI")
            value: root.cliVersion || "…"
        }

        InfoRow {
            label: qsTr("Quickshell")
            value: root.quickshellVersion || "…"
        }

        InfoRow {
            last: true
            label: qsTr("Qt")
            value: CortetsuUtils.qtVersion || "…"
        }

        // Plugins
        SectionHeader {
            text: qsTr("Plugins")
        }

        InfoRow {
            first: true
            last: true
            label: qsTr("Loaded plugins")
            value: root.pluginCount.toString()
        }
    }
}
