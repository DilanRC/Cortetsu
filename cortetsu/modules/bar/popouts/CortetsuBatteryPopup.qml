pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Services.UPower
import "../../../components"
import "../../CortetsuDesign.js" as CortetsuDesign

Column {
    id: root

    spacing: CortetsuDesign.spacingStandard
    width: 300

    readonly property bool hasBattery: UPower.displayDevice.isLaptopBattery
    readonly property int percentage: Math.round(UPower.displayDevice.percentage * 100)
    readonly property bool critical: root.hasBattery && root.percentage <= 15 && UPower.onBattery

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
        detail: root.hasBattery
            ? UPower.onBattery ? qsTr("On battery") : qsTr("Charging")
            : qsTr("Desktop power")
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
                        text: UPower.onBattery ? "battery_full" : "bolt"
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
                        text: UPower.onBattery
                            ? qsTr("%1 remaining").arg(root.formatSeconds(UPower.displayDevice.timeToEmpty))
                            : qsTr("%1 until full").arg(root.formatSeconds(UPower.displayDevice.timeToFull))
                        textSize: CortetsuDesign.labelSmallPx
                        color: CortetsuDesign.colorOnSurfaceVariant
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: 5
                radius: 3
                color: Qt.alpha(CortetsuDesign.colorSurfaceGlassStrong, 0.9)

                Rectangle {
                    width: parent.width * Math.max(0, Math.min(1, UPower.displayDevice.percentage))
                    height: parent.height
                    radius: parent.radius
                    color: root.critical
                        ? CortetsuDesign.colorVermillion
                        : CortetsuDesign.colorPrimary

                    Behavior on width {
                        NumberAnimation {
                            duration: CortetsuDesign.motionStandardMs
                            easing.type: Easing.OutCubic
                        }
                    }
                }
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
        scale: stateLayer.pressed ? 0.985 : 1

        Behavior on scale {
            NumberAnimation {
                duration: CortetsuDesign.motionInstantMs
                easing.type: Easing.OutCubic
            }
        }

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
