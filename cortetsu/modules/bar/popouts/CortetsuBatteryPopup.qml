pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Services.UPower
import "../../../components"
import "../../../services"
import "../../CortetsuDesign.js" as CortetsuDesign
import "../../../utils"

CortetsuPopupSurface {
    id: root

    implicitWidth: 332
    implicitHeight: body.implicitHeight + CortetsuDesign.spacingComfortable * 2

    readonly property bool hasBattery: CortetsuPower.hasBattery
    readonly property int percentage: CortetsuPower.percent
    readonly property bool batteryCharging: CortetsuPower.charging
    readonly property bool critical: CortetsuPower.hasBattery && root.percentage <= 15 && CortetsuPower.onBattery
    readonly property string batteryStatus: !root.hasBattery
        ? qsTr("External power")
        : root.batteryCharging && root.percentage >= 100
            ? qsTr("Fully charged")
            : root.batteryCharging
                ? qsTr("Charging")
                : CortetsuPower.onBattery
                    ? qsTr("On battery")
                    : qsTr("External power")

    Column {
        id: body

        anchors.fill: parent
        anchors.margins: CortetsuDesign.spacingComfortable
        spacing: CortetsuDesign.spacingStandard

        function formatSeconds(seconds: int): string {
            if (seconds <= 0)
                return qsTr("Calculating…");
            const hours = Math.floor(seconds / 3600);
            const minutes = Math.floor(seconds / 60) % 60;
            return hours > 0
                ? qsTr("%1h %2m").arg(hours).arg(minutes)
                : qsTr("%1m").arg(minutes);
        }

        CortetsuSectionHeader {
            title: qsTr("Power")
            detail: root.hasBattery ? root.batteryStatus : qsTr("Desktop power")
        }

        CortetsuSurface {
            width: parent.width
            visible: root.hasBattery
            implicitHeight: 112
            radiusValue: CortetsuDesign.radiusLarge
            baseColor: root.critical
                ? Qt.alpha(CortetsuDesign.colorVermillion, 0.12)
                : Qt.alpha(CortetsuDesign.colorSurfaceGlassStrong, 0.78)
            outlineColor: root.critical
                ? Qt.alpha(CortetsuDesign.colorVermillion, 0.42)
                : Qt.alpha(CortetsuDesign.colorOutlineVariant, 0.24)
            outlined: true

            Column {
                anchors.fill: parent
                anchors.margins: CortetsuDesign.spacingStandard
                spacing: CortetsuDesign.spacingCompact

                Row {
                    width: parent.width
                    spacing: CortetsuDesign.spacingStandard

                    Item {
                        width: 44
                        height: 44

                        CortetsuSurface {
                            anchors.fill: parent
                            radiusValue: CortetsuDesign.radiusMedium
                            baseColor: root.critical
                                ? Qt.alpha(CortetsuDesign.colorVermillion, 0.14)
                                : Qt.alpha(CortetsuDesign.colorPrimary, 0.14)
                        }

                        CortetsuIcon {
                            anchors.centerIn: parent
                            text: root.hasBattery
                                ? Icons.getBatteryIcon(CortetsuPower.value, root.batteryCharging)
                                : "balance"
                            iconSize: CortetsuDesign.iconMediumPx + 4
                            color: root.critical
                                ? CortetsuDesign.colorVermillion
                                : CortetsuDesign.colorPrimary
                        }
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 1

                        CortetsuText {
                            text: qsTr("%1%").arg(root.percentage)
                            textSize: CortetsuDesign.bodyLargePx + 4
                            font.weight: Font.DemiBold
                            color: root.critical
                                ? CortetsuDesign.colorVermillion
                                : CortetsuDesign.colorOnSurface
                        }

                        CortetsuText {
                            text: root.batteryCharging && root.percentage < 100
                                ? qsTr("%1 until full").arg(body.formatSeconds(CortetsuPower.timeToFull))
                                : CortetsuPower.onBattery
                                    ? qsTr("%1 remaining").arg(body.formatSeconds(CortetsuPower.timeToEmpty))
                                    : root.batteryStatus
                            textSize: CortetsuDesign.labelSmallPx
                            color: CortetsuDesign.colorOnSurfaceVariant
                        }
                    }
                }

                CortetsuProgressBar {
                    width: parent.width
                    value: CortetsuPower.value
                    barHeight: 5
                    barRadius: 3
                    trackColor: Qt.alpha(CortetsuDesign.colorSurfaceGlassStrong, 0.9)
                    fillColor: root.critical
                        ? CortetsuDesign.colorVermillion
                        : CortetsuDesign.colorPrimary
                    motionDuration: CortetsuDesign.motionStandardMs
                }
            }
        }

        CortetsuText {
            visible: PowerProfiles.degradationReason !== PerformanceDegradationReason.None
            width: parent.width
            text: qsTr("Performance limited: %1").arg(
                PerformanceDegradationReason.toString(PowerProfiles.degradationReason))
            textSize: CortetsuDesign.labelSmallPx
            color: CortetsuDesign.colorVermillion
            wrapMode: Text.WordWrap
        }

        CortetsuStateMessage {
            width: parent.width
            visible: !root.hasBattery
            kind: "empty"
            title: qsTr("No battery detected")
            detail: qsTr("Power profile controls remain available")
        }

        CortetsuSectionHeader {
            title: qsTr("Power profile")
            detail: PowerProfile.toString(PowerProfiles.profile)
        }

        Row {
            spacing: CortetsuDesign.spacingCompact
            anchors.horizontalCenter: parent.horizontalCenter

            ProfileButton {
                profile: PowerProfile.PowerSaver
                icon: "energy_savings_leaf"
                label: qsTr("Saver")
            }
            ProfileButton {
                profile: PowerProfile.Balanced
                icon: "balance"
                label: qsTr("Balanced")
            }
            ProfileButton {
                profile: PowerProfile.Performance
                icon: "rocket_launch"
                label: qsTr("Performance")
            }
        }
    }

    component ProfileButton: Item {
        id: profileButton

        required property int profile
        required property string icon
        required property string label
        readonly property bool selected: PowerProfiles.profile === profile

        implicitWidth: 86
        implicitHeight: 68
        focus: true
        activeFocusOnTab: true
        // Keep the profile target fixed while the shared surface paints the
        // pressed state. This prevents profile selection from moving under
        // the pointer during a press.
        scale: 1

        CortetsuSurface {
            anchors.fill: parent
            radiusValue: CortetsuDesign.radiusMedium
            baseColor: profileButton.selected
                ? Qt.alpha(CortetsuDesign.colorPrimaryContainer, 0.66)
                : Qt.alpha(CortetsuDesign.colorSurfaceGlass, 0.72)
            outlineColor: profileButton.activeFocus
                ? Qt.alpha(CortetsuDesign.colorWashi, 0.82)
                : profileButton.selected
                    ? Qt.alpha(CortetsuDesign.colorPrimary, 0.34)
                    : Qt.alpha(CortetsuDesign.colorOutlineVariant, 0.18)
            outlined: true
            focused: profileButton.activeFocus
            hovered: stateLayer.containsMouse
            pressed: stateLayer.pressed
        }

        CortetsuStateLayer {
            id: stateLayer
            anchors.fill: parent
            radius: CortetsuDesign.radiusMedium
            onPressed: profileButton.forceActiveFocus()
            onClicked: PowerProfiles.profile = profileButton.profile
        }

        Column {
            anchors.centerIn: parent
            spacing: 3

            CortetsuIcon {
                anchors.horizontalCenter: parent.horizontalCenter
                text: profileButton.icon
                color: profileButton.selected
                    ? CortetsuDesign.colorWashi
                    : CortetsuDesign.colorPrimary
            }

            CortetsuText {
                anchors.horizontalCenter: parent.horizontalCenter
                text: profileButton.label
                textSize: CortetsuDesign.labelSmallPx
                color: profileButton.selected
                    ? CortetsuDesign.colorOnPrimaryContainer
                    : CortetsuDesign.colorOnSurfaceVariant
            }
        }

        Keys.onEnterPressed: PowerProfiles.profile = profileButton.profile
        Keys.onReturnPressed: PowerProfiles.profile = profileButton.profile
        Keys.onSpacePressed: PowerProfiles.profile = profileButton.profile
    }
}
